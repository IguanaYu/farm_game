extends SceneTree
## 2.2：战斗规则冒烟——时序、能量、格挡清除、状态时序、中毒击杀、目标死亡拒绝、
## 洗弃牌、手牌上限。对应总计划 §12.1"战斗"块。


var failed := false


func _initialize() -> void:
	# —— 算例一的前半段：基础回合与格挡（2.2 设计 §8）——
	var order := _order(["slash", "slash", "shield_up", "brace", "observe", "slash", "slash", "shield_up"])
	var combat := CombatGame.create([_player(order)], "tutorial", 7, null, order)
	_check(combat.start()["ok"], "开局：战斗开始成功")
	var player: Dictionary = combat.state["players"]["p1"]
	var slime: Dictionary = combat.state["enemies"][0]
	_check(int(combat.state["round"]) == 1 and int(player["energy"]) == 3, "第 1 回合：能量 3")
	_check(player["hand"].size() == 5, "第 1 回合：抽 5 张")
	_check(int(slime["hp"]) == 18, "教学场：小泥团 18 血")
	_check(_intent_has(slime, "攻击 5"), "意图：攻击 5（回合开始确定）")

	_check(_play(combat, "slash")["ok"], "出牌：切击")
	_check(int(slime["hp"]) == 12, "切击：18→12")
	_check(int(player["energy"]) == 2, "能量：3→2")
	_play(combat, "slash")
	_check(int(slime["hp"]) == 6, "切击：12→6")
	_play(combat, "shield_up")
	_play(combat, "brace")
	_check(int(player["block"]) == 9, "格挡：架盾 6＋稳住 3＝9")
	var rejected := _play(combat, "observe")
	_check(not rejected["ok"] and str(rejected["reason"]).find("能量") >= 0, "能量不足：拒绝且不扣资源")
	_check(_hand_has(combat, "observe"), "被拒的牌保留在手牌")

	var turn := combat.end_turn("p1")
	_check(turn["ok"] and str(turn.get("outcome", "")) == "", "结束行动：进入敌方阶段")
	_check(int(player["hp"]) == 40 and _log_has(combat, "格挡抵消 5"), "敌方攻击 5：被格挡吸收（日志可核对）")
	_check(int(combat.state["round"]) == 2 and int(player["block"]) == 0, "第 2 回合：残余格挡清除")
	_check(int(player["energy"]) == 3, "第 2 回合：能量重置 3")
	var intent_before := str(slime["intent"])
	_check(intent_before != "", "意图已为本回合确定")

	# —— 目标死亡拒绝（设计 §9）——
	var order2 := _order(["heavy_strike", "slash", "slash", "slash", "slash", "slash", "slash", "slash"])
	var two := CombatGame.create([_player(order2)], "normal", 11, null, order2)
	two.start()
	var first: Dictionary = two.state["enemies"][0]
	var second: Dictionary = two.state["enemies"][1]
	_play(two, "heavy_strike")
	_check(int(first["hp"]) == 5, "重击：18→5（能量 3→1）")
	_play(two, "slash")
	_check(not bool(first["alive"]) and int(first["hp"]) == 0, "补刀切击：小泥团被击败")
	_check(bool(second["alive"]), "洞穴蝠仍在")
	_check(str(two.state["outcome"]) == "", "仍有敌人：不判胜")
	two.end_turn("p1")
	var p2: Dictionary = two.state["players"]["p1"]
	var energy_before := int(p2["energy"])
	var hand_before: int = p2["hand"].size()
	var dead_target := _play(two, "slash", "e1")
	_check(not dead_target["ok"] and str(dead_target["reason"]).find("目标") >= 0, "目标已死：请求被拒绝")
	_check(int(p2["energy"]) == energy_before and p2["hand"].size() == hand_before, "拒绝后：能量与手牌不变")
	var alive_target := _play(two, "slash", "e2")
	_check(alive_target["ok"], "改打存活目标：成功")

	# —— 易伤算例（设计 §8 算例二）——
	var order3 := _order(["expose", "slash", "slash", "slash", "slash", "slash", "slash", "slash"])
	var crab := CombatGame.create([_player(order3)], "defensive", 13, null, order3)
	crab.state["enemies"][0]["cycle_index"] = 1
	crab.start()
	var crab_enemy: Dictionary = crab.state["enemies"][0]
	crab_enemy["block"] = 6
	_play(crab, "expose")
	_check(int(crab_enemy["block"]) == 2, "破绽：4 伤害被格挡吸收，6→2")
	_check(int(crab_enemy["statuses"].get("vulnerable", {}).get("stacks", 0)) == 1, "破绽：添加 1 回合易伤")
	_play(crab, "slash")
	_check(int(crab_enemy["block"]) == 0 and int(crab_enemy["hp"]) == 19, "切击：⌊6×1.5⌋=9，扣 2 格挡后生命 -7（26→19）")
	crab.end_turn("p1")
	_check(int(crab.state["players"]["p1"]["hp"]) == 31, "碎石蟹攻击 9：无格挡直接扣血（40→31）")
	_check(not crab_enemy["statuses"].has("vulnerable"), "易伤：敌人行动结束后消失")

	# —— 虚弱时序：敌人给的虚弱覆盖玩家下一次行动阶段 ——
	var order4 := _order(["slash", "slash", "slash", "slash", "slash", "slash", "slash", "slash"])
	var bat := CombatGame.create([_player(order4)], "normal", 17, null, order4)
	bat.state["enemies"][1]["cycle_index"] = 1
	bat.state["enemies"][0]["cycle_index"] = 99  # 意图在 start() 时锁定，先改再开
	bat.start()
	var bat_enemy: Dictionary = bat.state["enemies"][1]
	bat.end_turn("p1")
	# 蝠打出"攻击4并施加1回合虚弱"，但玩家可能有格挡为 0 → 命中并上虚弱。
	var bat_player: Dictionary = bat.state["players"]["p1"]
	_check(int(bat_player["statuses"].get("weak", {}).get("stacks", 0)) == 1, "洞穴蝠：玩家获得 1 回合虚弱")
	var preview_damage := bat.preview_play("p1", _uid_of(bat, "slash"), "e2")
	_check(int(preview_damage.get("damage", 99)) == int(6 * 0.75), "虚弱：玩家攻击 ×0.75（6→4）")
	bat.play_card("p1", _uid_of(bat, "slash"), "e2")
	_check(int(bat_enemy["hp"]) == 10, "虚弱下的切击：14→10")
	bat.end_turn("p1")
	_check(not bat_player["statuses"].has("weak"), "虚弱：玩家行动阶段结束后消失")

	# —— 中毒击杀：跳过行动、最后敌人死立即判胜（设计 §9）——
	var order5 := _order(["venom_stab", "slash", "slash", "slash", "slash", "slash", "slash", "slash"])
	var poison := CombatGame.create([_player(order5)], "tutorial", 19, null, order5)
	poison.start()
	var poison_slime: Dictionary = poison.state["enemies"][0]
	poison_slime["hp"] = 3
	poison_slime["block"] = 5
	_play(poison, "venom_stab")
	_check(int(poison_slime["hp"]) == 3 and int(poison_slime["block"]) == 2, "毒刺：3 伤害被格挡吸收")
	_check(int(poison_slime["statuses"]["poison"]["stacks"]) == 3, "毒刺：3 层中毒")
	var poison_turn := poison.end_turn("p1")
	_check(not bool(poison_slime["alive"]), "中毒：3 层在行动前击杀泥团（绕过格挡）")
	_check(int(poison.state["players"]["p1"]["hp"]) == 40, "中毒击杀：该敌人跳过行动")
	_check(str(poison.state["outcome"]) == "won", "最后敌人死亡：立即判胜")

	# —— 洗弃牌与手牌上限（设计 §3/§9）——
	var order6 := _order(["observe", "observe", "slash", "slash", "slash", "slash", "slash", "slash"])
	var piles := CombatGame.create([_player(order6)], "tutorial", 23, null, order6)
	piles.start()
	var piles_player: Dictionary = piles.state["players"]["p1"]
	piles_player["draw_pile"] = []
	var observe_card := _find_hand(piles, "observe")
	var filler: Array = []
	for index in range(9):
		filler.append({"uid": 900 + index, "card_id": "slash", "source_instance_id": 0, "source_seq": 0, "owner": "p1"})
	piles_player["discard_pile"] = [filler[0], filler[1]]
	piles_player["hand"] = filler.duplicate()
	piles_player["hand"].append(observe_card)
	_check(piles_player["hand"].size() == 10, "手牌：构造满手 10 张")
	_play(piles, "observe")
	_check(piles_player["hand"].size() == 10 and piles_player["draw_pile"].size() == 1, "观察：抽满上限（10 张），剩余 1 张留在抽牌堆")
	_check(_log_has(piles, "手牌已满"), "手牌满：有提示日志")
	_check(piles_player["discard_pile"].size() == 1 and str(piles_player["discard_pile"][0]["card_id"]) == "observe", "抽牌：空时洗入弃牌堆（打出的观察牌随后入弃）")

	_finish()


