extends SceneTree
## 森林第一章 P1：新牌与新战斗效果——灼烧时点、寒冷多段、穿透算例、净化、补给清牌、
## 伤害顺序、序列化恢复一致。算例数值全部来自开发计划 §5-P1 与内容设计 §10。

var failed := false
var _uid := 9100


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# ① 微光弹穿透算例：6 格挡、5 伤害、忽略至多 3 → 抵消 3、生命 -2、剩余 3 格挡。
	var combat := _combat()
	combat.start()
	var enemy: Dictionary = combat.state["enemies"][0]
	enemy["block"] = 6
	var bolt := _play_source(combat, "forest_runic_wand", "forest_glow_bolt", "e1")
	_check(bool(bolt["ok"]), "微光弹：可打出")
	_check(int(enemy["hp"]) == int(enemy["max_hp"]) - 2, "穿透算例：6 格挡受 5 伤害 → 生命 -2")
	_check(int(enemy["block"]) == 3, "穿透算例：被忽略的格挡不删除（剩余 3）")
	var preview: Dictionary = bolt["preview"]
	_check(int(preview.get("damage", 0)) == 5 and int(preview.get("pierce", 0)) == 3, "伤害预览：共用计算入口（5 伤害＋忽略 3）")

	# ② 剩余格挡仍可阻挡下一击：3 格挡受 2 伤害（投网）→ 全部抵消；绳网整件消耗。
	var net_result := _play_source(combat, "forest_rope_net", "forest_throw_net", "e1")
	_check(bool(net_result["ok"]), "投网：可打出")
	_check(int(enemy["hp"]) == int(enemy["max_hp"]) - 2, "投网：2 伤害被剩余 3 格挡全抵消（生命不变）")
	_check(int(enemy["block"]) == 1, "投网：格挡 3→1")
	_check(_has_status(enemy, "weak"), "投网：附加 1 回合虚弱")
	var net_id := _instance_of(combat, "forest_rope_net")
	_check(combat.inventory.uses_remaining(net_id) == 0, "投网：绳网实体耗尽")
	_check(not _source_alive(combat, net_id), "投网：负担牌连同实体一并移除（含未洗入牌堆）")

	# ③ 灼烧时点：行动开始结算一次并清除；无视格挡；取最高强度不叠加。
	var burn_combat := _combat()
	burn_combat.start()
	var target: Dictionary = burn_combat.state["enemies"][0]
	target["block"] = 10
	burn_combat._add_status(target, "burn", 1)
	burn_combat._add_status(target, "burn", 2)
	_check(int(target["statuses"]["burn"]["stacks"]) == 2, "灼烧：重复施加取最高强度（1+2→2）")
	var hp0 := int(target["hp"])
	burn_combat.end_turn("p1")
	_check(int(target["hp"]) == hp0 - 2, "灼烧：敌人行动开始受 2 点（无视 10 格挡）")
	_check(not _has_status(target, "burn"), "灼烧：结算一次即清除")
	var hp1 := int(target["hp"])
	burn_combat.end_turn("p1")
	_check(int(target["hp"]) == hp1, "灼烧：下一回合不再结算（已清除）")

	# ④ 寒冷多段：只减第一段 2 点，首段结算即消耗；不攻击也在行动结束清除。
	var chill_combat := _combat("normal")
	chill_combat.start()
	var bat: Dictionary = {}
	var slime: Dictionary = {}
	for entry in chill_combat.state["enemies"]:
		if str(entry["def_id"]) == "cave_bat":
			bat = entry
		if str(entry["def_id"]) == "slime":
			slime = entry
	bat["intent"] = {"kind": "attack", "value": 3, "times": 2, "seed_locked": true}
	slime["intent"] = {"kind": "block", "value": 0, "seed_locked": true}
	chill_combat._add_status(bat, "chill", 1)
	var victim: Dictionary = chill_combat.state["players"]["p1"]
	var vhp0 := int(victim["hp"])
	chill_combat.end_turn("p1")
	_check(int(victim["hp"]) == vhp0 - 4, "寒冷多段：首段 3-2=1＋次段 3 → 共 -4")
	_check(not _has_status(bat, "chill"), "寒冷多段：首段结算后即消耗（即使被格挡）")
	slime["intent"] = {"kind": "block", "value": 4, "seed_locked": true}
	chill_combat._add_status(slime, "chill", 1)
	chill_combat.end_turn("p1")
	_check(not _has_status(slime, "chill"), "寒冷：该次只防守也在行动结束清除")

	# ⑤ 伤害顺序：玩家带寒冷时首段攻击在易伤/虚弱取整后减 2；回合结束清除。
	var order_combat := _combat()
	order_combat.start()
	var p1: Dictionary = order_combat.state["players"]["p1"]
	order_combat._add_status(p1, "chill", 1)
	_uid += 1
	p1["hand"].append({"uid": _uid, "card_id": "slash", "source_instance_id": 0, "source_seq": 0, "owner": "p1"})
	var e0: Dictionary = order_combat.state["enemies"][0]
	var ehp0 := int(e0["hp"])
	order_combat.play_card("p1", _uid, "e1")
	_check(int(e0["hp"]) == ehp0 - 4, "伤害顺序：玩家带寒冷时切击 6→4（取整后再减寒冷）")
	_check(not _has_status(p1, "chill"), "伤害顺序：玩家第一段攻击后寒冷消耗")
	order_combat._add_status(p1, "chill", 1)
	order_combat.end_turn("p1")
	_check(not _has_status(p1, "chill"), "伤害顺序：玩家回合结束寒冷清除（该回合未再攻击）")

	# ⑥ 净化（安息铃）：移除 2 层中毒并清除灼烧。
	var cleanse_combat := _combat()
	cleanse_combat.start()
	var ally: Dictionary = cleanse_combat.state["players"]["p1"]
	cleanse_combat._add_status(ally, "poison", 3)
	cleanse_combat._add_status(ally, "burn", 2)
	var bell := _play_source(cleanse_combat, "forest_ritual_bellstaff", "forest_rest_bell", "p1")
	_check(bool(bell["ok"]), "安息铃：可打出")
	_check(int(ally["statuses"].get("poison", {}).get("stacks", 0)) == 1, "安息铃：中毒 3→1（移除 2 层）")
	_check(not _has_status(ally, "burn"), "安息铃：灼烧整项清除")

	# ⑦ 补给清牌：食蜜/火囊一次消耗并清除关联牌；敷伤苔复用包扎。
	var supply_combat := _combat()
	supply_combat.start()
	var honey_id := _instance_of(supply_combat, "forest_honey_chunk")
	var honey := _play_by_card(supply_combat, "forest_eat_honey", "p1", honey_id)
	_check(bool(honey["ok"]), "食蜜：可打出")
	_check(supply_combat.inventory.uses_remaining(honey_id) == 0, "食蜜：蜂蜜块实体耗尽")
	_check(not _source_alive(supply_combat, honey_id), "食蜜：关联牌全部移除")
	var fire_id := _instance_of(supply_combat, "forest_fire_gel_sac")
	var fire := _play_by_card(supply_combat, "forest_throw_fire_sac", "e1", fire_id)
	_check(bool(fire["ok"]), "投掷火囊：可打出")
	var fire_target: Dictionary = supply_combat.state["enemies"][0]
	_check(_has_status(fire_target, "burn") and int(fire_target["statuses"]["burn"]["stacks"]) == 2, "投掷火囊：附加灼烧 2")
	_check(not _source_alive(supply_combat, fire_id), "投掷火囊：赤凝胶囊实体与关联牌移除")
	var moss_id := _instance_of(supply_combat, "forest_healing_moss")
	var moss := _play_by_card(supply_combat, "first_aid", "p1", moss_id)
	_check(bool(moss["ok"]) and supply_combat.inventory.uses_remaining(moss_id) == 0, "敷伤苔：复用应急包扎并一次消耗")

	# ⑧ 序列化恢复：灼烧/寒冷跨快照保留并继续按规则结算。
	var ser_combat := _combat()
	ser_combat.start()
	var ser_enemy: Dictionary = ser_combat.state["enemies"][0]
	ser_combat._add_status(ser_enemy, "burn", 2)
	ser_combat._add_status(ser_enemy, "chill", 1)
	var restored := CombatGame.new()
	_check(restored.load_dict(ser_combat.to_dict()), "序列化：快照可加载")
	var r_enemy: Dictionary = restored.state["enemies"][0]
	_check(int(r_enemy["statuses"]["burn"]["stacks"]) == 2 and _has_status(r_enemy, "chill"), "序列化：灼烧/寒冷跨快照保留")
	var r_hp := int(r_enemy["hp"])
	restored.end_turn("p1")
	_check(int(restored.state["enemies"][0]["hp"]) == r_hp - 2, "序列化恢复后：灼烧仍按行动开始结算")

	if failed:
		push_error("FOREST_COMBAT_SMOKE_FAIL")
	else:
		print("FOREST_COMBAT_SMOKE_PASS")
	quit(1 if failed else 0)


