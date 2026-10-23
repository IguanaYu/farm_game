extends SceneTree
## 费用锚点与五状态验收：通过出牌、行动边界和 JSON 快照验证同一套结算规则。

class FixtureCombat extends CombatGame:
	var custom_cards: Dictionary = {}

	func card_definition(card_id: String) -> Dictionary:
		return custom_cards.get(card_id, CardDefs.get_card(card_id))


var checks := 0
var failed := false


func _initialize() -> void:
	_test_attack_block_and_preview()
	_test_order_and_effect_targets()
	_test_multihit()
	_test_action_boundaries()
	_test_intent_preview()
	_test_poison()
	_test_coop_poison_and_rescue()
	_test_snapshot_and_cleanup()
	_test_anchor_cards_and_samples()
	print("D67_COMBAT_STATUS_ANCHOR_%s checks=%d" % ["FAIL" if failed else "PASS", checks])
	quit(1 if failed else 0)


func _test_attack_block_and_preview() -> void:
	var combat := _combat()
	var player := _player(combat)
	var enemy := _enemy(combat)
	_status(combat, player, "strength", 2)
	_status(combat, player, "weak", 2)
	_status(combat, enemy, "vulnerable", 3)
	enemy["block"] = 5
	var uid := _give(combat, "attack8", _card("enemy", [{"kind": "damage", "value": 8}]))
	var before := combat.to_dict()
	var preview := combat.preview_play("p1", uid, "e1")
	_check(int(preview.get("damage", -1)) == 11, "8 攻＋2 力量，同时虚弱与易伤，最后一次取整得到 11")
	var details := _effects(preview, "damage")
	_check(details.size() == 1, "单击预览有一个伤害明细")
	if details.size() == 1:
		_check(int(details[0].get("blocked", -1)) == 5 and int(details[0].get("to_hp", -1)) == 6, "预览在倍率后抵扣 5 格挡，扣 6 生命")
		_check(str(details[0].get("target", "")) == "e1", "预览明细保留真正受击目标")
	combat.preview_play("p1", uid, "e1")
	_check(combat.to_dict() == before, "反复预览不修改状态、日志、手牌、状态层数或 RNG")
	var result := combat.play_card("p1", uid, "e1")
	_check(bool(result.get("ok", false)) and int(enemy["hp"]) == 114 and int(enemy["block"]) == 0, "实际出牌与 11 伤害／6 扣血的预览一致")
	_check(_stacks(player, "weak") == 2 and _stacks(enemy, "vulnerable") == 3, "出牌不会提前减少虚弱、易伤层数")

	var rounding := _combat()
	_status(rounding, _player(rounding), "weak", 1)
	_status(rounding, _enemy(rounding), "vulnerable", 1)
	var seven := _give(rounding, "attack7", _card("enemy", [{"kind": "damage", "value": 7}]))
	_check(int(rounding.preview_play("p1", seven, "e1").get("damage", -1)) == 7, "7×0.75×1.5＝7.875：不在中间取整")
	rounding.play_card("p1", seven, "e1")
	_check(int(_enemy(rounding)["hp"]) == 113, "取整算例实际扣 7 血")

	var defense := _combat()
	_status(defense, _player(defense), "dexterity", 2)
	var guard := _give(defense, "guard8", _card("self", [{"kind": "block", "value": 8}]))
	_check(int(defense.preview_play("p1", guard, "p1").get("block", -1)) == 10, "8 格挡＋2 敏捷预览为 10")
	defense.play_card("p1", guard, "p1")
	_check(int(_player(defense)["block"]) == 10, "8 格挡＋2 敏捷实际为 10")

	var drawing := _combat()
	var draw_uid := _give(drawing, "draw", _card("self", [{"kind": "draw", "value": 2}]))
	var draw_player := _player(drawing)
	draw_player["discard_pile"] = draw_player["draw_pile"]
	draw_player["draw_pile"] = []
	var draw_before := drawing.to_dict()
	_check(int(drawing.preview_play("p1", draw_uid, "p1").get("draw", -1)) == 2 and drawing.to_dict() == draw_before, "预览洗弃牌堆与抽牌不会消耗真实 RNG 或移动真实牌")
	drawing.play_card("p1", draw_uid, "p1")
	_check(str(drawing.to_dict()["rng_state"]) != str(draw_before["rng_state"]), "同一抽牌在实际出牌时确实发生洗牌并推进 RNG")


