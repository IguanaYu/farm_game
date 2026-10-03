class_name OnlineClient
extends Node
## M1 线上客户端传输层（计划 §5.2，W02 客户端半）：WSS+证书钉扎、信封收发、
## req_id 关联、断线重连（指数退避）、重连后原号重发 pending（服务器按收据去重）。
## 会话凭据（N02）：user://online/session.json，可删除即撤销本机登录。
## 认证由持有者驱动：begin_with_token() 自动登录；activate() 一次性开户（登录面板用）。

signal welcome_received(payload: Dictionary)
signal handshake_failed(code: String, need: Dictionary)
signal request_completed(req_id: String, reply: Dictionary)
signal kicked(reason: String)
signal state_changed(state: int)
signal bye_received(code: String)

enum State { OFFLINE, CONNECTING, ONLINE, RECONNECTING }

const RECONNECT_MIN_MS := 1000
const RECONNECT_MAX_MS := 15000
const HELLO_TIMEOUT_MS := 10000

var server_url := OnlineProtocol.DEFAULT_SERVER_URL
var cert_path := OnlineProtocol.CLIENT_CERT_PATH
var state := State.OFFLINE
var token := ""
var account_id := 0
var nick := ""
var features: Array = []
## 服务器时间锚点（F08）：server_now 在本地经过的毫秒由单调时钟补足。
var server_now := 0
var server_now_at_ms := 0

var peer := WebSocketMultiplayerPeer.new()
var _pending := {}      # req_id -> {op, args}（未收到终态应答；重连后原号重发）
var _replies := {}      # req_id -> 终态应答缓存（await_completed 轮询用，定期清理）
var _reply_order: Array = []
var _reconnect_at := 0
var _reconnect_delay := RECONNECT_MIN_MS
var _authenticated := false
var _activating := false
var _hello_sent := false
var _hello_deadline := 0



## 自动登录生命周期（farm_world / 登录面板共用）：断线自动重连，直到 shutdown()。
func begin_with_token(url: String, login_token: String) -> void:
	server_url = url if url != "" else OnlineProtocol.DEFAULT_SERVER_URL
	token = login_token
	_authenticated = false
	_connect_once()


## 一次性邀请激活（登录面板）：不进入自动重连生命周期，成功/失败即止。
func activate(url: String, invite: String, nick_name: String) -> void:
	server_url = url if url != "" else OnlineProtocol.DEFAULT_SERVER_URL
	token = ""
	_authenticated = false
	_activating = true
	_connect_once()
	# 连接成功后 _on_connected 发 activate 包
	_pending_activate = {"invite": invite, "nick": nick_name}


var _pending_activate := {}


func shutdown() -> void:
	state = State.OFFLINE
	_reconnect_at = 0
	_peer_close()


func now() -> int:
	if server_now <= 0:
		return int(Time.get_unix_time_from_system())
	return server_now + int((Time.get_ticks_msec() - server_now_at_ms) / 1000.0)


func can_submit() -> bool:
	return state == State.ONLINE and _authenticated


func _process(_delta: float) -> void:
	peer.poll()
	match state:
		State.CONNECTING, State.RECONNECTING:
			var status := peer.get_connection_status()
			if status == MultiplayerPeer.CONNECTION_CONNECTED:
				_on_connected()
			elif state == State.RECONNECTING and _reconnect_at != 0:
				## 等待重试计时期间完全无视旧 peer（尸体每帧报 DISCONNECTED/超时，
				## 任何一条都会把重连时刻无限推后）；到点即发起下一次尝试。
				if Time.get_ticks_msec() >= _reconnect_at:
					_try_reconnect()
			elif status == MultiplayerPeer.CONNECTION_DISCONNECTED or Time.get_ticks_msec() >= _hello_deadline:
				_on_disconnected()
		State.ONLINE:
			if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
				_on_disconnected()
	# 入站包在所有状态都要读：welcome/错误应答在 CONNECTING 期间到达，
	# 状态切换本身依赖读到这些包（否则握手死锁）。
	while peer.get_available_packet_count() > 0:
		_handle_packet(peer.get_packet().get_string_from_utf8())


func _connect_once() -> void:
	_reconnect_at = 0
	_hello_sent = false
	var cert := X509Certificate.new()
	if cert.load(cert_path) != OK:
		push_error("线上服务器证书加载失败：%s" % cert_path)
		_fail_handshake(OnlineProtocol.ERR_INTERNAL, {})
		return
	_peer_close()
	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_client(server_url, TLSOptions.client(cert))
	if err != OK:
		push_error("WSS 连接建立失败：%s err=%d" % [server_url, err])
		_fail_handshake(OnlineProtocol.ERR_INTERNAL, {})
		return
	_set_state(State.CONNECTING)
	_hello_deadline = Time.get_ticks_msec() + HELLO_TIMEOUT_MS


func _try_reconnect() -> void:
	_reconnect_at = 0
	_connect_once()
	_set_state(State.RECONNECTING)
	_hello_deadline = Time.get_ticks_msec() + HELLO_TIMEOUT_MS


func _on_connected() -> void:
	## 每个连接周期只发一次握手包（CONNECTING 状态每帧都会调到这里，裸发会洪水重发）。
	if _hello_sent:
		return
	_hello_sent = true
	if _activating and not _pending_activate.is_empty():
		_send(_activate_payload(_pending_activate["invite"], _pending_activate["nick"]))
		return
	_send(_hello_payload(token))


