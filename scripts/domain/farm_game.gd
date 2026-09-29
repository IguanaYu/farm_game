class_name FarmGame
extends RefCounted

const SAVE_VERSION := 3
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
		"warehouse_level": 1,
		"fertilizers": {},
		"breeder": _default_breeder(),
		"pending": {"crops": [], "seeds": []},
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


func _default_breeder() -> Dictionary:
	return {"owned": false, "level": 1, "template_seed_id": 0, "pending": 0, "progress": {}, "last_settled": 0}


func load_state(saved: Dictionary) -> bool:
	if saved.is_empty():
		return false
	var source := saved
	if int(saved.get("version", -1)) == 1:
		source = _migrate_v1_to_v2(saved)
	if int(source.get("version", -1)) == 2:
		source = _migrate_v2_to_v3(source)
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
	if int(source.get("warehouse_level", 0)) < 1 or int(source.get("warehouse_level", 0)) > BreedingDefs.WAREHOUSE_CAPACITY_BY_LEVEL.size():
		return false
	var breeder: Dictionary = source.get("breeder", {})
	if not breeder is Dictionary or not breeder.get("progress") is Dictionary:
		return false
	var pending: Dictionary = source.get("pending", {})
	if not pending is Dictionary or not pending.get("crops") is Array or not pending.get("seeds") is Array:
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
		if not seed.get("traits") is Array:
			return false
		for entry in seed["traits"]:
			if not entry is Dictionary or not BreedingDefs.get_effect(str(entry.get("effect", ""))) is Dictionary:
				return false
			if not BreedingDefs.EFFECTS.has(str(entry.get("effect", ""))):
				return false
			if not _is_number(entry.get("tier")):
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
	state["warehouse_level"] = int(state["warehouse_level"])
	var breeder_state: Dictionary = state["breeder"]
	breeder_state["level"] = int(breeder_state["level"])
	breeder_state["template_seed_id"] = int(breeder_state["template_seed_id"])
	breeder_state["pending"] = int(breeder_state["pending"])
	breeder_state["last_settled"] = int(breeder_state["last_settled"])
	for key in breeder_state["progress"]:
		breeder_state["progress"][key] = int(breeder_state["progress"][key])
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


## ---- 仓库（阶段 3） ----

func warehouse_capacity() -> int:
	return BreedingDefs.WAREHOUSE_CAPACITY_BY_LEVEL[int(state["warehouse_level"]) - 1]


func crop_slots_used() -> int:
	return state["crop_batches"].size() + state["pending"]["crops"].size()


func seed_slots_used() -> int:
	return _seed_slots_for(state["seeds"])


func _seed_slots_for(seeds: Array) -> int:
	var groups: Dictionary = {}
	for seed in seeds:
		var signature: String = BreedingDefs.seed_signature(seed)
		groups[signature] = groups.get(signature, 0) + 1
	var slots := 0
	for signature in groups:
		slots += int(ceil(float(groups[signature]) / BreedingDefs.SEED_STACK_MAX))
	return slots


func seed_slots_after_adding(extra_seeds: Array) -> int:
	return _seed_slots_for(state["seeds"] + extra_seeds)


func seed_groups() -> Array:
	## 返回仓库种子区的分组视图：[{signature, kind, traits, count, seed_ids: [..]}]，按品质降序。
	var groups: Dictionary = {}
	for seed in state["seeds"]:
		var signature: String = BreedingDefs.seed_signature(seed)
		if not groups.has(signature):
			groups[signature] = {"signature": signature, "kind": seed["kind"], "traits": seed.get("traits", []), "count": 0, "seed_ids": []}
		groups[signature]["count"] += 1
		groups[signature]["seed_ids"].append(seed["id"])
	var result: Array = groups.values()
	result.sort_custom(func(a, b):
		var quality_a: int = BreedingDefs.quality_score(a["traits"])
		var quality_b: int = BreedingDefs.quality_score(b["traits"])
		if quality_a != quality_b:
			return quality_a > quality_b
		return int(a["seed_ids"][0]) < int(b["seed_ids"][0]))
	return result


