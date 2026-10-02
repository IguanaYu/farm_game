extends SceneTree
## 2.8：第二层内容——层间衔接、深层奖励池、新敌人/首领、萤果全链、内容预算核对。
## 内容扩展轮：预算扩到第三层（晶脉矿窟），通关断言移到第三层守门后。


var failed := false


func _initialize() -> void:
	# —— 内容预算核对（总计划 §10-2.8 ＋ 内容扩展轮）——
	_check(ItemDefs.ITEMS.size() - 3 == 24, "预算：正式物品 24 种（20＋扩展轮 4）")
	_check(CardDefs.CARDS.size() == 19, "预算：牌效果模板 %d 个（17＋扩展轮 2）" % CardDefs.CARDS.size())
	var enemy_count := 0
	for def_id in CombatGame.ENEMIES:
		if str(CombatGame.ENEMIES[def_id]["name"]).find("首领") < 0:
			enemy_count += 1
	_check(enemy_count == 9, "预算：普通敌人 9 种（浅 3＋深 3＋晶脉 3）")
	_check(ExpeditionDefs.DEEP_EVENTS.size() == 6 and ExpeditionDefs.EVENTS.size() == 3, "预算：事件 9 个（浅 3＋深 6）")
	_check(PlantDefs.is_known_plant("glow_berry") and PlantDefs.is_known_plant("star_bloom"), "预算：稀有植物第 2/3 种（萤果/星瓣花）")
	_check(CombatGame.ENCOUNTERS.has("layer2_guardian") and CombatGame.ENCOUNTERS.has("layer3_guardian"), "预算：两层首领遭遇（根须守卫/晶暴君）")

	# —— 第二层图与连通 ——
	var layer2 := ExpeditionDefs.layer("iron_root_deeps")
	_check(not layer2.is_empty() and int(layer2["rows"]) == 9, "第二层：9 排（0~8）")
	_check(str(layer2["map"][4][0]["type"]) == "rest_exit" and str(layer2["map"][7][0]["type"]) == "exit", "第二层：4/7 排撤离站")
	_check(str(layer2["map"][8][0]["type"]) == "gate", "第二层：第 8 排首领")

	# —— 第三层图与连通 ——
	var layer3 := ExpeditionDefs.layer("crystal_vein_deeps")
	_check(not layer3.is_empty() and int(layer3["rows"]) == 9, "第三层：9 排（0~8）")
	_check(str(layer3["map"][4][0]["type"]) == "rest_exit" and str(layer3["map"][7][0]["type"]) == "exit", "第三层：4/7 排撤离站")
	_check(str(layer3["map"][8][0]["type"]) == "gate", "第三层：第 8 排首领")
	_check(ExpeditionDefs.next_layer("moss_stone_shallow") == "iron_root_deeps" \
			and ExpeditionDefs.next_layer("iron_root_deeps") == "crystal_vein_deeps" \
			and ExpeditionDefs.next_layer("crystal_vein_deeps") == "", "第三层：层间顺序链 moss→iron→crystal→结算")

	# —— 层间衔接：第一层守门战胜利 → 同局进入第二层 ——
	var game := _fresh_game()
	var depart := ExpeditionGame.depart(game, 1000)
	var expedition: ExpeditionGame = depart["game"]
	_advance_all(expedition, 8)
	_check(str(expedition.run["layer_id"]) == "iron_root_deeps", "衔接：第一层通关后进入第二层（同一局）")
	_check(int(expedition.run["current"]["row"]) == 0 and str(expedition.run["phase"]) == "map", "衔接：第二层从第 0 排重新出发")
	_check(int(expedition.run["player"]["hp"]) > 0, "衔接：生命延续（不重置满血）")
	## 第二层节点裁定走深层池（奖励固定后含铁矿类）。
	expedition.move_to(1, 1)  # 第二层第 1 排候选 1 是采集（铁矿脉）
	var gather_key := expedition.node_id(1, 1)
	var gather_node: Dictionary = expedition.run["map"]["rows"][1][1]
	if str(gather_node["type"]) == "gather":
		var rewards: Array = expedition.run["resolved"][gather_key]["rewards"]
		_check(not rewards.is_empty(), "第二层：采集节点按深层池裁定（铁矿类）")
		var iron_def := "copper_scrap"
		for candidate in rewards:
			if str(candidate) == "iron_ore":
				iron_def = str(candidate)
				break
		var claim_iron := expedition.run_inventory().claim_reward(iron_def, "pack")
		_check(claim_iron["ok"], "第二层：领取深层采集物（入背包）")
	else:
		expedition.move_to(1, 0)
		_check(str(expedition.current_node()["type"]) == "battle", "第二层：第 1 排候选 0 是深层战斗")
	if str(expedition.run["phase"]) == "node":
		expedition.leave_node()

	# —— 第二层首领战 → 衔接第三层（同一局）——
	_advance_all(expedition, 8)
	_check(str(expedition.run["layer_id"]) == "crystal_vein_deeps", "衔接：第二层通关后进入第三层（同一局）")
	_check(int(expedition.run["current"]["row"]) == 0 and str(expedition.run["phase"]) == "map", "衔接：第三层从第 0 排重新出发")
	## 第三层节点裁定走晶脉池（采集三件候选全为辉晶/铁矿类）。
	expedition.move_to(1, 1)  # 第三层第 1 排候选 1 是采集（辉晶矿脉）
	var l3_key := expedition.node_id(1, 1)
	if str(expedition.run["map"]["rows"][1][1]["type"]) == "gather":
		var l3_rewards: Array = expedition.run["resolved"][l3_key]["rewards"]
		_check(l3_rewards.has("radiant_cluster"), "第三层：采集节点按晶脉池裁定（辉晶簇）")
		var radiant_claim := expedition.run_inventory().claim_reward("radiant_cluster", "pack")
		_check(radiant_claim["ok"], "第三层：领取辉晶簇（入背包）")
	if str(expedition.run["phase"]) == "node":
		expedition.leave_node()

	# —— 第三层首领战 → 整局通关结算 ——
	_advance_all(expedition, 8)
	_check(str(expedition.run["outcome"]) == "gate_clear", "通关：第三层首领胜利 → gate_clear 结算（打穿三层）")
	_check(str(expedition.run.get("settlement_id", "")) != "", "通关：结算 ID 已生成")

	# —— 深层奖励含铁矿/辉晶：目标与配方解锁链 ——
	var stats: Dictionary = game.state["expedition"]["crafting"]["stats"]
	var iron_brought := 0
	var radiant_brought := 0
	for entry in stats.get("brought", []):
		if str(entry.get("id", "")) == "iron_ore":
			iron_brought = int(entry.get("count", 0))
		if str(entry.get("id", "")) == "radiant_cluster":
			radiant_brought = int(entry.get("count", 0))
	_check(iron_brought >= 1, "成长：铁矿带回计入「深层材料」目标")
	_check(radiant_brought >= 1, "成长：辉晶簇带回解锁辉晶配方（stat 口径）")

	# —— 萤果全链：种子转换 → 解锁 → 种植 ——
	var game2 := FarmGame.new()
	game2.new_game(1000)
	game2.state["expedition"]["crafting"]["plant_unlocks"] = ["glow_berry"]
	_check(game2.add_seed_with_traits("glow_berry", [{"effect": "fiber_guarantee", "tier": 1}]), "萤果：种子转换入种子区")
	var berry_seed := {}
	for seed_entry in game2.state["seeds"]:
		if str(seed_entry["kind"]) == "glow_berry":
			berry_seed = seed_entry
	_check(not berry_seed.is_empty(), "萤果：种子在种子区（带词条）")
	game2.state["market"]["day_index"] = -1
	game2.refresh_market(6000)
	_check(game2.state["market"]["formulas"].has("glow_berry"), "萤果：解锁后进入市场公式")
	var plant_plot := 1
	berry_seed["id"] = 9910
	game2.state["seeds"].erase(berry_seed)
	game2.state["seeds"].append(berry_seed)
	_check(game2.plant_seed(plant_plot, 9910, 7000) == "", "萤果：可播种")
	game2.get_plot(plant_plot)["ready_at"] = 7000 + int(PlantDefs.get_plant("glow_berry")["grow_seconds"])
	var harvest := game2.harvest(plant_plot, 7000 + 7200)
	_check(harvest["ok"] and str(harvest["batch"]["kind"]) == "glow_berry", "萤果：收获成功（120 分钟档）")
	_check(int(harvest["batch"]["count"]) == 4, "萤果：4 个作物/茬")

	# —— 新敌人规则冒烟 ——
	var combat := CombatGame.create([{"key": "p1", "name": "农夫", "max_hp": 40, "deck": CombatGame.basic_kit_demo_deck()}], "deep_hard", 81, null, [])
	combat.start()
	_check(int(combat.state["enemies"][0]["hp"]) == 32, "深层敌人：矿偶 32 血")
	var boss := CombatGame.create([{"key": "p1", "name": "农夫", "max_hp": 40, "deck": CombatGame.basic_kit_demo_deck()}], "layer2_guardian", 83, null, [])
	boss.start()
	_check(int(boss.state["enemies"][0]["hp"]) == 60, "首领：根须守卫 60 血")
	var intent_text := str(boss.enemy_intents()[0]["text"])
	_check(intent_text.find("攻击 6×2") >= 0, "首领：首意图为 6×2 双段攻击")
	var tyrant := CombatGame.create([{"key": "p1", "name": "农夫", "max_hp": 40, "deck": CombatGame.basic_kit_demo_deck()}], "layer3_guardian", 85, null, [])
	tyrant.start()
	_check(int(tyrant.state["enemies"][0]["hp"]) == 90, "晶脉首领：晶暴君 90 血")
	_check(str(tyrant.enemy_intents()[0]["text"]).find("攻击 7×2") >= 0, "晶脉首领：首意图为 7×2 双段攻击")

	_finish()


## 逐排推进并打完所有战斗节点；to_gate=true 时打到第 8 排守门战。
func _advance_all(expedition: ExpeditionGame, target_row: int, to_gate := false) -> void:
	for row in range(1, target_row + 1):
		if str(expedition.run["phase"]) == "over":
			return
		if str(expedition.run["phase"]) != "map":
			return
		expedition.move_to(row, 0)
		var node := expedition.current_node()
		if node.is_empty():
			return
		if str(node["type"]) in ["battle", "elite", "gate"]:
			var battle := expedition.start_battle()
			if not battle["ok"]:
				return
			for enemy in battle["combat"].state["enemies"]:
				enemy["hp"] = 0
				enemy["alive"] = false
			battle["combat"]._events_check_outcome([])
			expedition.finish_battle(battle["combat"])
		var leave := expedition.leave_node()
		if leave.has("layer_changed"):
			return


func _fresh_game() -> FarmGame:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261200)
	game.new_game(1000)
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	for instance in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	return game


func _finish() -> void:
	if failed:
		push_error("D28_CONTENT_SMOKE_FAIL")
	else:
		print("D28_CONTENT_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
