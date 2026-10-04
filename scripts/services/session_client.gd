class_name SessionClient
extends RefCounted
## 双人合作会话·客机侧（2.6）。传输层二选一：ENet 局域网直连（connect_to_host）
## 或 TCP 中继「互联网房号」（connect_relay）。提交意图、接收快照与结算；
## 只对自己的农场档落盘。

signal welcome_received(ok: bool, reason: String)
signal run_received(run: Dictionary)
signal action_result_received(action_id: String, result: Dictionary)
signal settlement_received(settlement: Dictionary)
signal room_updated(room: Dictionary)
signal join_failed(reason: String)

var transport: SessionTransport = null
var farm_game: FarmGame
var mirror_run: Dictionary = {}
## 镜像序号：每收到 depart/snapshot 递增，UI 据此判断是否需要重建。
var mirror_serial := 0
var pending_run_id := ""
var next_action_seq := 0
var _last_ping_ms := 0
## 连接建立前的待发队列（握手包不再被静默丢弃——2.7）。
var _outbox: Array = []


func connect_to_host(address: String, farm: FarmGame, port := SessionHost.DEFAULT_PORT) -> bool:
	farm_game = farm
	var direct := EnetTransport.new()
	if not direct.open_guest(address, port):
		return false
	transport = direct
	return true


## 互联网模式：连中继服务器按房号加入；失败原因经 join_failed 信号上报。
func connect_relay(code: String, farm: FarmGame, address: String, port: int) -> bool:
	farm_game = farm
	var relay := RelayTransport.new()
	if not relay.open_guest(address, port, code):
		return false
	transport = relay
	return true


func poll() -> void:
	if transport == null:
		return
	## 心跳：主机据此判定在线/掉线（2.7）。
	var now_ms := Time.get_ticks_msec()
	if link_ready():
		if now_ms - _last_ping_ms > 800:
			_last_ping_ms = now_ms
			_send({"t": "ping"})
		if not _outbox.is_empty():
			var flush: Array = _outbox.duplicate()
			_outbox.clear()
			for message in flush:
				_send(message)
	for event in transport.poll():
		match str(event.get("kind", "")):
			"message":
				_handle(event["message"])
			"error":
				join_failed.emit(str(event.get("reason", "")))
			_:
				pass


func link_ready() -> bool:
	return transport != null and transport.link_ready()


## 主动断开（重连前调用，释放主机侧旧 peer）。
func disconnect_link() -> void:
	if transport != null:
		transport.close()
		transport = null


func _send(message: Dictionary) -> void:
	if not link_ready():
		_outbox.append(message)
		return
	transport.send(1, message)


# —— 加入与准备 ——————————————————————————————————————————————


func hello() -> void:
	var expedition: Dictionary = farm_game.state["expedition"]
	var inventory := InventoryGame.new()
	inventory.bind(expedition)
	hello_with(str(expedition.get("player_id", "")), inventory)


## 测试入口：允许自定义身份与携带（同一存档在不同局复用）。
func hello_with(player_id: String, inventory: InventoryGame) -> void:
	var carried: Array = []
	for container in ExpeditionBaseline.CONTAINERS:
		for instance in inventory.loadout_list(container):
			carried.append(int(instance["instance_id"]))
	_send({
		"t": "hello",
		"name": "客机农夫",
		"player_id": player_id,
		"rules_version": ExpeditionBaseline.PROTO_RULES_VERSION,
		"next_instance_id": int(inventory.expedition.get("next_instance_id", 1000)),
		"container_levels": (inventory.expedition.get("crafting", {}).get("upgrade_levels", {}) as Dictionary).duplicate(true),
		"loadout": (inventory.expedition.get("inventory", {}) as Dictionary).get("loadout", {}).duplicate(true),
		"carried": carried,
		"hp": ExpeditionBaseline.MAX_HP,
	})


func set_ready(ready: bool) -> void:
	var expedition: Dictionary = farm_game.state["expedition"]
	var inventory := InventoryGame.new()
	inventory.bind(expedition)
	var carried: Array = []
	for container in ExpeditionBaseline.CONTAINERS:
		for instance in inventory.loadout_list(container):
			carried.append(int(instance["instance_id"]))
	_send({
		"t": "ready",
		"ready": ready,
		"container_levels": (expedition.get("crafting", {}).get("upgrade_levels", {}) as Dictionary).duplicate(true),
		"loadout": (inventory.expedition.get("inventory", {}) as Dictionary).get("loadout", {}).duplicate(true),
		"carried": carried,
	})


