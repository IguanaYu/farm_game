class_name FarmGame
extends RefCounted

const SAVE_VERSION := 2
const PLOT_COUNT := 6
const ROUND_EVENT_LIMIT := 24


var state: Dictionary = {}
var roll_randomizer := RandomNumberGenerator.new()


func _init() -> void:
	roll_randomizer.randomize()


func set_debug_random_seed(value: int) -> void:
	roll_randomizer.seed = value


func new_game(now: int) -> void:
	state = {
		"version": SAVE_VERSION,
		"next_id": 1,
		"coins": 0,
		"farming_exp": 0,
		"plant_exp": {},
		"shop_level": 1,
		"can_level": 1,
		"fertilizers": {},
		"plots": [],
		"seeds": [],
		"crop_batches": [],
		"created_at": now,
	}
	for kind in PlantDefs.FERTILIZERS:
		state["fertilizers"][kind] = 0
	for plot_index in range(PLOT_COUNT):
		state["plots"].append(_empty_plot(plot_index + 1))
	for seed_index in range(PLOT_COUNT):
		state["seeds"].append(_new_seed("cabbage"))


func load_state(saved: Dictionary) -> bool:
	if saved.is_empty():
		return false
	var source := saved
	if int(saved.get("version", -1)) == 1:
		source = _migrate_v1_to_v2(saved)
	if int(source.get("version", -1)) != SAVE_VERSION:
		return false
	# JSON 会把整数解析成浮点（3 → 3.0），而数组/字典的相等比较对类型严格；统一把整数值浮点归一化为 int。
	source = _normalize_numbers(source)
	for field in ["plots", "seeds", "crop_batches", "plant_exp", "fertilizers"]:
		if not source.get(field) is Array and not source.get(field) is Dictionary:
			return false
	if source["plots"].size() != PLOT_COUNT:
		return false
	if not _is_number(source.get("coins")) or not _is_number(source.get("next_id")):
		return false
	if int(source["coins"]) < 0 or int(source["next_id"]) < 1:
		return false
	if not _is_number(source.get("farming_exp")) or int(source["farming_exp"]) < 0:
		return false
	if int(source.get("shop_level", 0)) < 1 or int(source.get("shop_level", 0)) > 2:
		return false
	if int(source.get("can_level", 0)) < 1 or int(source.get("can_level", 0)) > PlantDefs.WATER_BONUS_BY_CAN.size():
		return false
	for plot in source["plots"]:
		if not plot is Dictionary:
			return false
		for field in ["id", "seed_id", "planted_at", "ready_at", "roll_seed"]:
			if not _is_number(plot.get(field)):
				return false
		if plot["seed_id"] != 0 and not PlantDefs.is_known_plant(str(plot.get("kind", ""))):
			return false
		for event in plot.get("events", []):
			if not event is Dictionary or not _is_number(event.get("t")):
				return false
	for seed in source["seeds"]:
		if not seed is Dictionary or not _is_number(seed.get("id")) or not PlantDefs.is_known_plant(str(seed.get("kind", ""))):
			return false
	for batch in source["crop_batches"]:
		if not batch is Dictionary:
			return false
		for field in ["id", "plot_id", "count", "base_score"]:
			if not _is_number(batch.get(field)):
				return false
		if not PlantDefs.is_known_plant(str(batch.get("kind", "cabbage"))):
			return false
	state = source.duplicate(true)
	state["coins"] = int(state["coins"])
	state["next_id"] = int(state["next_id"])
	state["farming_exp"] = int(state["farming_exp"])
	state["shop_level"] = int(state["shop_level"])
	state["can_level"] = int(state["can_level"])
	for key in state["plant_exp"]:
		state["plant_exp"][key] = int(state["plant_exp"][key])
	for kind in state["fertilizers"]:
		state["fertilizers"][kind] = int(state["fertilizers"][kind])
	for plot in state["plots"]:
		for field in ["id", "seed_id", "planted_at", "ready_at", "roll_seed"]:
			plot[field] = int(plot[field])
		for event in plot.get("events", []):
			event["t"] = int(event["t"])
	for seed in state["seeds"]:
		seed["id"] = int(seed["id"])
	for batch in state["crop_batches"]:
		for field in ["id", "plot_id", "count", "base_score"]:
			batch[field] = int(batch[field])
		if _is_number(batch.get("per_crop_score")):
			batch["per_crop_score"] = int(batch["per_crop_score"])
	return true


