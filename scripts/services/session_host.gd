class_name SessionHost
extends RefCounted
## 双人合作会话·主机侧（2.6）。ENet 直连 + JSON 包协议（不走 MultiplayerAPI 场景树，
## 便于 headless 双端同进程测试与跨进程部署）。主机权威：客户端只发意图，主机验证、
## 裁定并广播快照（总计划 §9.2）；客机结算单由客机自行应用，主机不写对方农场档。

signal packet_received(peer_id: int, message: Dictionary)

const DEFAULT_PORT := 31967
const MAX_MEMBERS := 2

var peer := ENetMultiplayerPeer.new()
var room: Dictionary = {}
var expedition: ExpeditionGame = null
var pending_run_id := ""
var farm_game: FarmGame
var state_version := 0
var action_log: Dictionary = {}


func listen(farm: FarmGame, port := DEFAULT_PORT) -> bool:
	farm_game = farm
	room = {
		"open": true,
		"members": {1: {"peer_id": 1, "name": "主机（我）", "player_id": str(farm.state["expedition"].get("player_id", "")), "ready": false, "is_host": true}},
	}
	return peer.create_server(port, MAX_MEMBERS - 1) == OK


func poll() -> void:
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var sender := peer.get_packet_peer()
		var message: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
		if message is Dictionary:
			if sender == 0:
				sender = 1
			_handle(sender, message)
			packet_received.emit(sender, message)


func _send(peer_id: int, message: Dictionary) -> void:
	peer.set_target_peer(peer_id)
	peer.put_packet(JSON.stringify(message).to_utf8_buffer())


func broadcast(message: Dictionary) -> void:
	for member_id in room["members"]:
		if int(member_id) != 1:
			_send(int(member_id), message)


# —— 消息处理 ————————————————————————————————————————————————


func _handle(sender: int, message: Dictionary) -> void:
	match str(message.get("t", "")):
		"hello":
			_on_hello(sender, message)
		"ready":
			_on_ready(sender, message)
		"depart_saved":
			_on_depart_saved(sender, message)
		"action":
			_on_action(sender, message)
		"settlement_applied":
			room["members"].get(sender, {}).set("settlement_confirmed", true)
		"leave_room":
			_remove_member(sender)
		_:
			_send(sender, {"t": "error", "reason": "未知消息类型"})


func _on_hello(sender: int, message: Dictionary) -> void:
	if (room["members"] as Dictionary).size() >= MAX_MEMBERS:
		_send(sender, {"t": "welcome", "ok": false, "reason": "房间已满（双人）"})
		return
	if str(message.get("rules_version", "")) != ExpeditionBaseline.PROTO_RULES_VERSION:
		_send(sender, {"t": "welcome", "ok": false, "reason": "规则版本不一致"})
		return
	room["members"][sender] = {
		"peer_id": sender,
		"name": str(message.get("name", "队友")),
		"player_id": str(message.get("player_id", "")),
		"ready": false,
		"is_host": false,
		"profile": {
			"name": str(message.get("name", "队友")),
			"player_id": str(message.get("player_id", "")),
			"loadout": message.get("loadout", {}),
			"carried": message.get("carried", []),
			"next_instance_id": int(message.get("next_instance_id", 1000)),
			"hp": int(message.get("hp", ExpeditionBaseline.MAX_HP)),
		},
	}
	_send(sender, {"t": "welcome", "ok": true, "room": _room_view()})


func _on_ready(sender: int, message: Dictionary) -> void:
	var member: Dictionary = room["members"].get(sender, {})
	if member.is_empty():
		return
	member["ready"] = bool(message.get("ready", false))
	var profile: Dictionary = member.get("profile", {})
	profile["loadout"] = message.get("loadout", profile.get("loadout", {}))
	profile["carried"] = message.get("carried", profile.get("carried", []))
	member["profile"] = profile
	broadcast({"t": "room", "room": _room_view()})


func _on_depart_saved(sender: int, message: Dictionary) -> void:
	var member: Dictionary = room["members"].get(sender, {})
	if not member.is_empty():
		member["depart_saved"] = true
	_try_begin_run()


func _try_begin_run() -> void:
	## 出发事务（2.6 设计 §3）：双方准备＋双方保存确认，才进入同一局。
	if expedition != null:
		return
	var guest: Dictionary = {}
	for member_id in room["members"]:
		var member: Dictionary = room["members"][member_id]
		if bool(member.get("is_host", false)):
			room["members"][member_id]["ready"] = bool(room["members"].get(1, {}).get("ready", false))
		elif not bool(member.get("ready", false)) or not bool(member.get("depart_saved", false)):
			return
		else:
			guest = member.get("profile", {})
	if guest.is_empty():
		return
	var result := ExpeditionGame.depart_coop(farm_game, guest, int(Time.get_unix_time_from_system()), pending_run_id)
	if not result["ok"]:
		broadcast({"t": "depart_failed", "reason": result["reason"]})
		return
	expedition = result["game"]
	broadcast({"t": "depart", "run": expedition.run})
	_push_snapshot()


func host_set_ready(ready: bool) -> void:
	room["members"][1]["ready"] = ready
	broadcast({"t": "room", "room": _room_view()})