func _test_order_and_effect_targets() -> void:
	for status_first in [true, false]:
		var combat := _combat()
		var effects: Array = [{"kind": "status", "status": "vulnerable", "stacks": 1}, {"kind": "damage", "value": 8}]
		if not status_first:
			effects.reverse()
		var uid := _give(combat, "ordered", _card("enemy", effects))
		var expected := 12 if status_first else 8
		_check(int(combat.preview_play("p1", uid, "e1").get("damage", -1)) == expected, "预览按定义顺序结算：先易伤=%s" % status_first)
		combat.play_card("p1", uid, "e1")
		_check(int(_enemy(combat)["hp"]) == 120 - expected and _stacks(_enemy(combat), "vulnerable") == 1, "实战保留相同效果顺序：先易伤=%s" % status_first)

	var mixed := _combat()
	_status(mixed, _player(mixed), "dexterity", 2)
	var mixed_uid := _give(mixed, "mixed", _card("enemy", [{"kind": "damage", "value": 3, "target": "enemy"}, {"kind": "block", "value": 3, "target": "self"}]))
	var before := mixed.to_dict()
	var preview := mixed.preview_play("p1", mixed_uid, "e1")
	var blocks := _effects(preview, "block")
	_check(int(preview.get("damage", -1)) == 3 and int(preview.get("block", -1)) == 5, "混合牌同时预览敌方 3 伤害与自己 5 格挡")
	_check(blocks.size() == 1 and str(blocks[0].get("target", "")) == "p1", "混合牌格挡预览指向施放者")
	_check(mixed.to_dict() == before, "混合效果预览仍不修改状态")
	mixed.play_card("p1", mixed_uid, "e1")
	_check(int(_enemy(mixed)["hp"]) == 117 and int(_enemy(mixed)["block"]) == 0 and int(_player(mixed)["block"]) == 5, "混合牌的伤害与格挡落到各自对象")

	var allies := _combat(true)
	_status(allies, _player(allies), "dexterity", 2)
	_status(allies, _player(allies, "p2"), "dexterity", 9)
	var ally_uid := _give(allies, "ally_guard", _card("ally", [{"kind": "block", "value": 8, "target": "ally"}, {"kind": "block", "value": 3, "target": "self"}]))
	allies.play_card("p1", ally_uid, "p2")
	_check(int(_player(allies, "p2")["block"]) == 10 and int(_player(allies)["block"]) == 5, "支援与自保均使用施放者＋2 敏捷，不使用受益者＋9")

	var selected := _combat(true)
	var selected_uid := _give(selected, "selected_guard", _card("ally", [{"kind": "block", "value": 8, "target": "selected"}]))
	selected.play_card("p1", selected_uid, "p2")
	_check(int(_player(selected, "p2")["block"]) == 8 and int(_player(selected)["block"]) == 0, "selected 效果沿用本张牌选中的队友")
	var invalid := _combat()
	var invalid_uid := _give(invalid, "invalid", _card("enemy", [{"kind": "damage", "value": 3}, {"kind": "block", "value": 3, "target": "ally"}]))
	var invalid_before := invalid.to_dict()
	_check(not bool(invalid.preview_play("p1", invalid_uid, "e1").get("ok", true)) and not bool(invalid.play_card("p1", invalid_uid, "e1").get("ok", true)), "任一效果的目标类型不合法时，预览与实战一致拒绝")
	_check(invalid.to_dict() == invalid_before, "拒绝混合效果时不先执行前半伤害，也不扣能量或手牌")


