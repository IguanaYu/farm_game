class_name RoomService
extends RefCounted
## M3 房间与洞窟裁定服务（计划：docs/plan/Godot_合并路线_R1_M3_洞窟与资产闭环_代码执行计划_v0.1.md §4.2）。
## 房间生命周期（C01～C04）、出发跨账户事务（S01）、局内动作裁定（复用 ExpeditionGame，
## 候选副本事务模式与 FarmService 同纪律）、结算双方同事务应用（S03）、推送路由（C09）。
##
## 持久化分工：run 行由本服务显式 INSERT/UPDATE（候选事务内）；ExpeditionStore.backend
## 只接结算单写入暂存区，事务内搬进 settlements 表，回滚即丢弃。
## 规则失败=空事务提交（回 req_err op_failed）；数据库失败=回滚（internal_error）。

var store: ServerDB
var auth: AuthService
var farm_service: FarmService
var features: Array = []
## 推送出口（server_main._reply 同款签名：peer_id, payload -> void）。
var send: Callable = Callable()

## 结算暂存区：ExpeditionStore.backend 落点。
var _staged_settlements := {}  # settlement_id -> Dictionary

class _Room:
	var row_id := 0
	var code := ""
	var state := {}  # {creator_account_id, phase, run_id, members:[{account_id,nick,ready}], run_members:{p1:{account_id,nick},p2:{...}}}

class _RunBox:
	var run_id := ""
	var room: _Room = null  # 单人局为 null
	var game: ExpeditionGame
	var version := 1
	var members := {}  # member_key -> {account_id, nick}


func _init() -> void:
	ExpeditionStore.backend = Callable(self, "_file_backend")


func now() -> int:
	return farm_service.now()


func _file_backend(kind: String, id: String, data: Dictionary) -> bool:
	## run 落库走本服务显式 SQL（事务内统一版本管理），这里只接结算单。
	if kind == "save_settlement":
		_staged_settlements[id] = data
	return true


# —— 启动恢复（S07） ——————————————————————————————————————————————


func restore() -> void:
	for row in store.query_all("SELECT id, code, state FROM rooms"):
		var room := _Room.new()
		room.row_id = int(row["id"])
		room.code = str(row["code"])
		var parsed: Variant = JSON.parse_string(str(row["state"]))
		room.state = parsed if parsed is Dictionary else {}
		_rooms_by_code[room.code] = room
		for member in room.state.get("members", []):
			_rooms_by_account[int(member["account_id"])] = room
	for row in store.query_all("SELECT run_id, room_id, owner_account_id, state, version FROM runs"):
		var parsed: Variant = JSON.parse_string(str(row["state"]))
		if not (parsed is Dictionary):
			continue
		var run: Dictionary = parsed
		if str(run.get("outcome", "")) != "":
			continue
		var room_row := int(row.get("room_id", 0)) if row.get("room_id") != null else 0
		var box := _RunBox.new()
		box.run_id = str(row["run_id"])
		box.version = int(row["version"])
		box.game = _build_instance(run)
		if bool(run.get("coop", false)) and room_row != 0:
			var room := _room_of_row(room_row)
			if room == null:
				continue
			box.room = room
			for key in room.state.get("run_members", {}):
				var info: Dictionary = room.state["run_members"][key]
				box.members[key] = {"account_id": int(info["account_id"]), "nick": str(info["nick"])}
		else:
			var owner := int(row.get("owner_account_id", 0)) if row.get("owner_account_id") != null else 0
			if owner == 0:
				continue
			box.members["p1"] = {"account_id": owner, "nick": ""}
		if box.members.is_empty():
			continue
		for key in box.members:
			_runs_by_account[int(box.members[key]["account_id"])] = box
	_log("restored rooms=%d active_runs=%d" % [_rooms_by_code.size(), _runs_by_account.size()])


func _room_of_row(row_id: int) -> _Room:
	for code in _rooms_by_code:
		if _rooms_by_code[code].row_id == row_id:
			return _rooms_by_code[code]
	return null


func _build_instance(run: Dictionary) -> ExpeditionGame:
	var instance := ExpeditionGame.new()
	instance.run = _normalize_run(run)
	instance.rng.seed = int(run.get("rng_seed", 0))
	instance.rng.state = int(str(run.get("rng_state", "0")))
	return instance


## JSON 往返归一（镜像 ExpeditionGame.resume）：带入/消耗清单 int 化。
func _normalize_run(run: Dictionary) -> Dictionary:
	run["carried_from_farm"] = (run.get("carried_from_farm", []) as Array).map(func(v): return int(v))
	run["consumed"] = (run.get("consumed", []) as Array).map(func(v): return int(v))
	return run


var _rooms_by_code := {}   # code -> _Room
var _rooms_by_account := {}  # account_id -> _Room（等待中/进行中房间）
var _runs_by_account := {}  # account_id -> _RunBox（活动局，含单人）


# —— 登录/断线联动 ———————————————————————————————————————————————


