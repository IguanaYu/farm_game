extends SceneTree
## 2.4：出发事务、地图推进、战斗接入、搜刮、撤离结算、幂等应用。


var failed := false


func _initialize() -> void:
	var game := _fresh_game()
	# —— 出发事务 ——
	var depart := ExpeditionGame.depart(game, 1000)
	_check(depart["ok"], "出发：事务成功")
	if not depart["ok"]:
		_finish()
		return
	var expedition: ExpeditionGame = depart["game"]
	var run_id := str(expedition.run["run_id"])
	_check(str(game.state["expedition"]["inventory"]["occupied_by_run"]) == run_id, "出发：农场侧写入占用")
	_check(str(game.state["expedition"]["active_run_ref"]) == run_id, "出发：活动局引用")
	_check(FileAccess.file_exists(ExpeditionStore.run_path(run_id)), "出发：局档落盘")
	_check(int(expedition.run["player"]["hp"]) == 40, "出发：生命初始化 40/40")
	_check(not ExpeditionGame.depart(game, 1001)["ok"], "出发：占用期间不能另开一局")

	# —— 地图推进 ——
	_check(not expedition.move_to(2, 0)["ok"], "推进：跳排被拒绝")
	_check(not expedition.move_to(1, 5)["ok"], "推进：越界列被拒绝")
	_check(expedition.move_to(1, 0)["ok"], "推进：进入第 1 排")
	_check(str(expedition.run["phase"]) == "node", "推进：进入节点阶段")
	_check(not expedition.leave_node()["ok"], "节点：战斗节点未开打不能离开")

	# —— 战斗：胜利 → 搜刮 ——
	var battle := expedition.start_battle()
	_check(battle["ok"], "战斗：从局内发起")
	var combat: CombatGame = battle["combat"]
	for enemy in combat.state["enemies"]:
		enemy["hp"] = 1
	var played := false
	for card in combat.state["players"]["p1"]["hand"]:
		if str(card["card_id"]) == "slash":
			combat.play_card("p1", int(card["uid"]), "e1")
			played = true
			break
	if not played:
		for enemy in combat.state["enemies"]:
			enemy["hp"] = 0
			enemy["alive"] = false
		combat._events_check_outcome([])
	_check(str(combat.state["outcome"]) == "won", "战斗：胜利（注入低血敌人）")
	var finish := expedition.finish_battle(combat)
	_check(finish["ok"] and str(finish.get("outcome", "")) == "won", "战斗：胜利回到节点")
	_check(str(expedition.run["phase"]) == "node", "战斗：进入搜刮")

	# —— 搜刮：二选一 + 公共物资 ——
	var key := expedition.node_id(1, 0)
	var resolved: Dictionary = expedition.run["resolved"][key]
	_check(resolved["rewards"].size() == 2 and resolved["public"].size() == 1, "奖励：个人二选一＋公共 1 件")
	var inventory := expedition.run_inventory()
	var first_reward := str(resolved["rewards"][0])
	_check(inventory.claim_reward(first_reward, "pack")["ok"], "搜刮：领取候选之一")
	resolved = expedition.run["resolved"][key]
	resolved["rewards"] = [first_reward]
	expedition.run["resolved"][key] = resolved
	var before_count := inventory.loadout_list("pack").size()
	_check(expedition.leave_node()["ok"], "节点：完成并离开（其余候选放弃）")
	_check(str(expedition.run["phase"]) == "map", "节点：回到地图")

	# —— 休整与撤离（第 4 排）——
	for row in [2, 3]:
		_check(expedition.move_to(row, 0)["ok"], "推进：进入第 %d 排" % row)
		if str(expedition.current_node()["type"]) in ["battle", "elite", "gate"]:
			var b := expedition.start_battle()
			for enemy in b["combat"].state["enemies"]:
				enemy["hp"] = 0
				enemy["alive"] = false
			b["combat"]._events_check_outcome([])
			expedition.finish_battle(b["combat"])
		_check(expedition.leave_node()["ok"], "节点：离开第 %d 排" % row)
	_check(expedition.move_to(4, 0)["ok"], "推进：到达休整·撤离站")
	_check(expedition.take_rest("heal")["ok"], "休整：恢复 8 生命")
	_check(not expedition.take_rest("prepare")["ok"], "休整：不能切换刷两份")
	var extract := expedition.extract()
	_check(extract["ok"], "撤离：结算成功")
	var settlement: Dictionary = extract["settlement"]
	_check(str(settlement["kind"]) == "extract", "撤离：类型正确")
	_check(settlement["returned"].size() >= 3, "撤离：带入装备按返还处理（基础 3 件）")
	_check(settlement["gained"].size() >= 1, "撤离：搜刮物按获得处理")
	_check(str(game.state["expedition"]["inventory"]["occupied_by_run"]) == "", "撤离：占用解除")
	_check(str(game.state["expedition"]["active_run_ref"]) == "", "撤离：活动局清空")
	_check(game.state["expedition"]["applied_settlements"].has(str(settlement["settlement_id"])), "撤离：结算已登记")
	var warehouse_after: int = game.state["expedition"]["inventory"]["warehouse"].size()
	_check(warehouse_after >= 1, "撤离：获得物入库（待整理进战备）")

	# —— 幂等：重复应用不发双份 ——
	var again := ExpeditionGame.apply_settlement(game, settlement)
	_check(again["ok"] and again.get("duplicate", false), "幂等：重复结算只回执")
	_check(game.state["expedition"]["inventory"]["warehouse"].size() == warehouse_after, "幂等：不重复发放")

	# —— 出发装备不重复发放：返还的是原实例 ——
	var chest_after: Array = game.state["expedition"]["inventory"]["loadout"]["chest"]
	_check(chest_after.size() == 3, "返还：带入装备仍在原容器（释放占用而非再发一份）")

	_finish()


func _fresh_game() -> FarmGame:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261002)
	game.new_game(1000)
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	for instance in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	return game


func _finish() -> void:
	if failed:
		push_error("D24_RUN_SMOKE_FAIL")
	else:
		print("D24_RUN_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
