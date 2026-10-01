class_name CraftingGame
extends RefCounted
## 制作/升级/目标的事务层（2.5）。绑定 farm_game.state 的 expedition 块与作物批次。
## 事务原则：一次扣料扣金币并生成成品；连续点击与重启不重复制作；取消不扣费。


var game: FarmGame
var expedition: Dictionary


func bind(farm_game: FarmGame) -> void:
	game = farm_game
	expedition = farm_game.state["expedition"]


func _crafting() -> Dictionary:
	return expedition.get("crafting", {})


# —— 查询 ————————————————————————————————————————————————————————


## 制作材料盘点：作物按批次计（锁定批次不自动消耗），物品只计未占用实例。
func material_counts() -> Dictionary:
	var inventory := InventoryGame.new()
	inventory.bind(expedition)
	var result := {}
	for instance in inventory.warehouse_list():
		var def := ItemDefs.get_item(str(instance["def_id"]))
		var key := "item:%s" % str(instance["def_id"])
		result[key] = int(result.get(key, 0)) + 1
	for batch in game.state["crop_batches"]:
		if bool(batch.get("locked", false)):
			continue
		var key := "crop:%s" % str(batch["kind"])
		result[key] = int(result.get(key, 0)) + int(batch["count"])
	return result


func recipe_status(recipe_id: String) -> Dictionary:
	var recipe := CraftingDefs.recipe(recipe_id)
	if recipe.is_empty():
		return {"known": false}
	var unlocked := is_recipe_unlocked(recipe_id)
	var counts := material_counts()
	var missing: Array = []
	for material in recipe["materials"]:
		var key := "%s:%s" % [str(material["kind"]), str(material["id"])]
		var have := int(counts.get(key, 0))
		if have < int(material["count"]):
			missing.append({"material": material, "have": have})
	var coins_ok := int(game.state["coins"]) >= int(recipe["coins"])
	return {
		"known": true,
		"unlocked": unlocked,
		"coins_ok": coins_ok,
		"missing": missing,
		"can_craft": unlocked and coins_ok and missing.is_empty(),
	}


func is_recipe_unlocked(recipe_id: String) -> bool:
	var recipe := CraftingDefs.recipe(recipe_id)
	var unlock: Dictionary = recipe.get("unlock", {"type": "always"})
	return _unlock_met(unlock)


func _unlock_met(unlock: Dictionary) -> bool:
	match str(unlock.get("type", "always")):
		"always":
			return true
		"goal":
			var goal_id := str(unlock.get("goal", ""))
			if bool(_crafting().get("goals", {}).get(goal_id, {}).get("done", false)):
				return true
			return _goal_condition_met(goal_id, _crafting().get("stats", {}))
		"stat":
			return _stat_value(str(unlock.get("stat", "")), str(unlock.get("id", ""))) >= int(unlock.get("value", 1))
		"any":
			for sub in unlock.get("of", []):
				if _unlock_met(sub):
					return true
			return false
	return false


func _stat_value(stat: String, id: String) -> int:
	var stats: Dictionary = _crafting().get("stats", {})
	match stat:
		"craft_copper_shortsword":
			return int(stats.get("craft_counts", {}).get("copper_shortsword", 0))
		"brought_total":
			var total := 0
			for entry in stats.get("brought", []):
				if typeof(entry) == TYPE_DICTIONARY and str(entry.get("id", "")) == id:
					total += int(entry.get("count", 0))
			return total
	return 0


## 目标完成判定（发现类按带回记录；制作类按实际制作；收获按农场记录）。
func goals_status() -> Array:
	var stats: Dictionary = _crafting().get("stats", {})
	var goals: Dictionary = _crafting().get("goals", {})
	var result: Array = []
	for goal_id in CraftingDefs.GOALS:
		var done := bool(goals.get(goal_id, {}).get("done", false))
		if not done:
			done = _goal_condition_met(goal_id, stats)
		result.append({
			"id": goal_id,
			"name": CraftingDefs.GOALS[goal_id]["name"],
			"done": done,
			"claimed": bool(goals.get(goal_id, {}).get("claimed", false)),
			"reward_text": CraftingDefs.GOALS[goal_id].get("reward_text", ""),
		})
	return result


