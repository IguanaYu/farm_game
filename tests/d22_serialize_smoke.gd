extends SceneTree
## 2.2：战斗状态序列化——保存恢复不改变手牌、回合、意图与消耗结果（设计 §9 最后一行）。


var failed := false


func _initialize() -> void:
	var order := _order(["slash", "shield_up", "brace", "observe", "slash", "slash", "shield_up", "brace"])
	var combat := CombatGame.create([_player(order)], "normal", 31, null, order)
	combat.start()
	_play(combat, "slash", "e2")
	_play(combat, "shield_up")
	var hand_before := _hand_ids(combat)
	var hp_before := int(combat.state["enemies"][1]["hp"])
	var energy_before := int(combat.state["players"]["p1"]["energy"])

	var snapshot := combat.to_dict()
	var restored := CombatGame.new()
	_check(restored.load_dict(snapshot), "快照：可恢复")
	_check(_hand_ids(restored) == hand_before, "恢复：手牌（顺序与 uid）一致")
	_check(int(restored.state["enemies"][1]["hp"]) == hp_before, "恢复：敌人生命一致")
	_check(int(restored.state["players"]["p1"]["energy"]) == energy_before, "恢复：能量一致")
	_check(str(restored.state["enemies"][0]["intent"]) == str(combat.state["enemies"][0]["intent"]), "恢复：意图不重掷")
	_check(int(restored.state["round"]) == int(combat.state["round"]), "恢复：回合一致")

	# 恢复后继续打同样的牌 → 同样的结果（同种子同状态）。
	_play(combat, "slash", "e2")
	_play(restored, "slash", "e2")
	_check(int(combat.state["enemies"][1]["hp"]) == int(restored.state["enemies"][1]["hp"]), "恢复：继续出牌结果一致")
	combat.end_turn("p1")
	restored.end_turn("p1")
	_check(int(combat.state["players"]["p1"]["hp"]) == int(restored.state["players"]["p1"]["hp"]), "恢复：敌方阶段结算一致")
	_check(int(combat.state["round"]) == int(restored.state["round"]), "恢复：回合推进一致")

	# 局内存档走一次 JSON 往返（2.4 局快照的存储形态）。
	var json_round: Variant = JSON.parse_string(JSON.stringify(snapshot))
	_check(json_round is Dictionary, "快照：JSON 可往返")
	var from_json := CombatGame.new()
	_check(from_json.load_dict(json_round), "快照：JSON 读回可恢复")
	_check(_hand_ids(from_json) == hand_before, "快照：JSON 读回手牌一致")

	if failed:
		push_error("D22_SERIALIZE_SMOKE_FAIL")
	else:
		print("D22_SERIALIZE_SMOKE_PASS")
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
	return {"ok": false, "reason": "missing"}


func _hand_ids(combat: CombatGame) -> Array:
	var result: Array = []
	for card in combat.state["players"]["p1"]["hand"]:
		result.append(int(card["uid"]))
	return result


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