## 出发事务第一步：只写内存占用与活动局引用，不发任何消息。
## 回执必须等占用状态落盘成功后再发（F-03 复核关闭标准）。
func prepare_depart() -> Dictionary:
	if pending_run_id == "":
		return {"ok": false, "reason": "还没有收到出发指令"}
	var run_id := pending_run_id
	var expedition: Dictionary = farm_game.state["expedition"]
	var inventory := InventoryGame.new()
	inventory.bind(expedition)
	if not inventory.is_run_occupied():
		var occupy := inventory.set_run_occupied(run_id)
		if not occupy["ok"]:
			return {"ok": false, "reason": occupy["reason"]}
	elif str((expedition.get("inventory", {}) as Dictionary).get("occupied_by_run", "")) != run_id:
		return {"ok": false, "reason": "已有其他活动局占用中"}
	expedition["active_run_ref"] = run_id
	return {"ok": true, "reason": ""}


## 占用已落盘后：发送成功回执（主机收到 depart_saved 才开局）。
func commit_depart() -> void:
	if pending_run_id == "":
		return
	_send({"t": "depart_saved", "run_id": pending_run_id})


## 准备后落盘失败等：回滚内存占用与引用并明确拒绝，主机可再次发起（F-03）。
func abort_depart(reason: String) -> void:
	if pending_run_id == "":
		return
	var run_id := pending_run_id
	pending_run_id = ""
	var expedition: Dictionary = farm_game.state["expedition"]
	var inventory := InventoryGame.new()
	inventory.bind(expedition)
	if str((expedition.get("inventory", {}) as Dictionary).get("occupied_by_run", "")) == run_id:
		inventory.clear_run_occupied(run_id)
	if str(expedition.get("active_run_ref", "")) == run_id:
		expedition["active_run_ref"] = ""
	_send({"t": "depart_declined", "run_id": "", "reason": reason})


## 兼容层：准备＋回执连做（d26/d27/d34 直接调用；UI 面板走拆分后的三步）。
func confirm_depart() -> Dictionary:
	var prepared := prepare_depart()
	if not prepared["ok"]:
		return prepared
	commit_depart()
	return {"ok": true, "reason": ""}


## 明确拒绝本次出发（如第一次存档写入失败）：主机收到后放弃开局，可再次发起（F-03）。
func decline_depart(reason: String) -> void:
	if pending_run_id == "":
		return
	pending_run_id = ""
	_send({"t": "depart_declined", "run_id": "", "reason": reason})


func send_action(kind: String, args: Dictionary = {}) -> String:
	next_action_seq += 1
	var action_id := ExpeditionStore.new_action_id(2, next_action_seq)
	_send({"t": "action", "id": action_id, "kind": kind, "args": args})
	return action_id


func send_settlement_applied(settlement_id: String) -> void:
	_send({"t": "settlement_applied", "settlement_id": settlement_id, "player_id": str(farm_game.state["expedition"].get("player_id", ""))})


# —— 消息处理 ——————————————————————————————————————————————


func _handle(message: Dictionary) -> void:
	match str(message.get("t", "")):
		"welcome":
			welcome_received.emit(bool(message.get("ok", false)), str(message.get("reason", "")))
			if message.has("room"):
				room_updated.emit(message["room"])
		"room":
			room_updated.emit(message["room"])
		"depart":
			mirror_run = message.get("run", {})
			mirror_serial += 1
			run_received.emit(mirror_run)
		"depart_begin":
			pending_run_id = str(message.get("run_id", ""))
		"depart_failed":
			welcome_received.emit(false, str(message.get("reason", "")))
		"snapshot":
			mirror_run = message.get("run", {})
			mirror_serial += 1
			run_received.emit(mirror_run)
		"action_result":
			action_result_received.emit(str(message.get("id", "")), message.get("result", {}))
		"settlement":
			_apply_guest_settlement(message.get("settlement", {}))
		_:
			pass


## 客机侧应用结算：主机不代替写档；重复收到只回执。
func _apply_guest_settlement(settlement: Dictionary) -> void:
	if settlement.is_empty():
		return
	var settlement_id := str(settlement.get("settlement_id", ""))
	var expedition: Dictionary = farm_game.state["expedition"]
	if (expedition.get("applied_settlements", []) as Array).has(settlement_id):
		send_settlement_applied(settlement_id)
		return
	var result := ExpeditionGame.apply_settlement(farm_game, settlement)
	if result["ok"]:
		send_settlement_applied(settlement_id)
	settlement_received.emit(settlement)
