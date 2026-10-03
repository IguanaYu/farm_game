class_name OnlineFarmBridge
extends Node
## M1 线上农场桥接层（计划 §5.3，W03/W04 之间）：持有 OnlineClient 与 FarmGame 副本，
## welcome/req_ok 快照经 load_state 灌入副本后发 snapshot_applied（farm_world 刷 UI）；
## now() 服务器时间锚点（F08）；离线/忙碌时 can_submit()==false（F09）。
## 请求串行化（_busy）：同屏只允许一个在途命令，超时不改 req_id——同意图重试由
## 服务器收据去重兜底（F02 重复点击/重试不重复扣发）。

signal snapshot_applied
signal login_failed(code: String, need: Dictionary)
signal status_changed(text: String, online: bool)

const REQUEST_TIMEOUT_MS := 8000

var client := OnlineClient.new()
var game := FarmGame.new()
var _busy := false
var _bootstrapped := false


func begin(url: String, token: String) -> void:
	add_child(client)
	client.server_url = url
	client.welcome_received.connect(_on_welcome)
	client.handshake_failed.connect(_on_handshake_failed)
	client.state_changed.connect(_on_state_changed)
	client.kicked.connect(_on_kicked)
	client.request_completed.connect(_on_request_completed)
	client.begin_with_token(url, token)
	_set_status("连接中…", false)


func now() -> int:
	return client.now()


func can_submit() -> bool:
	return client.can_submit() and not _busy


## 发命令并等待终态应答；返回 req_ok/req_err 原始信封。
## 返回 {}：未在线/前序命令在途/等待超时（状态提示已发）。
func request(op: String, args: Dictionary) -> Dictionary:
	if not client.can_submit():
		_set_status("连接不可用，操作未发送（恢复连接后重试）", false)
		return {}
	if _busy:
		_set_status("上一个操作仍在处理中…", true)
		return {}
	_busy = true
	var req_id := client.request(op, args)
	if req_id == "":
		_busy = false
		_set_status("操作发送失败，连接可能已断开", false)
		return {}
	var reply: Dictionary = await client.await_completed(req_id, REQUEST_TIMEOUT_MS)
	_busy = false
	if reply.is_empty():
		_set_status("操作响应超时；若已生效会在重连后从快照看到结果", false)
		return {}
	if str(reply.get("t", "")) == "req_ok" and _apply_snapshot(reply):
		_set_status("已连接", true)
	return reply


func _on_welcome(msg: Dictionary) -> void:
	var snapshot: Variant = msg.get("snapshot", {})
	if not (snapshot is Dictionary) or not _apply_snapshot(msg):
		login_failed.emit(OnlineProtocol.ERR_INTERNAL, {})
		return
	_set_status("已连接", true)
	if not _bootstrapped:
		_bootstrapped = true
		snapshot_applied.emit()


func _on_handshake_failed(code: String, need: Dictionary) -> void:
	login_failed.emit(code, need)


func _on_kicked(_reason: String) -> void:
	_set_status("该账户已在别处登录，本连接已被断开", false)


func _on_state_changed(state: int) -> void:
	match state:
		OnlineClient.State.CONNECTING:
			_set_status("连接中…", false)
		OnlineClient.State.RECONNECTING:
			_set_status("连接断开，正在重连…（断线期间操作不可用）", false)
		OnlineClient.State.OFFLINE:
			_set_status("离线", false)
		OnlineClient.State.ONLINE:
			if client.account_id != 0:
				_set_status("已连接", true)


## 迟到的 req_ok（超时后重连送达）也刷快照，保持副本最新。
func _on_request_completed(_req_id: String, reply: Dictionary) -> void:
	if str(reply.get("t", "")) == "req_ok":
		_apply_snapshot(reply)


func _apply_snapshot(reply: Dictionary) -> bool:
	var snapshot: Variant = reply.get("snapshot", {})
	if not (snapshot is Dictionary):
		return false
	var farm: Variant = snapshot.get("farm", {})
	if not (farm is Dictionary):
		return false
	if not game.load_state(farm):
		push_error("线上快照校验失败，丢弃本帧（服务器与客户端规则版本可能不一致）")
		return false
	if not _bootstrapped:
		snapshot_applied.emit()
		_bootstrapped = true
	return true


func _set_status(text: String, online: bool) -> void:
	status_changed.emit(text, online)