func _test_multihit() -> void:
	var combat := _combat()
	_status(combat, _player(combat), "strength", 2)
	_enemy(combat)["block"] = 7
	var uid := _give(combat, "double", _card("enemy", [{"kind": "damage", "value": 3, "times": 2}]))
	var preview := combat.preview_play("p1", uid, "e1")
	var hits := _effects(preview, "damage")
	_check(int(preview.get("damage", -1)) == 10 and hits.size() == 2, "两段 3 攻击逐段加 2 力量，预览总伤害 10")
	if hits.size() == 2:
		_check(int(hits[0].get("blocked", -1)) == 5 and int(hits[1].get("blocked", -1)) == 2 and int(hits[1].get("to_hp", -1)) == 3, "多段预览连续消耗格挡，第二段正确穿透")
	var result := combat.play_card("p1", uid, "e1")
	_check(_events(result, "damage").size() == 2 and int(_enemy(combat)["hp"]) == 117, "多段实战与预览一致")

	var lethal := _combat()
	_enemy(lethal)["hp"] = 4
	var lethal_uid := _give(lethal, "lethal_double", _card("enemy", [{"kind": "damage", "value": 5, "times": 2}]))
	_check(_effects(lethal.preview_play("p1", lethal_uid, "e1"), "damage").size() == 1, "多段预览在目标死亡时立即中断")
	var lethal_result := lethal.play_card("p1", lethal_uid, "e1")
	_check(_events(lethal_result, "damage").size() == 1 and _events(lethal_result, "enemy_died").size() == 1, "多段致死只触发一次死亡事件")

	var enemy_double := _combat()
	_status(enemy_double, _enemy(enemy_double), "strength", 2)
	_enemy(enemy_double)["intent"] = {"kind": "attack", "value": 3, "times": 2}
	_player(enemy_double)["block"] = 7
	var turn := enemy_double.end_turn("p1")
	_check(_events(turn, "damage").size() == 2 and int(_player(enemy_double)["hp"]) == 37, "敌方连击同样逐段应用力量和共享格挡")


func _test_action_boundaries() -> void:
	for layers in [1, 2]:
		var combat := _combat()
		_status(combat, _enemy(combat), "weak", layers)
		_status(combat, _enemy(combat), "vulnerable", layers)
		_status(combat, _enemy(combat), "strength", 2)
		_status(combat, _enemy(combat), "dexterity", 2)
		_enemy(combat)["intent"] = {"kind": "attack", "value": 8}
		var turn := combat.end_turn("p1")
		_check(int(_player(combat)["hp"]) == 33, "敌人 %d 层虚弱覆盖本次攻击，floor((8＋2)×.75)＝7" % layers)
		_check(_stacks(_enemy(combat), "weak") == layers - 1 and _stacks(_enemy(combat), "vulnerable") == layers - 1, "敌人易伤与虚弱仅在行动结束各减一次")
		_check(_events(turn, "enemy_acted").size() == 1 and _stacks(_enemy(combat), "strength") == 2 and _stacks(_enemy(combat), "dexterity") == 2, "敌人力量、敏捷不随行动衰减")

	var block_action := _combat()
	_status(block_action, _enemy(block_action), "dexterity", 2)
	_enemy(block_action)["block"] = 99
	_enemy(block_action)["intent"] = {"kind": "block", "value": 8}
	block_action.end_turn("p1")
	_check(int(_enemy(block_action)["block"]) == 10, "敌人开始行动清旧格挡，再以自身敏捷获得 8＋2 格挡")

	var coop := _combat(true)
	for key in ["p1", "p2"]:
		_status(coop, _player(coop, key), "weak", 2)
		_status(coop, _player(coop, key), "vulnerable", 2)
		_status(coop, _player(coop, key), "strength", 2)
		_status(coop, _player(coop, key), "dexterity", 2)
	_passive(coop)
	var waiting := coop.end_turn("p1")
	_check(bool(waiting.get("waiting", false)) and _stacks(_player(coop), "weak") == 2 and _stacks(_player(coop, "p2"), "vulnerable") == 2, "合作一人结束时不提前扣任何人的层数")
	var duplicate := coop.end_turn("p1")
	_check(not bool(duplicate.get("ok", true)) and _stacks(_player(coop), "weak") == 2, "重复结束请求被拒绝且不重复扣层")
	coop.end_turn("p2")
	for key in ["p1", "p2"]:
		_check(_stacks(_player(coop, key), "weak") == 1 and _stacks(_player(coop, key), "vulnerable") == 1, "合作共同行动阶段结束后 %s 仅扣一层" % key)
		_check(_stacks(_player(coop, key), "strength") == 2 and _stacks(_player(coop, key), "dexterity") == 2, "合作持久增益跨回合保留：" + key)


