class_name CorpseLootGame
extends RefCounted
## 固定尸体物资与搜索状态；隐藏物品仅存在权威局档，客户端得到可见投影。

const LEASE_MS := 10000
static var runtime_epoch := str(Time.get_unix_time_from_system()) + ":" + str(Time.get_ticks_usec())

static func build(run: Dictionary, node: Dictionary, encounter: String, rewards: Array, extras: Array, rng: RandomNumberGenerator) -> Array:
	var result: Array = []
	var enemies: Array = CombatGame.ENCOUNTERS.get(encounter, {}).get("enemies", [])
	for i in range(enemies.size()):
		var enemy := str(enemies[i])
		var regions: Array = []
		if enemy == "skeleton_scout":
			regions = [_region("weapon", "武器", Vector2i(1, 3)), _region("armor", "护具", Vector2i(2, 2)), _region("pouch", "腰包", Vector2i(2, 2)), _region("pack", "背包", Vector2i(3, 4))]
			_put(run, regions[0], str(CombatGame.ENEMIES[enemy]["equipment"]["weapon"]))
			_put(run, regions[1], str(CombatGame.ENEMIES[enemy]["equipment"]["armor"]))
			_put(run, regions[2], "bandage")
			_put(run, regions[3], "copper_scrap")
		else:
			regions = [_region("body", "遗骸", Vector2i(3, 4) if enemies.size() == 1 and str(node.get("type", "")) == "gate" else Vector2i(2, 3))]
		result.append({"id": "e%d" % (i + 1), "enemy_id": enemy, "name": str(CombatGame.ENEMIES[enemy]["name"]), "regions": regions})
	if result.is_empty():
		return result
	# 共享整场预算：普通战斗每人一份个人池抽取 + 一份额外物资，而非每具尸体复制整场奖励。
	var drops: Array = extras.duplicate()
	if not rewards.is_empty():
		if str(node.get("type", "")) == "gate":
			drops.append_array(rewards)
		else:
			for i in range(2 if bool(run.get("coop", false)) else 1):
				drops.append(rewards[rng.randi_range(0, rewards.size() - 1)])
	var has_skeleton := enemies.has("skeleton_scout")
	if has_skeleton:
		# 骷髅的实际配装已占用本场装备预算，只补一件包内材料。
		drops = ["fiber_clump"]
	for i in range(drops.size()):
		var source: Dictionary = result[i % result.size()]
		var regions: Array = source["regions"]
		var region: Dictionary = regions.back()
		var id := str(drops[i])
		if not _put(run, region, id):
			# 大型物品扩大遗骸区域，仍用真实格子检验，不丢弃已裁定掉落。
			region["size"] = [4, 4]
			if not _put(run, region, id):
				var overflow := _region("cache_%d" % i, "遗骸物资", ItemDefs.get_item(id)["size"])
				_put(run, overflow, id)
				regions.append(overflow)
	# 掉落品质只在生成尸体时裁定一次；搜查、重开面板、拿取都保留同一实例。
	for source in result:
		for region in source["regions"]:
			for item in region["items"]:
				var def := ItemDefs.get_item(str(item["def_id"]))
				if str(def.get("category", "")) in ["weapon", "armor", "tool"]:
					var roll := rng.randi_range(1, 100)
					var tier := 1 if roll <= 50 else (2 if roll <= 77 else (3 if roll <= 91 else (4 if roll <= 98 else 5)))
					item["quality"] = maxi(ItemDefs.quality_of(item), tier)
	return result

static func _region(id: String, title: String, size: Vector2i) -> Dictionary:
	return {"id": id, "name": title, "size": [size.x, size.y], "items": [], "searched": []}

static func _put(run: Dictionary, region: Dictionary, def_id: String) -> bool:
	var def := ItemDefs.get_item(def_id)
	var bounds := Vector2i(region["size"][0], region["size"][1])
	var occupied := {}
	for item in region["items"]:
		for cell in ExpeditionBaseline.cells_of(ItemDefs.get_item(str(item["def_id"]))["size"], Vector2i(item["cell"][0], item["cell"][1]), bool(item["rotated"])):
			occupied[ExpeditionBaseline.cell_key(cell)] = int(item["instance_id"])
	for rotated in [false, true]:
		for y in range(bounds.y):
			for x in range(bounds.x):
				if not ExpeditionBaseline.can_place_in(bounds, def["size"], Vector2i(x, y), rotated, occupied):
					continue
				var id := int(run.get("next_instance_id", 1000))
				run["next_instance_id"] = id + 1
				region["items"].append({"instance_id": id, "def_id": def_id, "quality": int(def.get("quality", 1)), "cell": [x, y], "rotated": rotated, "container": "corpse", "demo": false, "source": "corpse", "uses_remaining": int(def.get("uses", 1)), "revealed": false, "taken": false})
				return true
	return false