func _goal_condition_met(goal_id: String, stats: Dictionary) -> bool:
	match goal_id:
		"first_home":
			return int(stats.get("extracts", 0)) >= 1
		"found_copper":
			return _brought_count(stats, "copper_scrap") >= 1
		"ready_gear":
			return int(stats.get("craft_counts", {}).get("copper_shortsword", 0)) >= 1
		"cave_life":
			return _brought_count(stats, "rock_sprout_seed") >= 1
		"first_rock_harvest":
			return int(stats.get("harvested", {}).get("rock_sprout", 0)) >= 1
		"together_home":
			return int(stats.get("coop_extracts", 0)) >= 1
		"deep_material":
			return _brought_count(stats, "iron_ore") >= 1
		"beat_guardian":
			return int(stats.get("gate_clears", 0)) >= 1
	return false


func _brought_count(stats: Dictionary, def_id: String) -> int:
	for entry in stats.get("brought", []):
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("id", "")) == def_id:
			return int(entry.get("count", 0))
	return 0


# —— 事务 ————————————————————————————————————————————————————————


## 制作一次：扣料（作物按低分未锁批次）＋扣金币 → 成品入库（满则进待领取区）。
func craft(recipe_id: String) -> Dictionary:
	var status := recipe_status(recipe_id)
	if not status.get("known", false):
		return _fail("未知配方")
	if not status["unlocked"]:
		return _fail("配方未解锁")
	if not status["coins_ok"]:
		return _fail("金币不足（需要 %d）" % int(CraftingDefs.recipe(recipe_id)["coins"]))
	if not status["missing"].is_empty():
		return _fail("材料不足")
	var recipe := CraftingDefs.recipe(recipe_id)
	# 1) 扣作物（低分优先、跳过锁定批次；已扣个数不入库不回滚）。
	for material in recipe["materials"]:
		if str(material["kind"]) == "crop":
			var taken := _take_crops(str(material["id"]), int(material["count"]))
			if taken != int(material["count"]):
				return _fail("作物批次数量不足（不应发生，请报告）")
	# 2) 扣物品材料（从仓库删除对应实例，占用中的不可用——material_counts 已过滤）。
	var inventory := InventoryGame.new()
	inventory.bind(expedition)
	for material in recipe["materials"]:
		if str(material["kind"]) != "item":
			continue
		var need := int(material["count"])
		for instance in inventory.warehouse_list().duplicate():
			if need <= 0:
				break
			if str(instance["def_id"]) == str(material["id"]):
				expedition["inventory"]["warehouse"].erase(instance)
				need -= 1
	# 3) 扣金币。
	game.state["coins"] = int(game.state["coins"]) - int(recipe["coins"])
	# 4) 成品入库（满则待领取区）。
	var output_id := str(recipe["output"])
	var added := _grant_output(output_id, 1)
	var stats: Dictionary = _crafting().get("stats", {})
	var counts: Dictionary = stats.get("craft_counts", {})
	counts[recipe_id] = int(counts.get(recipe_id, 0)) + 1
	stats["craft_counts"] = counts
	expedition["crafting"]["stats"] = stats
	return {"ok": true, "reason": "", "to_pending": not added}


func _take_crops(kind: String, count: int) -> int:
	## 从未锁定批次扣作物：低分优先（2.5 设计 §3：默认优先使用低评分且未锁定批次）。
	var batches: Array = game.state["crop_batches"]
	var candidates: Array = []
	for index in range(batches.size()):
		var batch: Dictionary = batches[index]
		if str(batch["kind"]) == kind and not bool(batch.get("locked", false)):
			candidates.append(index)
	candidates.sort_custom(func(a, b):
		return float(batches[a].get("base_score", 0)) < float(batches[b].get("base_score", 0)))
	var taken := 0
	for index in candidates:
		if taken >= count:
			break
		var batch: Dictionary = batches[index]
		var take := mini(count - taken, int(batch["count"]))
		batch["count"] = int(batch["count"]) - take
		taken += take
		if int(batch["count"]) == 0:
			batches.erase(batch)
	return taken


