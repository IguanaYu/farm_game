extends SceneTree
## 2.4：死亡结算（保险箱保护、耗尽不列损失）、恢复不重抽奖励、事件生命下限。


var failed := false


func _initialize() -> void:
	# —— 死亡：未保护损失、保险箱保留、耗尽药水不列 ——
	var game := _fresh_game_with_supplies()
	var depart := ExpeditionGame.depart(game, 1000)
	var expedition: ExpeditionGame = depart["game"]
	expedition.move_to(1, 0)
	var battle := expedition.start_battle()
	var combat: CombatGame = battle["combat"]
	combat.state["players"]["p1"]["hp"] = 3
	var seed_id := -1
	for instance in expedition.run["inventory"]["loadout"]["safe"]:
		seed_id = int(instance["instance_id"])
	var potion_id := -1
	for instance in expedition.run["inventory"]["loadout"]["pack"]:
		if str(instance["def_id"]) == "small_potion":
			potion_id = int(instance["instance_id"])
	# 先耗尽药水（模拟战斗中使用）。
	expedition.run_inventory().consume_use(potion_id)
	combat.end_turn("p1")  # 敌方攻击致死（3 血 vs 浅层组合）
	var death := expedition.finish_battle(combat)
	_check(death["ok"], "死亡：结算成功")
	var settlement: Dictionary = death["settlement"]
	_check(str(settlement["kind"]) == "death", "死亡：类型正确")
	var lost_names: Array = []
	for entry in settlement["lost"]:
		lost_names.append(str(entry["def_id"]))
	_check(lost_names.has("old_shortsword") and not lost_names.has("rock_sprout_seed"), "死亡：未保护损失、保险箱种子不在损失列")
	_check(not lost_names.has("small_potion"), "死亡：已耗尽的药水不再列为掉落（设计 §9）")
	_check(settlement["protected"].size() == 1 and int(settlement["protected"][0]["instance_id"]) == seed_id, "死亡：保险箱白名单物保留")
	_check(str(game.state["expedition"]["inventory"]["occupied_by_run"]) == "", "死亡：占用解除")
	var chest: Array = game.state["expedition"]["inventory"]["loadout"]["chest"]
	_check(chest.is_empty(), "死亡：农场侧带入装备被清除（短刀）")
	var safe: Array = game.state["expedition"]["inventory"]["loadout"]["safe"]
	_check(safe.size() == 1 and int(safe[0]["instance_id"]) == seed_id, "死亡：保险箱物品仍在农场战备")
	_check(game.state["expedition"]["inventory"]["warehouse"].size() == 1 and str(game.state["expedition"]["inventory"]["warehouse"][0]["def_id"]) == "pack_tools", "死亡：没有新增物入库（仓库只有留在家里的工具）")
	var farm_pack: Array = game.state["expedition"]["inventory"]["loadout"]["pack"]
	_check(farm_pack.is_empty(), "死亡：已消耗的药水从农场侧清除")

	# —— 恢复同一局：奖励固定不重抽 ——
	var game2 := _fresh_game()
	var depart2 := ExpeditionGame.depart(game2, 2000)
	var expedition2: ExpeditionGame = depart2["game"]
	expedition2.move_to(1, 0)
	var b2 := expedition2.start_battle()
	for enemy in b2["combat"].state["enemies"]:
		enemy["hp"] = 0
		enemy["alive"] = false
	b2["combat"]._events_check_outcome([])
	expedition2.finish_battle(b2["combat"])
	expedition2.leave_node()
	expedition2.move_to(2, 0)
	var key2 := expedition2.node_id(2, 0)
	var rewards_before: Array = (expedition2.run["resolved"][key2]["rewards"] as Array).duplicate()
	expedition2.save()
	## 模拟强退重开：从磁盘恢复同一局。
	var reloaded := ExpeditionGame.resume(game2)
	_check(reloaded["ok"], "恢复：局档可恢复")
	var expedition3: ExpeditionGame = reloaded["game"]
	_check((expedition3.run["resolved"][key2]["rewards"] as Array) == rewards_before, "恢复：已裁定奖励不重抽（数组相等）")

	# —— 事件：生命代价至少留 1 ——
	var game3 := _fresh_game()
	var depart3 := ExpeditionGame.depart(game3, 3000)
	var expedition4: ExpeditionGame = depart3["game"]
	_advance_to(expedition4, 3)
	_check(str(expedition4.current_node()["type"]) == "event", "事件：第 3 排候选 0 是事件")
	expedition4.run["player"]["hp"] = 3
	var too_hurt := expedition4.choose_event("squeeze")
	_check(not too_hurt["ok"], "事件：生命不足（3-4<1）不可选")
	expedition4.run["player"]["hp"] = 10
	var dig_or_leave := expedition4.choose_event("leave")
	_check(dig_or_leave["ok"], "事件：离开总是可选")
	_check(not expedition4.choose_event("squeeze")["ok"], "事件：完成后不可重选")

	_finish()


## 逐排推进并停在目标排（战斗节点直接判胜通过）。
func _advance_to(expedition: ExpeditionGame, target_row: int) -> void:
	for row in range(1, target_row):
		if str(expedition.run["phase"]) != "map":
			return
		expedition.move_to(row, 0)
		if str(expedition.current_node()["type"]) in ["battle", "elite", "gate"]:
			var b := expedition.start_battle()
			for enemy in b["combat"].state["enemies"]:
				enemy["hp"] = 0
				enemy["alive"] = false
			b["combat"]._events_check_outcome([])
			expedition.finish_battle(b["combat"])
		expedition.leave_node()
	expedition.move_to(target_row, 0)


func _fresh_game() -> FarmGame:
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
	return game


func _fresh_game_with_supplies() -> FarmGame:
	var game := _fresh_game()
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.move_to_warehouse(_find(inventory, "pack_tools"))
	var potion := inventory.add_instance("small_potion", "test")
	inventory.move_to_loadout(int(potion["instance_id"]), "pack")
	var seed := inventory.add_instance("rock_sprout_seed", "test")
	inventory.move_to_loadout(int(seed["instance_id"]), "safe")
	return game


func _find(inventory: InventoryGame, def_id: String) -> int:
	for instance in inventory.all_instances():
		if str(instance["def_id"]) == def_id:
			return int(instance["instance_id"])
	return -1


func _finish() -> void:
	if failed:
		push_error("D24_SETTLE_SMOKE_FAIL")
	else:
		print("D24_SETTLE_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
