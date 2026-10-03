extends Node
## M0 服务端原型：无界面入口 + WSS(TLS 自签) + SQLite 事务。
## 依据：docs/【主要】Godot_好友联网试玩版_开发规划_v0.1.md §2.1/W01/M0。
## 运行（开发机本地点对点验证；正式部署由外部提供参数与守护）：
##   Godot --headless --path . res://scenes/server_main.tscn -- \
##     --port 31971 --db <绝对路径>.db --cert <crt> --key <key> [--bind 127.0.0.1] [--tag m0]
## 协议：一包一条 UTF-8 JSON；M0 只验证传输/事务/恢复，不实现账号与房间。

const PROTO_VERSION := 1
const SQL_SCHEMA := [
	"CREATE TABLE IF NOT EXISTS accounts(" +
		"id INTEGER PRIMARY KEY, name TEXT NOT NULL, balance INTEGER NOT NULL DEFAULT 0)",
	"CREATE TABLE IF NOT EXISTS receipts(" +
		"req_id TEXT PRIMARY KEY, op TEXT NOT NULL, delta INTEGER NOT NULL, " +
		"balance_after INTEGER NOT NULL, created_at TEXT NOT NULL)",
]

var tag := "m0"
var port := 31971
var bind := "127.0.0.1"
var db_path := ""
var db: SQLite
var peer := WebSocketMultiplayerPeer.new()
var listening := false
var peers := {}  # 4.6 的 WebSocketMultiplayerPeer 无 get_peer_list，用信号自维护在线表


func _ready() -> void:
	_read_args()
	if not _open_db():
		quit_now(3)
		return
	if not _listen_tls():
		quit_now(4)
		return
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	_log("ready proto=%d port=%d bind=%s db=%s" % [PROTO_VERSION, port, bind, db_path])


func _on_peer_connected(id: int) -> void:
	peers[id] = true
	_log("peer_connected id=%d" % id)


func _on_peer_disconnected(id: int) -> void:
	peers.erase(id)
	_log("peer_disconnected id=%d" % id)


func _process(_delta: float) -> void:
	if not listening:
		return
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var pid := peer.get_packet_peer()
		_handle_packet(pid, peer.get_packet())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown()


func _read_args() -> void:
	# 用户参数含无值开关（如 boot 分流的 --server），不能按固定步长配对解析，
	# 统一按名取值；--server 本身不在此处理。
	var args := OS.get_cmdline_user_args()
	var port_s := _arg_value(args, "--port")
	var bind_s := _arg_value(args, "--bind")
	var db_s := _arg_value(args, "--db")
	var tag_s := _arg_value(args, "--tag")
	var cert_path := _arg_value(args, "--cert")
	var key_path := _arg_value(args, "--key")
	if port_s != "":
		port = int(port_s)
	if bind_s != "":
		bind = bind_s
	if db_s != "":
		db_path = db_s
	if tag_s != "":
		tag = tag_s
	if cert_path != "" and key_path != "":
		_cert_paths = [cert_path, key_path]


var _cert_paths: Array = []


func _arg_value(args: Array, name: String) -> String:
	for i in range(args.size() - 1):
		if args[i] == name:
			return args[i + 1]
	return ""


func _open_db() -> bool:
	if not ClassDB.class_exists("SQLite"):
		push_error("godot-sqlite 扩展未加载（ClassDB 无 SQLite）")
		return false
	db = SQLite.new()
	db.path = db_path
	if not db.open_db():
		push_error("SQLite 打开失败: %s" % db.error_message)
		return false
	db.query("PRAGMA journal_mode=WAL;")
	db.query("PRAGMA synchronous=FULL;")
	for stmt in SQL_SCHEMA:
		if not db.query(stmt):
			push_error("SQLite 建表失败: %s" % stmt)
			return false
	if not db.query("SELECT COUNT(*) AS n FROM accounts WHERE id = 1") or db.query_result.is_empty():
		push_error("SQLite 自检查询失败")
		return false
	if int(db.query_result[0]["n"]) == 0:
		db.query("INSERT INTO accounts(id, name, balance) VALUES(1, 'm0-tester', 0)")
	_log("sqlite ok wal=%s" % _pragma("journal_mode"))
	return true


func _pragma(name: String) -> String:
	if db.query("PRAGMA %s;" % name) and not db.query_result.is_empty():
		return str(db.query_result[0][name])
	return "?"


func _listen_tls() -> bool:
	var key := CryptoKey.new()
	var cert := X509Certificate.new()
	if _cert_paths.size() == 2:
		if key.load(_cert_paths[1]) != OK or cert.load(_cert_paths[0]) != OK:
			push_error("证书/私钥加载失败: %s / %s" % [_cert_paths[0], _cert_paths[1]])
			return false
	var err := peer.create_server(port, bind, TLSOptions.server(key, cert))
	if err != OK:
		push_error("WSS 监听失败 port=%d err=%d" % [port, err])
		return false
	listening = true
	return true


