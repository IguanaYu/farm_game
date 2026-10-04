class_name VisitService
extends RefCounted
## R7 邻里拜访服务（计划：docs/plan/Godot_合并路线_R7_拜访系统_代码执行计划_v0.1.md §3）。
## 只读：地址簿（visit.list）与家园快照（visit.snapshot）——纯 SELECT，不写库、不产生收据，
## 绝不经过 FarmService 的写穿 runtime（资产隔离红线：访客路径零副作用）。
## 首版口径：封闭试玩池内所有账户互为邻里，家园开放由服务器全局开关（--visits-closed 关闭）。

var store: ServerDB
var auth: AuthService
var features: Array = []
var visits_open := true


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


func _req_err(req_id: String, op: String, code: String, msg := "") -> Dictionary:
	var payload := {"t": "req_err", "req_id": req_id, "op": op, "code": code, "server_now": int(Time.get_unix_time_from_system())}
	if msg != "":
		payload["msg"] = msg
	return payload
