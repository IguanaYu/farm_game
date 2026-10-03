class_name SessionHost
extends RefCounted
## 双人合作会话·主机侧（2.6）。传输层二选一：ENet 局域网直连（listen）或
## TCP 中继「互联网房号」（listen_relay，见 tools/relay_server.py）。JSON 包协议
## （不走 MultiplayerAPI 场景树，便于 headless 双端同进程测试与跨进程部署）。
## 主机权威：客户端只发意图，主机验证、裁定并广播快照（总计划 §9.2）；
## 客机结算单由客机自行应用，主机不写对方农场档。

signal packet_received(peer_id: int, message: Dictionary)
signal relay_error(reason: String)

const DEFAULT_PORT := 31967
const MAX_MEMBERS := 2
## 掉线判定与暂停（2.7 设计 §9.4：客户端掉线→暂停推进；等待可配）。
const MEMBER_TIMEOUT_MS := 2500

var transport: SessionTransport = null
var room: Dictionary = {}
var expedition: ExpeditionGame = null
var pending_run_id := ""
## 未确认的客机结算单：按 player_id 暂存，重连或收到 settlement_applied 前不丢弃。
var pending_settlements: Dictionary = {}
var farm_game: FarmGame
var state_version := 0
var action_log: Dictionary = {}


func listen(farm: FarmGame, port := DEFAULT_PORT) -> bool:
	var direct := EnetTransport.new()
	if not direct.listen(port):
		return false
	transport = direct
	_setup_room(farm)
	return true


## 互联网模式：主动连中继服务器建房，房号异步到达（relay_room_code()/relay_error）。
func listen_relay(farm: FarmGame, address: String, port: int) -> bool:
	var relay := RelayTransport.new()
	if not relay.open_host(address, port):
		return false
	transport = relay
	_setup_room(farm)
	return true


func _setup_room(farm: FarmGame) -> void:
	farm_game = farm
	room = {
		"open": true,
		"members": {1: {"peer_id": 1, "name": "主机（我）", "player_id": str(farm.state["expedition"].get("player_id", "")), "ready": false, "is_host": true}},
	}


## 中继模式房号（建房确认后非空；局域网模式恒空）。
func relay_room_code() -> String:
	return transport.room_code() if transport != null else ""


## 中继链路是否已就绪（房号确认）；局域网模式等同监听成功。
func relay_online() -> bool:
	return transport != null and transport.link_ready()


func poll() -> void:
	if transport == null:
		return
	for event in transport.poll():
		match str(event.get("kind", "")):
			"message":
				var sender := int(event.get("peer_id", 0))
				if sender == 0:
					sender = 1
				_handle(sender, event["message"])
				packet_received.emit(sender, event["message"])
			"peer_down":
				_mark_member_offline(int(event.get("peer_id", 0)))
			"error":
				relay_error.emit(str(event.get("reason", "")))
			_:
				pass
	sweep_members(Time.get_ticks_msec())


## 中继即时掉线路径：直接置离线并广播（超时扫落在其后兜底，语义一致）。
func _mark_member_offline(peer_id: int) -> void:
	var member: Dictionary = room["members"].get(peer_id, {})
	if member.is_empty() or not bool(member.get("online", true)):
		return
	member["online"] = false
	if expedition != null:
		expedition.run["log"].append("%s 掉线：本局暂停推进，等待重连" % str(member.get("name", "队友")))
	broadcast({"t": "room", "room": _room_view()})


## 掉线检测：超时成员标记离线并广播暂停（不凭掉线判负/判撤离）。
func sweep_members(now_ms: int) -> void:
	var changed := false
	for member_id in (room.get("members", {}) as Dictionary).keys():
		if int(member_id) == 1:
			continue
		var member: Dictionary = room["members"][member_id]
		if bool(member.get("online", true)) and now_ms - int(member.get("last_seen_ms", now_ms)) > MEMBER_TIMEOUT_MS:
			member["online"] = false
			changed = true
			if expedition != null:
				expedition.run["log"].append("%s 掉线：本局暂停推进，等待重连" % str(member.get("name", "队友")))
	if changed:
		broadcast({"t": "room", "room": _room_view()})


func any_member_offline() -> bool:
	for member_id in room.get("members", {}):
		if int(member_id) != 1 and not bool(room["members"][member_id].get("online", true)):
			return true
	return false