func _test_intent_preview() -> void:
	var retarget := _combat(true)
	_player(retarget)["hp"] = 2
	_status(retarget, _player(retarget), "vulnerable", 2)
	_enemy(retarget)["intent"] = {"kind": "attack", "value": 3, "times": 2}
	var before := retarget.to_dict()
	var preview := retarget.intent_preview(_enemy(retarget))
	var strikes: Array = preview.get("strikes", [])
	_check(strikes.size() == 2, "敌方连击预览逐段提供真实伤害明细")
	if strikes.size() == 2:
		_check(int(strikes[0].get("amount", -1)) == 4 and str(strikes[0].get("target", "")) == "p1" and int(strikes[1].get("amount", -1)) == 3 and str(strikes[1].get("target", "")) == "p2", "首段打倒易伤玩家后，预览第二段转向队友并重算伤害")
	_check(retarget.to_dict() == before, "敌方多段意图预览不真实击倒玩家、不更改目标、状态或 RNG")
	retarget.end_turn("p1")
	var turn := retarget.end_turn("p2")
	_check(_same_damage(strikes, _events(turn, "damage")), "倒地转向的各段预览与敌方实际行动完全一致")

	var applying := _combat()
	_enemy(applying)["intent"] = {"kind": "attack", "value": 3, "times": 2, "status": "vulnerable", "status_stacks": 1}
	var status_before := applying.to_dict()
	var status_preview := applying.intent_preview(_enemy(applying))
	var status_strikes: Array = status_preview.get("strikes", [])
	_check(status_strikes.size() == 2, "附带状态的连击预览保留两段")
	if status_strikes.size() == 2:
		_check(int(status_strikes[0].get("amount", -1)) == 3 and int(status_strikes[1].get("amount", -1)) == 4, "首段伤害后的新易伤只增强下一段，预览为 3＋4")
	_check(applying.to_dict() == status_before, "预览敌人附带状态不实际施加易伤")
	_check(_same_damage(status_strikes, _events(applying.end_turn("p1"), "damage")), "逐段附带易伤的敌方实际伤害与预览一致")

	for layers in [1, 2]:
		var expiring := _combat()
		_status(expiring, _player(expiring), "vulnerable", layers)
		_status(expiring, _enemy(expiring), "weak", 1)
		_enemy(expiring)["intent"] = {"kind": "attack", "value": 8}
		var expected := 6 if layers == 1 else 9
		_check(int(expiring.intent_preview(_enemy(expiring)).get("value", -1)) == expected, "意图预览计入玩家易伤先减层，但敌方虚弱保留至攻击后：%d 层" % layers)
		var actual := _events(expiring.end_turn("p1"), "damage")
		_check(actual.size() == 1 and int(actual[0].get("amount", -1)) == expected, "易伤跨行动阶段边界的攻击预览与实战一致")

	var consecutive := _combat(false, false, "normal")
	var first: Dictionary = consecutive.state["enemies"][0]
	var second: Dictionary = consecutive.state["enemies"][1]
	_status(consecutive, _player(consecutive), "vulnerable", 1)
	first["target_key"] = "p1"
	first["intent"] = {"kind": "attack", "value": 3, "status": "vulnerable", "status_stacks": 1}
	second["target_key"] = "p1"
	second["intent"] = {"kind": "attack", "value": 3}
	var consecutive_before := consecutive.to_dict()
	var consecutive_preview := consecutive.intent_preview(second)
	var consecutive_strikes: Array = consecutive_preview.get("strikes", [])
	_check(consecutive_strikes.size() == 1 and int(consecutive_strikes[0].get("amount", -1)) == 4, "后行动敌人的预览计入前敌新加易伤，不把它误当作玩家阶段结束前的旧易伤减层")
	_check(consecutive.to_dict() == consecutive_before, "预览后行动敌人不会真实执行前敌伤害或添加易伤")
	var consecutive_turn := consecutive.end_turn("p1")
	var consecutive_actual := _events(consecutive_turn, "damage").filter(func(hit): return str(hit.get("source", "")) == "e2")
	_check(_same_damage(consecutive_strikes, consecutive_actual) and int(_player(consecutive)["hp"]) == 33, "多敌人先后造成 3＋4 伤害，第二个敌人的预览与真实事件一致")

	var preceding_ko := _combat(true, false, "normal")
	_player(preceding_ko)["hp"] = 2
	_status(preceding_ko, _player(preceding_ko), "vulnerable", 2)
	var ko_first: Dictionary = preceding_ko.state["enemies"][0]
	var ko_second: Dictionary = preceding_ko.state["enemies"][1]
	ko_first["target_key"] = "p1"
	ko_first["intent"] = {"kind": "attack", "value": 3}
	ko_second["target_key"] = "p1"
	ko_second["intent"] = {"kind": "attack", "value": 3}
	var preceding_before := preceding_ko.to_dict()
	var preceding_preview := preceding_ko.intent_preview(ko_second)
	var preceding_strikes: Array = preceding_preview.get("strikes", [])
	_check(preceding_strikes.size() == 1 and str(preceding_strikes[0].get("target", "")) == "p2" and int(preceding_strikes[0].get("amount", -1)) == 3, "前敌击倒易伤玩家后，后敌预览转向无易伤队友并重新计算伤害")
	_check(preceding_ko.to_dict() == preceding_before and int(_player(preceding_ko)["hp"]) == 2, "多敌人倒地转向预览不改变真实玩家生命或敌人锁定目标")
	preceding_ko.end_turn("p1")
	var preceding_turn := preceding_ko.end_turn("p2")
	var preceding_actual := _events(preceding_turn, "damage").filter(func(hit): return str(hit.get("source", "")) == "e2")
	_check(_same_damage(preceding_strikes, preceding_actual) and int(_player(preceding_ko, "p2")["hp"]) == 37, "后敌转向队友的逐段预览与真实后敌事件一致")

	var poisoned := _combat()
	_enemy(poisoned)["hp"] = 3
	_status(poisoned, _enemy(poisoned), "poison", 3)
	var poison_before := poisoned.to_dict()
	var poison_preview := poisoned.intent_preview(_enemy(poisoned))
	_check(str(poison_preview.get("kind", "")) == "none" and poison_preview.get("strikes", []).is_empty() and int(poison_preview.get("times", -1)) == 0, "行动开始会被毒死的敌人不预告攻击段数")
	_check(poisoned.to_dict() == poison_before, "中毒死亡意图预览不会真实毒死敌人或清除状态")