func get_plot(plot_id: int) -> Dictionary:
	if plot_id < 1 or plot_id > PLOT_COUNT:
		return {}
	return state["plots"][plot_id - 1]


func is_ready(plot_id: int, now: int) -> bool:
	var plot := get_plot(plot_id)
	return not plot.is_empty() and plot["seed_id"] != 0 and now >= plot["ready_at"]


func farming_level() -> int:
	return PlantDefs.level_from_exp(int(state["farming_exp"]))


func plant_level(kind: String) -> int:
	return PlantDefs.level_from_exp(int(state["plant_exp"].get(kind, 0)))


func mature_plot_ids(now: int) -> Array:
	var result: Array = []
	for plot in state["plots"]:
		if plot["seed_id"] != 0 and now >= plot["ready_at"]:
			result.append(plot["id"])
	return result


func seed_counts() -> Dictionary:
	var result: Dictionary = {}
	for seed in state["seeds"]:
		var kind: String = seed["kind"]
		result[kind] = result.get(kind, 0) + 1
	return result


func plant(plot_id: int, now: int, kind := "") -> String:
	var plot := get_plot(plot_id)
	if plot.is_empty():
		return "找不到这块地。"
	if plot["seed_id"] != 0:
		return "这块地正在生长，成熟后才能收获。"
	if state["seeds"].is_empty():
		return "没有种子了。请到商店购买。"
	var planted_kind := kind
	if planted_kind == "":
		planted_kind = state["seeds"][0]["kind"]
	var seed_index := -1
	for index in range(state["seeds"].size()):
		if state["seeds"][index]["kind"] == planted_kind:
			seed_index = index
			break
	if seed_index < 0:
		return "没有%s种子了。请到商店购买。" % PlantDefs.get_plant(planted_kind).get("display_name", planted_kind)
	var defn := PlantDefs.get_plant(planted_kind)
	var seed: Dictionary = state["seeds"].pop_at(seed_index)
	plot["seed_id"] = seed["id"]
	plot["kind"] = planted_kind
	plot["planted_at"] = now
	plot["ready_at"] = now + defn["grow_seconds"]
	plot["roll_seed"] = int(roll_randomizer.randi())
	plot["snapshot"] = {
		"farming_level": farming_level(),
		"plant_level": plant_level(planted_kind),
	}
	plot["watered_segments"] = []
	plot["preroll"] = _roll_round(plot["roll_seed"], planted_kind)
	plot["events"] = [{
		"t": now,
		"type": "plant",
		"text": "播种了%s（预计 %d 分钟成熟）。" % [defn["display_name"], int(defn["grow_seconds"] / 60)],
	}]
	return ""


func water(plot_id: int, now: int) -> Dictionary:
	var plot := get_plot(plot_id)
	if plot.is_empty():
		return {"ok": false, "message": "找不到这块地。"}
	if plot["seed_id"] == 0:
		return {"ok": false, "message": "空地不需要浇水，播种后再来。"}
	if now >= plot["ready_at"]:
		return {"ok": false, "message": "作物已经成熟，浇水已经无效了。"}
	var segment := current_water_segment(plot_id, now)
	if segment < 0:
		return {"ok": false, "message": "现在不在有效浇水时段内。"}
	if segment in plot["watered_segments"]:
		return {"ok": false, "message": "这个时段已经浇过水了，效果只记一次。"}
	plot["watered_segments"].append(segment)
	_append_round_event(plot, now, "water", "完成第 %d 时段浇水。" % (segment + 1))
	return {"ok": true, "segment": segment}


func current_water_segment(plot_id: int, now: int) -> int:
	var plot := get_plot(plot_id)
	if plot.is_empty() or plot["seed_id"] == 0:
		return -1
	if now < plot["planted_at"] or now >= plot["ready_at"]:
		return -1
	var segment_length := PlantDefs.segment_seconds(plot["kind"])
	if segment_length <= 0:
		return -1
	var index := int((now - plot["planted_at"]) / segment_length)
	return clampi(index, 0, PlantDefs.get_plant(plot["kind"])["water_segments"] - 1)