## welcome 扩展（S05 核心）：账户在等待房间或活动局 → 附 room/run 供客户端恢复。
func attach_on_login(account_id: int, nick: String) -> Dictionary:
	var out := {}
	var room: _Room = _rooms_by_account.get(account_id)
	if room != null:
		for member in room.state.get("members", []):
			if int(member["account_id"]) == account_id:
				member["nick"] = nick
		out["room"] = room_view(room)
	var box: _RunBox = _runs_by_account.get(account_id)
	if box != null:
		if room == null and box.room != null:
			out["room"] = room_view(box.room)
		for key in box.members:
			if int(box.members[key]["account_id"]) == account_id:
				box.members[key]["nick"] = nick
		out["run"] = box.game.run
		out["version"] = box.version
	return out


## 断线：房间成员在线状态变化 → 推送房间视图（成员保留，重连可回）。
func notify_offline(account_id: int) -> void:
	var room: _Room = _rooms_by_account.get(account_id)
	if room != null:
		_broadcast_room(room)


# —— 命令入口 ——————————————————————————————————————————————————————


func is_expedition_op(op: String) -> bool:
	return op.begins_with("room.") or op.begins_with("run.")


func handle(account_id: int, nick: String, req_id: String, op: String, args: Dictionary) -> Dictionary:
	if req_id == "":
		return _req_err(req_id, op, OnlineProtocol.ERR_REQ_ID_REQUIRED)
	if not features.has(OnlineProtocol.FEATURE_EXPEDITION):
		return _req_err(req_id, op, OnlineProtocol.ERR_FEATURE_DISABLED)
	match op:
		"room.create": return _op_room_create(account_id, nick, req_id)
		"room.join": return _op_room_join(account_id, nick, req_id, args)
		"room.leave": return _op_room_leave(account_id, req_id)
		"room.ready": return _op_room_ready(account_id, req_id, args)
		"room.begin_depart": return _op_begin_depart(account_id, req_id)
		"run.depart_solo": return _op_depart_solo(account_id, req_id)
		"run.action": return _op_run_action(account_id, req_id, args)
	return _req_err(req_id, op, OnlineProtocol.ERR_UNKNOWN_OP)


## 收据去重前置检查（S02）：返回 {} 继续执行；{"duplicate":true,"result":…} 命中重放；
## {"error":信封} 同号异参冲突。
func _dedup_check(account_id: int, req_id: String, args: Dictionary) -> Dictionary:
	var digest := AuthService.sha256_hex(JSON.stringify(args))
	var receipt := store.query_one(
		"SELECT args_digest, result_json FROM receipts WHERE account_id = ? AND req_id = ?", [account_id, req_id]
	)
	if receipt.is_empty():
		return {}
	if str(receipt["args_digest"]) != digest:
		return {"error": _req_err(req_id, "", OnlineProtocol.ERR_REQ_ID_CONFLICT)}
	var replayed: Variant = JSON.parse_string(str(receipt["result_json"]))
	return {"duplicate": true, "result": replayed if replayed is Dictionary else {}}


# —— 房间生命周期（C01～C04） ————————————————————————————————————


func _op_room_create(account_id: int, nick: String, req_id: String) -> Dictionary:
	if _rooms_by_account.has(account_id):
		return _op_failed(req_id, "room.create", "已在房间中，先离开当前房间")
	if _runs_by_account.has(account_id):
		return _op_failed(req_id, "room.create", "已有进行中的探险，先完成或放弃")
	var occupied := _farm_occupied(account_id)
	if occupied != "":
		return _op_failed(req_id, "room.create", occupied)
	var room := _Room.new()
	room.code = _new_room_code()
	room.state = {
		"creator_account_id": account_id,
		"phase": "waiting",
		"run_id": "",
		"members": [{"account_id": account_id, "nick": nick, "ready": false}],
		"run_members": {},
	}
	var stamp := _now_string()
	var tx: Array = store.tx(func() -> bool:
		return store.exec(
			"INSERT INTO rooms(code, state, created_at, updated_at) VALUES(?, ?, ?, ?)",
			[room.code, JSON.stringify(room.state), stamp, stamp]
		)
	)
	if not bool(tx[0]):
		return _req_err(req_id, "room.create", OnlineProtocol.ERR_INTERNAL, "room_create_failed")
	var row := store.query_one("SELECT id FROM rooms WHERE code = ?", [room.code])
	if row.is_empty():
		return _req_err(req_id, "room.create", OnlineProtocol.ERR_INTERNAL, "room_create_failed")
	room.row_id = int(row["id"])
	_rooms_by_code[room.code] = room
	_rooms_by_account[account_id] = room
	return _req_ok(req_id, "room.create", {"code": room.code, "room": room_view(room)})