func _test_poison() -> void:
	var combat := _combat()
	var player := _player(combat)
	_status(combat, player, "poison", 3)
	_status(combat, player, "strength", 99)
	_status(combat, player, "weak", 4)
	_status(combat, player, "vulnerable", 4)
	player["block"] = 90
	# 直接走同一个持续伤害入口，额外证明毒伤不消耗格挡。
	var direct_events: Array = []
	combat._apply_poison(player, direct_events)
	_check(int(player["hp"]) == 37 and int(player["block"]) == 90 and _stacks(player, "poison") == 2, "中毒先造成 3 伤害再减层，绕过格挡及力量／虚弱／易伤")
	_status(combat, player, "poison", 1)
	player["hp"] = 40
	var expected_hp := 40
	for amount in [3, 2, 1]:
		_passive(combat)
		var turn := combat.end_turn("p1")
		expected_hp -= amount
		var poison := _events(turn, "poison", "p1")
		_check(poison.size() == 1 and int(poison[0].get("amount", -1)) == amount and int(player["hp"]) == expected_hp, "玩家行动开始中毒依次结算 %d 点" % amount)
		_check(_event_index(turn, "enemy_acted") < _event_index(turn, "poison", "p1"), "本轮敌人行动完成后才进入下次玩家行动开始的中毒")
	_check(_stacks(player, "poison") == 0 and int(player["hp"]) == 34, "3＋2＋1 共扣 6 生命，零层中毒移除")

	var poisoned_enemies := _combat(false, false, "normal")
	for enemy in poisoned_enemies.state["enemies"]:
		enemy["hp"] = 3
		enemy["block"] = 100
		_status(poisoned_enemies, enemy, "poison", 3)
		_status(poisoned_enemies, enemy, "weak", 2)
	var enemy_turn := poisoned_enemies.end_turn("p1")
	_check(str(poisoned_enemies.state["outcome"]) == "won" and _events(enemy_turn, "enemy_died").size() == 2, "多敌人各在自身行动开始被毒死，最后一只死亡立即获胜")
	_check(_events(enemy_turn, "enemy_acted").is_empty() and _events(enemy_turn, "damage").is_empty(), "被毒死的敌人不再攻击或执行后续意图")

	var doomed := _combat(false, true)
	_player(doomed)["hp"] = 3
	_player(doomed)["block"] = 99
	_status(doomed, _player(doomed), "poison", 3)
	var start := doomed.start()
	_check(str(doomed.state["outcome"]) == "lost" and _events(start, "player_downed").size() == 1 and _events(start, "outcome").size() == 1, "开局毒死玩家：立即倒地与判负，各只发一次事件")
	_check(_player(doomed)["hand"].is_empty() and int(_player(doomed)["energy"]) == 0, "行动开始被毒死不会获得抽牌或能量")