func watering_status(plot_id: int, now: int) -> Dictionary:
	var plot := get_plot(plot_id)
	if plot.is_empty() or plot["seed_id"] == 0:
		return {}
	var defn := PlantDefs.get_plant(plot["kind"])
	var segment_length := PlantDefs.segment_seconds(plot["kind"])
	var current := current_water_segment(plot_id, now)
	var segments: Array = []
	for index in range(defn["water_segments"]):
		segments.append({
			"index": index,
			"start_offset": index * segment_length,
			"end_offset": (index + 1) * segment_length,
			"watered": index in plot["watered_segments"],
		})
	return {"current": current, "segments": segments, "mature": now >= plot["ready_at"]}


func apply_fertilizer(plot_id: int, kind: String, now: int) -> Dictionary:
	var plot := get_plot(plot_id)
	if plot.is_empty():
		return {"ok": false, "message": "找不到这块地。"}
	var defn: Dictionary = PlantDefs.FERTILIZERS.get(kind, {})
	if defn.is_empty():
		return {"ok": false, "message": "未知肥料。"}
	if int(state["fertilizers"].get(kind, 0)) < 1:
		return {"ok": false, "message": "没有%s了，请先到商店购买。" % defn["display_name"]}
	if not plot.get("fertilizer", {}).is_empty() and plot["fertilizer"]["expires_at"] > now:
		var remaining_minutes := int(ceil(float(plot["fertilizer"]["expires_at"] - now) / 60.0))
		return {"ok": false, "message": "这块地的%s还有约 %d 分钟才到期，到期后才能换新肥料。" % [PlantDefs.FERTILIZERS[plot["fertilizer"]["kind"]]["display_name"], remaining_minutes]}
	state["fertilizers"][kind] = int(state["fertilizers"][kind]) - 1
	plot["fertilizer"] = {"kind": kind, "applied_at": now, "expires_at": now + defn["duration_seconds"]}
	if plot["seed_id"] != 0:
		_append_round_event(plot, now, "fertilizer", "施用了%s（对本次生长有效）。" % defn["display_name"])
	return {"ok": true, "fertilizer": plot["fertilizer"].duplicate(true)}


func active_fertilizer_for_round(plot: Dictionary) -> String:
	var fertilizer: Dictionary = plot.get("fertilizer", {})
	if fertilizer.is_empty():
		return ""
	# 覆盖判定：施肥区间 [applied_at, expires_at) 与本轮生长期 [planted_at, ready_at) 有交集。
	# 播种前已生效、生长中途施肥都算；成熟之后才施的肥只影响下一轮。
	if fertilizer["applied_at"] < plot["ready_at"] and fertilizer["expires_at"] > plot["planted_at"]:
		return fertilizer["kind"]
	return ""


func buy_seeds(quantity: int, kind := "cabbage") -> String:
	var defn := PlantDefs.get_plant(kind)
	if defn.is_empty():
		return "未知种子。"
	if quantity <= 0:
		return "购买数量必须大于零。"
	var lock_reason := seed_lock_reason(kind)
	if lock_reason != "":
		return lock_reason
	var total_price: int = quantity * defn["seed_price"]
	if state["coins"] < total_price:
		return "金币不足，需要 %d 金币。" % total_price
	state["coins"] -= total_price
	for seed_index in range(quantity):
		state["seeds"].append(_new_seed(kind))
	return ""


func seed_lock_reason(kind: String) -> String:
	var defn := PlantDefs.get_plant(kind)
	if defn.is_empty():
		return "未知种子。"
	var missing: Array = []
	if farming_level() < defn["unlock_farming_level"]:
		missing.append("种地等级 %d（当前 %d）" % [defn["unlock_farming_level"], farming_level()])
	if int(state["shop_level"]) < defn["unlock_shop_level"]:
		missing.append("商店等级 %d（当前 %d）" % [defn["unlock_shop_level"], int(state["shop_level"])])
	if missing.is_empty():
		return ""
	return "解锁%s还需要：" % defn["display_name"] + "、".join(missing) + "。"