func _op_room_join(account_id: int, nick: String, req_id: String, args: Dictionary) -> Dictionary:
	var code := str(args.get("code", "")).strip_edges().to_upper()
	var room: _Room = _rooms_by_code.get(code)
	if code.length() != 6 or room == null:
		return _op_failed(req_id, "room.join", "房码无效或房间不存在")
	if _rooms_by_account.has(account_id):
		var current: _Room = _rooms_by_account[account_id]
		if current == room:
			return _op_failed(req_id, "room.join", "已在这个房间里")
		return _op_failed(req_id, "room.join", "已在其他房间，先离开再加入")
	if _runs_by_account.has(account_id):
		return _op_failed(req_id, "room.join", "已有进行中的探险，先完成或放弃")
	var occupied := _farm_occupied(account_id)
	if occupied != "":
		return _op_failed(req_id, "room.join", occupied)
	if str(room.state.get("phase", "")) != "waiting":
		return _op_failed(req_id, "room.join", "本局已开始，不能中途加入新玩家")
	if (room.state.get("members", []) as Array).size() >= 2:
		return _op_failed(req_id, "room.join", "房间已满（双人）")
	room.state["members"].append({"account_id": account_id, "nick": nick, "ready": false})
	if not _save_room(room):
		room.state["members"].pop_back()
		return _req_err(req_id, "room.join", OnlineProtocol.ERR_INTERNAL, "room_join_failed")
	_rooms_by_account[account_id] = room
	_broadcast_room(room)
	return _req_ok(req_id, "room.join", {"room": room_view(room)})


func _op_room_leave(account_id: int, req_id: String) -> Dictionary:
	var room: _Room = _rooms_by_account.get(account_id)
	if room == null:
		return _op_failed(req_id, "room.leave", "不在任何房间中")
	if str(room.state.get("phase", "")) == "running":
		## 进行中离房 = 个人放弃（结算本人；队友继续，2.6 语义）。
		var abandon := _op_run_action(account_id, req_id + ":abandon", {
			"kind": "abandon_member", "args": {},
		})
		if str(abandon.get("t", "")) == "req_err":
			return abandon
		_remove_member(room, account_id)
		return _req_ok(req_id, "room.leave", {"ok": true})
	_remove_member(room, account_id)
	_broadcast_room(room)
	return _req_ok(req_id, "room.leave", {"ok": true})


func _remove_member(room: _Room, account_id: int) -> void:
	var kept: Array = []
	for member in room.state.get("members", []):
		if int(member["account_id"]) != account_id:
			kept.append(member)
	room.state["members"] = kept
	_rooms_by_account.erase(account_id)
	if kept.is_empty():
		store.exec("DELETE FROM rooms WHERE id = ?", [room.row_id])
		_rooms_by_code.erase(room.code)
	elif int(room.state.get("creator_account_id", 0)) == account_id:
		## C04：创建者离开 → 移交给最早成员。
		room.state["creator_account_id"] = int(kept[0]["account_id"])
		_save_room(room)
		_broadcast_room(room)


func _op_room_ready(account_id: int, req_id: String, args: Dictionary) -> Dictionary:
	var room: _Room = _rooms_by_account.get(account_id)
	if room == null:
		return _op_failed(req_id, "room.ready", "不在任何房间中")
	if str(room.state.get("phase", "")) != "waiting":
		return _op_failed(req_id, "room.ready", "本局已开始")
	var ready := bool(args.get("ready", false))
	for member in room.state.get("members", []):
		if int(member["account_id"]) == account_id:
			member["ready"] = ready
	if not _save_room(room):
		return _req_err(req_id, "room.ready", OnlineProtocol.ERR_INTERNAL, "room_ready_failed")
	_broadcast_room(room)
	return _req_ok(req_id, "room.ready", {"room": room_view(room)})


func _save_room(room: _Room) -> bool:
	return store.exec(
		"UPDATE rooms SET state = ?, updated_at = ? WHERE id = ?",
		[JSON.stringify(room.state), _now_string(), room.row_id]
	)


func _new_room_code() -> String:
	var alphabet := AuthService.CODE_ALPHABET
	for attempt in range(64):
		var bytes := Crypto.new().generate_random_bytes(6)
		var code := ""
		for b in bytes:
			code += alphabet[b % alphabet.length()]
		if not _rooms_by_code.has(code) and store.query_one("SELECT id FROM rooms WHERE code = ?", [code]).is_empty():
			return code
	return "R%06d" % (int(Time.get_unix_time_from_system()) % 1000000)


func room_view(room: _Room) -> Dictionary:
	var members: Array = []
	for member in room.state.get("members", []):
		var account := int(member["account_id"])
		members.append({
			"account_id": account,
			"nick": str(member.get("nick", "?")),
			"ready": bool(member.get("ready", false)),
			"online": auth.has_session(account),
		})
	return {
		"code": room.code,
		"phase": str(room.state.get("phase", "waiting")),
		"creator_account_id": int(room.state.get("creator_account_id", 0)),
		"run_id": str(room.state.get("run_id", "")),
		"members": members,
	}


# —— 出发事务（S01） ——————————————————————————————————————————————


## 账户农场占用检查（DB 为准）：返回空串=可出发。
func _farm_occupied(account_id: int) -> String:
	var row := store.query_one("SELECT farm_state FROM accounts WHERE id = ?", [account_id])
	if row.is_empty():
		return "账户不可用"
	var farm := _load_farm(str(row["farm_state"]))
	if farm == null:
		return "账户状态读取失败"
	return ExpeditionGame.depart_check(farm)


