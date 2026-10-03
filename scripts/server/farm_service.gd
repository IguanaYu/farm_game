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
	var inventory: InventoryGame
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
	runtime.inventory = _bind_inventory(runtime.farm)
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


## InventoryGame 绑定的是 state["expedition"] 字典本身；快照/换档会整体替换 state，
## 每次装载/换入候选副本后必须重绑，否则会在游离字典上改动（M2 实测坑，勿省）。
func _bind_inventory(farm: FarmGame) -> InventoryGame:
	var inventory := InventoryGame.new()
	inventory.bind(farm.state["expedition"])
	return inventory


## 候选副本：深拷贝当前档 → 独立 FarmGame/CraftingGame；提交成功前不碰正式副本。
func _build_candidate(runtime: _Runtime) -> _Runtime:
	var candidate := _Runtime.new()
	candidate.farm = FarmGame.new()
	if not candidate.farm.load_state(runtime.farm.state.duplicate(true)):
		return null
	candidate.crafting = _bind_crafting(candidate.farm)
	candidate.inventory = _bind_inventory(candidate.farm)
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
		"farm.buy_seeds": {"feature": OnlineProtocol.FEATURE_FARM_SHOP, "run": _cmd_buy_seeds},
		"farm.buy_fertilizer": {"feature": OnlineProtocol.FEATURE_FARM_SHOP, "run": _cmd_buy_fertilizer},
		"farm.upgrade_shop": {"feature": OnlineProtocol.FEATURE_FARM_SHOP, "run": _cmd_upgrade_shop},
		"farm.buy_can2": {"feature": OnlineProtocol.FEATURE_FARM_SHOP, "run": _cmd_buy_can2},
		"farm.buy_plot": {"feature": OnlineProtocol.FEATURE_FARM_SHOP, "run": _cmd_buy_plot},
		"farm.upgrade_warehouse": {"feature": OnlineProtocol.FEATURE_FARM_SHOP, "run": _cmd_upgrade_warehouse},
		"farm.recycle_seed": {"feature": OnlineProtocol.FEATURE_FARM_BREEDING, "run": _cmd_recycle_seed},
		"farm.recycle_pending_seed": {"feature": OnlineProtocol.FEATURE_FARM_BREEDING, "run": _cmd_recycle_pending_seed},
		"farm.claim_pending": {"feature": OnlineProtocol.FEATURE_FARM_BREEDING, "run": _cmd_claim_pending},
		"farm.buy_breeder": {"feature": OnlineProtocol.FEATURE_FARM_BREEDING, "run": _cmd_buy_breeder},
		"farm.upgrade_breeder": {"feature": OnlineProtocol.FEATURE_FARM_BREEDING, "run": _cmd_upgrade_breeder},
		"farm.set_breeder_template": {"feature": OnlineProtocol.FEATURE_FARM_BREEDING, "run": _cmd_set_breeder_template},
		"farm.clear_breeder_template": {"feature": OnlineProtocol.FEATURE_FARM_BREEDING, "run": _cmd_clear_breeder_template},
		"farm.collect_breeder": {"feature": OnlineProtocol.FEATURE_FARM_BREEDING, "run": _cmd_collect_breeder},
		"farm.sell_batch": {"feature": OnlineProtocol.FEATURE_FARM_MARKET, "run": _cmd_sell_batch},
		"farm.sell_all_batches": {"feature": OnlineProtocol.FEATURE_FARM_MARKET, "run": _cmd_sell_all_batches},
		"farm.sell_pending_crop": {"feature": OnlineProtocol.FEATURE_FARM_MARKET, "run": _cmd_sell_pending_crop},
		"farm.lock_guest": {"feature": OnlineProtocol.FEATURE_FARM_MARKET, "run": _cmd_lock_guest},
		"farm.lock_formula": {"feature": OnlineProtocol.FEATURE_FARM_MARKET, "run": _cmd_lock_formula},
		"farm.unlock_formula": {"feature": OnlineProtocol.FEATURE_FARM_MARKET, "run": _cmd_unlock_formula},
		"farm.sell_batch_to": {"feature": OnlineProtocol.FEATURE_FARM_MARKET, "run": _cmd_sell_batch_to},
		"craft.craft": {"feature": OnlineProtocol.FEATURE_FARM_CRAFT, "run": _cmd_craft},
		"craft.claim_pending": {"feature": OnlineProtocol.FEATURE_FARM_CRAFT, "run": _cmd_craft_claim_pending},
		"craft.buy_upgrade": {"feature": OnlineProtocol.FEATURE_FARM_CRAFT, "run": _cmd_craft_buy_upgrade},
		"craft.claim_goal": {"feature": OnlineProtocol.FEATURE_FARM_CRAFT, "run": _cmd_craft_claim_goal},
		"craft.sell_instance": {"feature": OnlineProtocol.FEATURE_FARM_CRAFT, "run": _cmd_craft_sell_instance},
		"inv.move_to_loadout": {"feature": OnlineProtocol.FEATURE_FARM_INVENTORY, "run": _cmd_inv_move_to_loadout},
		"inv.move_to_warehouse": {"feature": OnlineProtocol.FEATURE_FARM_INVENTORY, "run": _cmd_inv_move_to_warehouse},
		"inv.place_at": {"feature": OnlineProtocol.FEATURE_FARM_INVENTORY, "run": _cmd_inv_place_at},
		"inv.rotate": {"feature": OnlineProtocol.FEATURE_FARM_INVENTORY, "run": _cmd_inv_rotate},
		"inv.auto_tidy": {"feature": OnlineProtocol.FEATURE_FARM_INVENTORY, "run": _cmd_inv_auto_tidy},
		"inv.clear_loadout": {"feature": OnlineProtocol.FEATURE_FARM_INVENTORY, "run": _cmd_inv_clear_loadout},
		"inv.grant_basic_kit": {"feature": OnlineProtocol.FEATURE_FARM_INVENTORY, "run": _cmd_inv_grant_basic_kit},
		"inv.apply_preset": {"feature": OnlineProtocol.FEATURE_FARM_INVENTORY, "run": _cmd_inv_apply_preset},
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