func buy_fertilizer(kind: String) -> String:
	var defn: Dictionary = PlantDefs.FERTILIZERS.get(kind, {})
	if defn.is_empty():
		return "未知肥料。"
	var required_level := PlantDefs.FERTILIZER_UNLOCK_FARMING_LEVEL
	if kind == "golden":
		required_level = PlantDefs.GOLDEN_FERTILIZER_UNLOCK_LEVEL_PLACEHOLDER
	if farming_level() < required_level:
		return "%s需要种地等级 %d 解锁（当前 %d）。" % [defn["display_name"], required_level, farming_level()]
	if state["coins"] < defn["price"]:
		return "金币不足，需要 %d 金币。" % defn["price"]
	state["coins"] -= defn["price"]
	state["fertilizers"][kind] = int(state["fertilizers"].get(kind, 0)) + defn["uses_per_pack"]
	return ""


func upgrade_shop() -> String:
	var target := int(state["shop_level"]) + 1
	if not PlantDefs.SHOP_UPGRADE_COSTS.has(target):
		return "商店已经达到当前版本的最高等级。"
	var cost: int = PlantDefs.SHOP_UPGRADE_COSTS[target]
	if state["coins"] < cost:
		return "金币不足，升级商店需要 %d 金币。" % cost
	state["coins"] -= cost
	state["shop_level"] = target
	return ""


func harvest(plot_id: int, now: int) -> Dictionary:
	var plot := get_plot(plot_id)
	if plot.is_empty() or plot["seed_id"] == 0:
		return {"ok": false, "message": "这块地还没有作物。"}
	if now < plot["ready_at"]:
		return {"ok": false, "message": "作物还没成熟。"}
	var kind: String = plot["kind"]
	var defn := PlantDefs.get_plant(kind)
	var preroll: Dictionary = plot["preroll"]
	var breakdown := _score_breakdown(plot)
	var per_crop: int = breakdown["per_crop_score"]
	var batch := {
		"id": _take_id(),
		"plot_id": plot_id,
		"kind": kind,
		"count": defn["crop_count"],
		"base_score": defn["base_score"],
		"per_crop_score": per_crop,
		"score_breakdown": breakdown,
		"watered_segments": plot["watered_segments"].duplicate(),
		"encounter_tiers": preroll["encounters"].map(func(entry): return entry["tier"]),
		"fluctuation_pct": preroll["fluctuation_pct"],
		"sale_multiplier_bonus": 0.2 if breakdown["fertilizer_kind"] == "golden" else 0.0,
		"planted_at": plot["planted_at"],
		"harvested_at": now,
	}
	state["crop_batches"].append(batch)
	for seed_index in range(preroll["seed_count"]):
		state["seeds"].append(_new_seed(kind))
	var exp_gain: int = defn["harvest_exp"]
	var farming_before := farming_level()
	var plant_before := plant_level(kind)
	state["farming_exp"] = int(state["farming_exp"]) + exp_gain
	state["plant_exp"][kind] = int(state["plant_exp"].get(kind, 0)) + exp_gain
	var events := _round_story(plot, breakdown, now, batch)
	plot["seed_id"] = 0
	plot["kind"] = ""
	plot["planted_at"] = 0
	plot["ready_at"] = 0
	plot["roll_seed"] = 0
	plot["snapshot"] = {}
	plot["watered_segments"] = []
	plot["preroll"] = {}
	plot["events"] = []
	return {
		"ok": true,
		"batch": batch.duplicate(true),
		"seeds": preroll["seed_count"],
		"exp_gain": exp_gain,
		"farming_level_up": farming_level() > farming_before,
		"plant_level_up": plant_level(kind) > plant_before,
		"events": events,
	}


func harvest_all(now: int) -> Dictionary:
	var results: Array = []
	var total_crops := 0
	var total_seeds := 0
	var total_exp := 0
	var level_ups := 0
	for plot_id in mature_plot_ids(now):
		var result := harvest(plot_id, now)
		if result["ok"]:
			results.append(result)
			total_crops += result["batch"]["count"]
			total_seeds += result["seeds"]
			total_exp += result["exp_gain"]
			if result["farming_level_up"] or result["plant_level_up"]:
				level_ups += 1
	return {"ok": not results.is_empty(), "results": results, "total_crops": total_crops, "total_seeds": total_seeds, "total_exp": total_exp, "level_up_count": level_ups}