func _op_depart_solo(account_id: int, req_id: String) -> Dictionary:
	var dedup := _dedup_check(account_id, req_id, {})
	if dedup.has("error"):
		return dedup["error"]
	if not dedup.is_empty():
		return _req_ok(req_id, "run.depart_solo", dedup["result"], true)
	if _rooms_by_account.has(account_id):
		return _op_failed(req_id, "run.depart_solo", "已在房间中，先离开房间再单独出发")
	if _runs_by_account.has(account_id):
		return _op_failed(req_id, "run.depart_solo", "已有进行中的探险")
	var problem := _farm_occupied(account_id)
	if problem != "":
		return _op_failed(req_id, "run.depart_solo", problem)
	var run_id := ExpeditionStore.new_run_id()
	var env := {"reply": null, "req_id": req_id, "account_id": account_id}
	var tx: Array = store.tx(func() -> bool:
		return _build_depart([account_id], {}, run_id, false, ["", ""], null, env)
	)
	return _finish_depart(tx, env, req_id, "run.depart_solo", null, run_id)


func _op_begin_depart(account_id: int, req_id: String) -> Dictionary:
	var dedup := _dedup_check(account_id, req_id, {})
	if dedup.has("error"):
		return dedup["error"]
	if not dedup.is_empty():
		return _req_ok(req_id, "room.begin_depart", dedup["result"], true)
	var room: _Room = _rooms_by_account.get(account_id)
	if room == null:
		return _op_failed(req_id, "room.begin_depart", "不在任何房间中")
	if int(room.state.get("creator_account_id", 0)) != account_id:
		return _op_failed(req_id, "room.begin_depart", "只有房间创建者可以发起出发")
	if str(room.state.get("phase", "")) != "waiting":
		return _op_failed(req_id, "room.begin_depart", "本局已开始")
	var members: Array = room.state.get("members", [])
	if members.size() < 2:
		return _op_failed(req_id, "room.begin_depart", "队友尚未加入房间")
	for member in members:
		if not bool(member.get("ready", false)):
			return _op_failed(req_id, "room.begin_depart", "还有成员未准备（%s）" % str(member.get("nick", "?")))
	var run_id := ExpeditionStore.new_run_id()
	var env := {"reply": null, "req_id": req_id, "account_id": account_id}
	var room_ref := room
	var guest_id := int(members[1]["account_id"])
	var guest_nick := str(members[1].get("nick", "队友"))
	var creator_id := int(members[0]["account_id"])
	var creator_nick := str(members[0].get("nick", "房主"))
	var tx: Array = store.tx(func() -> bool:
		var guest_farm := _load_account_farm(guest_id)
		if guest_farm == null:
			env["reply"] = {"kind": "internal"}
			return false
		var profile := _guest_profile(guest_farm, guest_nick)
		var labels := ["", "队友（%s）：" % guest_nick]
		var built := _build_depart([creator_id, guest_id], profile, run_id, true, labels, room_ref.row_id, env)
		if built and env["reply"] != null and str((env["reply"] as Dictionary).get("kind", "")) == "ok":
			room_ref.state["run_members"] = {
				"p1": {"account_id": creator_id, "nick": creator_nick},
				"p2": {"account_id": guest_id, "nick": guest_nick},
			}
			room_ref.state["phase"] = "running"
			room_ref.state["run_id"] = run_id
			if not _save_room(room_ref):
				env["reply"] = {"kind": "internal"}
				return false
		return built
	)
	return _finish_depart(tx, env, req_id, "room.begin_depart", room, run_id)


