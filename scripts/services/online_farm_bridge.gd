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
## M3：房间/局推送（服务器主动下发；run 带 version，客户端丢弃旧版本）。
signal room_updated(room: Dictionary)
signal run_snapshot(run: Dictionary, version: int)
signal settlement_arrived(settlement: Dictionary)

const REQUEST_TIMEOUT_MS := 8000

var client := OnlineClient.new()
var game := FarmGame.new()
var _busy := false
var _bootstrapped := false
## M3：局镜像（版本门控）。welcome 重连恢复与 push.run 同一入口维护。
var mirror_run := {}
var mirror_run_version := 0
var mirror_room := {}


func begin(url: String, token: String) -> void:
	_wire_client()
	client.begin_with_token(url, token)
	_set_status("连接中…", false)


## 一次性邀请激活（M3 测试/登录面板用）：与 begin() 同一装配，走 activate 路径。
func begin_with_invite(url: String, invite: String, nick_name: String) -> void:
	_wire_client()
	client.activate(url, invite, nick_name)
	_set_status("连接中…", false)


func _wire_client() -> void:
	add_child(client)
	client.welcome_received.connect(_on_welcome)
	client.handshake_failed.connect(_on_handshake_failed)
	client.state_changed.connect(_on_state_changed)
	client.kicked.connect(_on_kicked)
	client.request_completed.connect(_on_request_completed)
	client.push_received.connect(_on_push)


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
	## M3 起 room/run 应答不带农场快照（局态在 run/version）；仅应答携带快照时回灌。
	if str(reply.get("t", "")) == "req_ok" and reply.has("snapshot") and _apply_snapshot(reply):
		_set_status("已连接", true)
	return reply


func _on_welcome(msg: Dictionary) -> void:
	var snapshot: Variant = msg.get("snapshot", {})
	if not (snapshot is Dictionary) or not _apply_snapshot(msg):
		login_failed.emit(OnlineProtocol.ERR_INTERNAL, {})
		return
	_set_status("已连接", true)
	## M3：重连恢复——welcome 附带房间与活动局（S05 核心）。
	if msg.has("room"):
		mirror_room = msg["room"]
		room_updated.emit(mirror_room)
	if msg.has("run"):
		_apply_run(msg["run"], int(msg.get("version", 0)))
	if not _bootstrapped:
		_bootstrapped = true
		snapshot_applied.emit()


func _on_push(kind: String, msg: Dictionary) -> void:
	match kind:
		"room":
			var room: Variant = msg.get("room", {})
			if room is Dictionary:
				mirror_room = room
				room_updated.emit(room)
		"run":
			_apply_run(msg.get("run", {}), int(msg.get("version", 0)))
		"settlement":
			var settlement: Variant = msg.get("settlement", {})
			if settlement is Dictionary:
				settlement_arrived.emit(settlement)


func _apply_run(run: Variant, version: int) -> void:
	if not (run is Dictionary) or run.is_empty():
		return
	## 版本是"每局"计数：换局（run_id 变化）时重置基线，否则旧局版本会挡住新局快照。
	var rid := str(run.get("run_id", ""))
	if rid != "" and rid != str(mirror_run.get("run_id", "")):
		mirror_run_version = 0
	if version <= mirror_run_version and not mirror_run.is_empty():
		return
	mirror_run = run
	mirror_run_version = version
	run_snapshot.emit(run, version)


# —— M3 局命令面（W07 客户端半） ——————————————————————————————————


## 房间/出发应答的 result 里带 room/run：即刻吸收进镜像，不依赖后续推送的到达时机。
func _absorb_room(reply: Dictionary) -> void:
	var result: Variant = reply.get("result", {})
	if not (result is Dictionary):
		return
	var room: Variant = result.get("room", {})
	if room is Dictionary and not room.is_empty():
		mirror_room = room
		room_updated.emit(room)


func _absorb_run(reply: Dictionary) -> void:
	var result: Variant = reply.get("result", {})
	if not (result is Dictionary):
		return
	if result.has("run"):
		_apply_run(result.get("run", {}), int(result.get("version", 0)))


func room_create() -> Dictionary:
	var reply: Dictionary = await request("room.create", {})
	_absorb_room(reply)
	return reply


func room_join(code: String) -> Dictionary:
	var reply: Dictionary = await request("room.join", {"code": code})
	_absorb_room(reply)
	return reply


func room_leave() -> Dictionary:
	var reply: Dictionary = await request("room.leave", {})
	if str(reply.get("t", "")) == "req_ok":
		mirror_room = {}
		room_updated.emit({})
	return reply


func room_ready(ready: bool) -> Dictionary:
	var reply: Dictionary = await request("room.ready", {"ready": ready})
	_absorb_room(reply)
	return reply


func begin_depart() -> Dictionary:
	var reply: Dictionary = await request("room.begin_depart", {})
	_absorb_room(reply)
	_absorb_run(reply)
	return reply


func depart_solo() -> Dictionary:
	var reply: Dictionary = await request("run.depart_solo", {})
	_absorb_run(reply)
	return reply


## 局内动作（供 map/battle/loot 的 sink 调用）：返回规则结果字典；
## 失败/超时返回 {ok:false, reason}。req_ok 附带的 run 已按 version 灌入镜像。
func run_action(kind: String, args: Dictionary = {}) -> Dictionary:
	var reply: Dictionary = await request("run.action", {"kind": kind, "args": args})
	if reply.is_empty():
		return {"ok": false, "reason": "连接不可用或响应超时，稍后会自动重试"}
	if str(reply.get("t", "")) != "req_ok":
		return {"ok": false, "reason": str(reply.get("msg", reply.get("code", "操作失败")))}
	if reply.has("run"):
		_apply_run(reply["run"], int(reply.get("version", 0)))
	var result: Variant = reply.get("result", {})
	return result if result is Dictionary else {"ok": true}


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
	if str(reply.get("t", "")) == "req_ok" and reply.has("snapshot"):
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