func _send(peer_id: int, message: Dictionary) -> void:
	if transport == null:
		return
	transport.send(peer_id, message)


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
		"depart_declined":
			## 客机保存失败等明确拒绝：本次出发作废（不开局），主机可再次发起。
			pending_run_id = ""
			var declined_member: Dictionary = room["members"].get(sender, {})
			if not declined_member.is_empty():
				declined_member["depart_saved"] = false
			_send(sender, {"t": "depart_failed", "reason": "客机未能确认出发：%s" % str(message.get("reason", "未知原因"))})
		"action":
			_on_action(sender, message)
		"settlement_applied":
			room["members"].get(sender, {}).set("settlement_confirmed", true)
			pending_settlements.erase(str(message.get("player_id", "")) if message.has("player_id") else _player_id_of(sender))
		"ping":
			var member: Dictionary = room["members"].get(sender, {})
			if not member.is_empty():
				member["last_seen_ms"] = Time.get_ticks_msec()
				member["online"] = true
		"leave_room":
			_remove_member(sender)
		_:
			_send(sender, {"t": "error", "reason": "未知消息类型"})


func _on_hello(sender: int, message: Dictionary) -> Dictionary:
	if str(message.get("rules_version", "")) != ExpeditionBaseline.PROTO_RULES_VERSION:
		_send(sender, {"t": "welcome", "ok": false, "reason": "规则版本不一致"})
		return {"ok": false, "reason": "版本不一致"}
	var player_id := str(message.get("player_id", ""))
	## 重连：同 player_id 的掉线成员换新 peer 接回，不重复占位、不重开一局（2.7）。
	for member_id in (room["members"] as Dictionary).keys():
		var member: Dictionary = room["members"][member_id]
		if int(member_id) != 1 and str(member.get("player_id", "")) == player_id:
			(room["members"] as Dictionary).erase(member_id)
			member["peer_id"] = sender
			member["online"] = true
			member["ready"] = bool(member.get("ready", false))
			member["last_seen_ms"] = Time.get_ticks_msec()
			room["members"][sender] = member
			_send(sender, {"t": "welcome", "ok": true, "rejoined": true, "room": _room_view()})
			if expedition != null:
				_push_snapshot_to(sender)
				_resend_pending_settlement(player_id, sender)
			return {"ok": true, "reason": "rejoined"}
	if expedition != null:
		## 主机重启接回（2.7）：房间为空但局在进行，按局档客机身份放行重连。
		var guest_pid := str(expedition.run.get("guest", {}).get("player_id", ""))
		if guest_pid != "" and player_id == guest_pid:
			var guest: Dictionary = expedition.run.get("guest", {})
			room["members"][sender] = {
				"peer_id": sender,
				"name": str(guest.get("name", "队友")),
				"player_id": player_id,
				"ready": true,
				"is_host": false,
				"online": true,
				"last_seen_ms": Time.get_ticks_msec(),
				"profile": {
					"name": str(guest.get("name", "队友")),
					"player_id": player_id,
					"loadout": (guest.get("inventory", {}) as Dictionary).get("loadout", {}),
					"container_levels": guest.get("inventory", {}).get("container_levels", {}),
					"carried": guest.get("carried_from_farm", []),
					"next_instance_id": int(expedition.run.get("next_instance_id", 1000)),
					"hp": int(guest.get("hp", ExpeditionBaseline.MAX_HP)),
				},
			}
			_send(sender, {"t": "welcome", "ok": true, "rejoined": true, "room": _room_view()})
			_push_snapshot_to(sender)
			_resend_pending_settlement(player_id, sender)
			return {"ok": true, "reason": "rejoined"}
		_send(sender, {"t": "welcome", "ok": false, "reason": "本局已开始，不能中途加入新玩家"})
		return {"ok": false, "reason": "本局进行中"}
	if (room["members"] as Dictionary).size() >= MAX_MEMBERS:
		_send(sender, {"t": "welcome", "ok": false, "reason": "房间已满（双人）"})
		return {"ok": false, "reason": "满员"}
	room["members"][sender] = {
		"peer_id": sender,
		"name": str(message.get("name", "队友")),
		"player_id": player_id,
		"ready": false,
		"is_host": false,
		"online": true,
		"last_seen_ms": Time.get_ticks_msec(),
		"profile": {
			"name": str(message.get("name", "队友")),
			"player_id": player_id,
			"loadout": message.get("loadout", {}),
			"container_levels": message.get("container_levels", {}),
			"carried": message.get("carried", []),
			"next_instance_id": int(message.get("next_instance_id", 1000)),
			"hp": int(message.get("hp", ExpeditionBaseline.MAX_HP)),
		},
	}
	_send(sender, {"t": "welcome", "ok": true, "room": _room_view()})
	return {"ok": true, "reason": ""}


