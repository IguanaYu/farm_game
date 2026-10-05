extends SceneTree
## 五档权威搜索、多包同屏、品质实例流转、卡面来源、快捷自用及事件特效。
var checks := 0
var failed := false
var now := 1000

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("D56_QUALITY_FEEDBACK_FAIL: " + message)

func _frames() -> void:
	for i in range(4):
		await process_frame

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _frames()
	var directory := "res://screenshots/quality_feedback"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.get_texture().get_image().save_png(directory + "/" + name + ".png")

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

func _authority() -> void:
	var previous_duration := 0
	var colors := {}
	for quality in range(1, 6):
		var duration := ItemDefs.search_ms(quality)
		_check(duration > previous_duration and duration < CorpseLootGame.LEASE_MS, "rarer tier searches longer within lease")
		previous_duration = duration
		colors[ItemDefs.quality_color(quality)] = true
		var region := CorpseLootGame._region("armor", "护具", Vector2i(2, 2))
		var run := {"next_instance_id": 1000, "loot_searches": {}, "resolved": {}}
		CorpseLootGame._put(run, region, "wooden_shield")
		var item: Dictionary = region["items"][0]
		item["quality"] = quality
		var resolved := {"corpses": [{"id": "e1", "regions": [region]}]}
		run["resolved"]["r1c0"] = resolved
		_check(CorpseLootGame.start(run, resolved, "r1c0", "p1", "e1", "armor", 1000)["ok"], "start tier")
		_check(int(run["loot_searches"]["p1"]["duration"]) == duration, "authority uses instance quality")
		var visible: Dictionary = CorpseLootGame.view(run, 1000)["resolved"]["r1c0"]["corpses"][0]["regions"][0]
		_check(visible["items"].is_empty() and visible["unknown"][0].size() == 2, "unknown exposes geometry only")
		_check(not CorpseLootGame.step(run, resolved, "p1", 1000 + duration - 1)["ok"] and not bool(item["revealed"]), "one millisecond early cannot reveal")
		_check(CorpseLootGame.step(run, resolved, "p1", 1000 + duration)["ok"] and bool(item["revealed"]), "exact duration reveals")
		_check(region["searched"].size() == 4 and ItemDefs.quality_of(item) == quality, "all four cells reveal original tier once")
	_check(colors.size() == 5, "five distinct tier colors")
	var tiers := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 56
	for i in range(200):
		var sources := CorpseLootGame.build({"next_instance_id": 1000}, {"type": "battle"}, "skeleton_patrol", [], [], rng)
		for region in sources[0]["regions"]:
			for item in region["items"]:
				if str(ItemDefs.get_item(str(item["def_id"]))["category"]) in ["weapon", "armor"]:
					tiers[ItemDefs.quality_of(item)] = true
	_check(tiers.size() == 5, "normal authority drops can produce all five tiers")

func _effect_count(screen: BattleScreen, kind: String) -> int:
	var count := 0
	for child in screen.get_children():
		if child is BattleEffect and child.kind == kind:
			count += 1
	return count

func _card(screen: BattleScreen, card_id: String) -> Dictionary:
	for card in screen.combat.state["players"]["p1"]["hand"]:
		if str(card["card_id"]) == card_id:
			return card
	return {}