## 出发事务主体：候选装载 → 逐成员校验 → compose_run → 占用 → INSERT runs →
## UPDATE accounts → 收据。规则失败=空事务提交（op_failed）；DB 失败=false 回滚。
func _build_depart(account_ids: Array, guest_profile: Dictionary, run_id: String, coop: bool, labels: Array, room_row: Variant, env: Dictionary) -> bool:
	var candidates := {}  # account_id -> {farm, seq}
	for account_id in account_ids:
		var row := store.query_one("SELECT farm_state, farm_seq FROM accounts WHERE id = ?", [account_id])
		if row.is_empty():
			env["reply"] = {"kind": "internal"}
			return false
		var farm := _load_farm(str(row["farm_state"]))
		if farm == null:
			env["reply"] = {"kind": "internal"}
			return false
		candidates[int(account_id)] = {"farm": farm, "seq": int(row["farm_seq"])}
	var p1: FarmGame = candidates[int(account_ids[0])]["farm"]
	var preview := InventoryGame.new()
	preview.bind(p1.state["expedition"])
	var totals: Dictionary = preview.deck_preview()["totals"]
	var log_line := "出发：生命 %d/%d，携带牌 %d 张" % [
		ExpeditionBaseline.MAX_HP, ExpeditionBaseline.MAX_HP,
		int(totals[1]) + int(totals[2]) + int(totals[3]),
	]
	if coop:
		log_line = "双人出发：主机与 %s" % str(guest_profile.get("name", "队友"))
	for index in range(account_ids.size()):
		var problem := ExpeditionGame.depart_check(candidates[int(account_ids[index])]["farm"])
		if problem != "":
			var prefix := str(labels[index]) if index < labels.size() else ""
			env["reply"] = {"kind": "op_failed", "msg": prefix + problem}
			return true
	var run := ExpeditionGame.compose_run(p1, guest_profile, run_id, now(), coop, log_line)
	## 占用各候选（depart_check 已确认未占用）。
	for account_id in account_ids:
		var farm: FarmGame = candidates[int(account_id)]["farm"]
		var inventory := InventoryGame.new()
		inventory.bind(farm.state["expedition"])
		if not inventory.set_run_occupied(run_id)["ok"]:
			env["reply"] = {"kind": "op_failed", "msg": "写入占用失败"}
			return true
		farm.state["expedition"]["active_run_ref"] = run_id
	if not store.exec(
		"INSERT INTO runs(run_id, room_id, owner_account_id, state, version, updated_at) VALUES(?, ?, ?, ?, 1, ?)",
		[run_id, room_row, int(account_ids[0]), JSON.stringify(run), _now_string()]
	):
		env["reply"] = {"kind": "internal"}
		return false
	for account_id in candidates:
		var entry: Dictionary = candidates[int(account_id)]
		if not store.exec(
			"UPDATE accounts SET farm_state = ?, farm_seq = ? WHERE id = ?",
			[JSON.stringify(entry["farm"].state), entry["seq"] + 1, int(account_id)]
		):
			env["reply"] = {"kind": "internal"}
			return false
	var result_json := JSON.stringify({"run_id": run_id, "run": run, "version": 1})
	if not store.exec(
		"INSERT INTO receipts(account_id, req_id, op, args_digest, outcome, result_json, farm_seq, created_at) " +
		"VALUES(?, ?, 'run.depart', ?, 'ok', ?, 0, ?)",
		[int(account_ids[0]), _receipt_req_id(env), AuthService.sha256_hex("{}"), result_json, _now_string()]
	):
		env["reply"] = {"kind": "internal"}
		return false
	env["reply"] = {"kind": "ok", "run": run, "candidates": candidates}
	return true


func _finish_depart(tx: Array, env: Dictionary, req_id: String, op: String, room: _Room, run_id: String) -> Dictionary:
	if not bool(tx[0]):
		return _req_err(req_id, op, OnlineProtocol.ERR_INTERNAL, "depart_tx_failed")
	var reply: Dictionary = env["reply"]
	if reply == null:
		return _req_err(req_id, op, OnlineProtocol.ERR_INTERNAL, "depart_failed")
	if str(reply.get("kind", "")) == "internal":
		return _req_err(req_id, op, OnlineProtocol.ERR_INTERNAL, "depart_internal")
	if str(reply.get("kind", "")) != "ok":
		return _op_failed(req_id, op, str(reply.get("msg", "出发失败")))
	## 提交成功：换入内存态。
	var candidates: Dictionary = reply["candidates"]
	for account_id in candidates:
		farm_service.evict(int(account_id))
	var box := _RunBox.new()
	box.run_id = run_id
	box.room = room
	box.version = 1
	box.game = _build_instance((reply["run"] as Dictionary).duplicate(true))
	if room != null:
		for key in room.state.get("run_members", {}):
			var info: Dictionary = room.state["run_members"][key]
			box.members[key] = {"account_id": int(info["account_id"]), "nick": str(info["nick"])}
	else:
		box.members["p1"] = {"account_id": int(_receipt_account(env)), "nick": ""}
	for key in box.members:
		_runs_by_account[int(box.members[key]["account_id"])] = box
	if room != null:
		_broadcast_room(room)
		_broadcast_run(box)
	else:
		var peer := auth.peer_of_account(int(_receipt_account(env)))
		if peer != 0 and send.is_valid():
			send.call(peer, _push("run", {"run": box.game.run, "version": box.version}))
	var result := {"run": box.game.run, "version": box.version}
	if room != null:
		result["room"] = room_view(room)
	return _req_ok(req_id, op, result)


func _guest_profile(farm: FarmGame, nick: String) -> Dictionary:
	var expedition: Dictionary = farm.state["expedition"]
	var inventory := InventoryGame.new()
	inventory.bind(expedition)
	var carried: Array = []
	for container in ExpeditionBaseline.CONTAINERS:
		for instance in inventory.loadout_list(container):
			carried.append(int(instance["instance_id"]))
	return {
		"name": nick,
		"player_id": str(expedition.get("player_id", "")),
		"next_instance_id": int(expedition.get("next_instance_id", 1000)),
		"container_levels": (expedition.get("crafting", {}).get("upgrade_levels", {}) as Dictionary).duplicate(true),
		"loadout": ((expedition.get("inventory", {}) as Dictionary).get("loadout", {}) as Dictionary).duplicate(true),
		"carried": carried,
		"hp": ExpeditionBaseline.MAX_HP,
	}


# —— 局内动作裁定（C06/C07）与结算（S03） ————————————————————————