## 独立战场：新农场库存，发放基础套装＋本轮全部森林测试物品（仓库不进牌堆），返回绑定战斗。
func _combat(encounter := "tutorial") -> CombatGame:
	var farm := FarmGame.new()
	farm.new_game(1000)
	var inv := InventoryGame.new()
	inv.bind(farm.state["expedition"])
	inv.grant_basic_kit()
	for def_id in [
		"forest_runic_wand", "forest_rope_net", "forest_ritual_bellstaff",
		"forest_honey_chunk", "forest_fire_gel_sac", "forest_healing_moss",
	]:
		var added: Dictionary = inv.add_instance(def_id, "test")
		if not added.has("instance_id"):
			push_error("  FAIL: 测试物品 %s 发放失败：%s" % [def_id, str(added.get("reason", ""))])
			failed = true
	return CombatGame.create([{"key": "p1", "name": "农夫", "max_hp": 40, "deck": DeckBuilder.build(inv)["entries"]}], encounter, 7, inv)


func _instance_of(combat: CombatGame, def_id: String) -> int:
	for instance in combat.inventory.all_instances():
		if str(instance["def_id"]) == def_id:
			return int(instance["instance_id"])
	return 0


## 从装备好的来源物品构造对应牌直接入手打出（算例不经抽牌随机）。
func _play_source(combat: CombatGame, source_def: String, card_id: String, target: String) -> Dictionary:
	return _play_by_card(combat, card_id, target, _instance_of(combat, source_def))


func _play_by_card(combat: CombatGame, card_id: String, target: String, source_id: int) -> Dictionary:
	var player: Dictionary = combat.state["players"]["p1"]
	_uid += 1
	player["hand"].append({"uid": _uid, "card_id": card_id, "source_instance_id": source_id, "source_seq": 0, "owner": "p1"})
	var preview: Dictionary = combat.preview_play("p1", _uid, target)
	var result := combat.play_card("p1", _uid, target)
	result["preview"] = preview
	return result


func _source_alive(combat: CombatGame, source_id: int) -> bool:
	var player: Dictionary = combat.state["players"]["p1"]
	for pile_name in ["hand", "draw_pile", "discard_pile"]:
		for card in player[pile_name]:
			if int(card.get("source_instance_id", 0)) == source_id:
				return true
	return false


func _has_status(unit: Dictionary, status: String) -> bool:
	return int(unit.get("statuses", {}).get(status, {}).get("stacks", 0)) > 0


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
