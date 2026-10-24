extends SceneTree
## 直接重排真实 CardButton 做视觉对照；不绘制或修改插图像素。

func _initialize() -> void:
	_run.call_deferred()

func _frames(count := 8) -> void:
	for i in range(count): await process_frame

func _label(parent: Control, value: String, at: Vector2, font_size: int, color: Color) -> void:
	var label := ExpeditionUI.label(value, font_size, color)
	label.position = at
	parent.add_child(label)

func _run() -> void:
	var out := "res://screenshots/card_story_v06/framing/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	root.size = Vector2i(1540, 1180)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	var game = (load("res://scenes/forest_story_expansion_playtest.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _frames()
	var board := Control.new()
	board.theme = ExpeditionUI.make_theme()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(board)
	var paper := ColorRect.new()
	paper.color = Color("#eae1d1")
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.add_child(paper)
	_label(board, "同一手真实卡牌 · 放进卡框前后", Vector2(44, 28), 34, Color("#4f6253"))
	_label(board, "插图、规则、费用不变；比较边界、留白、图窗对齐与小字层级", Vector2(46, 78), 18, Color("#7b8274"))
	for variant in range(2):
		game.battle.framed_cards = variant == 1
		game._begin_battle()
		await _frames()
		var y := 158 if variant == 0 else 706
		_label(board, "A · 直接贴图" if variant == 0 else "B · 米纸卡底 + 细描边 + 衬纸图框", Vector2(46, y - 46), 24, Color("#4f6253"))
		var index := 0
		for card in game.battle.hand_row.get_children():
			game.battle.hand_row.remove_child(card)
			board.add_child(card)
			card.position = Vector2(46 + index * 295, y)
			card.scale = Vector2.ONE * 1.75
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			index += 1
	game.hide()
	await _frames()
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(out + "01_before_after.png")
	print("CARD_FRAME_COMPARISON: %s" % ("PASS" if result == OK else "FAIL"))
	board.queue_free()
	game.queue_free()
	await _frames()
	quit(0 if result == OK else 1)