func _hello_payload(login_token: String) -> Dictionary:
	return {
		"t": "hello", "token": login_token,
		"proto": OnlineProtocol.PROTO_VERSION,
		"rules": OnlineProtocol.RULES_VERSION,
		"build": OnlineProtocol.CLIENT_BUILD,
	}


func _activate_payload(invite: String, nick_name: String) -> Dictionary:
	var payload := _hello_payload("")
	payload["t"] = "activate"
	payload["invite"] = invite
	payload["nick"] = nick_name
	return payload


func _handle_packet(raw: String) -> void:
	var parsed := JSON.new()
	if parsed.parse(raw) != OK or not (parsed.data is Dictionary):
		return
	var msg: Dictionary = parsed.data
	match str(msg.get("t", "")):
		"welcome":
			_on_welcome(msg)
		"req_ok", "req_err":
			var req_id := str(msg.get("req_id", ""))
			_pending.erase(req_id)
			_replies[req_id] = msg
			_reply_order.append(req_id)
			while _reply_order.size() > 64:
				_replies.erase(_reply_order.pop_front())
			request_completed.emit(req_id, msg)
		"kicked":
			shutdown()
			kicked.emit(str(msg.get("reason", "")))
		"bye":
			shutdown()
			bye_received.emit(str(msg.get("code", "")))
		"pong":
			pass
		"error":
			var code := str(msg.get("code", ""))
			if not _authenticated:
				_fail_handshake(code, msg.get("need", {}) if msg.get("need") is Dictionary else {})
			else:
				push_error("线上服务错误：%s %s" % [code, str(msg.get("msg", ""))])


func _on_welcome(msg: Dictionary) -> void:
	_authenticated = true
	_activating = false
	_pending_activate = {}
	_reconnect_delay = RECONNECT_MIN_MS
	account_id = int(msg.get("account_id", 0))
	nick = str(msg.get("nick", ""))
	features = msg.get("features", [])
	server_now = int(msg.get("server_now", 0))
	server_now_at_ms = Time.get_ticks_msec()
	var new_token := str(msg.get("token", ""))
	if new_token.begins_with("t_"):
		token = new_token
		save_session(token, account_id, nick)
	_set_state(State.ONLINE)
	welcome_received.emit(msg)
	# 重连恢复：原号重发未决请求（服务器按收据去重，F02 重试不重复扣发）
	for req_id in _pending.keys():
		var entry: Dictionary = _pending[req_id]
		_send({"t": "req", "req_id": req_id, "op": entry["op"], "args": entry["args"]})


func _fail_handshake(code: String, need: Dictionary) -> void:
	shutdown()
	handshake_failed.emit(code, need)


func _on_disconnected() -> void:
	_authenticated = false
	if _activating:
		_activating = false
		_pending_activate = {}
		_fail_handshake(OnlineProtocol.ERR_INTERNAL, {})
		return
	if token == "":
		shutdown()
		return
	_set_state(State.RECONNECTING)
	_reconnect_at = Time.get_ticks_msec() + _reconnect_delay
	_reconnect_delay = mini(_reconnect_delay * 2, RECONNECT_MAX_MS)
	_hello_deadline = _reconnect_at + HELLO_TIMEOUT_MS


func _send(payload: Dictionary) -> bool:
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	peer.set_target_peer(1)
	return peer.put_packet(JSON.stringify(payload).to_utf8_buffer()) == OK


func request(op: String, args: Dictionary) -> String:
	if not can_submit():
		return ""
	var req_id := "%d-%s" % [account_id, OnlineProtocol.bytes_to_hex(Crypto.new().generate_random_bytes(8))]
	_pending[req_id] = {"op": op, "args": args}
	if not _send({"t": "req", "req_id": req_id, "op": op, "args": args}):
		_pending.erase(req_id)
		return ""
	return req_id


## 等待某请求的终态应答；超时返回 {}（不取消 pending：重连后仍会原号重发）。
func await_completed(req_id: String, timeout_ms: int) -> Dictionary:
	if req_id == "":
		return {}
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if _replies.has(req_id):
			return _replies[req_id]
		await get_tree().process_frame
	return _replies.get(req_id, {})


func _set_state(next: int) -> void:
	if state == next:
		return
	state = next
	state_changed.emit(next)


func _peer_close() -> void:
	peer.close()


# —— 本机凭据（N02） ————————————————————————————————————————————

static func session_path() -> String:
	return OnlineProtocol.SESSION_PATH


static func save_session(login_token: String, acct_id: int, nick_name: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://online"))
	var file := FileAccess.open(OnlineProtocol.SESSION_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"token": login_token, "account_id": acct_id, "nick": nick_name}))
	file.close()
	return true


static func load_session() -> Dictionary:
	if not FileAccess.file_exists(OnlineProtocol.SESSION_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(OnlineProtocol.SESSION_PATH))
	if parsed is Dictionary and str(parsed.get("token", "")).begins_with("t_"):
		return parsed
	return {}


static func clear_session() -> void:
	if FileAccess.file_exists(OnlineProtocol.SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OnlineProtocol.SESSION_PATH))
