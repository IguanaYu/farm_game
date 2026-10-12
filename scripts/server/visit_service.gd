class_name VisitService
extends RefCounted
## R7 邻里拜访服务（计划：docs/plan/Godot_合并路线_R7_拜访系统_代码执行计划_v0.1.md §3）。
## 地址簿（visit.list）与家园快照（visit.snapshot）保持只读：纯 SELECT，不写库、不产生收据。
## R8 好友互助扩展（docs/plan/Godot_好友互助浇水施肥_代码执行计划_v0.1.md）：visit.water/
## visit.fertilize 是本服务唯一的写路径——一个事务同时动主人农场（浇水/施肥生效、好友加成
## 记录）与帮助者农场（扣自己的肥料、加通用经验），照 room_service 双账户事务先例实现，
## 提交后 evict 双方写穿缓存。访客仍不可收获/消费/买卖主人的任何资产（红线不变）。
## 首版口径：封闭试玩池内所有账户互为邻里，家园开放由服务器全局开关（--visits-closed 关闭）。

var store: ServerDB
var auth: AuthService
var features: Array = []
var visits_open := true
## R8：提交后 evict 双方缓存 + 复用 farm_service.now()（含 --dev-time-shift，判定时钟与 farm.* 一致）。
var farm_service: FarmService


func is_visit_op(op: String) -> bool:
	return op.begins_with("visit.")


func handle(account_id: int, req_id: String, op: String, args: Dictionary) -> Dictionary:
	if req_id == "":
		return _req_err(req_id, op, OnlineProtocol.ERR_REQ_ID_REQUIRED)
	if not features.has(OnlineProtocol.FEATURE_VISIT):
		return _req_err(req_id, op, OnlineProtocol.ERR_FEATURE_DISABLED)
	match op:
		"visit.list":
			return _op_list(account_id, req_id)
		"visit.snapshot":
			return _op_snapshot(account_id, req_id, args)
		"visit.water", "visit.fertilize":
			if not features.has(OnlineProtocol.FEATURE_VISIT_HELP):
				return _req_err(req_id, op, OnlineProtocol.ERR_FEATURE_DISABLED)
			return _op_help(account_id, req_id, op, args)
	return _req_err(req_id, op, OnlineProtocol.ERR_UNKNOWN_OP)


## 地址簿：除自己外全部账户（试玩池 ≤10，全量下发；分页留真实需求）。
func _op_list(account_id: int, req_id: String) -> Dictionary:
	var neighbors: Array = []
	for row in store.query_all(
		"SELECT id, nick FROM accounts WHERE disabled = 0 AND id != ? ORDER BY nick", [account_id]
	):
		var nid := int(row["id"])
		neighbors.append({
			"account_id": nid,
			"nick": str(row["nick"]),
			"online": auth.has_session(nid),
			"visits_open": visits_open,
		})
	return _req_ok(req_id, "visit.list", {"neighbors": neighbors, "visits_open": visits_open})


## 家园快照：只读 farm_state；未开放/账户不存在给出原因（设计稿 §7 四态之读取失败路径）。
func _op_snapshot(account_id: int, req_id: String, args: Dictionary) -> Dictionary:
	if not visits_open:
		return _req_err(req_id, "visit.snapshot", OnlineProtocol.ERR_OP_FAILED, "visit_closed：主人暂未开放参观")
	var target := int(args.get("account_id", 0)) if args.get("account_id") is float or args.get("account_id") is int else 0
	if target <= 0 or target == account_id:
		return _req_err(req_id, "visit.snapshot", OnlineProtocol.ERR_OP_FAILED, "account_missing：要拜访的邻居不存在")
	var row := store.query_one("SELECT nick, farm_state FROM accounts WHERE id = ? AND disabled = 0", [target])
	if row.is_empty():
		return _req_err(req_id, "visit.snapshot", OnlineProtocol.ERR_OP_FAILED, "account_missing：要拜访的邻居不存在")
	var parsed: Variant = JSON.parse_string(str(row["farm_state"]))
	if not (parsed is Dictionary):
		return _req_err(req_id, "visit.snapshot", OnlineProtocol.ERR_INTERNAL, "snapshot_broken")
	return _req_ok(req_id, "visit.snapshot", {
		"owner": {"account_id": target, "nick": str(row["nick"]),
			"online": auth.has_session(target), "appearance": "default",
			"roof_color": "#b9785c", "welcome_message": "",
			"snapshot_read_at": int(Time.get_unix_time_from_system())},
		"farm": parsed,
	})