func _run() -> void:
	_authority()
	var playtest := (load("res://scenes/card_playtest.tscn") as PackedScene).instantiate() as CardPlaytest
	root.add_child(playtest)
	await _frames()
	_check(playtest.quality_picker.item_count == 6, "playtest exposes random and five quality choices")
	playtest.quality_picker.select(5)
	playtest.quality_picker.item_selected.emit(5)
	await _frames()
	var inventory := playtest.expedition.run_inventory()
	var entries: Array = DeckBuilder.build(inventory)["entries"]
	for entry in entries:
		var item := inventory.find_instance(int(entry["source_instance_id"]))
		_check(entry["source_def_id"] == item["def_id"] and int(entry["source_quality"]) == ItemDefs.quality_of(item), "deck snapshots exact equipment source and quality")
	await _shot("01_red_card_sources")
	var combat := playtest.battle.combat
	for enemy in combat.state["enemies"]:
		enemy["alive"] = false
		enemy["hp"] = 0
	combat._events_check_outcome([])
	playtest.battle._on_close()
	await _frames()
	playtest.expedition.search_clock = func() -> int: return now
	playtest.loot._open_corpse("e1")
	await _frames()
	var loot := playtest.loot
	_check(loot.source_grids.size() == 4, "weapon, armor, pouch, pack all exist on same page")
	for grid in loot.source_grids.values():
		_check(grid.is_visible_in_tree() and loot.list_column.get_parent().get_global_rect().encloses(grid.get_global_rect()), "each package fully visible without tab or scroll")
	var stable_grid: CorpseSearchGrid = loot.source_grids["weapon"]
	_check(stable_grid.region["items"].is_empty() and not stable_grid.region["unknown"][0].has("quality"), "unknown grid has no tier or identity")
	await _shot("02_all_packages_searching")
	loot._search_region("pouch")
	_check(playtest.expedition.run["loot_searches"]["p1"]["region"] == "pouch", "individual package button prioritizes that package")
	_check(loot.source_grids["weapon"] == stable_grid and loot.source_grids.size() == 4, "snapshots retain all grid controls")
	loot._search_region("pouch")
	_check(playtest.expedition.run["loot_searches"].is_empty(), "same button pauses search")
	for region in ["weapon", "armor", "pouch", "pack"]:
		loot._search_region(region)
		for i in range(30):
			var session: Dictionary = playtest.expedition.run.get("loot_searches", {}).get("p1", {})
			if session.is_empty():
				break
			now += int(session["duration"]) + 1
			_check(playtest._loot_action("search_step", {})["ok"], "complete region through authority")
	var weapon: Dictionary = loot.source_grids["weapon"].region["items"][0]
	_check(ItemDefs.quality_of(weapon) == 5, "chosen red tier persists after reveal")
	var id := int(weapon["instance_id"])
	_check(playtest._loot_action("claim_corpse", {"instance_id": id, "container": "pack"})["ok"], "take exact revealed instance")
	_check(ItemDefs.quality_of(playtest.expedition.run_inventory().find_instance(id)) == 5, "red tier survives original instance transfer")
	loot.select_item("carried:%d" % id)
	_check(loot.drag_payload("carried:%d" % id)["quality"] == 5, "drag preview uses instance tier")
	await _shot("03_revealed_and_packed")
	root.size = Vector2i(1024, 640)
	await _frames()
	for grid in loot.source_grids.values():
		_check(loot.list_column.get_parent().get_global_rect().encloses(grid.get_global_rect()), "all packages also fit small window")
	await _shot("04_small_window_packages")
	root.size = Vector2i(1280, 800)
	playtest.loot.visible = false
	var deck := entries.duplicate(true)
	var order := [{"card_id": "shield_up"}, {"card_id": "slash"}, {"card_id": "cover"}, {"card_id": "drink_potion"}, {"card_id": "brace"}, {"card_id": "heavy_strike"}, {"card_id": "slash"}, {"card_id": "shield_up"}]
	var battle := CombatGame.create([{"key": "p1", "name": "农夫", "max_hp": 40, "hp": 25, "deck": deck}], "skeleton_patrol", 56, inventory, order)
	battle.start()
	var screen := playtest.battle
	screen.open_run(battle)
	await _frames()
	var shield := _card(screen, "shield_up")
	var uid := int(shield["uid"])
	var chip := screen.hand_row.find_child("CardSource", true, false) as Label
	_check(chip != null and chip.text.contains("木盾") and chip.get_theme_color("font_color").is_equal_approx(ItemDefs.quality_color(5)), "card face labels actual red shield source")
	await _click(screen.hand_row.find_child("Card_%d" % uid, true, false) as Control)
	_check(int(battle.state["players"]["p1"]["block"]) == 6 and screen.selected_uid == -1 and screen._hand_card(uid).is_empty(), "one actual card click immediately stacks armor")
	_check(_effect_count(screen, "block") == 1 and _effect_count(screen, "card_played") == 1, "committed self card generates shield and card effects")
	await create_timer(0.18).timeout
	await _shot("05_shield_effect")
	screen._clear_feedback()
	var attack := _card(screen, "slash")
	var before := int(battle.state["enemies"][0]["hp"])
	screen._on_card_clicked(int(attack["uid"]))
	_check(screen.selected_uid == int(attack["uid"]) and int(battle.state["enemies"][0]["hp"]) == before, "attack still waits for chosen enemy")
	await _frames()
	_check(_effect_count(screen, "damage") == 0, "selecting card has no speculative damage effect")
	screen._on_target_clicked("e1")
	await _frames()
	_check(int(battle.state["enemies"][0]["hp"]) == before - 6 and _effect_count(screen, "damage") == 1, "confirmed attack generates real hit effect")
	await create_timer(0.16).timeout
	await _shot("06_hit_effect")
	screen._clear_feedback()
	var potion := _card(screen, "drink_potion")
	screen._on_card_clicked(int(potion["uid"]))
	await _frames()
	_check(int(battle.state["players"]["p1"]["hp"]) == 33 and _effect_count(screen, "heal") == 1, "one click potion consumes source and displays healing")
	await _shot("07_healing_effect")
	await create_timer(0.85).timeout
	_check(_effect_count(screen, "heal") == 0, "effects clean themselves up")
	var cover := _card(screen, "cover")
	screen._on_card_clicked(int(cover["uid"]))
	_check(int(battle.state["players"]["p1"]["block"]) == 12, "single legal ally auto-targets self in solo")
	var coop := CombatGame.create([{"key": "p1", "name": "你", "deck": deck}, {"key": "p2", "name": "队友", "deck": deck}], "skeleton_patrol", 56, null, order)
	coop.start()
	screen.open_run(coop)
	var ally_cover := _card(screen, "cover")
	screen._on_card_clicked(int(ally_cover["uid"]))
	_check(screen.selected_uid == int(ally_cover["uid"]) and int(coop.state["players"]["p1"]["block"]) == 0, "coop cover retains explicit self or ally choice")
	screen._on_target_clicked("p2")
	_check(int(coop.state["players"]["p2"]["block"]) == 6 and int(coop.state["players"]["p1"]["block"]) == 0, "coop cover honors selected teammate")
	await _frames()
	var basic_deck := CombatGame.basic_kit_demo_deck()
	var draw_order := [{"card_id": "observe"}, {"card_id": "shield_up"}, {"card_id": "slash"}, {"card_id": "brace"}, {"card_id": "deep_breath"}, {"card_id": "shield_up"}, {"card_id": "slash"}, {"card_id": "cover"}]
	var draw_battle := CombatGame.create([{"key": "p1", "name": "你", "deck": basic_deck}], "skeleton_patrol", 56, null, draw_order)
	draw_battle.start()
	screen.open_run(draw_battle)
	screen._on_card_clicked(int(_card(screen, "observe")["uid"]))
	await _frames()
	_check(_effect_count(screen, "draw") == 1 and draw_battle.state["players"]["p1"]["hand"].size() == 6, "real draw effect displays after one click")
	await create_timer(0.15).timeout
	await _shot("08_draw_effect")
	screen._clear_feedback()
	draw_battle.state["players"]["p1"]["energy"] = 0
	screen._on_card_clicked(int(_card(screen, "shield_up")["uid"]))
	await _frames()
	_check(_effect_count(screen, "block") == 0 and int(draw_battle.state["players"]["p1"]["block"]) == 0, "unaffordable card produces neither armor nor effect")
	draw_battle.state["players"]["p1"]["energy"] = 3
	var calls := [0]
	screen.action_sink = func(_kind: String, _args: Dictionary) -> String:
		calls[0] += 1
		return "pending-self-card"
	var pending_uid := int(_card(screen, "shield_up")["uid"])
	screen._on_card_clicked(pending_uid)
	screen._on_card_clicked(pending_uid)
	await _frames()
	_check(calls[0] == 1 and screen.pending_action and _effect_count(screen, "block") == 0, "async self click sends once and waits for authority before effects")
	screen.action_sink = Callable()
	screen.pending_action = false
	var old_motion := SettingsStore.get_reduce_motion()
	# 测试静态特效路径，不改用户设置文件。
	var effect := BattleEffect.new()
	effect.kind = "block"
	effect.reduce_motion = true
	effect.center = Vector2(600, 200)
	screen.add_child(effect)
	await _frames()
	_check(effect.mouse_filter == Control.MOUSE_FILTER_IGNORE and SettingsStore.get_reduce_motion() == old_motion, "effects ignore input and respect motion preference without editing it")
	playtest.queue_free()
	await _frames()
	print("D56_LOOT_QUALITY_FEEDBACK_%s checks=%d" % ["FAIL" if failed else "PASS", checks])
	quit(1 if failed else 0)
