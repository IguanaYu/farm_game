extends SceneTree
## 2.5：目标判定与一次性奖励——结算钩子（带回统计/撤离计数）、种子转换、防重复领奖。


var failed := false


func _initialize() -> void:
	var game := FarmGame.new()
	game.new_game(1000)
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	# 三栏改版：武器与草帽先上装备槽（保证第 1 回合有牌），其余基础件入胸挂。
	for instance in inventory.warehouse_list().duplicate():
		if str(instance["def_id"]) == "old_shortsword":
			inventory.equip(int(instance["instance_id"]), "main_weapon")
		elif str(instance["def_id"]) == "straw_hat":
			inventory.equip(int(instance["instance_id"]), "helmet")
	for instance in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	var crafting := CraftingGame.new()
	crafting.bind(game)

	# —— 出发 → 撤离，带回铜片与种子 ——
	var depart := ExpeditionGame.depart(game, 1000)
	var expedition: ExpeditionGame = depart["game"]
	expedition.move_to(1, 0)
	var battle := expedition.start_battle()
	for enemy in battle["combat"].state["enemies"]:
		enemy["hp"] = 0
		enemy["alive"] = false
	battle["combat"]._events_check_outcome([])
	expedition.finish_battle(battle["combat"])
	## 直接给局内塞入"新战利品"（模拟搜刮领取）：铜片×1、带词条种子×1。
	var run_inventory := expedition.run_inventory()
	run_inventory.claim_reward("copper_scrap", "pack")
	var seed_claim := run_inventory.claim_reward("rock_sprout_seed", "safe")
	if seed_claim["ok"]:
		var seed_instance := run_inventory.find_instance(int(seed_claim["instance_id"]))
		seed_instance["seed_traits"] = [{"effect": "color_guarantee", "tier": 1}]
	expedition.leave_node()
	for row in [2, 3]:
		expedition.move_to(row, 0)
		if str(expedition.current_node()["type"]) in ["battle", "elite", "gate"]:
			var b := expedition.start_battle()
			for enemy in b["combat"].state["enemies"]:
				enemy["hp"] = 0
				enemy["alive"] = false
			b["combat"]._events_check_outcome([])
			expedition.finish_battle(b["combat"])
		expedition.leave_node()
	expedition.move_to(4, 0)
	var extract := expedition.extract()
	_check(extract["ok"], "结算：撤离成功")

	# —— 目标自动判定 ——
	var goals: Dictionary = {}
	for goal in crafting.goals_status():
		goals[str(goal["id"])] = goal
	_check(bool(goals["first_home"]["done"]), "目标：第一次安全回家（结算钩子）")
	_check(bool(goals["found_copper"]["done"]), "目标：发现铜片（带回统计）")
	_check(bool(goals["cave_life"]["done"]), "目标：洞里的新生命（保险箱保住的种子也算带回）")

	# —— 一次性领奖与解锁 ——
	var claim1 := crafting.claim_goal("first_home")
	_check(claim1["ok"], "领奖：第一次回家")
	_check(crafting.recipe_status("bandage")["unlocked"] and crafting.recipe_status("cabbage_soup")["unlocked"], "领奖：解锁绷带与汤配方")
	var seeds_after: Array = game.state["seeds"]
	_check(seeds_after.any(func(seed_entry): return str(seed_entry["kind"]) == "rock_sprout"), "转换：种子物品已转为农场种子")
	_check(game.state["expedition"]["inventory"]["warehouse"].all(func(instance): return str(instance["def_id"]) != "rock_sprout_seed"), "转换：仓库不再有种子物品")
	var converted_traits := []
	for seed_entry in seeds_after:
		if str(seed_entry["kind"]) == "rock_sprout":
			converted_traits = seed_entry["traits"]
	_check(converted_traits.size() == 1 and str(converted_traits[0]["effect"]) == "color_guarantee", "转换：洞窟词条保留在农场种子上")
	var claim_again := crafting.claim_goal("first_home")
	_check(not claim_again["ok"], "领奖：不能重复领取")
	var claim2 := crafting.claim_goal("cave_life")
	_check(claim2["ok"], "领奖：洞里的新生命")
	_check(game.state["expedition"]["crafting"]["plant_unlocks"].has("rock_sprout"), "领奖：解锁岩芽菜种类")

	_finish()


func _finish() -> void:
	if failed:
		push_error("D25_GOALS_SMOKE_FAIL")
	else:
		print("D25_GOALS_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
