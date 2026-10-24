extends SceneTree

const OUT := "res://screenshots/card_story_v06/gameplay/"
var checks := 0
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("STORY_EXPANSION_UI_FAIL: " + note)

func _frames(count := 8) -> void:
	for i in range(count): await process_frame

func _shot(name: String) -> void:
	await _frames()
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(OUT + name + ".png") == OK, "save " + name)

func _layout(screen: BattleScreen) -> void:
	for button in screen.hand_row.get_children():
		_check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(button.get_global_rect()), "card within window")
		for name in ["CardTitle", "CardEffect", "CardKind"]:
			var label := button.find_child(name, true, false) as Label
			_check(label != null and button.get_global_rect().encloses(label.get_global_rect()), "label in card " + name)
		for art in button.find_children("*", "Control", true, false):
			if art is ExpeditionArt:
				_check(art._resolve_texture() != null, "runtime illustration resolves")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var save_hash := FileAccess.get_sha256(SaveStore.SAVE_PATH) if FileAccess.file_exists(SaveStore.SAVE_PATH) else "missing"
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	var preview = (load("res://scenes/chapter_preview.tscn") as PackedScene).instantiate()
	root.add_child(preview)
	current_scene = preview
	await _frames()
	var entry := preview.find_child("ForestExpansionPlaytestButton", true, false) as Button
	_check(entry != null and entry.is_visible_in_tree(), "new cards entry visible in forest catalog")
	entry.pressed.emit()
	await _frames()
	var game = current_scene
	_check(game.get_script().resource_path == "res://scripts/ui/forest_story_expansion_playtest.gd", "catalog entry opens actual expansion scene")
	await _frames()
	for group in range(2):
		game.group_index = group
		game._begin_battle()
		await _frames()
		var screen: BattleScreen = game.battle
		_check(screen.combat is ForestStoryExpansionCombat, "expansion session active")
		for id in ForestStoryExpansionCombat.GROUPS[group]:
			_check(screen.combat.state.players.p1.hand.any(func(c): return c.card_id == id), "new card naturally drawn " + id)
			_check(ChapterArtRegistry.card(id).name == screen.combat.card_definition(id).name, "catalog and gameplay names " + id)
		_layout(screen)
		await _shot("%02d_group_%d_large" % [group * 2 + 1, group])
		root.size = Vector2i(1024, 640)
		root.content_scale_size = root.size
		DisplayServer.window_set_size(root.size)
		await _frames()
		_layout(screen)
		await _shot("%02d_group_%d_small" % [group * 2 + 2, group])
		root.size = Vector2i(1280, 800)
		root.content_scale_size = root.size
		DisplayServer.window_set_size(root.size)
		# 通过真实 UI 选择和目标输入结算一张代表牌。
		var id: String = "forest_scatter_stings" if group == 0 else "forest_rest_bell"
		for card in screen.combat.state.players.p1.hand.duplicate():
			if card.card_id == id:
				screen._on_card_clicked(int(card.uid))
				if group == 0: screen._on_target_clicked("e1")
		await _frames(24)
		if group == 0:
			_check(screen.combat.state.enemies[0].statuses.has("poison"), "UI stinger applies poison")
		else:
			_check(screen.combat.state.players.p1.statuses.is_empty(), "UI bell removes actual negatives")
		await _shot("%02d_group_%d_effect" % [group + 5, group])
	game._open_settings()
	await _frames()
	var switcher := game.find_child("ExpansionGroupButton", true, false) as Button
	_check(switcher != null and switcher.is_visible_in_tree(), "group switch accessible in settings")
	switcher.pressed.emit()
	await _frames()
	_check(game.group_index == 0 and not game.pause_view.visible, "group switch starts other deck and closes settings")
	_check((FileAccess.get_sha256(SaveStore.SAVE_PATH) if FileAccess.file_exists(SaveStore.SAVE_PATH) else "missing") == save_hash, "no farm save writes")
	await create_timer(1.0).timeout
	game.queue_free()
	await _frames()
	print("STORY_EXPANSION_UI: %d checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