func claim_pending() -> Dictionary:
	## 腾出空间后领取待领取结果；只搬当前放得下的部分，重复领取不会产生新物品。
	var moved_crops := 0
	while not state["pending"]["crops"].is_empty() and state["crop_batches"].size() < warehouse_capacity():
		state["crop_batches"].append(state["pending"]["crops"].pop_front())
		moved_crops += 1
	var moved_seeds := 0
	while not state["pending"]["seeds"].is_empty() and seed_slots_after_adding([state["pending"]["seeds"][0]]) <= warehouse_capacity():
		state["seeds"].append(state["pending"]["seeds"].pop_front())
		moved_seeds += 1
	return {"crops": moved_crops, "seeds": moved_seeds}


func recycle_seed(seed_id: int) -> Dictionary:
	if int(state["breeder"]["template_seed_id"]) == seed_id:
		return {"ok": false, "message": "这粒种子是育种机模板，先在育种机里解除模板。"}
	for index in range(state["seeds"].size()):
		if int(state["seeds"][index]["id"]) == seed_id:
			state["seeds"].remove_at(index)
			state["coins"] += BreedingDefs.SEED_RECYCLE_PRICE
			return {"ok": true, "coins": BreedingDefs.SEED_RECYCLE_PRICE}
	return {"ok": false, "message": "找不到这粒种子。"}


func recycle_pending_seed(seed_id: int) -> Dictionary:
	for index in range(state["pending"]["seeds"].size()):
		if int(state["pending"]["seeds"][index]["id"]) == seed_id:
			state["pending"]["seeds"].remove_at(index)
			state["coins"] += BreedingDefs.SEED_RECYCLE_PRICE
			return {"ok": true, "coins": BreedingDefs.SEED_RECYCLE_PRICE}
	return {"ok": false, "message": "找不到这粒待领取种子。"}


func sell_pending_crop(batch_id: int) -> Dictionary:
	for index in range(state["pending"]["crops"].size()):
		var batch: Dictionary = state["pending"]["crops"][index]
		if int(batch["id"]) == batch_id:
			var price := batch_sale_price(batch)
			state["pending"]["crops"].remove_at(index)
			state["coins"] += price
			return {"ok": true, "coins": price}
	return {"ok": false, "message": "找不到这批待领取作物。"}


func upgrade_warehouse() -> String:
	var target := int(state["warehouse_level"]) + 1
	if not BreedingDefs.WAREHOUSE_UPGRADE_COSTS.has(target):
		return "仓库已达到当前版本的最高等级。"
	var cost: int = BreedingDefs.WAREHOUSE_UPGRADE_COSTS[target]
	if state["coins"] < cost:
		return "金币不足，升级仓库需要 %d 金币。" % cost
	state["coins"] -= cost
	state["warehouse_level"] = target
	return ""


## ---- 育种机（阶段 3） ----

func buy_breeder(now: int) -> String:
	if bool(state["breeder"]["owned"]):
		return "已经拥有育种机了。"
	if farming_level() < BreedingDefs.BREEDER_UNLOCK_FARMING_LEVEL:
		return "育种机需要种地等级 %d 解锁（当前 %d）。" % [BreedingDefs.BREEDER_UNLOCK_FARMING_LEVEL, farming_level()]
	if state["coins"] < BreedingDefs.BREEDER_BUY_COST:
		return "金币不足，购买育种机需要 %d 金币。" % BreedingDefs.BREEDER_BUY_COST
	state["coins"] -= BreedingDefs.BREEDER_BUY_COST
	state["breeder"]["owned"] = true
	state["breeder"]["level"] = 1
	state["breeder"]["last_settled"] = now
	return ""