func _test_coop_poison_and_rescue() -> void:
	var combat := _combat(true, true)
	var p1 := _player(combat)
	var p2 := _player(combat, "p2")
	p1["hp"] = 3
	_status(combat, p1, "poison", 3)
	_status(combat, p2, "poison", 2)
	var start := combat.start()
	_check(int(p1["hp"]) == 0 and int(p2["hp"]) == 38 and _events(start, "player_downed").size() == 1, "合作行动开始各结算一次中毒，倒地者不妨碍队友开局")
	var snapshot := combat.to_dict()
	_check(not bool(combat.start().get("ok", true)) and combat.to_dict() == snapshot, "重复 start 不再次中毒、倒地或发资源")
	_passive(combat)
	var next := combat.end_turn("p2")
	_check(_events(next, "poison", "p1").is_empty() and _events(next, "player_downed").is_empty() and _stacks(p1, "poison") == 2, "倒地者后续回合跳过中毒，不重复死亡与扣层")
	_check(int(p2["hp"]) == 37 and _stacks(p2, "poison") == 0, "合作存活队友下次开始仅结算一次余毒")
	var rescue_uid := _give(combat, "rescue", _card("rescue", [{"kind": "rescue", "value": 8}]), "p2")
	var rescue := combat.play_card("p2", rescue_uid, "p1")
	_check(bool(rescue.get("ok", false)) and int(p1["hp"]) == 8 and not bool(p1["downed"]) and bool(p1["rescued_once"]), "救援恢复 8 血，清倒地并登记本场一次")
	_check(p1["hand"].size() == 5 and int(p1["energy"]) == 3 and _stacks(p1, "poison") == 2, "补发错过的资源一次，救援不会额外触发中毒")
	p1["hp"] = 1
	_passive(combat)
	combat.end_turn("p1")
	var down_again := combat.end_turn("p2")
	_check(int(p1["hp"]) == 0 and _events(down_again, "player_downed").size() == 1, "获救玩家可在下一次自身行动开始被余毒再次击倒")
	var held: int = p1["hand"].size()
	var second_uid := _give(combat, "rescue_again", _card("rescue", [{"kind": "rescue", "value": 8}]), "p2")
	combat.play_card("p2", second_uid, "p1")
	_check(int(p1["hp"]) == 0 and p1["hand"].size() == held and bool(p1["downed"]), "本场第二次救援不能恢复生命或重复补发资源")


func _test_snapshot_and_cleanup() -> void:
	var combat := _combat(true)
	for unit in [_player(combat), _player(combat, "p2"), _enemy(combat)]:
		for status in ["strength", "dexterity", "weak", "vulnerable", "poison"]:
			_status(combat, unit, status, 2)
	_status(combat, _player(combat), "strength", 2)
	_status(combat, _player(combat), "dexterity", 3)
	_check(_stacks(_player(combat), "strength") == 4 and _stacks(_player(combat), "dexterity") == 5, "同名力量、敏捷重复施加按层数相加")
	var json_snapshot: Variant = JSON.parse_string(JSON.stringify(combat.to_dict()))
	var restored := CombatGame.new()
	_check(json_snapshot is Dictionary and restored.load_dict(json_snapshot), "五状态可经 JSON 战斗快照恢复")
	for key in ["p1", "p2", "e1"]:
		_check(_same_json(restored._find_unit(key)["statuses"], combat._find_unit(key)["statuses"]), "快照恢复双方完整状态及层数：" + key)
	_passive(combat)
	_passive(restored)
	combat.end_turn("p1")
	restored.end_turn("p1")
	var original_turn := combat.end_turn("p2")
	var restored_turn := restored.end_turn("p2")
	_check(_same_json(original_turn, restored_turn) and _same_json(combat.to_dict(), restored.to_dict()), "合作快照继续共同回合后事件、RNG、状态与资源完全一致")

	var legacy := combat.to_dict()
	for unit in [legacy["players"]["p1"], legacy["players"]["p2"], legacy["enemies"][0]]:
		unit["statuses"].erase("strength")
		unit["statuses"].erase("dexterity")
	var legacy_combat := CombatGame.new()
	_check(legacy_combat.load_dict(legacy), "旧快照缺少力量与敏捷仍可恢复")
	_check(legacy_combat._outgoing_damage("p1", {"statuses": {}}, 8) == 6 and legacy_combat._block_gain("p1", 8) == 8, "旧快照新增状态默认为零，仍保留原有虚弱")

	var finish := _combat(true)
	for unit in [_player(finish), _player(finish, "p2"), _enemy(finish)]:
		_status(finish, unit, "strength", 2)
		_status(finish, unit, "dexterity", 2)
	var kill := _give(finish, "finish", _card("enemy", [{"kind": "damage", "value": 999}]))
	finish.play_card("p1", kill, "e1")
	_check(str(finish.state["outcome"]) == "won" and _player(finish)["statuses"].is_empty() and _player(finish, "p2")["statuses"].is_empty() and _enemy(finish)["statuses"].is_empty(), "战斗结束清除所有单位的本场状态")
	var fresh := _combat()
	_check(_player(fresh)["statuses"].is_empty() and _enemy(fresh)["statuses"].is_empty(), "新战斗不携带上一场力量、敏捷")


