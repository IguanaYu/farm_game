class_name FarmService
extends RefCounted
## M1 农场命令服务（计划 §4.3，规划 F01/F02/F08）：按账户组合 FarmGame+CraftingGame，
## 命令在候选副本上执行，"规则成功 → 同事务写库（新档+收据）→ 提交后换入正式副本 →
## 回 req_ok 附全快照"（规划 §4.2：先保存，再回复成功）。
## 所有 now 均为服务器时间（F08）；客户端请求不携带时间。
## GDScript lambda 按值捕获局部变量，跨 lambda 结果一律走 Dictionary 容器。

const TutorialFinished := 99

var store: ServerDB
var features: Array = []
## 服务器时间偏移（秒）：仅 --dev 模式允许（测试跨成熟；公网 bind 拒绝 --dev）。
var time_shift := 0

var _runtimes := {}  # account_id -> _Runtime


class _Runtime:
	var farm: FarmGame
	var crafting: CraftingGame
	var seq := 0


func now() -> int:
	return int(Time.get_unix_time_from_system()) + time_shift


## 登录/命令前加载：DB → FarmGame → 市场跨日与育种结算（与 farm_world._ready 同语义），
## 有变化立即落库（离线期间累计产出由此生效）。失败返回 null。
func load_runtime(account_id: int) -> _Runtime:
	if _runtimes.has(account_id):
		return _runtimes[account_id]
	var row := store.query_one(
		"SELECT farm_state, farm_seq FROM accounts WHERE id = ? AND disabled = 0", [account_id]
	)
	if row.is_empty():
		return null
	var parsed: Variant = JSON.parse_string(str(row["farm_state"]))
	if not (parsed is Dictionary):
		push_error("账户 %d 农场档解析失败" % account_id)
		return null
	var runtime := _Runtime.new()
	runtime.farm = FarmGame.new()
	if not runtime.farm.load_state(parsed):
		push_error("账户 %d 农场档校验失败" % account_id)
		return null
	runtime.seq = int(row["farm_seq"])
	var now_s := now()
	var market_changed := runtime.farm.refresh_market(now_s)
	var settle_changed := runtime.farm.breeder_settle(now_s)
	if market_changed or settle_changed:
		runtime.seq += 1
		if not store.exec(
			"UPDATE accounts SET farm_state = ?, farm_seq = ? WHERE id = ?",
			[JSON.stringify(runtime.farm.state), runtime.seq, account_id]
		):
			push_error("账户 %d 登录结算落库失败" % account_id)
			return null
	runtime.crafting = _bind_crafting(runtime.farm)
	_runtimes[account_id] = runtime
	return runtime


## 断开即逐出缓存：所有变更都是写穿提交，逐出无损失。
func evict(account_id: int) -> void:
	_runtimes.erase(account_id)


func snapshot(runtime: _Runtime) -> Dictionary:
	return {"farm": runtime.farm.state, "farm_seq": runtime.seq}