# —— M2：商店/扩地/升级 ————————————————————————————————————————

func _cmd_buy_seeds(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var message: String = candidate.farm.buy_seeds(_arg_int(args, "quantity", 1), str(args.get("kind", "cabbage")))
	return {"ok": message == "", "reason": message, "result": message}


func _cmd_buy_fertilizer(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var message: String = candidate.farm.buy_fertilizer(str(args.get("kind", "")), _arg_int(args, "quantity", 1))
	return {"ok": message == "", "reason": message, "result": message}


func _cmd_upgrade_shop(candidate: _Runtime, _args: Dictionary, _now_s: int) -> Dictionary:
	var message: String = candidate.farm.upgrade_shop()
	return {"ok": message == "", "reason": message, "result": message}


func _cmd_buy_can2(candidate: _Runtime, _args: Dictionary, _now_s: int) -> Dictionary:
	var message: String = candidate.farm.buy_can2()
	return {"ok": message == "", "reason": message, "result": message}


func _cmd_buy_plot(candidate: _Runtime, _args: Dictionary, _now_s: int) -> Dictionary:
	var message: String = candidate.farm.buy_plot()
	return {"ok": message == "", "reason": message, "result": message}


func _cmd_upgrade_warehouse(candidate: _Runtime, _args: Dictionary, _now_s: int) -> Dictionary:
	var message: String = candidate.farm.upgrade_warehouse()
	return {"ok": message == "", "reason": message, "result": message}


# —— M2：育种机/回收/待领取 ——————————————————————————————————————

func _cmd_recycle_seed(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.farm.recycle_seed(_arg_int(args, "seed_id"))
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("message", "")), "result": result}


func _cmd_recycle_pending_seed(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.farm.recycle_pending_seed(_arg_int(args, "seed_id"))
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("message", "")), "result": result}


func _cmd_claim_pending(candidate: _Runtime, _args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.farm.claim_pending()
	return {"ok": true, "reason": "", "result": result}


func _cmd_buy_breeder(candidate: _Runtime, _args: Dictionary, now_s: int) -> Dictionary:
	var message: String = candidate.farm.buy_breeder(now_s)
	return {"ok": message == "", "reason": message, "result": message}


func _cmd_upgrade_breeder(candidate: _Runtime, _args: Dictionary, _now_s: int) -> Dictionary:
	var message: String = candidate.farm.upgrade_breeder()
	return {"ok": message == "", "reason": message, "result": message}


func _cmd_set_breeder_template(candidate: _Runtime, args: Dictionary, now_s: int) -> Dictionary:
	var result: Dictionary = candidate.farm.set_breeder_template(_arg_int(args, "seed_id"), now_s)
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("message", "")), "result": result}


func _cmd_clear_breeder_template(candidate: _Runtime, _args: Dictionary, now_s: int) -> Dictionary:
	var message: String = candidate.farm.clear_breeder_template(now_s)
	return {"ok": message == "", "reason": message, "result": message}


func _cmd_collect_breeder(candidate: _Runtime, _args: Dictionary, now_s: int) -> Dictionary:
	var result: Dictionary = candidate.farm.collect_breeder(now_s)
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("message", "")), "result": result}


# —— M2：市场出售/锁定 ————————————————————————————————————————————

func _cmd_sell_batch(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.farm.sell_batch(_arg_int(args, "batch_id"))
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("message", "")), "result": result}


func _cmd_sell_all_batches(candidate: _Runtime, _args: Dictionary, _now_s: int) -> Dictionary:
	## 规则返回裸整数（总收益）；JSON 往返会变浮点，客户端 _finish 处取整。
	var earned: int = candidate.farm.sell_all_batches()
	return {"ok": true, "reason": "", "result": earned}