func upgrade_breeder() -> String:
	if not bool(state["breeder"]["owned"]):
		return "还没有育种机。"
	var level := int(state["breeder"]["level"])
	if level >= 3:
		return "育种机已达到当前版本的最高等级。"
	var cost: int = BreedingDefs.BREEDER_LEVELS[level]["upgrade_cost"]
	if cost < 0:
		return "这一级升级价格待定，暂未开放。"
	if state["coins"] < cost:
		return "金币不足，升级育种机需要 %d 金币。" % cost
	state["coins"] -= cost
	state["breeder"]["level"] = level + 1
	return ""


func set_breeder_template(seed_id: int, now: int) -> Dictionary:
	breeder_settle(now)
	if not bool(state["breeder"]["owned"]):
		return {"ok": false, "message": "还没有育种机，请先到商店购买。"}
	if int(state["breeder"]["template_seed_id"]) == seed_id:
		return {"ok": false, "message": "这粒种子已经是模板了。"}
	for seed in state["seeds"]:
		if int(seed["id"]) == seed_id:
			state["breeder"]["template_seed_id"] = seed_id
			return {"ok": true}
	return {"ok": false, "message": "找不到这粒种子。"}


func clear_breeder_template(now: int) -> String:
	breeder_settle(now)
	if int(state["breeder"]["template_seed_id"]) == 0:
		return "当前没有模板。"
	state["breeder"]["template_seed_id"] = 0
	return ""


func breeder_settle(now: int) -> bool:
	## 结算育种机计时（含离线）。跨多个周期只产到机内容量上限；满了就暂停，不积累进度。
	var breeder: Dictionary = state["breeder"]
	if not bool(breeder["owned"]):
		breeder["last_settled"] = now
		return false
	var changed := false
	var template_id := int(breeder["template_seed_id"])
	var capacity := BreedingDefs.capacity(int(breeder["level"]))
	var cycle := BreedingDefs.cycle_seconds(int(breeder["level"]))
	var elapsed: int = maxi(0, now - int(breeder["last_settled"]))
	if template_id != 0:
		while elapsed > 0 and int(breeder["pending"]) < capacity:
			var have: int = int(breeder["progress"].get(template_id, 0))
			var need: int = cycle - have
			if elapsed >= need:
				breeder["pending"] = int(breeder["pending"]) + 1
				breeder["progress"][template_id] = 0
				elapsed -= need
				changed = true
			else:
				breeder["progress"][template_id] = have + elapsed
				elapsed = 0
				changed = true
	breeder["last_settled"] = now
	return changed


func breeder_status(now: int) -> Dictionary:
	breeder_settle(now)
	var breeder: Dictionary = state["breeder"]
	var template_id := int(breeder["template_seed_id"])
	var template: Dictionary = {}
	if template_id != 0:
		for seed in state["seeds"]:
			if int(seed["id"]) == template_id:
				template = seed
				break
	var cycle := BreedingDefs.cycle_seconds(int(breeder["level"]))
	var progress: int = int(breeder["progress"].get(template_id, 0)) if template_id != 0 else 0
	return {
		"owned": bool(breeder["owned"]),
		"level": int(breeder["level"]),
		"capacity": BreedingDefs.capacity(int(breeder["level"])),
		"pending": int(breeder["pending"]),
		"template_id": template_id,
		"template": template,
		"cycle_seconds": cycle,
		"progress_seconds": progress,
		"running": template_id != 0 and int(breeder["pending"]) < BreedingDefs.capacity(int(breeder["level"])),
	}


func collect_breeder(now: int) -> Dictionary:
	breeder_settle(now)
	var breeder: Dictionary = state["breeder"]
	var pending_count := int(breeder["pending"])
	if not bool(breeder["owned"]) or pending_count == 0:
		return {"ok": false, "message": "育种机里还没有副本。"}
	var template_id := int(breeder["template_seed_id"])
	var template: Dictionary = {}
	for seed in state["seeds"]:
		if int(seed["id"]) == template_id:
			template = seed
			break
	if template.is_empty():
		return {"ok": false, "message": "找不到模板种子，先重新设置模板。"}
	var copies: Array = []
	for copy_index in range(pending_count):
		copies.append(_new_seed(template["kind"], template.get("traits", []).duplicate(true)))
	if seed_slots_after_adding(copies) > warehouse_capacity():
		return {"ok": false, "message": "种子区空间不足，副本继续留在育种机里，请先整理或回收种子。"}
	for copy in copies:
		state["seeds"].append(copy)
	breeder["pending"] = 0
	return {"ok": true, "count": pending_count}


