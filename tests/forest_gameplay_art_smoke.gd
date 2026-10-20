extends SceneTree
## 实际首页输入→五区/23外观/43物件→真实出牌获胜→搜索装包→返回；可带窗口留截图。

const OUT := "res://screenshots/forest_gameplay_2026-10-21"
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("FOREST_GAMEPLAY_ART_FAIL: " + message)

func _frames(count := 4) -> void:
	for i in range(count):
		await process_frame

func _click(control: Control) -> void:
	if control == null:
		_check(false, "点击目标存在")
		return
	await _frames()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = control.get_global_rect().get_center()
		root.push_input(event, true)
		await process_frame
	await _frames()

func _shot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_check(root.get_texture().get_image().save_png(OUT.path_join(filename + ".png")) == OK, "保存截图 " + filename)

func _fingerprints() -> Dictionary:
	var files := {}
	for path in ["user://farm_save_v1.json", "user://farm_save_v1.json.bak"]:
		files[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	var directory := DirAccess.open(ExpeditionStore.EXPEDITION_DIR)
	if directory != null:
		for filename in directory.get_files():
			var path := ExpeditionStore.EXPEDITION_DIR.path_join(filename)
			files[path] = FileAccess.get_sha256(path)
	return files

func _fight(screen: BattleScreen) -> void:
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
			var target := "p1"
			if str(CardDefs.get_card(str(card["card_id"]))["target"]) == "enemy":
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
	var before := _fingerprints()
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu
	await _frames()
	if not FarmTestMode.enabled:
		await _click(menu.find_child("TestModeButton", true, false))
	await _click(menu.find_child("ForestPreviewButton", true, false))
	await _click(current_scene.find_child("ForestPlaytestButton", true, false))
	var game := current_scene as ForestPlaytest
	_check(game != null, "首页经森林图鉴进入试玩")
	if game == null:
		quit(1)
		return
	_check(game.exploration.visible and not game.battle.visible, "林间展示与战斗互斥")
	for area_index in range(ChapterOneDefs.AREA_ORDER.size()):
		# 触发 OptionButton 的选择信号，复用真实用户选择入口。
		game.area_picker.item_selected.emit(area_index)
		await _frames()
		var area := str(ChapterOneDefs.AREA_ORDER[area_index])
		_check(game.area_id == area, "区域选择 " + area)
		var backdrop := game.exploration.find_child("CaveBackdrop", true, false) as ExpeditionArt
		_check(backdrop._resolve_texture() != null and backdrop.layer_id == "forest_ch1." + area, "真实背景 " + area)
		_check(game.prop_row.get_child_count() == ChapterOneDefs.templates_for_area(area).size(), "物件齐全 " + area)
		for prop in game.prop_row.get_children():
			var art := prop.get_child(0).get_child(0) as ExpeditionArt
			_check(art._resolve_texture() != null, "物件纹理 " + art.subject)
		await _shot("explore_" + area)
		await _click(game.prop_row.get_child(0))
		_check(game.inspection.visible and game.inspection_art._resolve_texture() != null, "点击查看物件 " + area)
		game.inspection.hide()
		await _click(game.find_child("ForestBattleButton", true, false))
		_check(game.battle.visible and not game.exploration.visible, "开始实际战斗 " + area)
		_check(str(game.battle.combat.state["enemies"][0]["def_id"]) == "skeleton_scout", "外观不改战斗规则")
		_check(game.battle.enemy_art_overrides["e1"] == "enemy." + game.enemy_id, "区域敌人接入战斗")
		await _shot("battle_" + area)
		game._show_exploration()
	for i in range(ChapterOneDefs.ENEMIES.size()):
		game.enemy_picker.item_selected.emit(i)
		_check(game.actor_art._resolve_texture() != null, "23 外观切换 " + game.enemy_id)
	# 真正通过现有出牌流程击败敌人，不伪造胜利状态。
	game.select_area(0)
	await _click(game.find_child("ForestBattleButton", true, false))
	await _fight(game.battle)
	_check(str(game.battle.combat.state["outcome"]) == "won", "真实出牌获胜")
	if str(game.battle.combat.state["outcome"]) != "won":
		quit(1)
		return
	await _click(game.battle.overlay_column.get_child(game.battle.overlay_column.get_child_count() - 1))
	_check(game.loot.visible and not game.battle.visible, "获胜进入实际搜刮")
	var corpse := game.loot.battlefield.find_child("Corpse_e1", true, false) as Control
	var corpse_art := corpse.get_child(0).get_child(0).get_child(0) as ExpeditionArt
	_check(corpse_art.subject == "enemy.forest_alpha_wolf" and corpse_art.fallen and corpse_art._resolve_texture() != null, "遗骸延续敌人外观")
	_check((game.loot.battlefield.get_child(0) as ExpeditionArt).layer_id == "forest_ch1.trail", "战后延续场景")
	await _shot("corpse_loot")
	await _click(corpse)
	await create_timer(float(game.expedition.visible_run().get("loot_searches", {}).get("p1", {}).get("remaining", 0)) / 1000.0 + 0.3).timeout
	_check(not game.loot.scene_mode and not game.loot.entries.is_empty(), "点击遗骸自动搜索并发现物品")
	var item: Dictionary = game.expedition.run["resolved"]["r3c1"]["corpses"][0]["regions"][0]["items"][0]
	var instance_id := int(item["instance_id"])
	_check(ExpeditionLootPanel.item_art(str(item["def_id"])) == "item.copper_shortsword", "实际掉落使用新铜剑插图")
	_check(game._loot_action("claim_corpse", {"instance_id": instance_id, "container": "pack"})["ok"], "已发现物品可实际装包")
	_check(game.expedition.run_inventory().find_instance(instance_id)["container"] == "pack", "装包改变真实临时背包")
	await _shot("search_and_pack")
	game._loot_action("search_cancel", {})
	game.loot._confirm_leave()
	await _click(game.loot.modal_content.get_child(2))
	_check(game.exploration.visible and not game.loot.visible, "确认离开回到林间")
	await _click(game.find_child("ForestBattleButton", true, false))
	_check(not game.expedition.run_inventory().find_instance(instance_id).is_empty(), "装包装备带入下一场")
	var item_cards := 0
	for turn in range(4):
		for card in game.battle.hand_row.get_children():
			var art := card.get_child(0).get_child(0).get_child(1) as ExpeditionArt
			if art != null and art.subject == "item.copper_shortsword":
				item_cards += 1
		if item_cards > 0:
			break
		game.battle._on_end_turn()
		await _frames()
	_check(item_cards > 0, "实战来源卡牌使用铜剑插图")
	root.size = Vector2i(1024, 640)
	root.content_scale_size = root.size
	await _frames()
	_check(root.get_visible_rect().encloses(game.battle.end_button.get_global_rect()), "小窗口战斗按钮无遮挡")
	await _shot("small_battle")
	game._show_exploration()
	await _frames()
	_check(root.get_visible_rect().encloses((game.find_child("ForestBattleButton", true, false) as Control).get_global_rect()), "小窗口开始按钮可达")
	_check(root.get_visible_rect().encloses(game.area_picker.get_global_rect()), "小窗口区域选择可达")
	await _shot("small_explore")
	await _click(game.find_child("ForestHomeButton", true, false))
	_check(current_scene is MainMenu, "返回首页")
	_check(_fingerprints() == before, "农场和正式探险存档字节不变")
	current_scene.queue_free()
	await _frames()
	print("FOREST_GAMEPLAY_ART_%s: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
