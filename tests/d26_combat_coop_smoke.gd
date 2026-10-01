extends SceneTree
## 2.6：双人合作战斗——人数缩放、意图目标、队友支援、倒地与救援、共同回合、胜利复活。


var failed := false


func _initialize() -> void:
	# —— 人数缩放与固定目标 ——
	var combat := CombatGame.create([_p("p1", "农夫"), _p("p2", "阿禾")], "tutorial", 61, null, _fixed_deck())
	combat.start()
	var slime: Dictionary = combat.state["enemies"][0]
	_check(int(slime["hp"]) == 29 and int(slime["max_hp"]) == 29, "缩放：双人泥团 18→29（×1.6 向上取整）")
	_check(str(slime["target_key"]) == "p1", "目标：e1 固定指派给 p1")
	var p1: Dictionary = combat.state["players"]["p1"]
	var p2: Dictionary = combat.state["players"]["p2"]
	_check(int(p2["energy"]) == 3 and p2["hand"].size() == 5, "双人：各自满资源开局")

	# —— 队友支援：p2 给 p1 掩护格挡（合作算例 §11 的骨架）——
	p1["hp"] = 12
	var cover := _play(combat, "p2", "cover", "p1")
	_check(cover["ok"], "支援：p2 可给 p1 掩护")
	_check(int(p1["block"]) >= 6, "支援：p1 获得 6 格挡")

	# —— 共同回合：一人结束要等待另一人 ——
	var waiting := combat.end_turn("p1")
	_check(bool(waiting.get("waiting", false)), "共同回合：p1 结束后等待 p2")
	var done := combat.end_turn("p2")
	_check(not bool(done.get("waiting", false)), "共同回合：全员结束才进敌方阶段")
	_check(int(p1["hp"]) == 12, "敌方攻击：p1 被格挡保护（合作算例）")

	# —— 倒地：不能出牌、不计入结束人数 ——
	p1["hp"] = 4
	p1["block"] = 0
	_force_attack(combat)
	combat.end_turn("p1")
	combat.end_turn("p2")
	_check(bool(p1.get("downed", false)) and int(p1["hp"]) == 0, "倒地：生命归零进入倒地而非直接失败")
	_check(str(combat.state["outcome"]) == "", "倒地：还有队友站着，战斗继续")
	var denied := _play(combat, "p1", "slash", "e1")
	_check(not denied["ok"], "倒地：不能出牌")
	var skip_wait := combat.end_turn("p2")
	_check(not bool(skip_wait.get("waiting", false)), "倒地者不计入结束人数：p2 单独结束即推进")

	# —— 救援：救援包实体支撑救援牌（共享一次使用）——
	var inv_game := FarmGame.new()
	inv_game.new_game(1000)
	var inv := InventoryGame.new()
	inv.bind(inv_game.state["expedition"])
	var kit := inv.add_instance("rescue_kit", "test")
	var kit_id := int(kit["instance_id"])
	combat.inventory = inv
	p2["hand"].append({"uid": 9101, "card_id": "rescue_signal", "source_instance_id": kit_id, "source_seq": 0, "owner": "p2"})
	var rescue := combat.play_card("p2", 9101, "p1")
	_check(rescue["ok"], "救援：p2 对倒地的 p1 使用救援信号")
	_check(int(p1["hp"]) == 8 and not bool(p1.get("downed", false)), "救援：恢复到 8 生命并站起")
	_check(bool(p1.get("rescued_once", false)), "救援：本场被救一次标记")
	_check(inv.uses_remaining(kit_id) == 0, "救援包：共享实体一次使用后耗尽")

	# —— 再次倒地：实体已耗尽，救援牌打不出（同一份不能使用两次）——
	p1["hp"] = 1
	p1["block"] = 0
	_force_attack(combat)
	combat.end_turn("p1")
	combat.end_turn("p2")
	_check(bool(p1.get("downed", false)), "再次倒地")
	p2["hand"].append({"uid": 9102, "card_id": "rescue_signal", "source_instance_id": kit_id, "source_seq": 0, "owner": "p2"})
	var rescue2 := combat.play_card("p2", 9102, "p1")
	_check(not rescue2["ok"], "救援包耗尽：第二张救援牌不能使用（共享一次）")
	_check(bool(p1.get("downed", false)) and int(p1["hp"]) == 0, "p1 保持倒地")

	# —— 全部倒地立即失败 ——
	p2["hp"] = 3
	p2["block"] = 0
	_force_attack(combat)
	combat.end_turn("p2")
	_check(str(combat.state["outcome"]) == "lost", "全部倒地：立即失败")

	# —— 胜利时倒地队友复活到 4 ——
	var combat2 := CombatGame.create([_p("p1", "农夫"), _p("p2", "阿禾")], "tutorial", 67, null, _fixed_deck())
	combat2.start()
	var q1: Dictionary = combat2.state["players"]["p1"]
	var q2: Dictionary = combat2.state["players"]["p2"]
	q1["hp"] = 0
	q1["downed"] = true
	var e: Dictionary = combat2.state["enemies"][0]
	e["hp"] = 1
	e["alive"] = true
	for card in q2["hand"].duplicate():
		if str(card["card_id"]) == "slash":
			combat2.play_card("p2", int(card["uid"]), "e1")
			break
	_check(str(combat2.state["outcome"]) == "won", "胜利：最后敌人死亡")
	_check(int(q1["hp"]) == 4 and not bool(q1.get("downed", false)), "胜利：倒地队友恢复到 4 生命（不长期旁观）")

	# —— 原目标倒地时敌人重选存活者 ——
	var combat3 := CombatGame.create([_p("p1", "农夫"), _p("p2", "阿禾")], "tutorial", 71, null, _fixed_deck())
	combat3.start()
	var r1: Dictionary = combat3.state["players"]["p1"]
	var r2: Dictionary = combat3.state["players"]["p2"]
	r1["hp"] = 4
	r1["block"] = 0
	r2["block"] = 0
	_force_attack(combat3)
	combat3.end_turn("p1")
	combat3.end_turn("p2")
	_check(bool(r1.get("downed", false)), "重选前奏：p1 被打倒")
	_force_attack(combat3)
	combat3.end_turn("p2")
	_check(int(r2["hp"]) < 40 or bool(r2.get("downed", false)), "重选：敌人转向存活的 p2（不再打倒地者）")

	_finish()


