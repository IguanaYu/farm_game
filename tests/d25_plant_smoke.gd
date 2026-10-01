extends SceneTree
## 2.5：岩芽菜完整接入——植物定义、市场公式解锁、种子购买门槛、种子转换与收获。


var failed := false
var game: FarmGame


func _initialize() -> void:
	game = FarmGame.new()
	game.set_debug_random_seed(20261004)
	game.new_game(1000)

	# —— 植物定义齐全（设计 §6：生长/分数/作物数/浇水段/遭遇/经验）——
	var def := PlantDefs.get_plant("rock_sprout")
	_check(not def.is_empty(), "植物：岩芽菜已注册")
	_check(int(def["grow_seconds"]) == 3600 and int(def["base_score"]) == 600, "植物：60 分钟档位、基准 600")
	_check(int(def["crop_count"]) == 5 and int(def["water_segments"]) == 1 and int(def["encounter_count"]) == 2, "植物：5 作物/1 浇水段/2 遭遇")
	_check(int(def["harvest_exp"]) == 60, "植物：收获经验 60")

	# —— 市场公式：解锁后纳入，未解锁不纳入 ——
	game.state["market"]["day_index"] = -1
	game.refresh_market(5000)
	_check(not game.state["market"]["formulas"].has("rock_sprout"), "市场：未解锁时不生成岩芽菜公式")
	game.state["expedition"]["crafting"]["plant_unlocks"] = ["rock_sprout"]
	game.state["market"]["day_index"] = -1
	game.refresh_market(5000)
	_check(game.state["market"]["formulas"].has("rock_sprout"), "市场：解锁后生成岩芽菜公式")
	_check(game.state["market"]["formulas"].has("cabbage") and game.state["market"]["formulas"].has("carrot"), "市场：原两种植物不受影响")

	# —— 种子购买门槛：先解锁种类，再商店 3 级 ——
	_check(game.seed_lock_reason("rock_sprout") != "", "购买：未解锁种类时被拒")
	game.state["expedition"]["crafting"]["plant_unlocks"] = ["rock_sprout"]
	_check(game.seed_lock_reason("rock_sprout") != "", "购买：商店等级不足（需 3 级）")
	game.state["shop_level"] = 3
	_check(game.seed_lock_reason("rock_sprout") == "", "购买：解锁＋3 级商店可买")
	var coins_before := int(game.state["coins"])
	game.state["coins"] = 100
	_check(game.buy_seeds(1, "rock_sprout") == "", "购买：岩芽菜基础种子成功")
	_check(game.state["seeds"].any(func(seed_entry): return str(seed_entry["kind"]) == "rock_sprout"), "购买：种子入种子区")
	game.state["coins"] = coins_before

	# —— 种子转换与完整种植循环 ——
	_check(game.add_seed_with_traits("rock_sprout", [{"effect": "water_guarantee", "tier": 2}]), "转换：洞窟种子（带词条）入种子区")
	var converted := {}
	for seed_entry in game.state["seeds"]:
		if str(seed_entry["kind"]) == "rock_sprout" and not (seed_entry["traits"] as Array).is_empty():
			converted = seed_entry
	_check(not converted.is_empty() and (converted["traits"] as Array).size() == 1, "转换：词条保留")
	var plot_id := 1
	game.state["seeds"].erase(converted)
	converted["id"] = 9900
	game.state["seeds"].append(converted)
	_check(game.plant_seed(plot_id, int(converted["id"]), 6000) == "", "种植：岩芽菜可播种")
	var plot := game.get_plot(plot_id)
	_check(str(plot["kind"]) == "rock_sprout", "种植：地块种类正确")
	plot["ready_at"] = 6000 + int(PlantDefs.get_plant("rock_sprout")["grow_seconds"])
	var harvest := game.harvest(plot_id, 6000 + 3600)
	_check(harvest["ok"] and str(harvest["batch"]["kind"]) == "rock_sprout", "收获：岩芽菜成熟收获")
	_check(int(harvest["batch"]["count"]) == 5, "收获：5 个作物")
	var crafting := CraftingGame.new()
	crafting.bind(game)
	crafting.record_event("harvested", {"kind": "rock_sprout", "count": 5})
	_check(crafting.goals_status().any(func(goal): return str(goal["id"]) == "first_rock_harvest" and bool(goal["done"])), "目标：第一茬岩芽完成")

	_finish()


func _finish() -> void:
	if failed:
		push_error("D25_PLANT_SMOKE_FAIL")
	else:
		print("D25_PLANT_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
