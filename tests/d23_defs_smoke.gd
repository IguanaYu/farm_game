extends SceneTree
## 2.3：物品定义表与 DeckBuilder。15 种正式物品、占格=牌数、保险箱白名单、耗尽跳过。


var failed := false


func _initialize() -> void:
	_check(ItemDefs.validate_definitions().is_empty(), "定义表：占格数=牌数、牌引用全部有效")
	var real_count := 0
	var demo_count := 0
	for def_id in ItemDefs.ITEMS:
		if bool(ItemDefs.ITEMS[def_id].get("demo", false)):
			demo_count += 1
		else:
			real_count += 1
	_check(real_count == 19, "物品池：正式物品 19 种（2.3 的 15＋2.5 的 4）")
	_check(demo_count == 3, "物品池：演示物品 3 种隔离")

	var cargo_value := 0
	for def_id in ItemDefs.ITEMS:
		var def: Dictionary = ItemDefs.ITEMS[def_id]
		if bool(def.get("demo", false)) or not bool(def.get("sellable", false)):
			continue
		var all_cargo: bool = not (def["cards"] as Array).is_empty()
		for card_id in def["cards"]:
			if str(card_id) != "heavy_cargo":
				all_cargo = false
		if all_cargo:
			cargo_value += 1
	_check(cargo_value >= 3, "值钱但拖累：可售纯货物牌物品 ≥2 种（实际 %d）" % cargo_value)

	for pair in [["copper_scrap", true], ["iron_ore", true], ["rock_sprout_seed", true], ["antique_ornament", false], ["glow_crystal", false], ["copper_shortsword", false]]:
		_check(bool(ItemDefs.get_item(pair[0]).get("safe_allowed", false)) == pair[1], "保险箱白名单：%s = %s" % [pair[0], pair[1]])
	_check(int(ItemDefs.get_item("small_potion").get("uses", 1)) == 1 and int(ItemDefs.get_item("bandage").get("uses", 1)) == 1, "补给：药水/绷带各 1 次实体")
	var crystal := ItemDefs.get_item("glow_crystal")
	_check(crystal["cards"] == ["brace", "observe"] and int(crystal["base_value"]) == 60, "微光晶石：贵且能打（60 金币，稳住＋观察）")

	# —— DeckBuilder：布局→牌组、按回合分组、耗尽跳过 ——
	var game := FarmGame.new()
	game.new_game(1000)
	var inv := InventoryGame.new()
	inv.bind(game.state["expedition"])
	inv.grant_basic_kit()
	for instance in inv.warehouse_list().duplicate():
		inv.move_to_loadout(int(instance["instance_id"]), "chest")
	var build := DeckBuilder.build(inv)
	_check(int(build["totals"][1]) == 8 and int(build["totals"][2]) == 0, "牌组：基础套装入胸挂 → 首回合 8 张")
	for instance in inv.loadout_list("chest").duplicate():
		if str(instance["def_id"]) == "wooden_shield":
			inv.move_to_warehouse(int(instance["instance_id"]))
			inv.move_to_loadout(int(instance["instance_id"]), "pack")
	var shield_id := -1
	for instance in inv.loadout_list("pack"):
		shield_id = int(instance["instance_id"])
	build = DeckBuilder.build(inv)
	_check(int(build["totals"][1]) == 4 and int(build["totals"][2]) == 4, "牌组：木盾挪背包 → 1/2 回合各 4 张（设计 §9 场景）")
	var join_of_shield := 0
	for entry in build["entries"]:
		if int(entry["source_instance_id"]) == shield_id:
			join_of_shield = int(entry["join_round"])
	_check(join_of_shield == 2, "牌组：来源牌记录加入回合")

	var potion := inv.add_instance("small_potion", "test")
	inv.move_to_loadout(int(potion["instance_id"]), "pack")
	inv.find_instance(int(potion["instance_id"]))["uses_remaining"] = 0
	build = DeckBuilder.build(inv)
	var potion_cards := 0
	for entry in build["entries"]:
		if str(entry["card_id"]) == "drink_potion":
			potion_cards += 1
	_check(potion_cards == 0, "牌组：已耗尽的药水不再生成牌")

	_finish()


func _finish() -> void:
	if failed:
		push_error("D23_DEFS_SMOKE_FAIL")
	else:
		print("D23_DEFS_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