func _grant_output(def_id: String, count: int) -> bool:
	## 成品入库；对应分区满则进待领取区（2.5 设计 §2）。返回是否全部入正仓。
	var inventory := InventoryGame.new()
	inventory.bind(expedition)
	var zone := ExpeditionBaseline.warehouse_zone(def_id)
	var cap := ExpeditionBaseline.warehouse_capacity(expedition)
	var zone_used := 0
	for instance in expedition["inventory"]["warehouse"]:
		if ExpeditionBaseline.warehouse_zone(str(instance["def_id"])) == zone:
			zone_used += 1
	var all_stored := true
	for index in range(count):
		if zone_used < cap:
			var added := inventory.add_instance(def_id, "craft")
			if added["ok"]:
				zone_used += 1
				continue
		expedition["crafting"]["pending_items"].append({"def_id": def_id, "count": 1, "source": "craft"})
		all_stored = false
	return all_stored


## 待领取区领取：能放下的部分入仓，其余留下（不提供"完成结算"式锁定）。
func claim_pending() -> Dictionary:
	var inventory := InventoryGame.new()
	inventory.bind(expedition)
	var pending: Array = _crafting().get("pending_items", [])
	var moved := 0
	var remaining: Array = []
	for entry in pending:
		var def_id := str(entry["def_id"])
		var zone := ExpeditionBaseline.warehouse_zone(def_id)
		var cap := ExpeditionBaseline.warehouse_capacity(expedition)
		var zone_used := 0
		for instance in expedition["inventory"]["warehouse"]:
			if ExpeditionBaseline.warehouse_zone(str(instance["def_id"])) == zone:
				zone_used += 1
		if zone_used < cap:
			for copy in range(int(entry.get("count", 1))):
				if inventory.add_instance(def_id, "pending")["ok"]:
					moved += 1
					zone_used += 1
				else:
					remaining.append({"def_id": def_id, "count": 1, "source": "pending"})
		else:
			remaining.append(entry)
	expedition["crafting"]["pending_items"] = remaining
	return {"ok": true, "reason": "", "moved": moved, "remaining": remaining.size()}


## 设施升级（一次性，等级制）。材料与金币一次扣；失败不退级（本版无降级路径）。
func buy_upgrade(upgrade_id: String) -> Dictionary:
	var upgrade := CraftingDefs.upgrade(upgrade_id)
	if upgrade.is_empty():
		return _fail("未知升级")
	var levels: Dictionary = _crafting().get("upgrade_levels", {})
	var target := str(upgrade["target"])
	if int(levels.get(target, 1)) >= int(upgrade["to"]):
		return _fail("已达到该等级")
	if target == "chest" and not (_crafting().get("unlocked_upgrades", []) as Array).has(upgrade_id):
		return _fail("需要先达成「深层材料」目标（带回铁矿）解锁这项扩展")
	if int(game.state["coins"]) < int(upgrade["coins"]):
		return _fail("金币不足（需要 %d）" % int(upgrade["coins"]))
	var counts := material_counts()
	var inventory := InventoryGame.new()
	inventory.bind(expedition)
	for material in upgrade["materials"]:
		var key := "item:%s" % str(material["id"])
		if int(counts.get(key, 0)) < int(material["count"]):
			return _fail("材料不足：%s 需要 %d" % [ItemDefs.get_item(str(material["id"]))["name"], int(material["count"])])
	for material in upgrade["materials"]:
		var need := int(material["count"])
		for instance in expedition["inventory"]["warehouse"].duplicate():
			if need <= 0:
				break
			if str(instance["def_id"]) == str(material["id"]):
				expedition["inventory"]["warehouse"].erase(instance)
				need -= 1
	game.state["coins"] = int(game.state["coins"]) - int(upgrade["coins"])
	levels[target] = int(upgrade["to"])
	expedition["crafting"]["upgrade_levels"] = levels
	return {"ok": true, "reason": ""}