## 命令统一入口。返回完整的 req_ok / req_err 应答（含 req_id、快照、server_now）。
func execute(account_id: int, req_id: String, op: String, args: Dictionary) -> Dictionary:
	if req_id == "":
		return _req_err(req_id, op, OnlineProtocol.ERR_OP_FAILED, "req_id_required")
	if not _command_table().has(op):
		return _req_err(req_id, op, OnlineProtocol.ERR_UNKNOWN_OP)
	var feature: String = _command_table()[op]["feature"]
	if not features.has(feature):
		return _req_err(req_id, op, OnlineProtocol.ERR_FEATURE_DISABLED)
	var runtime := load_runtime(account_id)
	if runtime == null:
		return _req_err(req_id, op, OnlineProtocol.ERR_INTERNAL, "account_load_failed")
	var digest := AuthService.sha256_hex(JSON.stringify(args))
	var env := {"reply": null}
	var tx_result: Array = store.tx(func() -> bool:
		var receipt := store.query_one(
			"SELECT args_digest, result_json FROM receipts WHERE account_id = ? AND req_id = ?",
			[account_id, req_id]
		)
		if not receipt.is_empty():
			if str(receipt["args_digest"]) != digest:
				env["reply"] = {"kind": "conflict"}
				return false
			var replayed: Variant = JSON.parse_string(str(receipt["result_json"]))
			env["reply"] = {"kind": "duplicate", "result": replayed if replayed is Dictionary else {}}
			return true
		var candidate := _build_candidate(runtime)
		if candidate == null:
			env["reply"] = {"kind": "internal"}
			return false
		var handled: Dictionary = _run_command(op, candidate, args, now())
		if not handled["ok"]:
			# 规则失败不是数据库失败：丢弃候选副本，提交空事务。
			env["reply"] = {"kind": "op_failed", "msg": str(handled["reason"])}
			return true
		var new_seq := runtime.seq + 1
		if not store.exec(
			"UPDATE accounts SET farm_state = ?, farm_seq = ? WHERE id = ?",
			[JSON.stringify(candidate.farm.state), new_seq, account_id]
		):
			return false
		if not store.exec(
			"INSERT INTO receipts(account_id, req_id, op, args_digest, outcome, result_json, farm_seq, created_at) " +
			"VALUES(?, ?, ?, ?, 'ok', ?, ?, ?)",
			[account_id, req_id, op, digest, JSON.stringify(handled["result"]), new_seq, Time.get_datetime_string_from_system(true)]
		):
			return false
		env["reply"] = {"kind": "ok", "result": handled["result"], "candidate": candidate, "new_seq": new_seq}
		return true
	)
	if not bool(tx_result[0]) and env["reply"] == null:
		return _req_err(req_id, op, OnlineProtocol.ERR_INTERNAL, "tx_failed")
	var reply: Dictionary = env["reply"]
	if reply == null:
		return _req_err(req_id, op, OnlineProtocol.ERR_INTERNAL, "tx_failed")
	match reply["kind"]:
		"conflict":
			return _req_err(req_id, op, OnlineProtocol.ERR_REQ_ID_CONFLICT)
		"duplicate":
			return _req_ok(req_id, op, reply["result"], true, runtime)
		"op_failed":
			return _req_err(req_id, op, OnlineProtocol.ERR_OP_FAILED, str(reply["msg"]))
		"internal":
			return _req_err(req_id, op, OnlineProtocol.ERR_INTERNAL, "candidate_failed")
		"ok":
			runtime.farm = reply["candidate"].farm
			runtime.crafting = reply["candidate"].crafting
			runtime.seq = int(reply["new_seq"])
			return _req_ok(req_id, op, reply["result"], false, runtime)
	return _req_err(req_id, op, OnlineProtocol.ERR_INTERNAL)


func _req_ok(req_id: String, op: String, result: Variant, duplicate: bool, runtime: _Runtime) -> Dictionary:
	return {
		"t": "req_ok", "req_id": req_id, "op": op, "duplicate": duplicate,
		"result": result, "farm_seq": runtime.seq, "server_now": now(),
		"snapshot": snapshot(runtime),
	}


func _req_err(req_id: String, op: String, code: String, msg := "") -> Dictionary:
	var payload := {"t": "req_err", "req_id": req_id, "op": op, "code": code, "server_now": now()}
	if msg != "":
		payload["msg"] = msg
	return payload


func _bind_crafting(farm: FarmGame) -> CraftingGame:
	var crafting := CraftingGame.new()
	crafting.bind(farm)
	return crafting


## 候选副本：深拷贝当前档 → 独立 FarmGame/CraftingGame；提交成功前不碰正式副本。
func _build_candidate(runtime: _Runtime) -> _Runtime:
	var candidate := _Runtime.new()
	candidate.farm = FarmGame.new()
	if not candidate.farm.load_state(runtime.farm.state.duplicate(true)):
		return null
	candidate.crafting = _bind_crafting(candidate.farm)
	return candidate


# —— 命令表（计划 §4.4；M2 扩全量） ————————————————————————————

func _command_table() -> Dictionary:
	return {
		"farm.plant": {"feature": OnlineProtocol.FEATURE_FARM_BASIC, "run": _cmd_plant},
		"farm.plant_seed": {"feature": OnlineProtocol.FEATURE_FARM_BASIC, "run": _cmd_plant_seed},
		"farm.water": {"feature": OnlineProtocol.FEATURE_FARM_BASIC, "run": _cmd_water},
		"farm.fertilize": {"feature": OnlineProtocol.FEATURE_FARM_BASIC, "run": _cmd_fertilize},
		"farm.harvest": {"feature": OnlineProtocol.FEATURE_FARM_BASIC, "run": _cmd_harvest},
		"farm.harvest_all": {"feature": OnlineProtocol.FEATURE_FARM_BASIC, "run": _cmd_harvest_all},
	}