## 主机确认出发（双方已准备）：先广播预备，等所有成员 depart_saved 再开局。
func begin_depart() -> Dictionary:
	if expedition != null:
		return {"ok": false, "reason": "已在局中"}
	for member_id in room["members"]:
		var member: Dictionary = room["members"][member_id]
		if not bool(member.get("ready", false)):
			return {"ok": false, "reason": "还有成员未准备"}
	## 两段式出发：先发局 ID 让客机写占用；全员回执后才真正开局（设计 §3）。
	pending_run_id = ExpeditionStore.new_run_id(int(Time.get_unix_time_from_system() * 1000.0))
	broadcast({"t": "depart_begin", "run_id": pending_run_id})
	room["members"][1]["depart_saved"] = true
	_try_begin_run()
	if expedition == null:
		return {"ok": true, "reason": "等待客机保存确认", "waiting": true}
	return {"ok": true, "reason": ""}


# —— 动作裁定（总计划 §9.2：验证身份/费用/目标后按到达序执行）———————————


func _on_action(sender: int, message: Dictionary) -> void:
	var action_id := str(message.get("id", ""))
	if action_log.has(action_id):
		## 重传同一动作返回已有结果，不再次扣费或领取。
		_send(sender, {"t": "action_result", "id": action_id, "result": action_log[action_id]})
		return
	var member_key := "p2" if sender != 1 else "p1"
	var result := _execute_action(member_key, str(message.get("kind", "")), message.get("args", {}))
	action_log[action_id] = result
	state_version += 1
	_send(sender, {"t": "action_result", "id": action_id, "result": result})
	if expedition != null and result.get("run_changed", false):
		_push_snapshot()
	if result.has("guest_settlement"):
		broadcast({"t": "settlement", "settlement": result["guest_settlement"]})


## 主机自己的动作直通裁定（与客机动作同一入口，保证同一验证路径）。
func host_action(kind: String, args: Dictionary = {}) -> Dictionary:
	return _execute_action("p1", kind, args)


func _execute_action(member_key: String, kind: String, args: Dictionary) -> Dictionary:
	if expedition == null:
		return {"ok": false, "reason": "尚未开局"}
	var run: Dictionary = expedition.run
	match kind:
		"vote_move":
			var r := expedition.vote_move(member_key, int(args.get("row", -1)), int(args.get("col", -1)))
			r["run_changed"] = true
			return r
		"start_battle":
			var r := expedition.start_battle()
			r["run_changed"] = true
			return r
		"play_card":
			var combat := expedition.restore_battle()
			if combat == null:
				return {"ok": false, "reason": "没有进行中的战斗"}
			var r := combat.play_card(member_key, int(args.get("uid", -1)), str(args.get("target", "")))
			run["battle"] = combat.to_dict()
			expedition.save()
			r["run_changed"] = true
			return r
		"end_turn":
			var combat := expedition.restore_battle()
			if combat == null:
				return {"ok": false, "reason": "没有进行中的战斗"}
			var r := combat.end_turn(member_key)
			run["battle"] = combat.to_dict()
			expedition.save()
			r["run_changed"] = true
			return r
		"finish_battle":
			var combat := expedition.restore_battle()
			if combat == null:
				return {"ok": false, "reason": "没有进行中的战斗"}
			var r := expedition.finish_battle(combat)
			if r.has("settlements"):
				var guest_settle: Dictionary = r["settlements"].get("p2", {})
				if not guest_settle.is_empty():
					r["guest_settlement"] = guest_settle
			r["run_changed"] = true
			return r
		"claim_reward":
			var inv := expedition.member_inventory(member_key)
			var r: Dictionary = inv.claim_reward(str(args.get("def_id", "")), str(args.get("container", "pack")))
			if r["ok"]:
				expedition.save()
			r["run_changed"] = true
			return r
		"take_rest":
			var r := expedition.take_rest(str(args.get("option", "")))
			r["run_changed"] = true
			return r
		"choose_event":
			var r := expedition.choose_event(str(args.get("option", "")))
			r["run_changed"] = true
			return r
		"leave_node":
			var r := expedition.leave_node()
			if r.has("settlements"):
				var guest_settle: Dictionary = r["settlements"].get("p2", {})
				if not guest_settle.is_empty():
					r["guest_settlement"] = guest_settle
			r["run_changed"] = true
			return r
		"vote_extract":
			var r := expedition.vote_extract(member_key, bool(args.get("agree", true)))
			if r.has("settlements"):
				var guest_settle: Dictionary = r["settlements"].get("p2", {})
				if not guest_settle.is_empty():
					r["guest_settlement"] = guest_settle
			r["run_changed"] = true
			return r
		"share_offer":
			var r := expedition.share_offer(member_key, int(args.get("instance_id", 0)))
			r["run_changed"] = true
			return r
		"share_accept":
			var r := expedition.share_accept(member_key, str(args.get("container", "pack")))
			r["run_changed"] = true
			return r
		"share_cancel":
			var r := expedition.share_cancel()
			r["run_changed"] = true
			return r
		"abandon_member":
			var r := expedition.abandon_member(member_key)
			if r.has("settlement") and member_key == "p2":
				r["guest_settlement"] = r["settlement"]
			r["run_changed"] = true
			return r
	return {"ok": false, "reason": "未知动作：%s" % kind}


func _push_snapshot() -> void:
	broadcast({"t": "snapshot", "version": state_version, "run": expedition.run})


func _remove_member(peer_id: int) -> void:
	room["members"].erase(peer_id)
	broadcast({"t": "room", "room": _room_view()})


func _room_view() -> Dictionary:
	var view := {"open": bool(room.get("open", false)), "members": {}}
	for member_id in room["members"]:
		var member: Dictionary = room["members"][member_id]
		view["members"][member_id] = {
			"name": member.get("name", "?"),
			"ready": bool(member.get("ready", false)),
			"is_host": bool(member.get("is_host", false)),
		}
	return view