## ---- 育种规则（阶段 3） ----

func _generate_child_traits(parent_traits: Array, preserve: bool, mutation: bool, randomizer: RandomNumberGenerator) -> Array:
	## 判定顺序固定：亲本继承 → 保留后升档 → 按保留后条数判定一条全新词条。
	var rate_key := "preserve" if preserve else "normal"
	var kept: Array = []
	for entry in parent_traits:
		if randomizer.randf() < BreedingDefs.KEEP_RATE[rate_key]:
			kept.append({"effect": str(entry["effect"]), "tier": int(entry["tier"])})
	for entry in kept:
		var defn: Dictionary = BreedingDefs.EFFECTS[entry["effect"]]
		var max_tier: int = defn["tiers"].size() - 1
		if entry["tier"] >= max_tier:
			continue
		var rate: float = BreedingDefs.UPGRADE_RATES[defn["kind"]][entry["tier"]][rate_key]
		if randomizer.randf() < rate:
			entry["tier"] += 1
	var kept_count := kept.size()
	if kept_count < BreedingDefs.TRAIT_LIMIT:
		var new_rate: float = BreedingDefs.NEW_TRAIT_RATES[clampi(kept_count, 0, BreedingDefs.NEW_TRAIT_RATES.size() - 1)]
		if mutation:
			new_rate += BreedingDefs.NEW_TRAIT_RATE_BONUS_MUTATION
		if randomizer.randf() < new_rate:
			var owned: Dictionary = {}
			for entry in kept:
				owned[entry["effect"]] = true
			var candidates: Array = []
			for effect in BreedingDefs.EFFECTS:
				if not owned.has(effect):
					candidates.append(effect)
			if not candidates.is_empty():
				kept.append({"effect": candidates[randomizer.randi_range(0, candidates.size() - 1)], "tier": 0})
	return kept


func _allocate_attributes(plot: Dictionary, randomizer: RandomNumberGenerator) -> Dictionary:
	## 基础总点数 = 播种时种地等级 + 植物等级；先满足保底词条（可超总点数），剩余按权重随机分配。
	var snapshot: Dictionary = plot.get("snapshot", {"farming_level": 1, "plant_level": 1})
	var total: int = int(snapshot["farming_level"]) + int(snapshot["plant_level"])
	var attributes := {"water": 0, "fiber": 0, "color": 0}
	var weights := {"water": BreedingDefs.ATTRIBUTE_BASE_WEIGHT, "fiber": BreedingDefs.ATTRIBUTE_BASE_WEIGHT, "color": BreedingDefs.ATTRIBUTE_BASE_WEIGHT}
	var spent := 0
	for entry in plot.get("parent_traits", []):
		var defn: Dictionary = BreedingDefs.EFFECTS.get(str(entry.get("effect", "")), {})
		if defn.is_empty():
			continue
		if defn["kind"] == "guarantee":
			var points: int = defn["tiers"][int(entry.get("tier", 0))]
			attributes[defn["attribute"]] += points
			spent += points
		else:
			weights[defn["attribute"]] = BreedingDefs.ATTRIBUTE_BASE_WEIGHT * (1.0 + float(defn["tiers"][int(entry.get("tier", 0))]) / 100.0)
	var remaining: int = maxi(0, total - spent)
	for _point in range(remaining):
		var total_weight: float = weights["water"] + weights["fiber"] + weights["color"]
		var pick: float = randomizer.randf() * total_weight
		if pick < weights["water"]:
			attributes["water"] += 1
		elif pick < weights["water"] + weights["fiber"]:
			attributes["fiber"] += 1
		else:
			attributes["color"] += 1
	return attributes


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
	_plant_seed_at(plot, state["seeds"][seed_index], now)
	return ""


