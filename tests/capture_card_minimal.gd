extends SceneTree
## Visual QA using temporary in-memory inventory. Does not read or save a farm.

const OUTPUT := "res://screenshots/card_berry_theme_2026-10-12"
var playtest: CardPlaytest
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _settle() -> void:
	for i in range(6):
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func _shot(caption: String) -> void:
	await _settle()
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(OUTPUT + "/" + caption + ".png")
	print("CARD_MINIMAL_SCREEN ", caption)

func _battle_fits() -> void:
	for control in [playtest.battle.end_button, playtest.battle.find_child("BattleSettingsButton", true, false), playtest.battle.find_child("HandScroll", true, false)]:
		if not root.get_visible_rect().encloses(control.get_global_rect()):
			failed = true
			push_error("CARD_MINIMAL_OVERFLOW: " + control.name)
	var actor_y := -1.0
	var actor_height := -1.0
	for target in playtest.battle.target_controls.values():
		var rect: Rect2 = target.get_global_rect()
		if not playtest.battle.battlefield.get_global_rect().encloses(rect):
			failed = true
			push_error("CARD_BATTLEFIELD_OVERFLOW: " + target.name)
		if actor_y >= 0 and (absf(actor_y - rect.position.y) > 1 or absf(actor_height - rect.size.y) > 1):
			failed = true
			push_error("CARD_BATTLEFIELD_UNALIGNED: " + target.name)
		actor_y = rect.position.y
		actor_height = rect.size.y

func _settings_fit() -> void:
	for name in ["PlaytestResumeButton", "PlaytestHomeButton", "ReplayBattleButton", "PlaytestOptionsButton", "ResetPlaytestButton", "PlaytestEncounterPicker", "PlaytestQualityPicker"]:
		var control := playtest.find_child(name, true, false) as Control
		if control.is_visible_in_tree() and not root.get_visible_rect().encloses(control.get_global_rect()):
			failed = true
			push_error("CARD_SETTINGS_OVERFLOW: " + name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	playtest = (load("res://scenes/card_playtest.tscn") as PackedScene).instantiate()
	root.add_child(playtest)
	await _shot("01_battle")
	_battle_fits()
	playtest.battle._open_settings()
	await _shot("19_settings")
	_settings_fit()
	playtest.test_options.show()
	await _shot("20_settings_options")
	_settings_fit()
	playtest._close_settings()
	var selected := -1
	for card in playtest.battle.combat.state["players"]["p1"]["hand"]:
		if CardDefs.is_attack_card(str(card["card_id"])):
			selected = int(card["uid"])
			break
	if selected >= 0:
		playtest.battle._on_card_clicked(selected)
		await _shot("02_target")
		_battle_fits()
	playtest.battle._open_help()
	await _shot("03_help")
	playtest.battle._close_inspector()
	playtest._select_encounter(1)
	await _shot("04_multi_enemy")
	_battle_fits()
	root.size = Vector2i(1024, 640)
	root.content_scale_size = root.size
	await _shot("05_small_window")
	_battle_fits()
	playtest._open_settings()
	playtest.test_options.show()
	await _shot("21_small_settings")
	_settings_fit()
	playtest._close_settings()
	var player: Dictionary = playtest.battle.combat.state["players"]["p1"]
	player["hand"].clear()
	var uid := 9000
	for card_id in ["expose", "venom_stab", "deep_breath", "drink_potion", "rescue_signal", "heavy_cargo", "heavy_strike"]:
		uid += 1
		player["hand"].append({"uid": uid, "card_id": card_id, "source_instance_id": 0, "source_def_id": "", "source_quality": 1, "owner": "p1"})
	playtest.battle.selected_uid = -1
	playtest.battle._refresh()
	await _shot("06_special_cards")
	_battle_fits()
	var prior_combat := playtest.battle.combat
	var kit := CombatGame.basic_kit_demo_deck()
	var coop := CombatGame.create([
		{"key": "p1", "name": "农夫", "max_hp": 40, "hp": 30, "deck": kit},
		{"key": "p2", "name": "队友", "max_hp": 40, "hp": 28, "deck": kit},
	], "normal", 1012)
	coop.start()
	coop.state["players"]["p1"]["block"] = 6
	coop.state["players"]["p1"]["statuses"] = {"poison": {"stacks": 3}}
	playtest.battle.open_run(coop)
	await _shot("14_small_coop")
	_battle_fits()
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	await _shot("15_large_coop")
	_battle_fits()
	coop.state["players"]["p2"]["hp"] = 0
	coop.state["players"]["p2"]["downed"] = true
	coop.state["players"]["p1"]["hand"].append({"uid": 9100, "card_id": "rescue_signal", "source_instance_id": 0, "source_def_id": "", "source_quality": 1, "owner": "p1"})
	playtest.battle._refresh()
	playtest.battle._on_card_clicked(9100)
	await _shot("16_rescue_target")
	_battle_fits()
	var crowded := CombatGame.create([
		{"key": "p1", "name": "农夫", "max_hp": 40, "hp": 30, "deck": kit},
		{"key": "p2", "name": "队友", "max_hp": 40, "hp": 28, "deck": kit},
	], "gate_keeper", 1012)
	crowded.start()
	playtest.battle.open_run(crowded)
	await _shot("17_five_actors")
	_battle_fits()
	root.size = Vector2i(1024, 640)
	root.content_scale_size = root.size
	await _shot("18_small_five_actors")
	_battle_fits()
	playtest.battle.open_run(prior_combat)
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	playtest.battle.combat.state["outcome"] = "won"
	playtest.battle._refresh()
	await _shot("07_victory")
	playtest.battle._on_close()
	await _shot("08_loot_stage")
	playtest._open_settings()
	await _shot("22_loot_settings")
	_settings_fit()
	playtest._close_settings()
	playtest.loot._open_corpse("e1")
	await _shot("09_loot_workspace")
	playtest._stop_search()
	playtest.hide()
	var prep := LoadoutPanel.new()
	root.add_child(prep)
	prep.open(playtest.farm)
	await _shot("10_loadout")
	prep.hide()
	var hub := ExpeditionHubPanel.new()
	root.add_child(hub)
	hub.open(playtest.farm)
	await _shot("11_camp")
	hub.hide()
	var expedition := ExpeditionGame.new()
	expedition.bind(playtest.farm)
	expedition.run = ExpeditionGame.compose_run(playtest.farm, {}, "visual-qa", 1000, false, "预览")
	var map := ExpeditionMapPanel.new()
	root.add_child(map)
	map.open(expedition)
	await _shot("12_route")
	map._select_route(1, 0)
	await _shot("13_route_preview")
	map.hide()
	var home := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	root.add_child(home)
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	await _shot("23_home")
	_home_fits(home)
	root.size = Vector2i(1024, 640)
	root.content_scale_size = root.size
	await _shot("24_small_home")
	_home_fits(home)
	home._on_settings()
	await _shot("25_small_home_settings")
	_home_fits(home)
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	await _shot("26_home_settings")
	_home_fits(home)
	print("CARD_MINIMAL_", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func _home_fits(home: MainMenu) -> void:
	for control in home.find_children("*", "Button", true, false):
		if not control.is_visible_in_tree():
			continue
		# The settings content intentionally scrolls inside its paper panel.
		if home.settings_panel.is_ancestor_of(control):
			continue
		if not root.get_visible_rect().encloses(control.get_global_rect()):
			failed = true
			push_error("CARD_HOME_OVERFLOW: " + control.name)
