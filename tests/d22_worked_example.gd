extends SceneTree
## 2.2：固定种子算例（2.2 设计 §8 两个完整攻防算例），逐回合断言。


var failed := false


func _initialize() -> void:
	# —— 算例一：40 生命 / 0 格挡 / 3 能量 vs 泥团 18 血（意图攻击 5）——
	# 手牌：切击、切击、架盾、稳住、观察。
	var order := _order(["slash", "slash", "shield_up", "brace", "observe", "slash", "shield_up", "brace"])
	var combat := CombatGame.create([_player(order)], "tutorial", 20261001, null, order)
	combat.start()
	var player: Dictionary = combat.state["players"]["p1"]
	var slime: Dictionary = combat.state["enemies"][0]

	_play(combat, "slash")
	_play(combat, "slash")
	_check(int(slime["hp"]) == 6, "算例一：切击×2 后泥团 18→12→6")
	_check(int(player["energy"]) == 1, "算例一：两张 1 费牌后剩 1 能量")
	_play(combat, "shield_up")
	_check(int(player["energy"]) == 0, "算例一：架盾耗最后 1 能量")
	_play(combat, "brace")
	_check(int(player["block"]) == 9, "算例一：架盾 6＋稳住 3＝9 格挡")
	var turn := combat.end_turn("p1")
	_check(int(player["hp"]) == 40, "算例一：敌人攻击 5 全被格挡吸收")
	var absorbed := false
	for entry in combat.state["log"]:
		if str(entry).find("格挡抵消 5") >= 0:
			absorbed = true
	_check(absorbed, "算例一：日志记录格挡抵消 5（9→4）")
	_check(int(combat.state["round"]) == 2 and int(player["block"]) == 0, "算例一：下回合开始残余 4 格挡清除、能量恢复 3")

	# —— 算例二：敌人 6 格挡 → 破绽 → 切击（易伤 ×1.5 只取整一次）——
	var order2 := _order(["expose", "slash", "slash", "slash", "slash", "slash", "slash", "slash"])
	var crab := CombatGame.create([_player(order2)], "defensive", 20261002, null, order2)
	crab.state["enemies"][0]["cycle_index"] = 1
	crab.start()
	var enemy: Dictionary = crab.state["enemies"][0]
	enemy["block"] = 6
	_play(crab, "expose")
	_check(int(enemy["block"]) == 2 and int(enemy["hp"]) == 26, "算例二：破绽 4 伤害被格挡吸收（6→2），不追溯易伤")
	_play(crab, "slash")
	_check(int(enemy["hp"]) == 19, "算例二：切击 ⌊6×1.5⌋=9，扣 2 格挡后生命 -7")
	_check(int(enemy["max_hp"]) == 26, "算例二：碎石蟹上限 26")

	if failed:
		push_error("D22_WORKED_EXAMPLE_FAIL")
	else:
		print("D22_WORKED_EXAMPLE_PASS")
	quit(1 if failed else 0)


func _player(order: Array) -> Dictionary:
	return {"key": "p1", "name": "农夫", "max_hp": 40, "deck": order}


func _order(card_ids: Array) -> Array:
	var deck: Array = []
	var seq := 0
	for card_id in card_ids:
		deck.append({"card_id": card_id, "source_instance_id": 0, "source_seq": seq, "join_round": 1})
		seq += 1
	return deck


func _play(combat: CombatGame, card_id: String, target := "") -> Dictionary:
	for card in combat.state["players"]["p1"]["hand"]:
		if str(card["card_id"]) == card_id:
			if target == "":
				var rule := str(CardDefs.get_card(card_id).get("target", "enemy"))
				target = "p1" if rule != "enemy" else "e1"
			return combat.play_card("p1", int(card["uid"]), target)
	return {"ok": false, "reason": "手牌里没有 %s" % card_id}


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