func _finish() -> void:
	if failed:
		push_error("D22_RULES_SMOKE_FAIL")
	else:
		print("D22_RULES_SMOKE_PASS")
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
	var uid := _uid_of(combat, card_id)
	if uid < 0:
		return {"ok": false, "reason": "手牌里没有 %s" % card_id}
	if target == "":
		var rule := str(CardDefs.get_card(card_id).get("target", "enemy"))
		target = "p1" if rule != "enemy" else "e1"
	return combat.play_card("p1", uid, target)


func _uid_of(combat: CombatGame, card_id: String) -> int:
	for card in combat.state["players"]["p1"]["hand"]:
		if str(card["card_id"]) == card_id:
			return int(card["uid"])
	return -1


func _find_hand(combat: CombatGame, card_id: String) -> Dictionary:
	for card in combat.state["players"]["p1"]["hand"]:
		if str(card["card_id"]) == card_id:
			return card
	return {}


func _hand_has(combat: CombatGame, card_id: String) -> bool:
	return not _find_hand(combat, card_id).is_empty()


func _intent_has(enemy: Dictionary, fragment: String) -> bool:
	for entry in [enemy]:
		if str(entry.get("intent", {}).get("value", "")) != "":
			pass
	return int(enemy["intent"].get("value", -1)) == 5 and str(enemy["intent"].get("kind", "")) == "attack"


func _log_has(combat: CombatGame, fragment: String) -> bool:
	for entry in combat.state["log"]:
		if str(entry).find(fragment) >= 0:
			return true
	return false


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