func batch_sale_price(batch: Dictionary) -> int:
	# 整笔计价额先合计，再除以 100 向下取整。金克拉倍率加成由阶段 4 报价算法使用，本阶段默认出售仍是 1.2 倍。
	var per_crop := int(batch.get("per_crop_score", batch["base_score"]))
	return int(floor(float(batch["count"] * per_crop) * PlantDefs.DEFAULT_SALE_MULTIPLIER / 100.0))


func sell_batch(batch_id: int) -> Dictionary:
	for index in range(state["crop_batches"].size()):
		var batch: Dictionary = state["crop_batches"][index]
		if batch["id"] == batch_id:
			var price := batch_sale_price(batch)
			state["crop_batches"].remove_at(index)
			state["coins"] += price
			return {"ok": true, "coins": price}
	return {"ok": false, "message": "找不到这批作物。"}


func sell_all_batches() -> int:
	var total_score := 0
	for batch in state["crop_batches"]:
		total_score += batch["count"] * int(batch.get("per_crop_score", batch["base_score"]))
	var earned := int(floor(float(total_score) * PlantDefs.DEFAULT_SALE_MULTIPLIER / 100.0))
	state["crop_batches"].clear()
	state["coins"] += earned
	return earned


func _score_breakdown(plot: Dictionary) -> Dictionary:
	var kind: String = plot["kind"]
	var defn := PlantDefs.get_plant(kind)
	var base: int = defn["base_score"]
	var snapshot: Dictionary = plot.get("snapshot", {"farming_level": 1, "plant_level": 1})
	var farming_units: int = PlantDefs.LEVEL_BONUS_PER_LEVEL * (int(snapshot["farming_level"]) - 1)
	var plant_units: int = PlantDefs.LEVEL_BONUS_PER_LEVEL * (int(snapshot["plant_level"]) - 1)
	var level_bonus := _percent_of(base, farming_units + plant_units)
	var fluctuation_pct: int = plot["preroll"]["fluctuation_pct"]
	var fluctuation_bonus := _percent_of(base, fluctuation_pct)
	var segments_done: int = plot["watered_segments"].size()
	var can_pct: int = PlantDefs.WATER_BONUS_BY_CAN[int(state["can_level"])]
	var water_bonus := _percent_of(base, can_pct * segments_done)
	var fertilizer_kind := active_fertilizer_for_round(plot)
	var fertilizer_bonus := 0
	if fertilizer_kind != "":
		fertilizer_bonus = _percent_of(base, PlantDefs.FERTILIZERS[fertilizer_kind]["score_bonus"])
	var encounter_tiers: Array = []
	var encounter_bonus := 0
	for entry in plot["preroll"]["encounters"]:
		encounter_tiers.append(entry["tier"])
		encounter_bonus += entry["tier"]
	var per_crop := base + level_bonus + fluctuation_bonus + water_bonus + fertilizer_bonus + encounter_bonus
	return {
		"base": base,
		"farming_level_snapshot": snapshot["farming_level"],
		"plant_level_snapshot": snapshot["plant_level"],
		"level_bonus": level_bonus,
		"fluctuation_pct": fluctuation_pct,
		"fluctuation_bonus": fluctuation_bonus,
		"water_segments_done": segments_done,
		"water_segments_total": defn["water_segments"],
		"water_bonus": water_bonus,
		"fertilizer_kind": fertilizer_kind,
		"fertilizer_bonus": fertilizer_bonus,
		"encounter_tiers": encounter_tiers,
		"encounter_bonus": encounter_bonus,
		"per_crop_score": per_crop,
		"crop_count": defn["crop_count"],
		"batch_total": per_crop * defn["crop_count"],
	}