func _req_ok(req_id: String, op: String, result: Variant) -> Dictionary:
	return {
		"t": "req_ok", "req_id": req_id, "op": op, "duplicate": false,
		"result": result, "farm_seq": 0, "server_now": int(Time.get_unix_time_from_system()),
	}


# —— R8 好友互助写路径 ——————————————————————————————————————————————


## visit.water / visit.fertilize 统一入口。收据记在帮助者名下（同 run.action 口径），
## 重放只回放结果不再执行；应答带帮助者自己的农场快照（客户端桥接自动回灌）。
func _op_help(helper_id: int, req_id: String, op: String, args: Dictionary) -> Dictionary:
	if not visits_open:
		return _req_err(req_id, op, OnlineProtocol.ERR_OP_FAILED, "visit_closed：主人暂未开放参观")
	var owner_id := int(args.get("owner_id", 0)) if args.get("owner_id") is float or args.get("owner_id") is int else 0
	var plot_id := int(args.get("plot_id", 0)) if args.get("plot_id") is float or args.get("plot_id") is int else 0
	var kind := str(args.get("kind", ""))
	if owner_id <= 0 or owner_id == helper_id:
		return _req_err(req_id, op, OnlineProtocol.ERR_OP_FAILED, "account_missing：要拜访的邻居不存在")
	if plot_id < 1 or plot_id > FarmGame.MAX_PLOTS:
		return _req_err(req_id, op, OnlineProtocol.ERR_OP_FAILED, "plot_missing：要照料的地块不存在")
	var digest := AuthService.sha256_hex(JSON.stringify(args))
	var receipt := store.query_one(
		"SELECT args_digest, result_json FROM receipts WHERE account_id = ? AND req_id = ?", [helper_id, req_id]
	)
	if not receipt.is_empty():
		if str(receipt["args_digest"]) != digest:
			return _req_err(req_id, op, OnlineProtocol.ERR_REQ_ID_CONFLICT)
		var replayed: Variant = JSON.parse_string(str(receipt["result_json"]))
		var replay_result: Dictionary = replayed if replayed is Dictionary else {}
		return _help_ok(req_id, op, replay_result, true, _farm_snapshot(helper_id))
	var helper_nick := str(auth.nick_of(helper_id))
	var env := {"reply": null, "req_id": req_id, "digest": digest}
	var tx: Array = store.tx(func() -> bool:
		return _arbitrate_help(helper_id, owner_id, op, plot_id, kind, helper_nick, env)
	)
	if not bool(tx[0]):
		return _req_err(req_id, op, OnlineProtocol.ERR_INTERNAL, "help_tx_failed")
	var reply: Dictionary = env["reply"]
	if reply == null:
		return _req_err(req_id, op, OnlineProtocol.ERR_INTERNAL, "help_failed")
	match str(reply.get("kind", "")):
		"internal":
			return _req_err(req_id, op, OnlineProtocol.ERR_INTERNAL, "help_internal")
		"op_failed":
			return _req_err(req_id, op, OnlineProtocol.ERR_OP_FAILED, str(reply.get("msg", "帮助失败")))
	# 提交成功：双账户写穿缓存失效（主人在线时其内存副本已过期，重载即见好友的帮助）。
	farm_service.evict(helper_id)
	farm_service.evict(owner_id)
	return _help_ok(req_id, op, reply["result"], false, _farm_snapshot(helper_id))