func _handle_packet(pid: int, raw: PackedByteArray) -> void:
	var text := raw.get_string_from_utf8()
	var msg: Variant
	var parsed := JSON.new()
	if parsed.parse(text) != OK or not (parsed.data is Dictionary):
		_reply(pid, {"t": "error", "reason": "bad_json"})
		return
	msg = parsed.data
	var t := str(msg.get("t", ""))
	match t:
		"ping":
			_reply(pid, {"t": "pong", "proto": PROTO_VERSION})
		"balance":
			_cmd_balance(pid)
		"tx":
			_cmd_tx(pid, msg)
		"receipts":
			_cmd_receipts(pid, msg)
		_:
			_reply(pid, {"t": "error", "reason": "unknown_t"})


func _cmd_balance(pid: int) -> void:
	if not db.query("SELECT balance FROM accounts WHERE id = 1") or db.query_result.is_empty():
		_reply(pid, {"t": "error", "reason": "db_read_failed"})
		return
	_reply(pid, {"t": "balance", "value": int(db.query_result[0]["balance"])})


func _cmd_tx(pid: int, msg: Dictionary) -> void:
	var req_id := str(msg.get("req_id", ""))
	var delta := int(msg.get("delta", 0))
	if req_id == "":
		_reply(pid, {"t": "error", "reason": "req_id_required"})
		return
	if not db.query("BEGIN IMMEDIATE"):
		_reply(pid, {"t": "error", "reason": "begin_failed"})
		return
	if not db.query_with_bindings("SELECT delta, balance_after FROM receipts WHERE req_id = ?", [req_id]):
		db.query("ROLLBACK")
		_reply(pid, {"t": "error", "reason": "dedup_read_failed"})
		return
	if not db.query_result.is_empty():
		var row: Dictionary = db.query_result[0]
		db.query("ROLLBACK")
		_reply(pid, {
			"t": "tx_ok", "req_id": req_id, "duplicate": true,
			"delta": int(row["delta"]), "balance": int(row["balance_after"]),
		})
		return
	if not db.query_with_bindings("UPDATE accounts SET balance = balance + ? WHERE id = 1", [delta]):
		db.query("ROLLBACK")
		_reply(pid, {"t": "error", "reason": "update_failed"})
		return
	if not db.query("SELECT balance FROM accounts WHERE id = 1") or db.query_result.is_empty():
		db.query("ROLLBACK")
		_reply(pid, {"t": "error", "reason": "readback_failed"})
		return
	var balance := int(db.query_result[0]["balance"])
	var created := Time.get_datetime_string_from_system(true)
	if not db.query_with_bindings(
		"INSERT INTO receipts(req_id, op, delta, balance_after, created_at) VALUES(?, ?, ?, ?, ?)",
		[req_id, "credit", delta, balance, created]
	):
		db.query("ROLLBACK")
		_reply(pid, {"t": "error", "reason": "receipt_insert_failed"})
		return
	if not db.query("COMMIT"):
		db.query("ROLLBACK")
		_reply(pid, {"t": "error", "reason": "commit_failed"})
		return
	_reply(pid, {"t": "tx_ok", "req_id": req_id, "duplicate": false, "delta": delta, "balance": balance})


func _cmd_receipts(pid: int, msg: Dictionary) -> void:
	var limit := int(msg.get("limit", 100))
	if not db.query("SELECT COUNT(*) AS n FROM receipts") or db.query_result.is_empty():
		_reply(pid, {"t": "error", "reason": "db_read_failed"})
		return
	var count := int(db.query_result[0]["n"])
	if not db.query_with_bindings(
		"SELECT req_id, delta, balance_after, created_at FROM receipts ORDER BY created_at LIMIT ?",
		[limit]
	):
		_reply(pid, {"t": "error", "reason": "db_read_failed"})
		return
	_reply(pid, {"t": "receipts", "count": count, "rows": db.query_result})


func _reply(pid: int, payload: Dictionary) -> void:
	if not peers.has(pid):
		_log("reply 丢弃：peer %d 已不在" % pid)
		return
	peer.set_target_peer(pid)
	var err := peer.put_packet(JSON.stringify(payload).to_utf8_buffer())
	if err != OK:
		_log("reply 失败 peer=%d err=%d" % [pid, err])


func _log(line: String) -> void:
	print("[%s] %s" % [tag, line])


func _shutdown() -> void:
	if db != null:
		db.close_db()
		db = null


func quit_now(code: int) -> void:
	_shutdown()
	get_tree().quit(code)
