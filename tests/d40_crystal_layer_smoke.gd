extends SceneTree
## 第三层晶脉矿窟全链（方案 docs/plan/Godot_第三层晶脉矿窟_内容扩展_方案与执行计划_v0.1.md）。
## 覆盖：定义表与版本锚点、晶脉敌人遭遇、辉晶配方解锁→制作→扣料、
## 目标奖励星瓣花种子、星瓣花种植→市场→收获全链、商店 4 级门槛。
## 全部内存态 FarmGame，不写农场主档；层间衔接与整局通关由 d28 覆盖。


var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_definitions()
	_combat_smoke()
	_recipe_chain()
	_goal_reward()
	_star_bloom_chain()
	_finish()


# —— 定义表 ——————————————————————————————————————————————————————


func _definitions() -> void:
	_check(str(ExpeditionBaseline.PROTO_RULES_VERSION) == "d2-baseline-v0.2", "定义：规则版本升级 v0.2（内容变更）")
	var pools: Array = ExpeditionDefs.battle_pools("crystal_vein_deeps")
	_check((pools[0] as Array).has("radiant_cluster") and (pools[3] as Array).has("radiant_cluster"), "定义：晶脉战斗/采集池含辉晶簇")
	_check((ExpeditionDefs.gate_rewards("crystal_vein_deeps") as Array).has("star_bloom_seed"), "定义：第三层守门奖励含星瓣花种子")
	_check(ItemDefs.validate_definitions().is_empty(), "定义：新物品占格=牌数校验通过")
	_check((ExpeditionDefs.events_for_node(2, "crystal_vein_deeps") as Array).has("resonant_vein"), "定义：第三层第 2 排事件映射晶脉事件")
	_check(ExpeditionDefs.encounter_for({"type": "elite", "depth": 3}) == "layer3_elite", "定义：depth=3 精英遭遇泛化 layer3_elite")


# —— 晶脉敌人 ————————————————————————————————————————————————————


func _combat_smoke() -> void:
	var patrol := CombatGame.create([{"key": "p1", "name": "农夫", "max_hp": 40, "deck": CombatGame.basic_kit_demo_deck()}], "deep3_pair", 91, null, [])
	patrol.start()
	_check(patrol.state["enemies"].size() == 2, "晶脉敌人：巡逻遭遇两名敌人")
	var total_hp := 0
	for enemy in patrol.state["enemies"]:
		total_hp += int(enemy["hp"])
	_check(total_hp == 28 + 32, "晶脉敌人：晶脉爬虫 28＋暗渊蛾 32")
	var golem := CombatGame.create([{"key": "p1", "name": "农夫", "max_hp": 40, "deck": CombatGame.basic_kit_demo_deck()}], "deep3_hard", 93, null, [])
	golem.start()
	_check(int(golem.state["enemies"][0]["hp"]) == 42, "晶脉敌人：棱镜魔像 42 血")


# —— 辉晶配方链 ——————————————————————————————————————————————————


func _recipe_chain() -> void:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261300)
	game.new_game(1000)
	var crafting := CraftingGame.new()
	crafting.bind(game)
	_check(not crafting.is_recipe_unlocked("crystal_blade"), "配方：未带回辉晶簇前锁定")
	crafting.record_event("brought", {"id": "radiant_cluster", "count": 1})
	_check(crafting.is_recipe_unlocked("crystal_blade") and crafting.is_recipe_unlocked("crystal_aegis"), "配方：带回辉晶簇后解锁刃与盾")
	game.state["coins"] = 200
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	for count in range(5):
		inventory.add_instance("radiant_cluster", "loot")
	for count in range(2):
		inventory.add_instance("iron_ore", "loot")
	var crafted := crafting.craft("crystal_blade")
	_check(bool(crafted["ok"]), "配方：辉晶刃制作成功")
	_check(int(game.state["coins"]) == 200 - 45, "配方：制作扣 45 金币")
	var has_blade := false
	for instance in inventory.warehouse_list():
		if str(instance["def_id"]) == "crystal_blade":
			has_blade = true
	_check(has_blade, "配方：辉晶刃已入库")
	_check(not bool(crafting.craft("crystal_blade")["ok"]), "配方：材料不足时第二次制作被拒绝")


# —— 目标奖励 ————————————————————————————————————————————————————


func _goal_reward() -> void:
	var game := FarmGame.new()
	game.new_game(1000)
	var crafting := CraftingGame.new()
	crafting.bind(game)
	crafting.record_event("gate_clear", {})
	var beaten := false
	for goal in crafting.goals_status():
		if str(goal["id"]) == "beat_guardian":
			beaten = bool(goal["done"])
	_check(beaten, "目标：打穿整局（gate_clear）点亮「击穿晶脉矿窟」")
	_check(bool(crafting.claim_goal("beat_guardian")["ok"]), "目标：奖励领取成功")
	var got_seed := false
	for entry in game.state["expedition"]["crafting"].get("pending_items", []):
		if str(entry.get("def_id", "")) == "star_bloom_seed":
			got_seed = true
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	for instance in inventory.warehouse_list():
		if str(instance["def_id"]) == "star_bloom_seed":
			got_seed = true
	_check(got_seed, "目标：星瓣花种子已发放（仓库或待领取区）")
	_check(not bool(crafting.claim_goal("beat_guardian")["ok"]), "目标：重复领取被拒绝")


# —— 星瓣花全链 ——————————————————————————————————————————————————


func _star_bloom_chain() -> void:
	var game := FarmGame.new()
	game.new_game(1000)
	game.state["expedition"]["crafting"]["plant_unlocks"] = ["star_bloom"]
	_check(game.add_seed_with_traits("star_bloom", [{"effect": "fiber_guarantee", "tier": 1}]), "星瓣花：种子转换入种子区")
	var bloom_seed := {}
	for seed_entry in game.state["seeds"]:
		if str(seed_entry["kind"]) == "star_bloom":
			bloom_seed = seed_entry
	_check(not bloom_seed.is_empty(), "星瓣花：种子在种子区（带词条）")
	game.state["market"]["day_index"] = -1
	game.refresh_market(6000)
	_check(game.state["market"]["formulas"].has("star_bloom"), "星瓣花：解锁后进入市场公式")
	var plot_id := 1
	bloom_seed["id"] = 9920
	game.state["seeds"].erase(bloom_seed)
	game.state["seeds"].append(bloom_seed)
	_check(game.plant_seed(plot_id, 9920, 7000) == "", "星瓣花：可播种")
	game.get_plot(plot_id)["ready_at"] = 7000 + int(PlantDefs.get_plant("star_bloom")["grow_seconds"])
	var harvest := game.harvest(plot_id, 7000 + 14400)
	_check(harvest["ok"] and str(harvest["batch"]["kind"]) == "star_bloom", "星瓣花：收获成功（240 分钟档）")
	_check(int(harvest["batch"]["count"]) == 4, "星瓣花：4 个作物/茬")
	_check(game.seed_lock_reason("star_bloom").find("商店等级 4") >= 0, "星瓣花：购买门槛提示商店等级 4")


func _finish() -> void:
	if failed:
		push_error("D40_CRYSTAL_LAYER_FAIL")
	else:
		print("D40_CRYSTAL_LAYER_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