## 事务主体：装载双方候选 → 帮助者侧扣库存 → 主人侧生效 → 双行 UPDATE + 收据。
## 规则失败=空事务提交（op_failed）；DB 失败=false 回滚。
func _arbitrate_help(helper_id: int, owner_id: int, op: String, plot_id: int, kind: String, helper_nick: String, env: Dictionary) -> bool:
	var owner_row := store.query_one("SELECT farm_state, farm_seq FROM accounts WHERE id = ? AND disabled = 0", [owner_id])
	if owner_row.is_empty():
		env["reply"] = {"kind": "op_failed", "msg": "account_missing：要拜访的邻居不存在"}
		return true
	var helper_row := store.query_one("SELECT farm_state, farm_seq FROM accounts WHERE id = ?", [helper_id])
	if helper_row.is_empty():
		env["reply"] = {"kind": "internal"}
		return false
	var owner_farm := _load_farm(str(owner_row["farm_state"]))
	var helper_farm := _load_farm(str(helper_row["farm_state"]))
	if owner_farm == null or helper_farm == null:
		env["reply"] = {"kind": "internal"}
		return false
	if op == "visit.fertilize":
		var spend: Dictionary = helper_farm.spend_fertilizer_for_help(kind)
		if not bool(spend.get("ok", false)):
			env["reply"] = {"kind": "op_failed", "msg": str(spend.get("message", "帮助失败"))}
			return true
	var applied: Dictionary
	if op == "visit.water":
		applied = owner_farm.water_help(plot_id, helper_id, helper_nick, int(helper_farm.state["can_level"]), farm_service.now())
	else:
		applied = owner_farm.fertilize_help(plot_id, kind, helper_id, helper_nick, farm_service.now())
	if not bool(applied.get("ok", false)):
		env["reply"] = {"kind": "op_failed", "msg": str(applied.get("message", "帮助失败"))}
		return true
	helper_farm.grant_help_exp(int(applied.get("exp", 0)))
	var result := {
		"owner_id": owner_id,
		"plot_id": plot_id,
		"watered": applied.get("watered", []),
		"upgraded": applied.get("upgraded", []),
		"skipped": applied.get("skipped", []),
		"exp": int(applied.get("exp", 0)),
		"plots": applied.get("plots", []),
		"fertilizer": applied.get("fertilizer", {}),
	}
	var helper_seq := int(helper_row["farm_seq"]) + 1
	for entry in [
		{"id": owner_id, "farm": owner_farm, "seq": int(owner_row["farm_seq"]) + 1},
		{"id": helper_id, "farm": helper_farm, "seq": helper_seq},
	]:
		if not store.exec(
			"UPDATE accounts SET farm_state = ?, farm_seq = ? WHERE id = ?",
			[JSON.stringify(entry["farm"].state), entry["seq"], entry["id"]]
		):
			env["reply"] = {"kind": "internal"}
			return false
	if not store.exec(
		"INSERT INTO receipts(account_id, req_id, op, args_digest, outcome, result_json, farm_seq, created_at) " +
		"VALUES(?, ?, ?, ?, 'ok', ?, ?, ?)",
		[helper_id, str(env.get("req_id", "")), op, str(env.get("digest", "")), JSON.stringify(result), helper_seq, Time.get_datetime_string_from_system(true)]
	):
		env["reply"] = {"kind": "internal"}
		return false
	env["reply"] = {"kind": "ok", "result": result}
	return true


func _load_farm(state_json: String) -> FarmGame:
	var parsed: Variant = JSON.parse_string(state_json)
	if not (parsed is Dictionary):
		return null
	var farm := FarmGame.new()
	if not farm.load_state(parsed):
		return null
	return farm


func _farm_snapshot(account_id: int) -> Dictionary:
	var row := store.query_one("SELECT farm_state, farm_seq FROM accounts WHERE id = ?", [account_id])
	if row.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(str(row["farm_state"]))
	return {"farm": parsed if parsed is Dictionary else {}, "farm_seq": int(row["farm_seq"])}


func _help_ok(req_id: String, op: String, result: Dictionary, duplicate: bool, snapshot: Dictionary) -> Dictionary:
	return {
		"t": "req_ok", "req_id": req_id, "op": op, "duplicate": duplicate,
		"result": result, "farm_seq": int(snapshot.get("farm_seq", 0)),
		"server_now": int(Time.get_unix_time_from_system()), "snapshot": snapshot,
	}


func _req_err(req_id: String, op: String, code: String, msg := "") -> Dictionary:
	var payload := {"t": "req_err", "req_id": req_id, "op": op, "code": code, "server_now": int(Time.get_unix_time_from_system())}
	if msg != "":
		payload["msg"] = msg
	return payload