static func region_of(resolved: Dictionary, source_id: String, region_id: String) -> Dictionary:
	for source in resolved.get("corpses", []):
		if str(source["id"]) == source_id:
			for region in source["regions"]:
				if str(region["id"]) == region_id:
					return region
	return {}

static func _source_of(resolved: Dictionary, source_id: String) -> Dictionary:
	for source in resolved.get("corpses", []):
		if str(source["id"]) == source_id:
			return source
	return {}

static func _held_by_other(run: Dictionary, member: String, source_id: String, region_id: String) -> bool:
	for other in run.get("loot_searches", {}):
		if other != member:
			var active: Dictionary = run["loot_searches"][other]
			if str(active["source"]) == source_id and str(active["region"]) == region_id:
				return true
	return false

static func _flush_empty(region: Dictionary) -> void:
	## 空格不进搜索计时：进入区域时直接判为已检查，只留真正藏物品的占格排队。
	var occupied := {}
	for item in region["items"]:
		if bool(item.get("taken", false)):
			continue
		for cell in ExpeditionBaseline.cells_of(ItemDefs.get_item(str(item["def_id"]))["size"], Vector2i(item["cell"][0], item["cell"][1]), bool(item["rotated"])):
			occupied[ExpeditionBaseline.cell_key(cell)] = true
	var searched: Array = region["searched"]
	for i in range(int(region["size"][0]) * int(region["size"][1])):
		var cell := Vector2i(i % int(region["size"][0]), i / int(region["size"][0]))
		if not occupied.has(ExpeditionBaseline.cell_key(cell)) and not searched.any(func(value): return int(value) == i):
			searched.append(i)

static func _next_item_cell(region: Dictionary) -> int:
	var width := int(region["size"][0])
	var best := -1
	for item in region["items"]:
		if bool(item.get("revealed", false)) or bool(item.get("taken", false)):
			continue
		for cell in ExpeditionBaseline.cells_of(ItemDefs.get_item(str(item["def_id"]))["size"], Vector2i(item["cell"][0], item["cell"][1]), bool(item["rotated"])):
			var index: int = cell.y * width + cell.x
			if best < 0 or index < best:
				best = index
	return best

static func _item_at(region: Dictionary, index: int) -> Dictionary:
	var cell := Vector2i(index % int(region["size"][0]), index / int(region["size"][0]))
	for item in region["items"]:
		var cells := ExpeditionBaseline.cells_of(ItemDefs.get_item(str(item["def_id"]))["size"], Vector2i(item["cell"][0], item["cell"][1]), bool(item["rotated"]))
		if cells.has(cell):
			return item
	return {}

static func _footprint(item: Dictionary) -> Dictionary:
	var dimensions: Vector2i = ItemDefs.get_item(str(item["def_id"]))["size"]
	if bool(item["rotated"]):
		dimensions = Vector2i(dimensions.y, dimensions.x)
	# 未揭晓时只公开占格轮廓，不公开定义、实例 ID 或属性。
	return {"cell": item["cell"].duplicate(), "size": [dimensions.x, dimensions.y]}

static func expire(run: Dictionary, now: int) -> void:
	var sessions: Dictionary = run.get("loot_searches", {})
	for member in sessions.keys():
		var session: Dictionary = sessions[member]
		if str(session.get("epoch", "")) != runtime_epoch or now - int(session["started"]) > LEASE_MS:
			sessions.erase(member)

static func cancel(run: Dictionary, member := "") -> void:
	if member == "":
		run["loot_searches"] = {}
	else:
		(run.get("loot_searches", {}) as Dictionary).erase(member)

static func _begin_cell(run: Dictionary, region: Dictionary, member: String, key: String, source_id: String, region_id: String, now: int) -> bool:
	_flush_empty(region)
	var next := _next_item_cell(region)
	if next < 0:
		return false
	var item := _item_at(region, next)
	var sessions: Dictionary = run.get("loot_searches", {})
	sessions[member] = {"node": key, "source": source_id, "region": region_id, "cell": next, "started": now, "duration": ItemDefs.search_ms(ItemDefs.quality_of(item)), "epoch": runtime_epoch}
	run["loot_searches"] = sessions
	return true

