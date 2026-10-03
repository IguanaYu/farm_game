extends Node
## M1 线上农场服务端（计划 §4.4）：WSS(TLS 自签) + SQLite + 邀请/账号/会话 + 农场命令。
## 依据：docs/plan/Godot_好友联网_M1_M2_线上身份与个人农场_代码执行计划_v0.1.md。
## 运行（开发机本地点对点验证；正式部署由外部提供参数与守护）：
##   Godot --headless --path . res://scenes/server_main.tscn -- \
##     --port 31971 --db <绝对路径>.db --cert <crt> --key <key> [--bind 127.0.0.1] \
##     [--tag m1] [--features farm_basic,farm_shop] [--dev --dev-time-shift 3600]
## 邀请管理（O07 最小切片，不开监听）：
##   Godot --headless --path . res://scenes/server_main.tscn -- --db <db> --new-invite 3 [--invite-note 试玩批1]
## 协议见 scripts/services/online_protocol.gd；M0 假账户命令已退役（ping 保留为健康检查）。

const PROTO_VERSION := OnlineProtocol.PROTO_VERSION
const RULES_VERSION := OnlineProtocol.RULES_VERSION
const MIN_CLIENT_BUILD := OnlineProtocol.MIN_CLIENT_BUILD

var tag := "m1"
var port := 31971
var bind := "127.0.0.1"
var db_path := ""
var features: Array = [OnlineProtocol.FEATURE_FARM_BASIC]
var dev_mode := false

var store: ServerDB
var auth: AuthService
var farms: FarmService
var peer := WebSocketMultiplayerPeer.new()
var listening := false
## 4.6 的 WebSocketMultiplayerPeer 无 get_peer_list，用信号自维护在线表。
var peers := {}
## N05 包纪律：每 peer 消息时间窗、畸形包计数。
var _rate_times := {}   # peer_id -> Array[int]（毫秒）
var _malformed := {}    # peer_id -> int
## 待断开队列：put_packet 的应答要等下一次 poll 才冲刷，立刻 disconnect 会把它丢掉
## （实测 version_mismatch/kicked 因此从未送达）。延迟若干 poll 周期再断。
var _pending_drops := {}  # peer_id -> 断开时刻（毫秒）
## 待踢出队列：在"处理 peer A 的包"期间给空闲的 peer B 推包，实测该包会静默丢失
## （同一机制直接推空闲 peer 则必达）。踢出挪到下一帧、poll 派发之外执行。
var _pending_kicks: Array = []  # [{pid: int, reason: String}]


func _ready() -> void:
	_read_args()
	if _fatal_arg_error:
		quit_now(5)
		return
	if db_path == "":
		push_error("缺少 --db <路径>")
		quit_now(3)
		return
	store = ServerDB.new()
	if not store.open(db_path):
		quit_now(3)
		return
	auth = AuthService.new()
	auth.store = store
	if _invite_mode:
		_run_invite_mode()
		return
	farms = FarmService.new()
	farms.store = store
	farms.features = features
	if dev_mode:
		farms.time_shift = _dev_time_shift
	if not _listen_tls():
		quit_now(4)
		return
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	_log("ready proto=%d rules=%d port=%d bind=%s db=%s features=%s" % [
		PROTO_VERSION, RULES_VERSION, port, bind, db_path, ",".join(features),
	])


func _on_peer_connected(id: int) -> void:
	peers[id] = true
	_rate_times[id] = []
	_malformed[id] = 0
	_log("peer_connected id=%d online=%d" % [id, peers.size()])


func _on_peer_disconnected(id: int) -> void:
	peers.erase(id)
	_rate_times.erase(id)
	_malformed.erase(id)
	var account_id := auth.account_of_peer(id)
	auth.unbind_peer(id)
	if account_id != 0:
		farms.evict(account_id)
	_log("peer_disconnected id=%d online=%d" % [id, peers.size()])


func _process(_delta: float) -> void:
	if not listening:
		return
	_flush_pending_kicks()
	peer.poll()
	_flush_pending_drops()
	while peer.get_available_packet_count() > 0:
		var pid := peer.get_packet_peer()
		var raw := peer.get_packet()
		if raw.size() > OnlineProtocol.MAX_PACKET_BYTES:
			_log("oversized peer=%d size=%d → 断开" % [pid, raw.size()])
			_reply(pid, OnlineProtocol.error_payload(OnlineProtocol.ERR_OVERSIZED))
			_drop_peer(pid)
			continue
		_handle_packet(pid, raw)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown()


# —— 启动参数 ——————————————————————————————————————————————————————

var _invite_mode := false
var _invite_count := 0
var _invite_note := ""
var _dev_time_shift := 0
var _cert_paths: Array = []
var _fatal_arg_error := false


