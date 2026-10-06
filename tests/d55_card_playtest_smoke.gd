extends SceneTree
## 首页直达卡牌试玩、实战胜利搜刮、装包续战、重开、失败及存档隔离。

var checks := 0
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("D55_CARD_PLAYTEST_FAIL: " + message)

func _save_fingerprints() -> Dictionary:
	var files := {}
	for path in ["user://farm_save_v1.json", "user://farm_save_v1.json.bak"]:
		files[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	var directory := DirAccess.open(ExpeditionStore.EXPEDITION_DIR)
	if directory != null:
		for name in directory.get_files():
			var path := ExpeditionStore.EXPEDITION_DIR + "/" + name
			files[path] = FileAccess.get_sha256(path)
	return files

func _frames() -> void:
	await process_frame
	await process_frame
	await process_frame

func _click(control: Control) -> void:
	await _frames()
	var point := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		root.push_input(event, true)
		await process_frame
	await _frames()

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _frames()
	var directory := "res://screenshots/card_playtest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.get_texture().get_image().save_png(directory + "/" + name + ".png")

func _fight(screen: BattleScreen) -> void:
	# 实际走界面的选牌、目标和结束回合，验证默认装备能打赢样例。
	for turn in range(20):
		if str(screen.combat.state.get("outcome", "")) != "":
			break
		var hand: Array = screen.combat.state["players"]["p1"]["hand"].duplicate(true)
		for card in hand:
			if str(screen.combat.state.get("outcome", "")) != "":
				break
			var uid := int(card["uid"])
			if not screen._can_act() or not screen._playable_card(uid):
				continue
			var definition := CardDefs.get_card(str(card["card_id"]))
			var target := "p1"
			if str(definition["target"]) == "enemy":
				for enemy in screen.combat.state["enemies"]:
					if bool(enemy["alive"]):
						target = str(enemy["id"])
						break
			screen._on_card_clicked(uid)
			if screen._legal_target(uid, target):
				screen._on_target_clicked(target)
			await process_frame
		if screen._can_act():
			screen._on_end_turn()
		await process_frame

func _run() -> void:
	var before := _save_fingerprints()
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	root.add_child(menu)
	current_scene = menu
	await _frames()
	var entry := menu.find_child("CardPlaytestButton", true, false) as Button
	_check(entry != null and not entry.disabled, "homepage playtest entrance available with any save state")
	await _shot("01_home_entry")
	await _click(entry)
	var playtest := current_scene as CardPlaytest
	_check(playtest != null, "actual homepage click enters standalone card scene")
	if playtest == null:
		quit(1)
		return
	_check(playtest.battle.visible and playtest.battle.combat != null, "entry immediately starts battle")
	_check(playtest.battle.combat.state["enemies"][0]["def_id"] == "skeleton_scout", "default battle tests equipment skeleton")
	_check(playtest.expedition.run_inventory().loadout_list("chest").size() == 2 and playtest.expedition.run_inventory().equipped_list().size() == 4, "attack, defense and supply automatically equipped")
	_check(playtest.expedition.run_inventory().loadout_list("pack").is_empty(), "pack starts empty for loot tests")
	await _shot("02_immediate_battle")
	await _fight(playtest.battle)
	_check(str(playtest.battle.combat.state.get("outcome", "")) == "won", "default equipped deck wins real skeleton battle")
	if str(playtest.battle.combat.state.get("outcome", "")) != "won":
		quit(1)
		return
	await _click(playtest.battle.overlay_column.get_child(playtest.battle.overlay_column.get_child_count() - 1) as Control)
	_check(playtest.loot.visible and not playtest.battle.visible, "victory leads to corpse loot scene")
	if not playtest.loot.visible:
		quit(1)
		return
	await _shot("03_corpse_loot")
	await _click(playtest.loot.battlefield.find_child("Corpse_e1", true, false) as Control)
	await create_timer(float(playtest.expedition.visible_run().get("loot_searches", {}).get("p1", {}).get("remaining", 0)) / 1000.0 + 0.25).timeout
	_check(not playtest.loot.scene_mode and not playtest.loot.entries.is_empty(), "actual corpse click searches and reveals weapon")
	_check(str(playtest.expedition.run["loot_searches"].get("p1", {}).get("region", "")) == "armor", "finished weapon auto chains into the next package")
	var instance: Dictionary = playtest.expedition.run["resolved"]["r3c1"]["corpses"][0]["regions"][0]["items"][0]
	var id := int(instance["instance_id"])
	_check(playtest._loot_action("claim_corpse", {"instance_id": id, "container": "pack"})["ok"], "revealed equipment can be packed")
	_check(playtest.expedition.run_inventory().find_instance(id)["container"] == "pack", "original loot instance carried")
	await _shot("04_search_and_pack")
	playtest._loot_action("search_cancel", {})
	playtest.loot._confirm_leave()
	_check(playtest.loot.modal.visible, "unsearched bags still prompt before continuing")
	await _frames()
	await _click(playtest.loot.modal_content.get_child(2) as Control)
	_check(playtest.battle.visible and playtest.battle_number == 2, "complete looting enters next real battle")
	if playtest.battle.combat == null:
		quit(1)
		return
	_check(not playtest.expedition.run_inventory().find_instance(id).is_empty(), "looted equipment survives into next battle")
	_check(int(playtest.battle.combat.state["players"]["p1"]["hp"]) == ExpeditionBaseline.MAX_HP, "repeat battle restores health")
	_check(DeckBuilder.build(playtest.expedition.run_inventory())["entries"].any(func(card): return int(card.get("source_instance_id", -1)) == id), "picked weapon contributes to next deck")
	_check(int(playtest.expedition.run["next_instance_id"]) > id, "new corpse instances never reuse carried item id")
	playtest._select_encounter(2)
	await _frames()
	_check(playtest.battle.combat.state["enemies"].size() == 3, "encounter selector starts multi enemy gate battle")
	var shield_found := false
	for source in playtest.expedition.run["resolved"]["r8c0"]["corpses"]:
		for region in source["regions"]:
			shield_found = shield_found or region["items"].any(func(item): return str(item["def_id"]) == "reinforced_shield")
	_check(shield_found, "gate sample includes real 2x2 shield loot")
	await _shot("05_gate_battle")
	playtest._select_encounter(1)
	_check(playtest.battle.combat.state["enemies"].size() == 2, "normal encounter available directly")
	await _click(playtest.find_child("ReplayBattleButton", true, false) as Control)
	_check(not playtest.expedition.run_inventory().find_instance(id).is_empty(), "replay keeps this session's loot")
	await _click(playtest.find_child("ResetPlaytestButton", true, false) as Control)
	_check(playtest.battle_number == 1 and playtest.expedition.run_inventory().loadout_list("pack").is_empty(), "reset clears test loot and restores starter loadout")
	# 失败使用临时结算，确认后直接重试，不走正式农场资产结算。
	playtest.battle.combat.state["players"]["p1"]["hp"] = 0
	playtest.battle.combat._events_check_outcome([])
	playtest.battle._refresh()
	_check(str(playtest.battle.combat.state["outcome"]) == "lost", "defeat is handled in standalone playtest")
	var retry := playtest.battle.overlay_column.get_child(playtest.battle.overlay_column.get_child_count() - 1) as Button
	_check(retry.text == "重试本场", "defeat has direct retry button")
	await _click(retry)
	_check(playtest.battle.visible and playtest.battle.combat.state["outcome"] == "", "defeat retry immediately starts fresh battle")
	root.size = Vector2i(1024, 640)
	await _frames()
	_check(root.get_visible_rect().encloses((playtest.find_child("PlaytestHomeButton", true, false) as Control).get_global_rect()), "home button fits minimum window")
	_check(playtest.battle.end_button.get_global_rect().end.y <= root.get_visible_rect().end.y + 1, "card action controls fit minimum window")
	for control in playtest.battle.pile_panel.get_children():
		_check(root.get_visible_rect().encloses(control.get_global_rect()), "every pile control fits minimum window")
	await _shot("06_small_window")
	await _click(playtest.find_child("PlaytestHomeButton", true, false) as Control)
	_check(current_scene is MainMenu, "home button returns to homepage")
	_check(_save_fingerprints() == before, "entry, battle, loot, retry and return do not alter farm or expedition saves")
	print("D55_CARD_PLAYTEST_%s checks=%d" % ["FAIL" if failed else "PASS", checks])
	quit(1 if failed else 0)