func _op_run_action(account_id: int, req_id: String, args: Dictionary) -> Dictionary:
	_staged_settlements = {}
	var dedup := _dedup_check(account_id, req_id, args)
	if dedup.has("error"):
		return dedup["error"]
	if not dedup.is_empty():
		return _req_ok(req_id, "run.action", dedup["result"], true)
	var box: _RunBox = _runs_by_account.get(account_id)
	if box == null:
		return _op_failed(req_id, "run.action", "没有进行中的探险")
	var member_key := ""
	for key in box.members:
		if int(box.members[key]["account_id"]) == account_id:
			member_key = key
	if member_key == "":
		return _op_failed(req_id, "run.action", "你不是本局成员")
	var coop := bool(box.game.run.get("coop", false))
	if coop:
		for key in box.members:
			if not auth.has_session(int(box.members[key]["account_id"])):
				return _op_failed(req_id, "run.action", "有成员掉线：本局暂停推进，等待重连（不判撤离也不判失败）")
	var kind := str(args.get("kind", ""))
	var action_args: Dictionary = args.get("args", {}) if args.get("args") is Dictionary else {}
	var env := {"reply": null, "req_id": req_id, "account_id": account_id, "member_key": member_key}
	var box_ref := box
	var tx: Array = store.tx(func() -> bool:
		return _arbitrate_action(box_ref, kind, action_args, env)
	)
	if not bool(tx[0]):
		return _req_err(req_id, "run.action", OnlineProtocol.ERR_INTERNAL, "action_tx_failed")
	var reply: Dictionary = env["reply"]
	if reply == null:
		return _req_err(req_id, "run.action", OnlineProtocol.ERR_INTERNAL, "action_failed")
	match str(reply.get("kind", "")):
		"internal":
			return _req_err(req_id, "run.action", OnlineProtocol.ERR_INTERNAL, "action_internal")
		"op_failed":
			return _op_failed(req_id, "run.action", str(reply.get("msg", "操作失败")))
	# 提交成功：换入内存态 + 推送 + 农场缓存失效。
	var result: Dictionary = reply["result"]
	var new_run: Dictionary = reply["run"]
	var settlements: Dictionary = reply.get("settlements", {})
	var dirty: Array = reply.get("dirty", [])
	box_ref.game = _build_instance(new_run.duplicate(true))
	box_ref.version += 1
	for account_id_ in dirty:
		farm_service.evict(int(account_id_))
	_broadcast_run(box_ref)
	for key in settlements:
		var holder: Dictionary = box_ref.members.get(key, {})
		var peer := auth.peer_of_account(int(holder.get("account_id", 0)))
		if peer != 0 and send.is_valid():
			send.call(peer, _push("settlement", {"settlement": settlements[key]}))
	if str(new_run.get("outcome", "")) != "":
		_finish_run(box_ref)
	var extras := {"run": box_ref.game.run, "version": box_ref.version}
	if dirty.has(account_id):
		extras["snapshot"] = _farm_snapshot(account_id)
	return _req_ok_extra(req_id, "run.action", _sanitize(result), false, extras)


## 候选副本上的动作执行（事务内）：规则失败=空事务提交；成功=结算/局态/农场/收据同事务落库。
func _arbitrate_action(box: _RunBox, kind: String, args: Dictionary, env: Dictionary) -> bool:
	var candidate_run: Dictionary = box.game.run.duplicate(true)
	var instance := _build_instance(candidate_run)
	var p1_account := int(box.members["p1"]["account_id"])
	var p1_farm := _load_account_farm(p1_account)
	if p1_farm == null:
		env["reply"] = {"kind": "internal"}
		return false
	instance.game = p1_farm
	var dirty := {p1_account: p1_farm}
	var coop := bool(candidate_run.get("coop", false))
	if coop:
		var p2_farm := _load_account_farm(int(box.members["p2"]["account_id"]))
		if p2_farm == null:
			env["reply"] = {"kind": "internal"}
			return false
		instance.guest_farm = p2_farm
		instance.apply_guest_too = true
		dirty[int(box.members["p2"]["account_id"])] = p2_farm
	var member_key := str(env["member_key"])
	var result := _dispatch_action(instance, member_key, kind, args)
	if not bool(result.get("ok", false)):
		env["reply"] = {"kind": "op_failed", "msg": str(result.get("reason", "操作失败"))}
		return true
	var settlements := {}
	if result.has("settlement"):
		settlements[member_key] = result["settlement"]
	if result.has("settlements"):
		settlements = result["settlements"]
	var run_over := str(candidate_run.get("outcome", "")) != ""
	if run_over and coop and not settlements.has("p2") and _member_unsettled(instance.guest_farm, box.run_id):
		## 规则层语义：房主个人放弃会把局标记为 over（`_settle_one_member` 恒置 outcome），
		## 只结算本人。服务器无法依赖"客机自行处理"（离线路径），未结算成员的农场会悬空占用——
		## 为其补一份放弃结算（R1 计划 §9 风险表"占用不得静默悬空"的服务器侧落点）。
		var extra: Dictionary = instance.abandon_member("p2")
		if bool(extra.get("ok", false)) and extra.has("settlement"):
			settlements["p2"] = extra["settlement"]
			result["settlements"] = settlements
	if not _flush_staged_settlements():
		env["reply"] = {"kind": "internal"}
		return false
	var run_row := store.query_one("SELECT version FROM runs WHERE run_id = ?", [box.run_id])
	if run_row.is_empty():
		env["reply"] = {"kind": "internal"}
		return false
	if not store.exec(
		"UPDATE runs SET state = ?, version = ?, updated_at = ? WHERE run_id = ?",
		[JSON.stringify(candidate_run), int(run_row["version"]) + 1, _now_string(), box.run_id]
	):
		env["reply"] = {"kind": "internal"}
		return false
	var touched: Array = []
	if not settlements.is_empty() or run_over:
		for account_id in dirty:
			if not _update_farm_row(int(account_id), dirty[account_id]):
				env["reply"] = {"kind": "internal"}
				return false
			touched.append(int(account_id))
	if not store.exec(
		"INSERT INTO receipts(account_id, req_id, op, args_digest, outcome, result_json, farm_seq, created_at) " +
		"VALUES(?, ?, 'run.action', ?, 'ok', ?, 0, ?)",
		[int(env["account_id"]), str(env["req_id"]), AuthService.sha256_hex(JSON.stringify({"kind": kind, "args": args})), JSON.stringify(_sanitize(result)), _now_string()]
	):
		env["reply"] = {"kind": "internal"}
		return false
	env["reply"] = {
		"kind": "ok", "result": result, "run": candidate_run,
		"settlements": settlements, "dirty": touched,
	}
	return true