func _finish() -> void:
	if failed:
		push_error("D26_COMBAT_COOP_SMOKE_FAIL")
	else:
		print("D26_COMBAT_COOP_SMOKE_PASS")
	quit(1 if failed else 0)


func _p(key: String, name: String) -> Dictionary:
	return {"key": key, "name": name, "max_hp": 40, "deck": _fixed_deck()}


## 固定牌序（p2 复用同一顺序；掩护在首位确保可打）。
func _fixed_deck() -> Array:
	var ids := ["cover", "slash", "slash", "shield_up", "brace", "slash", "shield_up", "brace"]
	var deck: Array = []
	var seq := 0
	for card_id in ids:
		deck.append({"card_id": card_id, "source_instance_id": 0, "source_seq": seq, "join_round": 1})
		seq += 1
	return deck


## 把存活敌人的当前意图强制为攻击（绕过行为循环，聚焦被测规则）。
func _force_attack(combat: CombatGame, value := 5) -> void:
	for enemy in combat.state["enemies"]:
		if bool(enemy["alive"]):
			enemy["intent"] = {"kind": "attack", "value": value}
			enemy["target_key"] = "p1"


func _play(combat: CombatGame, owner: String, card_id: String, target: String) -> Dictionary:
	for card in combat.state["players"][owner]["hand"]:
		if str(card["card_id"]) == card_id:
			return combat.play_card(owner, int(card["uid"]), target)
	return {"ok": false, "reason": "手牌里没有 %s" % card_id}


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