func plant_seed(plot_id: int, seed_id: int, now: int) -> String:
	var plot := get_plot(plot_id)
	if plot.is_empty():
		return "找不到这块地。"
	if plot["seed_id"] != 0:
		return "这块地正在生长，成熟后才能收获。"
	for index in range(state["seeds"].size()):
		if int(state["seeds"][index]["id"]) == seed_id:
			_plant_seed_at(plot, state["seeds"][index], now)
			return ""
	return "找不到这粒种子，它可能已被播种、回收或作为育种机模板。"


func _plant_seed_at(plot: Dictionary, seed: Dictionary, now: int) -> void:
	state["seeds"].erase(seed)
	var planted_kind: String = seed["kind"]
	var defn := PlantDefs.get_plant(planted_kind)
	plot["seed_id"] = seed["id"]
	plot["kind"] = planted_kind
	plot["planted_at"] = now
	plot["ready_at"] = now + defn["grow_seconds"]
	plot["roll_seed"] = int(roll_randomizer.randi())
	plot["parent_traits"] = seed.get("traits", []).duplicate(true)
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
	var round_fertilizer := active_fertilizer_for_round(plot)
	var child_randomizer := RandomNumberGenerator.new()
	child_randomizer.seed = int(plot["roll_seed"]) ^ 0x5eed
	var preserve := round_fertilizer == "preserve"
	var mutation := round_fertilizer == "mutation"
	var new_children: Array = []
	for child_index in range(preroll["seed_count"]):
		var traits := _generate_child_traits(plot.get("parent_traits", []), preserve, mutation, child_randomizer)
		new_children.append(_new_seed(kind, traits))
	var attributes := _allocate_attributes(plot, child_randomizer)
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
		"attributes": attributes,
		"planted_at": plot["planted_at"],
		"harvested_at": now,
	}
	var stored_crops := true
	if state["crop_batches"].size() < warehouse_capacity():
		state["crop_batches"].append(batch)
	else:
		state["pending"]["crops"].append(batch)
		stored_crops = false
	var stored_seeds := true
	if seed_slots_after_adding(new_children) <= warehouse_capacity():
		for child in new_children:
			state["seeds"].append(child)
	else:
		for child in new_children:
			state["pending"]["seeds"].append(child)
		stored_seeds = false
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
	plot["parent_traits"] = []
	return {
		"ok": true,
		"batch": batch.duplicate(true),
		"seeds": preroll["seed_count"],
		"exp_gain": exp_gain,
		"farming_level_up": farming_level() > farming_before,
		"plant_level_up": plant_level(kind) > plant_before,
		"events": events,
		"stored_crops": stored_crops,
		"stored_seeds": stored_seeds,
		"child_traits": new_children.map(func(child): return child["traits"].duplicate(true)),
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
		"parent_traits": [],
	}


func _new_seed(kind: String, traits: Array = []) -> Dictionary:
	return {"id": _take_id(), "kind": kind, "traits": traits}


func _migrate_v2_to_v3(saved: Dictionary) -> Dictionary:
	var migrated := saved.duplicate(true)
	migrated["version"] = 3
	migrated["warehouse_level"] = 1
	migrated["breeder"] = _default_breeder()
	migrated["pending"] = {"crops": [], "seeds": []}
	for plot in migrated["plots"]:
		if not plot.has("parent_traits"):
			plot["parent_traits"] = []
	for seed in migrated["seeds"]:
		if not seed.has("traits"):
			seed["traits"] = []
	for batch in migrated["crop_batches"]:
		if not batch.has("attributes"):
			batch["attributes"] = {"water": 0, "fiber": 0, "color": 0}
	return migrated


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