## 目标领奖：一次性发放（物品入待领取区或仓库、解锁配方/植物/升级）。
func claim_goal(goal_id: String) -> Dictionary:
	var goals: Dictionary = _crafting().get("goals", {})
	var entry: Dictionary = goals.get(goal_id, {})
	if bool(entry.get("claimed", false)):
		return _fail("奖励已领取过")
	if not bool(entry.get("done", false)) and not _goal_condition_met(goal_id, _crafting().get("stats", {})):
		return _fail("目标未完成")
	var goal := CraftingDefs.goal(goal_id)
	for item_id in goal.get("reward_items", []):
		_grant_output(str(item_id), 1)
	var unlocked: Array = _crafting().get("unlocked_recipes", [])
	for recipe_id in goal.get("reward_unlock_recipes", []):
		if not unlocked.has(str(recipe_id)):
			unlocked.append(str(recipe_id))
	expedition["crafting"]["unlocked_recipes"] = unlocked
	var plants: Array = _crafting().get("plant_unlocks", [])
	for plant_id in goal.get("reward_unlock_plants", []):
		if not plants.has(str(plant_id)):
			plants.append(str(plant_id))
	expedition["crafting"]["plant_unlocks"] = plants
	var upgrades: Array = _crafting().get("unlocked_upgrades", [])
	for upgrade_id in goal.get("reward_unlock_upgrades", []):
		if not upgrades.has(str(upgrade_id)):
			upgrades.append(str(upgrade_id))
	expedition["crafting"]["unlocked_upgrades"] = upgrades
	entry["done"] = true
	entry["claimed"] = true
	goals[goal_id] = entry
	expedition["crafting"]["goals"] = goals
	return {"ok": true, "reason": ""}


## 事实记录钩子（由结算/农场动作调用）。
func record_event(event: String, payload: Dictionary) -> void:
	var crafting: Dictionary = expedition.get("crafting", {})
	var stats: Dictionary = crafting.get("stats", {})
	match event:
		"extract":
			stats["extracts"] = int(stats.get("extracts", 0)) + 1
		"coop_extract":
			stats["coop_extracts"] = int(stats.get("coop_extracts", 0)) + 1
		"gate_clear":
			stats["gate_clears"] = int(stats.get("gate_clears", 0)) + 1
		"brought":
			var brought: Array = stats.get("brought", [])
			var found := false
			for entry in brought:
				if str(entry.get("id", "")) == str(payload.get("id", "")):
					entry["count"] = int(entry.get("count", 0)) + int(payload.get("count", 1))
					found = true
			if not found:
				brought.append({"id": str(payload.get("id", "")), "count": int(payload.get("count", 1))})
			stats["brought"] = brought
		"harvested":
			var harvested: Dictionary = stats.get("harvested", {})
			var kind := str(payload.get("kind", ""))
			harvested[kind] = int(harvested.get(kind, 0)) + int(payload.get("count", 1))
			stats["harvested"] = harvested
	crafting["stats"] = stats
	expedition["crafting"] = crafting


## 出售一件仓库物品：金币入农场档；基础装备与占用物不可售（2.5 设计 §2/§8）。
func sell_instance(def_id: String) -> Dictionary:
	var def := ItemDefs.get_item(def_id)
	if def.is_empty() or not bool(def.get("sellable", false)):
		return _fail("这件物品不可出售（基础装备不可售）")
	var inventory := InventoryGame.new()
	inventory.bind(expedition)
	for instance in expedition["inventory"]["warehouse"]:
		if str(instance["def_id"]) == def_id:
			expedition["inventory"]["warehouse"].erase(instance)
			var coins := int(def.get("base_value", 0))
			game.state["coins"] = int(game.state["coins"]) + coins
			game._record_ledger(int(Time.get_unix_time_from_system()), "expedition_sell_%s" % def_id, coins)
			return {"ok": true, "reason": "", "coins": coins}
	return _fail("仓库里没有这件物品")


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
