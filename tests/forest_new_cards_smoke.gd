extends SceneTree
## 独立样稿的六张新卡：真实点击、数值、纹理、牌堆、动画及小窗口。

const OUT := "res://screenshots/card_story_v05/gameplay"
var checks := 0
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("FOREST_NEW_CARDS_FAIL: " + message)

func _frames(count := 5) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(OUT.path_join(name + ".png")) == OK, "保存截图 " + name)

func _check_layout(screen: BattleScreen, width: float) -> void:
	for button in screen.hand_row.get_children():
		if not button is BattleScreen.CardButton:
			continue
		_check(button.get_global_rect().end.x <= width, "卡牌没有越过窗口右侧")
		_check(button.size.x <= 149, "长牌名没有撑宽卡牌")
		var title := button.find_child("CardTitle", true, false) as Label
		_check(title != null and title.get_line_count() <= 2, "牌名至多两行")
		if title != null:
			_check(button.get_global_rect().encloses(title.get_global_rect()), "牌名位于卡内")
		var kind := button.find_child("CardKind", true, false) as Label
		_check(kind != null and kind.text in ["攻击", "防御"], "攻防文字标签明确")
		var effect := button.find_child("CardEffect", true, false) as Label
		_check(effect != null and button.get_global_rect().encloses(effect.get_global_rect()), "全部效果文字位于卡内")

func _fingerprints() -> Dictionary:
	var result := {}
	for path in [SaveStore.SAVE_PATH, SaveStore.SAVE_PATH + ".bak"]:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	return result

func _run() -> void:
	var before := _fingerprints()
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var game := (load("res://scenes/forest_animation_playtest.tscn") as PackedScene).instantiate() as ForestPlaytest
	root.add_child(game)
	await _frames()
	var screen := game.battle
	_check(screen.combat is ForestCardStudyCombat, "入口自动使用新卡样稿")
	_check(screen.combat.state["players"]["p1"]["hand"].size() == 5, "首手五张")
	for card_id in ForestCardStudyCombat.CARDS:
		var record := ChapterArtRegistry.card(card_id)
		_check(record.get("texture_path", "") == "res://assets/chapter_one/cards/" + card_id + ".png", "共享登记表使用情境卡图 " + card_id)
		_check(record.name == screen._card_definition(card_id).name, "图鉴与实战牌名一致 " + card_id)
		_check(Vector2i(ChapterArtRegistry.texture(record).get_size()) == Vector2i(640, 400), "游戏纹理尺寸 " + card_id)
	_check(screen._unit_art("p1")._resolve_texture() == load("res://assets/characters/farmer_cute.svg"), "主角仍为草帽双辫形象")
	for button in screen.hand_row.get_children():
		var arts := button.find_children("*", "Control", true, false)
		var found := false
		for art in arts:
			if art is ExpeditionArt:
				var id := art.subject.trim_prefix("card.") as String
				found = art.subject.begins_with("card.forest_") and art._resolve_texture() == load("res://assets/chapter_one/cards/" + id + ".png")
		_check(found, "首手卡牌都使用森林新插图")
	_check_layout(screen, 1280)
	await _shot("01_first_hand")
	screen._on_end_turn()
	await _frames()
	_check_layout(screen, 1280)
	await _shot("02_second_hand")
	screen._open_pile("discard_pile", "弃牌")
	await _shot("03_card_rules")
	screen._close_inspector()
	for card_id in ForestCardStudyCombat.CARDS:
		game._begin_battle()
		await _frames()
		if card_id == "forest_bell_strike":
			screen._on_end_turn()
			await _frames()
		var uid := -1
		for card in screen.combat.state["players"]["p1"]["hand"]:
			if str(card["card_id"]) == card_id:
				uid = int(card["uid"])
		_check(uid > 0, "通过真实抽牌找到 " + card_id)
		if uid < 0:
			continue
		var definition := screen._card_definition(card_id)
		var target := "e1" if definition["target"] == "enemy" else "p1"
		var snapshot := screen.combat.state.duplicate(true)
		_check(bool(screen.combat.preview_play("p1", uid, target).get("ok", false)), "目标预览合法 " + card_id)
		_check(screen.combat.state == snapshot, "预览没有修改状态 " + card_id)
		screen._on_card_clicked(uid)
		if target == "e1":
			screen._on_target_clicked(target)
		var effect: Dictionary = definition["effects"][0]
		if target == "e1":
			_check(int(screen.combat.state["enemies"][0]["hp"]) == int(snapshot["enemies"][0]["hp"]) - int(effect["value"]), "真实扣血 " + card_id)
		else:
			_check(int(screen.combat.state["players"]["p1"]["block"]) == int(effect["value"]), "真实格挡 " + card_id)
		if card_id == "forest_bell_strike":
			_check(int(screen.combat.state["players"]["p1"]["block"]) == int(snapshot["players"]["p1"]["block"]) + 3, "敲壳混合牌同时给自己 3 格挡")
		_check(int(screen.combat.state["players"]["p1"]["energy"]) == int(snapshot["players"]["p1"]["energy"]) - int(definition["cost"]), "费用匹配 " + card_id)
		_check(screen._hand_card(uid).is_empty(), "已使用牌离开手牌 " + card_id)
		await _frames()
		if card_id == "forest_guard_bell":
			await _shot("06_guard_block")
		elif card_id == "forest_smoke_screen":
			await _shot("07_smoke_block")
		elif card_id == "forest_bell_strike":
			await _shot("08_bell_strike")
		if str(definition.get("motion", "")) == "projectile" and not SettingsStore.get_reduce_motion():
			var ranged := false
			for child in screen.get_children():
				if child is BattleCutoutMotion:
					ranged = child.ranged
			_check(ranged, "射击牌触发箭矢 " + card_id)
			if card_id == "forest_shoot":
				await _shot("05_shooting")
	game._begin_battle()
	root.size = Vector2i(1024, 640)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	await _frames(8)
	_check_layout(screen, 1024)
	for button in screen.hand_row.get_children():
		_check(button.get_global_rect().end.x <= root.size.x, "小窗口卡牌可见")
	await _shot("04_small_window")
	screen._on_end_turn()
	await _frames(8)
	_check_layout(screen, 1024)
	await _shot("09_small_window_mixed_card")
	var legacy_cards := ["slash", "heavy_strike", "shield_up", "cover", "brace", "deep_breath", "observe", "expose", "venom_stab", "drink_potion", "heavy_cargo", "first_aid", "drink_soup", "drink_elixir", "slash7", "heavy_strike15", "slash8", "heavy_strike17", "rescue_signal"]
	_check(legacy_cards.all(func(id): return CardDefs.CARDS.has(id)), "森林样稿仍保留全部 19 张旧正式牌的兼容 ID")
	_check(not ChapterOneDefs.DEPARTURE_ENABLED, "森林正式出发开关维持原状态")
	_check(_fingerprints() == before, "样稿没有写入农场存档")
	# 等待第二手敌方反馈结束，避免退出时仍有动画协程持有对象。
	await create_timer(1.0).timeout
	game.queue_free()
	await _frames()
	print("FOREST_NEW_CARDS: %d checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
