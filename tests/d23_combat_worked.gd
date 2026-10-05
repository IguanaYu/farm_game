extends SceneTree
## 2.3：两场战斗串联——牌组来自布局、容器按回合加入、生命延续、补给耗尽清牌、货物负担。


var failed := false
var game: FarmGame
var inv: InventoryGame


func _initialize() -> void:
	game = FarmGame.new()
	game.new_game(1000)
	inv = InventoryGame.new()
	inv.bind(game.state["expedition"])
	inv.grant_basic_kit()
	# 三栏改版口径：装备槽=短刀＋草帽（第 1 回合）；胸挂=工具（第 2 回合）；背包=木盾＋1 瓶药水（第 3 回合）。
	inv.equip(_id_of("old_shortsword"), "main_weapon")
	inv.equip(_id_of("straw_hat"), "helmet")
	inv.move_to_loadout(_id_of("pack_tools"), "chest")
	inv.move_to_loadout(_id_of("wooden_shield"), "pack")
	var potion := inv.add_instance("small_potion", "test")
	inv.move_to_loadout(int(potion["instance_id"]), "pack")
	var potion_id := int(potion["instance_id"])

	var build := DeckBuilder.build(inv)
	_check(int(build["totals"][1]) == 6 and int(build["totals"][2]) == 2 and int(build["totals"][3]) == 5, "布局：第 1 回合 6 张（装备），第 2 回合 2 张（工具），第 3 回合 5 张（盾 4＋药 1）")

	# —— 第一场：固定牌序注入，验证容器加入时点 ——
	var fixed: Array = []
	for entry in build["entries"]:
		if int(entry["join_round"]) == 1:
			fixed.append(entry)
	var combat := CombatGame.create([_player()], "tutorial", 41, inv, fixed)
	combat.start()
	var player: Dictionary = combat.state["players"]["p1"]
	_check(player["hand"].size() == 5, "第 1 回合抽 5 张（装备槽 6 张池）")
	for card in player["hand"]:
		_check(_in_equipped(int(card["source_instance_id"])), "首日手牌全部来自装备槽（%s）" % _source_name(int(card["source_instance_id"])))
	combat.end_turn("p1")
	var saw_chest := false
	for card in player["hand"]:
		if _in_container(int(card["source_instance_id"]), "chest"):
			saw_chest = true
	_check(saw_chest, "第 2 回合：手牌里出现胸挂来源牌（工具）")
	combat.end_turn("p1")
	var saw_pack := false
	for card in player["hand"]:
		if _in_container(int(card["source_instance_id"]), "pack"):
			saw_pack = true
	_check(saw_pack, "第 3 回合：手牌里出现背包来源牌（盾）")

	# —— 药水：使用一次→实体耗尽→关联牌全部清除 ——
	player["hand"].append({"uid": 9001, "card_id": "drink_potion", "source_instance_id": potion_id, "source_seq": 0, "owner": "p1"})
	player["draw_pile"].append({"uid": 9002, "card_id": "drink_potion", "source_instance_id": potion_id, "source_seq": 0, "owner": "p1"})
	var hp_before := int(player["hp"])
	player["hp"] = 30
	var drink := combat.play_card("p1", 9001, "p1")
	_check(drink["ok"], "饮药：可对自己使用")
	_check(int(player["hp"]) == 38, "饮药：恢复 8（30→38）")
	_check(inv.uses_remaining(potion_id) == 0, "饮药：实体耗尽（uses 0）")
	var residue := 0
	for card in player["hand"]:
		if int(card.get("source_instance_id", 0)) == potion_id:
			residue += 1
	for card in player["draw_pile"]:
		if int(card.get("source_instance_id", 0)) == potion_id:
			residue += 1
	for card in player["discard_pile"]:
		if int(card.get("source_instance_id", 0)) == potion_id:
			residue += 1
	_check(residue == 0, "耗尽：手牌/抽牌/弃牌中的关联牌全部移除（含未打出的 9002）")
	var rebuild := DeckBuilder.build(inv)
	var potion_left := 0
	for entry in rebuild["entries"]:
		if str(entry["card_id"]) == "drink_potion":
			potion_left += 1
	_check(potion_left == 0, "下一场：耗尽药水不再生成牌")

	# —— 笨重货物：本场移除牌，物品仍在 ——
	player["hand"].append({"uid": 9003, "card_id": "heavy_cargo", "source_instance_id": 0, "source_seq": 0, "owner": "p1"})
	var cargo := combat.play_card("p1", 9003, "p1")
	_check(cargo["ok"], "笨重货物：花 1 能量本场移除")
	var exhausted := false
	for card in player["exhaust_pile"]:
		if int(card["uid"]) == 9003:
			exhausted = true
	_check(exhausted, "笨重货物：进入移除区")

	# —— 第二场：生命延续、格挡与手牌重建、新布局重新构建 ——
	player["hp"] = 25
	var carried := int(player["hp"])
	combat.end_turn("p1")
	var second := CombatGame.create([_player_with_hp(carried)], "tutorial", 43, inv, [])
	second.start()
	var p2: Dictionary = second.state["players"]["p1"]
	_check(int(p2["hp"]) == carried, "第二场：生命延续（%d）" % carried)
	_check(int(p2["block"]) == 0 and p2["hand"].size() == 5, "第二场：格挡清零、手牌按新布局重建（药水已耗尽不生成）")
	_check(int(second.state["enemies"][0]["hp"]) == 18, "第二场：敌人重新生成")

	_finish()


func _finish() -> void:
	if failed:
		push_error("D23_COMBAT_WORKED_FAIL")
	else:
		print("D23_COMBAT_WORKED_PASS")
	quit(1 if failed else 0)


func _player() -> Dictionary:
	return {"key": "p1", "name": "农夫", "max_hp": 40, "deck": DeckBuilder.build(inv)["entries"]}


func _player_with_hp(hp: int) -> Dictionary:
	var base := _player()
	base["hp"] = hp
	return base


func _id_of(def_id: String) -> int:
	for instance in inv.all_instances():
		if str(instance["def_id"]) == def_id:
			return int(instance["instance_id"])
	return -1


func _in_equipped(instance_id: int) -> bool:
	var instance := inv.find_instance(instance_id)
	return str(instance.get("container", "")) == "equipped" or instance_id == 0


func _in_container(instance_id: int, container: String) -> bool:
	if instance_id == 0:
		return true
	var instance := inv.find_instance(instance_id)
	return str(instance.get("container", "")) == container


func _source_name(instance_id: int) -> String:
	if instance_id == 0:
		return "无来源（注入）"
	return str(inv.find_instance(instance_id).get("def_id", "?"))


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