func _flush_staged_settlements() -> bool:
	var stamp := _now_string()
	for sid in _staged_settlements:
		var settlement: Dictionary = _staged_settlements[sid]
		if not store.exec(
			"INSERT INTO settlements(settlement_id, run_id, account_id, state, created_at) " +
			"VALUES(?, ?, 0, ?, ?) ON CONFLICT(settlement_id) DO UPDATE SET state = excluded.state",
			[sid, str(settlement.get("run_id", "")), JSON.stringify(settlement), stamp]
		):
			return false
	_staged_settlements = {}
	return true


## 该成员对本局是否还没有已应用的结算（防重复补结算）。
func _member_unsettled(farm: FarmGame, run_id: String) -> bool:
	if farm == null:
		return false
	var applied: Array = farm.state["expedition"].get("applied_settlements", [])
	for row in store.query_all("SELECT settlement_id FROM settlements WHERE run_id = ?", [run_id]):
		if applied.has(str(row["settlement_id"])):
			return false
	return true


## 局终收尾：清房间与内存映射；推送 room over。
func _finish_run(box: _RunBox) -> void:
	for key in box.members:
		_runs_by_account.erase(int(box.members[key]["account_id"]))
	if box.room != null:
		var room := box.room
		var members: Array = room.state.get("members", [])
		for member in members:
			_rooms_by_account.erase(int(member["account_id"]))
		store.exec("DELETE FROM rooms WHERE id = ?", [room.row_id])
		_rooms_by_code.erase(room.code)
		for member in members:
			var peer := auth.peer_of_account(int(member["account_id"]))
			if peer != 0 and send.is_valid():
				send.call(peer, _push("room", {
					"room": {"code": room.code, "phase": "over", "run_id": box.run_id, "members": []},
				}))


# —— 动作分发（对齐 session_host._execute_action + 单人直通） ——————————————


func _dispatch_action(instance: ExpeditionGame, member_key: String, kind: String, args: Dictionary) -> Dictionary:
	var run: Dictionary = instance.run
	var coop := bool(run.get("coop", false))
	match kind:
		"vote_move":
			if not coop:
				return instance.move_to(int(args.get("row", -1)), int(args.get("col", -1)))
			return instance.vote_move(member_key, int(args.get("row", -1)), int(args.get("col", -1)))
		"move_to":
			if coop:
				return {"ok": false, "reason": "合作局请使用共同投票选路"}
			return instance.move_to(int(args.get("row", -1)), int(args.get("col", -1)))
		"start_battle":
			return instance.start_battle()
		"play_card":
			var combat := instance.restore_battle()
			if combat == null:
				return {"ok": false, "reason": "没有进行中的战斗"}
			var r := combat.play_card(member_key, int(args.get("uid", -1)), str(args.get("target", "")))
			run["battle"] = combat.to_dict()
			instance.save()
			return r
		"end_turn":
			var combat := instance.restore_battle()
			if combat == null:
				return {"ok": false, "reason": "没有进行中的战斗"}
			var r := combat.end_turn(member_key)
			run["battle"] = combat.to_dict()
			instance.save()
			return r
		"finish_battle":
			var combat := instance.restore_battle()
			if combat == null:
				return {"ok": false, "reason": "没有进行中的战斗"}
			return instance.finish_battle(combat)
		"claim_reward":
			return instance.loot_action(member_key, "claim_reward", args)
		"claim_public":
			return instance.loot_action(member_key, "claim_public", args)
		"pick_drop":
			return instance.loot_action(member_key, "pick_drop", args)
		"loot_manage":
			return instance.loot_action(member_key, "loot_manage", args)
		"take_rest":
			return instance.take_rest(str(args.get("option", "")))
		"choose_event":
			return instance.choose_event(str(args.get("option", "")))
		"leave_node":
			return instance.leave_node()
		"vote_extract":
			if not coop:
				return instance.extract()
			return instance.vote_extract(member_key, bool(args.get("agree", true)))
		"extract":
			if coop:
				return {"ok": false, "reason": "合作局撤离需两人确认"}
			return instance.extract()
		"share_offer":
			return instance.share_offer(member_key, int(args.get("instance_id", 0)))
		"share_accept":
			return instance.share_accept(member_key, str(args.get("container", "pack")))
		"share_cancel":
			return instance.share_cancel()
		"signal":
			instance.run["log"].append("%s：%s" % [instance.member(member_key)["name"], str(args.get("text", ""))])
			instance.save()
			return {"ok": true}
		"abandon":
			if coop:
				return instance.abandon_member(member_key)
			return instance.abandon()
		"abandon_member":
			return instance.abandon_member(member_key)
	return {"ok": false, "reason": "未知动作：%s" % kind}