func _read_args() -> void:
	# 用户参数含无值开关（如 boot 分流的 --server），按名取值统一解析。
	var args := OS.get_cmdline_user_args()
	db_path = _arg_value(args, "--db")
	var port_s := _arg_value(args, "--port")
	var bind_s := _arg_value(args, "--bind")
	var tag_s := _arg_value(args, "--tag")
	var cert_path := _arg_value(args, "--cert")
	var key_path := _arg_value(args, "--key")
	var features_s := _arg_value(args, "--features")
	var invite_s := _arg_value(args, "--new-invite")
	_invite_note = _arg_value(args, "--invite-note")
	var shift_s := _arg_value(args, "--dev-time-shift")
	if port_s != "":
		port = int(port_s)
	if bind_s != "":
		bind = bind_s
	if tag_s != "":
		tag = tag_s
	if cert_path != "" and key_path != "":
		_cert_paths = [cert_path, key_path]
	if features_s == "-":
		# Windows 命令行会吞掉空串/空格参数，用 "-" 显式表示空特性（全灰度关闭）。
		features = []
	elif features_s != "":
		features = []
		for item in features_s.split(",", false):
			features.append(item.strip_edges())
	_invite_mode = invite_s != ""
	_invite_count = int(invite_s) if invite_s != "" else 0
	dev_mode = "--dev" in args
	if shift_s != "":
		_dev_time_shift = int(shift_s)
	if dev_mode and _dev_time_shift != 0 and bind != "127.0.0.1" and bind != "localhost":
		# 计划 §8：--dev 时间偏移只许本机联调，公网 bind 直接拒绝启动。
		push_error("--dev-time-shift 仅允许 --bind 127.0.0.1/localhost 的开发环境")
		_fatal_arg_error = true


func _arg_value(args: Array, name: String) -> String:
	for i in range(args.size() - 1):
		if args[i] == name:
			return args[i + 1]
	return ""


func _run_invite_mode() -> void:
	var codes := auth.generate_invites(_invite_count, _invite_note)
	if codes.is_empty():
		push_error("邀请码生成失败")
		quit_now(6)
		return
	for code in codes:
		print("INVITE %s" % code)
	_log("invites created n=%d" % codes.size())
	quit_now(0)


# —— 网络 ———————————————————————————————————————————————————————————

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
	if not _rate_allow(pid):
		_reply(pid, OnlineProtocol.error_payload(OnlineProtocol.ERR_RATE_LIMITED))
		return
	var text := raw.get_string_from_utf8()
	var parsed := JSON.new()
	if parsed.parse(text) != OK or not (parsed.data is Dictionary):
		_note_malformed(pid)
		return
	var msg: Dictionary = parsed.data
	var t := str(msg.get("t", ""))
	match t:
		"ping":
			_reply(pid, {"t": "pong", "proto": PROTO_VERSION})
		"hello":
			_cmd_hello(pid, msg)
		"activate":
			_cmd_activate(pid, msg)
		"req":
			_cmd_req(pid, msg)
		"bye":
			_drop_peer(pid)
		_:
			_note_malformed(pid, OnlineProtocol.ERR_UNKNOWN_T)


func _cmd_hello(pid: int, msg: Dictionary) -> void:
	var version_error: Variant = _version_check(msg)
	if version_error != null:
		_reply(pid, version_error)
		_drop_peer(pid)
		return
	var login: Dictionary = auth.login(str(msg.get("token", "")))
	if not bool(login.get("ok", false)):
		_reply(pid, OnlineProtocol.error_payload(str(login.get("code", OnlineProtocol.ERR_TOKEN_INVALID))))
		return
	_establish_session(pid, int(login["account_id"]), str(login["nick"]))


func _cmd_activate(pid: int, msg: Dictionary) -> void:
	var version_error: Variant = _version_check(msg)
	if version_error != null:
		_reply(pid, version_error)
		_drop_peer(pid)
		return
	var farm := FarmGame.new()
	farm.new_game(farms.now())
	var created: Dictionary = auth.activate(
		str(msg.get("invite", "")), str(msg.get("nick", "")), JSON.stringify(farm.state)
	)
	if not bool(created.get("ok", false)):
		_reply(pid, OnlineProtocol.error_payload(str(created.get("code", OnlineProtocol.ERR_INTERNAL))))
		return
	_establish_session(pid, int(created["account_id"]), str(created["nick"]), str(created["token"]))


## 登录/激活成功：绑定会话（N03 顶替旧 peer）→ 下发 welcome（含快照与特性开关）。
func _establish_session(pid: int, account_id: int, nick: String, new_token := "") -> void:
	var kicked_peer := auth.bind_session(account_id, pid)
	if kicked_peer != 0 and peers.has(kicked_peer):
		_log("kick peer=%d（账户 %d 被新连接顶替）" % [kicked_peer, account_id])
		_pending_kicks.append({"pid": kicked_peer, "reason": OnlineProtocol.ERR_SESSION_REPLACED})
	var runtime := farms.load_runtime(account_id)
	if runtime == null:
		_reply(pid, OnlineProtocol.error_payload(OnlineProtocol.ERR_INTERNAL, "account_load_failed"))
		return
	var payload := {
		"t": "welcome", "account_id": account_id, "nick": nick,
		"features": features, "server_now": farms.now(),
		"farm_seq": runtime.seq, "snapshot": farms.snapshot(runtime),
	}
	if new_token != "":
		payload["token"] = new_token
	_reply(pid, payload)
	_log("session peer=%d account=%d nick=%s" % [pid, account_id, nick])