func _on_ready(sender: int, message: Dictionary) -> void:
	var member: Dictionary = room["members"].get(sender, {})
	if member.is_empty():
		return
	member["ready"] = bool(message.get("ready", false))
	var profile: Dictionary = member.get("profile", {})
	profile["loadout"] = message.get("loadout", profile.get("loadout", {}))
	profile["container_levels"] = message.get("container_levels", profile.get("container_levels", {}))
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
	if pending_run_id != "":
		## 已有一次出发在等客机确认：不覆盖局 ID 重复发起（F-03 附带守卫）。
		return {"ok": true, "reason": "已发起出发，等待客机保存确认", "waiting": true}
	if (room["members"] as Dictionary).size() < 2:
		return {"ok": false, "reason": "客机尚未加入房间"}
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
	_broadcast_guest_settlement(result)


## 主机自己的动作直通裁定（与客机动作同一入口，保证同一验证路径与结算下发）。
func host_action(kind: String, args: Dictionary = {}) -> Dictionary:
	var result := _execute_action("p1", kind, args)
	## F-04：主机动作同样要广播快照——否则客机镜像永远看不到主机的推进。
	if expedition != null and result.get("run_changed", false):
		_push_snapshot()
	_broadcast_guest_settlement(result)
	return result


## 客机结算单统一下发与未决登记（主机直通与客机动作共用）。
func _broadcast_guest_settlement(result: Dictionary) -> void:
	if result.has("guest_settlement"):
		var guest_settlement: Dictionary = result["guest_settlement"]
		pending_settlements[str(guest_settlement.get("player_id", ""))] = guest_settlement
		broadcast({"t": "settlement", "settlement": guest_settlement})


func _execute_action(member_key: String, kind: String, args: Dictionary) -> Dictionary:
	if expedition == null:
		return {"ok": false, "reason": "尚未开局"}
	if any_member_offline():
		return {"ok": false, "reason": "有成员掉线：本局暂停推进，等待重连（不判撤离也不判失败）"}
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
			## 领取走规则层事务（F-02）：校验→放置→按成员记录领取；满包失败不消费候选。
			var r: Dictionary = expedition.loot_action(member_key, "claim_reward", args)
			r["run_changed"] = true
			return r
		"claim_public":
			var r: Dictionary = expedition.loot_action(member_key, "claim_public", args)
			r["run_changed"] = true
			return r
		"pick_drop":
			var r := expedition.loot_action(member_key, "pick_drop", args)
			r["run_changed"] = true
			return r
		"loot_manage":
			var r := expedition.loot_action(member_key, kind, args)
			r["run_changed"] = bool(r.get("ok", false))
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
		"signal":
			expedition.run["log"].append("%s：%s" % [expedition.member(member_key)["name"], str(args.get("text", ""))])
			expedition.save()
			return {"ok": true, "run_changed": true}
		"abandon_member":
			var r := expedition.abandon_member(member_key)
			if r.has("settlement") and member_key == "p2":
				r["guest_settlement"] = r["settlement"]
			r["run_changed"] = true
			return r
	return {"ok": false, "reason": "未知动作：%s" % kind}


func _push_snapshot() -> void:
	broadcast({"t": "snapshot", "version": state_version, "run": expedition.run})


func _push_snapshot_to(peer_id: int) -> void:
	_send(peer_id, {"t": "snapshot", "version": state_version, "run": expedition.run})


## 未确认结算重发：重连时补发（客户端按 applied_settlements 幂等去重）。
func _resend_pending_settlement(player_id: String, peer_id: int) -> void:
	if pending_settlements.has(player_id):
		_send(peer_id, {"t": "settlement", "settlement": pending_settlements[player_id]})


func _player_id_of(peer_id: int) -> String:
	var member: Dictionary = room["members"].get(peer_id, {})
	return str(member.get("player_id", ""))


## 主机重启后接回活动局（2.7：主机退出→下次载入局档恢复→成员重连）。
func attach_resumed_run(resumed: ExpeditionGame) -> void:
	expedition = resumed
	state_version += 1


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
			"online": bool(member.get("online", true)),
		}
	return view