# —— 推送与视图 ——————————————————————————————————————————————————


func _push(kind: String, payload: Dictionary) -> Dictionary:
	var out := {"t": "push", "kind": kind}
	for key in payload:
		out[key] = payload[key]
	return out


func _broadcast_room(room: _Room) -> void:
	if not send.is_valid():
		return
	var view := room_view(room)
	for member in room.state.get("members", []):
		var peer := auth.peer_of_account(int(member["account_id"]))
		if peer != 0:
			send.call(peer, _push("room", {"room": view}))


func _broadcast_run(box: _RunBox) -> void:
	if not send.is_valid():
		return
	var payload := _push("run", {"run": box.game.run, "version": box.version})
	for key in box.members:
		var peer := auth.peer_of_account(int(box.members[key]["account_id"]))
		if peer != 0:
			send.call(peer, payload)


# —— 农场候选读写 ————————————————————————————————————————————————


func _load_farm(state_json: String) -> FarmGame:
	var parsed: Variant = JSON.parse_string(state_json)
	if not (parsed is Dictionary):
		return null
	var farm := FarmGame.new()
	if not farm.load_state(parsed):
		return null
	return farm


func _load_account_farm(account_id: int) -> FarmGame:
	var row := store.query_one("SELECT farm_state FROM accounts WHERE id = ?", [account_id])
	if row.is_empty():
		return null
	return _load_farm(str(row["farm_state"]))


func _update_farm_row(account_id: int, farm: FarmGame) -> bool:
	var row := store.query_one("SELECT farm_seq FROM accounts WHERE id = ?", [account_id])
	if row.is_empty():
		return false
	return store.exec(
		"UPDATE accounts SET farm_state = ?, farm_seq = ? WHERE id = ?",
		[JSON.stringify(farm.state), int(row["farm_seq"]) + 1, account_id]
	)


func _farm_snapshot(account_id: int) -> Dictionary:
	var row := store.query_one("SELECT farm_state, farm_seq FROM accounts WHERE id = ?", [account_id])
	if row.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(str(row["farm_state"]))
	return {"farm": parsed if parsed is Dictionary else {}, "farm_seq": int(row["farm_seq"])}


# —— 应答助手（信封与 FarmService 一致） ————————————————————————————


func _receipt_req_id(env: Dictionary) -> String:
	return str(env.get("req_id", ""))


func _receipt_account(env: Dictionary) -> int:
	return int(env.get("account_id", 0))


func _req_ok(req_id: String, op: String, result: Variant, duplicate := false) -> Dictionary:
	return _req_ok_extra(req_id, op, result, duplicate, {})


func _req_ok_extra(req_id: String, op: String, result: Variant, duplicate: bool, extras: Dictionary) -> Dictionary:
	var payload := {
		"t": "req_ok", "req_id": req_id, "op": op, "duplicate": duplicate,
		"result": result, "farm_seq": 0, "server_now": now(),
	}
	for key in extras:
		payload[key] = extras[key]
	return payload


func _op_failed(req_id: String, op: String, msg: String) -> Dictionary:
	return _req_err(req_id, op, OnlineProtocol.ERR_OP_FAILED, msg)


func _req_err(req_id: String, op: String, code: String, msg := "") -> Dictionary:
	var payload := {"t": "req_err", "req_id": req_id, "op": op, "code": code, "server_now": now()}
	if msg != "":
		payload["msg"] = msg
	return payload


## 结果里可能带 CombatGame 对象（start_battle）：进 JSON 前剥离（战斗状态在 run.battle）。
func _sanitize(result: Dictionary) -> Dictionary:
	var out := result.duplicate(true)
	out.erase("combat")
	out.erase("game")
	return out


func _now_string() -> String:
	return Time.get_datetime_string_from_system(true)


func _log(line: String) -> void:
	print("[rooms] %s" % line)