func _test_anchor_cards_and_samples() -> void:
	for entry in [["slash", 5, "damage", "e1"], ["slash7", 8, "damage", "e1"], ["slash8", 13, "damage", "e1"], ["shield_up", 5, "block", "p1"], ["guard_standard", 8, "block", "p1"], ["guard_quality", 12, "block", "p1"]]:
		var combat := _combat()
		var id := str(entry[0])
		var def := CardDefs.get_card(id)
		_check(not def.is_empty() and int(def.get("cost", -1)) == 1, "正式锚点牌可用且费用为 1：" + id)
		if def.is_empty():
			continue
		var uid := _give(combat, id)
		var preview := combat.preview_play("p1", uid, str(entry[3]))
		_check(int(preview.get(str(entry[2]), -1)) == int(entry[1]), "正式锚点牌数值：" + id)
		_check(bool(combat.play_card("p1", uid, str(entry[3])).get("ok", false)), "正式锚点牌可以实际打出：" + id)
	var mixed := _combat()
	var mixed_uid := _give(mixed, "guarded_strike")
	mixed.play_card("p1", mixed_uid, "e1")
	_check(int(_enemy(mixed)["hp"]) == 117 and int(_player(mixed)["block"]) == 3, "正式 1 费混合牌具备 3 伤害＋自己 3 格挡")
	for entry in [["battle_focus", "strength"], ["nimble_stance", "dexterity"]]:
		var combat := _combat()
		var uid := _give(combat, str(entry[0]))
		var result := combat.play_card("p1", uid, "p1")
		_check(bool(result.get("ok", false)) and _stacks(_player(combat), str(entry[1])) == 2, "正式增益牌获得本场 2 层：" + str(entry[0]))
		_check(_player(combat)["exhaust_pile"].any(func(card): return int(card["uid"]) == uid), "正式增益牌使用后本场移除：" + str(entry[0]))
	for entry in [[7, 8, 0], [10, 8, 2], [15, 16, 0]]:
		var combat := _combat()
		_player(combat)["block"] = int(entry[1])
		_enemy(combat)["intent"] = {"kind": "attack", "value": int(entry[0])}
		combat.end_turn("p1")
		_check(int(_player(combat)["hp"]) == 40 - int(entry[2]), "%d 格挡应对 %d 攻击，生命损失 %d" % [int(entry[1]), int(entry[0]), int(entry[2])])
	for entry in [["expose", "vulnerable", 1], ["venom_stab", "poison", 3], ["suppress", "weak", 2]]:
		var combat := _combat()
		var uid := _give(combat, str(entry[0]))
		var result := combat.play_card("p1", uid, "e1")
		_check(bool(result.get("ok", false)) and _stacks(_enemy(combat), str(entry[1])) == int(entry[2]), "正式减益牌来源可施加对应层数：" + str(entry[0]))
	# 真正的样例构造入口：三档装备均能比较同一压力下的防御能量投入。
	for tier in AnchorSampleCombat.TIERS:
		for pressure in [7, 10, 15]:
			var sample := AnchorSampleCombat.create_sample(pressure, tier)
			_check(not sample.state.is_empty(), "样例可启动：%s／%d" % [tier, pressure])
			if sample.state.is_empty():
				continue
			var player := _player(sample)
			_check(player["hand"].size() == 5 and int(player["energy"]) == 3 and int(player["hp"]) == 40, "样例沿用 40 血／3 能量／抽 5：%s／%d" % [tier, pressure])
			var guard_id := str(AnchorSampleCombat.GUARDS[tier])
			var guard_value := int(CardDefs.get_card(guard_id)["effects"][0]["value"])
			var guard_count := int(ceil(float(pressure) / float(guard_value)))
			var played := 0
			for card in player["hand"].duplicate():
				if str(card["card_id"]) == guard_id and played < guard_count:
					sample.play_card("p1", int(card["uid"]), "p1")
					played += 1
			_check(played == guard_count and int(player["energy"]) == 3 - guard_count, "样例挡住 %d 需要 %s 档 %d 能量" % [pressure, tier, guard_count])
			sample.end_turn("p1")
			_check(int(player["hp"]) == 40 and int(_enemy(sample)["hp"]) == 72, "样例防御吸收完整来袭，敌人保持可持续验证的生命：%s／%d" % [tier, pressure])
	# 森林样稿使用同一规则引擎，混合牌的两种效果同样落到正确对象。
	var forest := ForestCardStudyCombat.create_study("tutorial", 67002, null)
	forest.state["players"]["p1"]["hand"] = [{"uid": 67099, "card_id": "forest_bell_strike", "owner": "p1", "source_instance_id": 0}]
	var forest_preview := forest.preview_play("p1", 67099, "e1")
	forest.play_card("p1", 67099, "e1")
	_check(int(forest_preview.get("damage", -1)) == 3 and int(forest_preview.get("block", -1)) == 3 and int(_player(forest)["block"]) == 3 and int(_enemy(forest)["hp"]) == 15, "森林样稿混合牌的预览与实际同为敌人 3 伤害＋自己 3 格挡")


