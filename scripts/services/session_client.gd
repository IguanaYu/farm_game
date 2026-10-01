class_name SessionClient
extends RefCounted
## 双人合作会话·客机侧（2.6）。提交意图、接收快照与结算；只对自己的农场档落盘。

signal welcome_received(ok: bool, reason: String)
signal run_received(run: Dictionary)
signal action_result_received(action_id: String, result: Dictionary)
signal settlement_received(settlement: Dictionary)
signal room_updated(room: Dictionary)

var peer := ENetMultiplayerPeer.new()
var farm_game: FarmGame
var mirror_run: Dictionary = {}
var pending_run_id := ""
var next_action_seq := 0
var _last_ping_ms := 0
## 连接建立前的待发队列（握手包不再被静默丢弃——2.7）。
var _outbox: Array = []


func connect_to_host(address: String, farm: FarmGame, port := SessionHost.DEFAULT_PORT) -> bool:
	farm_game = farm
	return peer.create_client(address, port) == OK


func poll() -> void:
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
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
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var message: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
		if message is Dictionary:
			_handle(message)


func link_ready() -> bool:
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## 主动断开（重连前调用，释放主机侧旧 peer）。
func disconnect_link() -> void:
	peer.close()


func _send(message: Dictionary) -> void:
	if not link_ready():
		_outbox.append(message)
		return
	peer.set_target_peer(1)
	peer.put_packet(JSON.stringify(message).to_utf8_buffer())


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
		"loadout": (inventory.expedition.get("inventory", {}) as Dictionary).get("loadout", {}).duplicate(true),
		"carried": carried,
	})


## 收到出发指令后：本机先写占用与活动局引用再回执（出发事务的客机半边）。
func confirm_depart() -> Dictionary:
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
	expedition["active_run_ref"] = run_id
	_send({"t": "depart_saved", "run_id": run_id})
	return {"ok": true, "reason": ""}


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
			run_received.emit(mirror_run)
		"depart_begin":
			pending_run_id = str(message.get("run_id", ""))
		"depart_failed":
			welcome_received.emit(false, str(message.get("reason", "")))
		"snapshot":
			mirror_run = message.get("run", {})
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
