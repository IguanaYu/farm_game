extends SceneTree
## 实际样例牌组、7／10／15 点防御投入、试玩入口，以及可复现的自动决策观察。
## 策略是先防御、再成长／状态／攻击；观察用于比较初值，不等同于人类最优打法。

var checks := 0
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("D68_ANCHOR_SAMPLE_FAIL: " + message)

func _play(session: CombatGame, card: Dictionary, counters: Dictionary) -> bool:
	var definition := session.card_definition(str(card["card_id"]))
	var player: Dictionary = session.state["players"]["p1"]
	if session.is_over() or int(player["energy"]) < int(definition["cost"]):
		return false
	var target := "e1" if str(definition["target"]) == "enemy" else "p1"
	var result := session.play_card("p1", int(card["uid"]), target)
	_check(bool(result.get("ok", false)), "sample card can resolve: " + str(card["card_id"]))
	if bool(result.get("ok", false)):
		counters["energy_spent"] = int(counters.get("energy_spent", 0)) + int(definition["cost"])
		if CardDefs.is_attack_card(str(card["card_id"])):
			counters["energy_attack"] = int(counters.get("energy_attack", 0)) + int(definition["cost"])
		return true
	return false

func _simulate(pressure: int, tier: String) -> Dictionary:
	var session := AnchorSampleCombat.create_sample(pressure, tier)
	var counters := {"energy_spent": 0, "energy_attack": 0}
	var turns := 0
	while not session.is_over() and turns < 30:
		turns += 1
		var player: Dictionary = session.state["players"]["p1"]
		var enemy: Dictionary = session.state["enemies"][0]
		# 如果一张现有攻击就能结束战斗，先完成击杀，不浪费能量防御。
		for card in player["hand"].duplicate(true):
			if session.is_over():
				break
			if not CardDefs.is_attack_card(str(card["card_id"])):
				continue
			var preview := session.preview_play("p1", int(card["uid"]), "e1")
			if int(preview.get("damage", 0)) >= int(enemy["hp"]):
				_play(session, card, counters)
		# 尽量挡住当前可见意图；不会凭空产生手牌或修改任何生命、能量。
		for card in player["hand"].duplicate(true):
			if session.is_over():
				break
			var intent := session.intent_preview(enemy)
			var incoming := int(intent.get("value", 0)) * int(intent.get("times", 1))
			if incoming > int(player["block"]) and CardDefs.is_defense_card(str(card["card_id"])):
				_play(session, card, counters)
		# 成长优先敏捷，然后力量；之后减攻、易伤、中毒，最后花剩余能量攻击。
		for card_id in ["nimble_stance", "battle_focus", "suppress", "expose", "venom_stab"]:
			for card in player["hand"].duplicate(true):
				if str(card["card_id"]) == card_id:
					_play(session, card, counters)
		for card in player["hand"].duplicate(true):
			if CardDefs.is_attack_card(str(card["card_id"])):
				_play(session, card, counters)
		if not session.is_over():
			_check(bool(session.end_turn("p1").get("ok", false)), "sample phase advances")
	_check(session.is_over(), "sample resolves within 30 turns: %d/%s" % [pressure, tier])
	return {"pressure": pressure, "tier": tier, "outcome": session.state["outcome"],
		"rounds": int(session.state["round"]), "hp_lost": 40 - int(session.state["players"]["p1"]["hp"]),
		"enemy_hp_remaining": int(session.state["enemies"][0]["hp"]),
		"energy_attack": int(counters["energy_attack"]), "energy_spent": int(counters["energy_spent"])}

func _run() -> void:
	_check(ItemDefs.validate_definitions().is_empty(), "every item area still matches card count and valid definitions")
	for pressure in [7, 10, 15]:
		for tier in AnchorSampleCombat.TIERS:
			var sample := AnchorSampleCombat.create_sample(pressure, tier)
			var player: Dictionary = sample.state["players"]["p1"]
			var enemy: Dictionary = sample.state["enemies"][0]
			_check(int(player["hp"]) == 40 and int(player["energy"]) == 3 and player["hand"].size() == 5, "sample uses 40hp/3energy/5draw")
			_check(player["draw_pile"].size() == 10 and int(enemy["hp"]) == 72, "sample retains 15 cards and durable target")
			_check(int(sample.intent_preview(enemy)["value"]) == pressure, "enemy exposes exact pressure")
			_check(str(player["hand"][0]["card_id"]) == AnchorSampleCombat.GUARDS[tier] and str(player["hand"][3]["card_id"]) == AnchorSampleCombat.ATTACKS[tier], "fixed first hand supports direct equipment comparison")
		# 验收的标准牌防御投入：8 挡应对 7／10；16 挡应对 15。
		var reference := AnchorSampleCombat.create_sample(pressure, "standard")
		var guards: Array = reference.state["players"]["p1"]["hand"].duplicate(true)
		var counter: Dictionary = {}
		_play(reference, guards[0], counter)
		if pressure == 15:
			_play(reference, guards[1], counter)
		reference.end_turn("p1")
		_check(int(reference.state["players"]["p1"]["hp"]) == (38 if pressure == 10 else 40), "8/16 block versus 7/10/15 actual damage")
	var metrics: Array = []
	for pressure in [7, 10, 15]:
		for tier in AnchorSampleCombat.TIERS:
			var observation := _simulate(pressure, str(tier))
			metrics.append(observation)
			print("D68_ANCHOR_OBSERVATION " + JSON.stringify(observation))
	_check(_simulate(15, "standard") == metrics[7], "same seed and decision policy reproduce full combat metrics")
	var playtest := (load("res://scenes/card_playtest.tscn") as PackedScene).instantiate() as CardPlaytest
	root.add_child(playtest)
	await process_frame
	playtest._select_encounter(4)
	_check(str(playtest.battle.combat.state["encounter_id"]) == "anchor_pressure_7" and playtest.anchor_tier_row.visible, "actual playtest selector enters anchor mode")
	_check(not playtest.quality_picker.get_parent().visible, "sample offers explicit card tiers without unrelated random quality selector")
	playtest.anchor_tier_picker.item_selected.emit(2)
	_check(str(playtest.battle.combat.state["anchor_sample"]["tier"]) == "quality", "tier selector starts high quality sample")
	playtest._select_encounter(6)
	_check(int(playtest.battle.combat.state["enemies"][0]["intent"]["value"]) == 15, "actual playtest selector switches heavy pressure")
	playtest._select_encounter(0)
	_check(str(playtest.battle.combat.state["enemies"][0]["def_id"]) == "skeleton_scout" and not playtest.anchor_tier_row.visible, "switching back restores ordinary battle")
	playtest.queue_free()
	await process_frame
	print("D68_ANCHOR_SAMPLE_%s checks=%d" % ["FAIL" if failed else "PASS", checks])
	quit(1 if failed else 0)