func _combat(coop := false, before_start := false, encounter := "tutorial") -> FixtureCombat:
	var deck: Array = []
	for index in range(10):
		deck.append({"card_id": "slash", "source_seq": index, "join_round": 1})
	var players: Array = [{"key": "p1", "name": "农夫", "max_hp": 40, "deck": deck}]
	if coop:
		players.append({"key": "p2", "name": "阿禾", "max_hp": 40, "deck": deck})
	var base := CombatGame.create(players, encounter, 67001, null, deck)
	var combat := FixtureCombat.new()
	combat.load_dict(base.to_dict())
	for enemy in combat.state["enemies"]:
		enemy["hp"] = 120
		enemy["max_hp"] = 120
	if not before_start:
		combat.start()
	return combat


func _card(target: String, effects: Array) -> Dictionary:
	return {"name": "规则测试", "target": target, "cost": 1, "after": "discard", "effects": effects}


func _give(combat: FixtureCombat, card_id: String, definition: Dictionary = {}, owner := "p1") -> int:
	if not definition.is_empty():
		combat.custom_cards[card_id] = definition
	var uid := int(combat.state["next_uid"])
	combat.state["next_uid"] = uid + 1
	_player(combat, owner)["hand"].append({"uid": uid, "card_id": card_id, "source_instance_id": 0, "source_seq": 0, "owner": owner})
	return uid


func _player(combat: CombatGame, key := "p1") -> Dictionary:
	return combat.state["players"][key]


func _enemy(combat: CombatGame) -> Dictionary:
	return combat.state["enemies"][0]


func _status(combat: CombatGame, unit: Dictionary, name: String, amount: int) -> void:
	combat._add_status(unit, name, amount)


func _stacks(unit: Dictionary, name: String) -> int:
	return int(unit["statuses"].get(name, {}).get("stacks", 0))


func _passive(combat: CombatGame) -> void:
	for enemy in combat.state["enemies"]:
		enemy["intent"] = {"kind": "block", "value": 0}


func _effects(preview: Dictionary, kind: String) -> Array:
	return preview.get("effects", []).filter(func(effect): return str(effect.get("kind", "")) == kind)


func _events(result: Dictionary, type: String, target := "") -> Array:
	return result.get("events", []).filter(func(event): return str(event.get("type", "")) == type and (target == "" or str(event.get("target", "")) == target))


func _event_index(result: Dictionary, type: String, target := "") -> int:
	var events: Array = result.get("events", [])
	for index in range(events.size()):
		if str(events[index].get("type", "")) == type and (target == "" or str(events[index].get("target", "")) == target):
			return index
	return -1


func _same_json(left: Variant, right: Variant) -> bool:
	# JSON 将整数读成浮点数；比较相同存储形态，避免把兼容快照的数值类型当成差异。
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))


func _same_damage(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index in range(left.size()):
		for key in ["amount", "target", "blocked", "to_hp"]:
			if left[index].get(key) != right[index].get(key):
				return false
	return true


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("D67_COMBAT_STATUS_ANCHOR_FAIL: " + message)