func _cmd_req(pid: int, msg: Dictionary) -> void:
	var account_id := auth.account_of_peer(pid)
	if account_id == 0:
		_reply(pid, OnlineProtocol.error_payload(OnlineProtocol.ERR_NOT_AUTHENTICATED))
		return
	var reply: Dictionary = farms.execute(
		account_id, str(msg.get("req_id", "")), str(msg.get("op", "")), _args_of(msg)
	)
	_reply(pid, reply)


func _args_of(msg: Dictionary) -> Dictionary:
	var args: Variant = msg.get("args", {})
	return args if args is Dictionary else {}


## N04 版本握手：不匹配拒绝在进入前，need 携带服务器要求的最低三元组。
func _version_check(msg: Dictionary) -> Variant:
	var proto := _as_int(msg.get("proto", 0))
	var rules := _as_int(msg.get("rules", 0))
	var build := _as_int(msg.get("build", 0))
	if proto != PROTO_VERSION or rules != RULES_VERSION or build < MIN_CLIENT_BUILD:
		return OnlineProtocol.error_payload(
			OnlineProtocol.ERR_VERSION_MISMATCH,
			"",
			{"need": {"proto": PROTO_VERSION, "rules": RULES_VERSION, "build": MIN_CLIENT_BUILD}}
		)
	return null


# —— 包纪律（N05） —————————————————————————————————————————————————

func _rate_allow(pid: int) -> bool:
	var times: Array = _rate_times.get(pid, [])
	var now_ms := Time.get_ticks_msec()
	times = times.filter(func(ms): return now_ms - ms < int(OnlineProtocol.RATE_WINDOW_SECONDS * 1000))
	times.append(now_ms)
	_rate_times[pid] = times
	return times.size() <= OnlineProtocol.RATE_WINDOW_MESSAGES


func _note_malformed(pid: int, code := OnlineProtocol.ERR_BAD_JSON) -> void:
	var count := int(_malformed.get(pid, 0)) + 1
	_malformed[pid] = count
	if count >= OnlineProtocol.MAX_MALFORMED:
		_log("malformed×%d peer=%d → 断开" % [count, pid])
		_drop_peer(pid)
		return
	_reply(pid, OnlineProtocol.error_payload(code))


func _drop_peer(pid: int, immediate := false) -> void:
	if immediate:
		peer.disconnect_peer(pid, true)
		return
	# 断开必须给出足够宽的送达窗口：实测客户端只要在这段时间内 poll 到数据即安全，
	# 过早断开（60ms 级）会把尚未读走的 kicked/version_mismatch 一并丢掉。
	_pending_drops[pid] = Time.get_ticks_msec() + 2000


func _flush_pending_kicks() -> void:
	if _pending_kicks.is_empty():
		return
	for kick in _pending_kicks:
		_reply(int(kick["pid"]), {"t": "kicked", "reason": str(kick["reason"])})
		_drop_peer(int(kick["pid"]))
	_pending_kicks.clear()


func _flush_pending_drops() -> void:
	if _pending_drops.is_empty():
		return
	var now_ms := Time.get_ticks_msec()
	for pid in _pending_drops.keys():
		if now_ms >= int(_pending_drops[pid]):
			_pending_drops.erase(pid)
			# 优雅关闭：先完成 WebSocket close 握手，排队中的应答数据有机会先到达客户端；
			# 强制断开在 TCP 层直接丢缓冲，kicked/version_mismatch 会随之丢失（实测）。
			peer.disconnect_peer(pid, false)


func _reply(pid: int, payload: Dictionary) -> void:
	if not peers.has(pid):
		_log("reply 丢弃：peer %d 已不在" % pid)
		return
	# 直接对端发送：set_target_peer+put_packet 在同一帧内先给 A（kicked）再给 B（welcome）
	# 时，实测 kicked 从未上线——目标_peer 被后一次设置覆盖。get_peer(pid) 绕开该状态。
	var target := peer.get_peer(pid)
	if target == null:
		_log("reply 丢弃：peer %d 无 WebSocketPeer" % pid)
		return
	var err := target.put_packet(JSON.stringify(payload).to_utf8_buffer())
	if err != OK:
		_log("reply 失败 peer=%d err=%d" % [pid, err])


func _log(line: String) -> void:
	print("[%s] %s" % [tag, line])


func _shutdown() -> void:
	if store != null:
		store.close()
		store = null


func quit_now(code: int) -> void:
	_shutdown()
	get_tree().quit(code)


static func _as_int(value: Variant) -> int:
	if value is float:
		return int(value)
	if value is int:
		return value
	if value is String and value.is_valid_int():
		return int(value)
	return 0