func _run_command(op: String, candidate: _Runtime, args: Dictionary, now_s: int) -> Dictionary:
	var handled: Dictionary = _command_table()[op]["run"].call(candidate, args, now_s)
	if bool(handled.get("ok", false)):
		_post_hooks(op, handled["result"], candidate)
	return handled


func _cmd_plant(candidate: _Runtime, args: Dictionary, now_s: int) -> Dictionary:
	var message: String = candidate.farm.plant(_arg_int(args, "plot_id"), now_s, str(args.get("kind", "")))
	return {"ok": message == "", "reason": message, "result": {"ok": message == "", "message": message}}


func _cmd_plant_seed(candidate: _Runtime, args: Dictionary, now_s: int) -> Dictionary:
	var message: String = candidate.farm.plant_seed(_arg_int(args, "plot_id"), _arg_int(args, "seed_id"), now_s)
	return {"ok": message == "", "reason": message, "result": {"ok": message == "", "message": message}}


func _cmd_water(candidate: _Runtime, args: Dictionary, now_s: int) -> Dictionary:
	var result: Dictionary = candidate.farm.water(_arg_int(args, "plot_id"), now_s)
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("message", "")), "result": result}


func _cmd_fertilize(candidate: _Runtime, args: Dictionary, now_s: int) -> Dictionary:
	var result: Dictionary = candidate.farm.apply_fertilizer(_arg_int(args, "plot_id"), str(args.get("kind", "")), now_s)
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("message", "")), "result": result}


func _cmd_harvest(candidate: _Runtime, args: Dictionary, now_s: int) -> Dictionary:
	var result: Dictionary = candidate.farm.harvest(_arg_int(args, "plot_id"), now_s)
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("message", "")), "result": result}


func _cmd_harvest_all(candidate: _Runtime, _args: Dictionary, now_s: int) -> Dictionary:
	var result: Dictionary = candidate.farm.harvest_all(now_s)
	return {"ok": bool(result.get("ok", false)), "reason": "现在没有成熟的地块。", "result": result}


## 命令成功后的服务器侧联动（镜像 farm_world：教程推进 + 收获进成长统计）。
## M2 扩 sell/craft/inventory 步；M1 只覆盖 farm_basic。
func _post_hooks(op: String, result: Variant, candidate: _Runtime) -> void:
	var step := int(candidate.farm.state.get("tutorial_step", TutorialFinished))
	match op:
		"farm.plant", "farm.plant_seed":
			if step == 0:
				candidate.farm.state["tutorial_step"] = 1
			elif step == 4:
				candidate.farm.state["tutorial_step"] = TutorialFinished
		"farm.water":
			if step == 1:
				candidate.farm.state["tutorial_step"] = 2
		"farm.harvest":
			if result is Dictionary and bool(result.get("ok", false)):
				_record_harvest(result, candidate.crafting)
			if step == 2:
				candidate.farm.state["tutorial_step"] = 3
		"farm.harvest_all":
			if result is Dictionary:
				for entry in result.get("results", []):
					_record_harvest(entry, candidate.crafting)
			if step == 2:
				candidate.farm.state["tutorial_step"] = 3
	return


func _record_harvest(harvest_result: Dictionary, crafting: CraftingGame) -> void:
	var batch: Dictionary = harvest_result.get("batch", {})
	if batch.is_empty():
		return
	crafting.record_event("harvested", {"kind": str(batch.get("kind", "")), "count": int(batch.get("count", 0))})


## JSON 数字解析为 float，统一安全取整；非法值回退 0（域层再拒绝）。
static func _arg_int(args: Dictionary, key: String) -> int:
	var value: Variant = args.get(key, null)
	if value is float:
		return int(value)
	if value is int:
		return value
	if value is String and value.is_valid_int():
		return int(value)
	return 0