static func _chain(run: Dictionary, resolved: Dictionary, key: String, member: String, source_id: String, now: int) -> Dictionary:
	## 区域搜完自动按顺序接续同尸体的下一个有待揭晓物品的区域；队友占用的跳过。
	for region in _source_of(resolved, source_id).get("regions", []):
		var id := str(region["id"])
		if _held_by_other(run, member, source_id, id):
			continue
		if _begin_cell(run, region, member, key, source_id, id, now):
			return {"ok": true}
	return {"ok": true, "complete": true}

static func start(run: Dictionary, resolved: Dictionary, key: String, member: String, source_id: String, region_id: String, now: int) -> Dictionary:
	expire(run, now)
	var region := region_of(resolved, source_id, region_id)
	if region.is_empty():
		return {"ok": false, "reason": "搜索区域不存在"}
	if _held_by_other(run, member, source_id, region_id):
		return {"ok": false, "reason": "队友正在搜索这个区域"}
	if _begin_cell(run, region, member, key, source_id, region_id, now):
		return {"ok": true}
	# 指定区域已无待揭晓物品（空格已直接判完）：接续下一个区域，不再要求手点。
	cancel(run, member)
	return _chain(run, resolved, key, member, source_id, now)

static func step(run: Dictionary, resolved: Dictionary, member: String, now: int) -> Dictionary:
	expire(run, now)
	var session: Dictionary = run.get("loot_searches", {}).get(member, {})
	if session.is_empty():
		return {"ok": false, "reason": "搜索已中断，请重新开始"}
	if now < int(session["started"]) + int(session["duration"]):
		return {"ok": false, "reason": "还在搜索中"}
	var region := region_of(resolved, str(session["source"]), str(session["region"]))
	if region.is_empty():
		return {"ok": false, "reason": "搜索区域已离开"}
	var item := _item_at(region, int(session["cell"]))
	if item.is_empty():
		region["searched"].append(int(session["cell"]))
	else:
		item["revealed"] = true
		for cell in ExpeditionBaseline.cells_of(ItemDefs.get_item(str(item["def_id"]))["size"], Vector2i(item["cell"][0], item["cell"][1]), bool(item["rotated"])):
			var index: int = cell.y * int(region["size"][0]) + cell.x
			if not (region["searched"] as Array).any(func(value): return int(value) == index):
				region["searched"].append(index)
	if _begin_cell(run, region, member, str(session["node"]), str(session["source"]), str(session["region"]), now):
		return {"ok": true}
	cancel(run, member)
	return _chain(run, resolved, str(session["node"]), member, str(session["source"]), now)

static func view(run: Dictionary, now: int) -> Dictionary:
	var visible := run.duplicate(true)
	visible.erase("rng_seed")
	visible.erase("rng_state")
	for enemy in visible.get("battle", {}).get("enemies", []):
		enemy.erase("equipment")
	for key in visible.get("resolved", {}):
		var resolved: Dictionary = visible["resolved"][key]
		for source in resolved.get("corpses", []):
			for region in source["regions"]:
				region["unknown"] = []
				for item in region["items"]:
					if not bool(item.get("revealed", false)) and not bool(item.get("taken", false)):
						region["unknown"].append(_footprint(item))
				region["items"] = (region["items"] as Array).filter(func(item): return bool(item.get("revealed", false)))
	var sessions := {}
	for member in run.get("loot_searches", {}):
		var session: Dictionary = run["loot_searches"][member]
		if str(session.get("epoch", "")) != runtime_epoch or now - int(session["started"]) > LEASE_MS:
			continue
		var region := region_of(run.get("resolved", {}).get(str(session["node"]), {}), str(session["source"]), str(session["region"]))
		if region.is_empty():
			continue
		var item := _item_at(region, int(session["cell"]))
		var footprint := _footprint(item) if not item.is_empty() else {"cell": [int(session["cell"]) % int(region["size"][0]), int(session["cell"]) / int(region["size"][0])], "size": [1, 1]}
		sessions[member] = {"source": session["source"], "region": session["region"], "cell": session["cell"], "footprint": footprint, "duration": session["duration"], "remaining": maxi(0, int(session["started"]) + int(session["duration"]) - now), "step": "%s:%s:%d:%d" % [session["source"], session["region"], int(session["cell"]), int(session["started"])]}
	visible["loot_searches"] = sessions
	return visible
