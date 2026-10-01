extends SceneTree
## 2.4：强制关闭恢复——出发与结算之间任意时点重开，同一地图与奖励、同一战斗状态。


var failed := false


func _initialize() -> void:
	var game := _fresh_game()
	SaveStore.save_state(game.state, "user://d24_recovery_farm.json")
	var depart := ExpeditionGame.depart(game, 1000)
	var expedition: ExpeditionGame = depart["game"]
	## 农场侧占用也要持久化（模拟正常运行中的保存）。
	SaveStore.save_state(game.state, "user://d24_recovery_farm.json")
	expedition.move_to(1, 0)
	var battle := expedition.start_battle()
	var combat: CombatGame = battle["combat"]
	var hand_before: Array = []
	for card in combat.state["players"]["p1"]["hand"]:
		hand_before.append(int(card["uid"]))
	var hp_before := int(combat.state["players"]["p1"]["hp"])
	expedition.save()

	## 模拟强退：进程消失，只有磁盘上的农场档与局档。
	var game2 := FarmGame.new()
	_check(game2.load_state(SaveStore.load_state("user://d24_recovery_farm.json")), "强退：农场档可恢复")
	_check(str(game2.state["expedition"]["active_run_ref"]) == str(expedition.run["run_id"]), "强退：占用与活动局引用保留")
	var resumed := ExpeditionGame.resume(game2)
	_check(resumed["ok"], "强退：局档可恢复")
	var expedition2: ExpeditionGame = resumed["game"]
	_check(str(expedition2.run["phase"]) == "battle", "强退：战斗阶段保留")
	var combat2 := expedition2.restore_battle()
	_check(combat2 != null, "强退：战斗快照可重建")
	var hand_after: Array = []
	for card in combat2.state["players"]["p1"]["hand"]:
		hand_after.append(int(card["uid"]))
	_check(hand_after == hand_before, "强退：手牌一致（不重抽）")
	_check(int(combat2.state["players"]["p1"]["hp"]) == hp_before, "强退：生命一致")
	_check(str(combat2.state["enemies"][0]["intent"]) == str(combat.state["enemies"][0]["intent"]), "强退：敌人意图一致")

	## 恢复后继续打完并撤离：结算能正常应用。
	for enemy in combat2.state["enemies"]:
		enemy["hp"] = 0
		enemy["alive"] = false
	combat2._events_check_outcome([])
	var finish := expedition2.finish_battle(combat2)
	_check(finish["ok"] and str(finish.get("outcome", "")) == "won", "强退：恢复后可继续完成战斗")
	expedition2.leave_node()
	var extract := expedition2.extract() if str(expedition2.current_node()["type"]) in ["rest_exit", "exit"] else {"ok": false}
	## 第 1 排不是撤离点：继续推进到第 4 排撤离，验证全链路。
	if not extract["ok"]:
		for row in range(2, 5):
			expedition2.move_to(row, 0)
			if str(expedition2.current_node()["type"]) in ["battle", "elite", "gate"]:
				var b := expedition2.start_battle()
				for enemy in b["combat"].state["enemies"]:
					enemy["hp"] = 0
					enemy["alive"] = false
				b["combat"]._events_check_outcome([])
				expedition2.finish_battle(b["combat"])
			expedition2.leave_node()
		extract = expedition2.extract()
	_check(extract["ok"], "强退：恢复后可完整撤离结算")
	_check(str(game2.state["expedition"]["inventory"]["occupied_by_run"]) == "", "强退：结算后占用解除")
	SaveStore.save_state(game2.state, "user://d24_recovery_farm.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://d24_recovery_farm.json"))

	if failed:
		push_error("D24_RECOVERY_SIM_FAIL")
	else:
		print("D24_RECOVERY_SIM_PASS")
	quit(1 if failed else 0)


func _fresh_game() -> FarmGame:
	var game := FarmGame.new()
	game.new_game(1000)
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	for instance in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	return game


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