func _cmd_sell_pending_crop(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.farm.sell_pending_crop(_arg_int(args, "batch_id"))
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("message", "")), "result": result}


func _cmd_lock_guest(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	## guest_id=0 即解锁客人位（镜像 farm_world._on_unlock_guest_requested）。
	var message: String = candidate.farm.request_lock_guest(_arg_int(args, "guest_id"))
	return {"ok": message == "", "reason": message, "result": message}


func _cmd_lock_formula(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var message: String = candidate.farm.request_lock_formula(str(args.get("kind", "")))
	return {"ok": message == "", "reason": message, "result": message}


func _cmd_unlock_formula(candidate: _Runtime, _args: Dictionary, _now_s: int) -> Dictionary:
	var message: String = candidate.farm.request_unlock_formula()
	return {"ok": message == "", "reason": message, "result": message}


func _cmd_sell_batch_to(candidate: _Runtime, args: Dictionary, now_s: int) -> Dictionary:
	var result: Dictionary = candidate.farm.sell_batch_to(
		_arg_int(args, "batch_id"), _arg_int(args, "count", 1), _arg_int(args, "guest_id"), now_s
	)
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("message", "")), "result": result}


# —— M2：制作/设施/目标 ————————————————————————————————————————————

func _cmd_craft(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.crafting.craft(str(args.get("recipe_id", "")))
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("reason", "")), "result": result}


func _cmd_craft_claim_pending(candidate: _Runtime, _args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.crafting.claim_pending()
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("reason", "")), "result": result}


func _cmd_craft_buy_upgrade(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.crafting.buy_upgrade(str(args.get("upgrade_id", "")))
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("reason", "")), "result": result}


func _cmd_craft_claim_goal(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.crafting.claim_goal(str(args.get("goal_id", "")))
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("reason", "")), "result": result}


func _cmd_craft_sell_instance(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.crafting.sell_instance(str(args.get("def_id", "")))
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("reason", "")), "result": result}


# —— M2：装备仓库与战备 ————————————————————————————————————————————

func _cmd_inv_move_to_loadout(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.inventory.move_to_loadout(_arg_int(args, "instance_id"), str(args.get("container", "")))
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("reason", "")), "result": result}


func _cmd_inv_move_to_warehouse(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.inventory.move_to_warehouse(_arg_int(args, "instance_id"))
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("reason", "")), "result": result}


func _cmd_inv_place_at(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var cell: Dictionary = args.get("cell", {}) if args.get("cell") is Dictionary else {}
	var result: Dictionary = candidate.inventory.place_at(
		_arg_int(args, "instance_id"), str(args.get("container", "")),
		Vector2i(_arg_int(cell, "x"), _arg_int(cell, "y")), bool(args.get("rotated", false))
	)
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("reason", "")), "result": result}


func _cmd_inv_rotate(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.inventory.rotate_instance(_arg_int(args, "instance_id"))
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("reason", "")), "result": result}


func _cmd_inv_auto_tidy(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.inventory.auto_tidy(str(args.get("container", "")))
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("reason", "")), "result": result}


func _cmd_inv_clear_loadout(candidate: _Runtime, _args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.inventory.clear_loadout()
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("reason", "")), "result": result}


func _cmd_inv_grant_basic_kit(candidate: _Runtime, _args: Dictionary, _now_s: int) -> Dictionary:
	var result: Dictionary = candidate.inventory.grant_basic_kit()
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("reason", "")), "result": result}


func _cmd_inv_apply_preset(candidate: _Runtime, args: Dictionary, _now_s: int) -> Dictionary:
	## 配装预设应用＝多件精确放置的复合操作，客户端逐件发命令不原子；
	## 预设本体是本机 QoL（PresetStore 不上传），应用走服务器单命令原子复原。
	var preset: Variant = args.get("preset", {})
	var result: Dictionary = LoadoutPresets.apply(candidate.inventory, preset if preset is Dictionary else {})
	return {"ok": bool(result.get("ok", false)), "reason": str(result.get("reason", "")), "result": result}


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
		"farm.sell_batch", "farm.sell_all_batches", "farm.sell_batch_to":
			## 镜像 farm_world：出售成功且正处第 3 步时推进（3→4；第 4 步再播种即完成引导）。
			if step == 3:
				candidate.farm.state["tutorial_step"] = 4
	return


func _record_harvest(harvest_result: Dictionary, crafting: CraftingGame) -> void:
	var batch: Dictionary = harvest_result.get("batch", {})
	if batch.is_empty():
		return
	crafting.record_event("harvested", {"kind": str(batch.get("kind", "")), "count": int(batch.get("count", 0))})


## JSON 数字解析为 float，统一安全取整；非法值回退 0（域层再拒绝）。
static func _arg_int(args: Dictionary, key: String, fallback := 0) -> int:
	var value: Variant = args.get(key, null)
	if value is float:
		return int(value)
	if value is int:
		return value
	if value is String and value.is_valid_int():
		return int(value)
	return fallback