func _round_story(plot: Dictionary, breakdown: Dictionary, harvested_at: int, batch: Dictionary) -> Array:
	var events: Array = plot.get("events", []).duplicate()
	var fertilizer: Dictionary = plot.get("fertilizer", {})
	if not fertilizer.is_empty() and fertilizer["applied_at"] < plot["planted_at"] and fertilizer["expires_at"] > plot["planted_at"]:
		events.append({
			"t": fertilizer["applied_at"],
			"type": "fertilizer",
			"text": "播种前施用了%s，本轮同样有效。" % PlantDefs.FERTILIZERS[fertilizer["kind"]]["display_name"],
		})
	for entry in plot["preroll"]["encounters"]:
		events.append({
			"t": plot["planted_at"] + entry["offset"],
			"type": "encounter",
			"text": "正向遭遇：每个作物 +%d 分。" % entry["tier"],
		})
	events.append({
		"t": harvested_at,
		"type": "harvest",
		"text": "收获 %d 个作物（每个 %d 分）和 %d 粒新种子。" % [batch["count"], breakdown["per_crop_score"], plot["preroll"]["seed_count"]],
	})
	events.sort_custom(func(a, b): return a["t"] < b["t"])
	return events


func _roll_round(roll_seed: int, kind: String) -> Dictionary:
	# 抽取顺序固定：新种子数 → 波动百分比 → 每条遭遇（档位、发生时间），读档与重复结算不重抽。
	var randomizer := RandomNumberGenerator.new()
	randomizer.seed = roll_seed
	var defn := PlantDefs.get_plant(kind)
	var result := {
		"seed_count": randomizer.randi_range(2, 3),
		"fluctuation_pct": randomizer.randi_range(0, PlantDefs.FLUCTUATION_MAX_PCT),
		"encounters": [],
	}
	for encounter_index in range(defn["encounter_count"]):
		var tier: int = PlantDefs.ENCOUNTER_TIERS[randomizer.randi_range(0, PlantDefs.ENCOUNTER_TIERS.size() - 1)]
		var offset: int = randomizer.randi_range(0, defn["grow_seconds"] - 1)
		result["encounters"].append({"tier": tier, "offset": offset})
	return result


func _append_round_event(plot: Dictionary, now: int, type: String, text: String) -> void:
	var events: Array = plot.get("events", [])
	events.append({"t": now, "type": type, "text": text})
	while events.size() > ROUND_EVENT_LIMIT:
		events.pop_front()
	plot["events"] = events


func _empty_plot(plot_id: int) -> Dictionary:
	return {
		"id": plot_id,
		"seed_id": 0,
		"planted_at": 0,
		"ready_at": 0,
		"roll_seed": 0,
		"kind": "",
		"snapshot": {},
		"watered_segments": [],
		"fertilizer": {},
		"preroll": {},
		"events": [],
	}


func _new_seed(kind: String) -> Dictionary:
	return {"id": _take_id(), "kind": kind, "traits": []}


func _take_id() -> int:
	var result: int = state["next_id"]
	state["next_id"] = result + 1
	return result


func _percent_of(base: int, percent: int) -> int:
	return int(float(base * percent) / 100.0)


func _migrate_v1_to_v2(saved: Dictionary) -> Dictionary:
	var migrated := saved.duplicate(true)
	migrated["version"] = 2
	migrated["farming_exp"] = 0
	migrated["plant_exp"] = {}
	migrated["shop_level"] = 1
	migrated["can_level"] = 1
	migrated["fertilizers"] = {}
	for kind in PlantDefs.FERTILIZERS:
		migrated["fertilizers"][kind] = 0
	for plot in migrated["plots"]:
		plot["watered_segments"] = []
		plot["fertilizer"] = {}
		plot["events"] = []
		if plot["seed_id"] != 0:
			plot["kind"] = "cabbage"
			plot["snapshot"] = {"farming_level": 1, "plant_level": 1}
			plot["preroll"] = _roll_round(int(plot["roll_seed"]), "cabbage")
		else:
			plot["kind"] = ""
			plot["snapshot"] = {}
			plot["preroll"] = {}
	for batch in migrated["crop_batches"]:
		batch["kind"] = str(batch.get("kind", "cabbage"))
		if not batch.has("watered_segments"):
			batch["watered_segments"] = []
	return migrated


func _is_number(value: Variant) -> bool:
	return value is int or value is float


func _normalize_numbers(value: Variant) -> Variant:
	match typeof(value):
		TYPE_FLOAT:
			if fmod(value, 1.0) == 0.0:
				return int(value)
			return value
		TYPE_ARRAY:
			for index in range(value.size()):
				value[index] = _normalize_numbers(value[index])
			return value
		TYPE_DICTIONARY:
			for key in value:
				value[key] = _normalize_numbers(value[key])
			return value
		_:
			return value
	return value
