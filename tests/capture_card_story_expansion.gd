extends "res://tests/capture_card_story_study.gd"

const EXPANSION_OUT := "res://screenshots/card_story_v06/"

func _load_cards(manifest_path: String) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	for story in manifest.cards:
		var definition: Dictionary = ForestStoryExpansionCombat.ADDITIONS.get(story.id, ForestCardStudyCombat.CARDS.get(story.id, {}))
		_check(not definition.is_empty(), "definition " + story.id)
		story["definition"] = definition
		story.name = definition.name
		story.cost = definition.cost
		cards.append(story)
		var texture := ChapterArtRegistry.texture(ChapterArtRegistry.card(story.id))
		_check(texture != null and texture.get_size() == Vector2(640, 400), "runtime texture " + story.id)
		textures.append(texture)

func _kind(card: Dictionary) -> String:
	for effect in card.definition.effects:
		if effect.kind == "damage": return "攻击"
		if effect.kind == "heal": return "恢复"
		if effect.kind == "block": return "防御"
		if effect.kind == "cleanse": return "净化"
	return "中毒"

func _wrapped(parent: Control, value: String, at: Vector2, extent: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = value
	label.position = at
	label.size = extent
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _study_card(index: int, at: Vector2, compact := false) -> void:
	var card: Dictionary = cards[index]
	var kind := _kind(card)
	var accent: Color = {"恢复": Color("#73966e"), "防御": Color("#5c8991"), "净化": Color("#b39459"), "中毒": Color("#97769d")}.get(kind, Color("#af7557"))
	var width := 410 if compact else 324
	var height := 370 if compact else 440
	var panel := _panel(board, at, Vector2(width, height), Color("#fcf7ed"), accent)
	_label(panel, card.name, Vector2(16, 12), Vector2(width - 70, 34), 22)
	_panel(panel, Vector2(width - 48, 12), Vector2(34, 34), accent, accent, 17)
	var cost := _label(panel, str(card.cost), Vector2(width - 48, 12), Vector2(34, 34), 22, Color("#fff6df"))
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var image_width := width - 24
	_image(panel, index, Vector2(12, 56), Vector2(image_width, image_width * 0.625))
	var text_y := 66 + image_width * 0.625
	_wrapped(panel, CardPresentation.effect_text(card.definition), Vector2(16, text_y), Vector2(width - 32, 62), 19 if compact else 20, accent)
	if compact:
		return
	_label(panel, kind + (" · 本场移除" if card.definition.after == "exhaust" else ""), Vector2(16, 334), Vector2(width - 32, 28), 14, accent)
	_wrapped(panel, card.hook, Vector2(16, 371), Vector2(width - 32, 58), 15, muted)

func _save(name: String) -> void:
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(EXPANSION_OUT + name + ".png") == OK, "save " + name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EXPANSION_OUT))
	_load_cards("res://assets/art_studies/card_story_v06/manifest.json")
	_check(cards.size() == 10, "ten new cards")
	_new_board(Vector2i(1780, 1050), "森林小冒险 · 新增十张情境卡", "净化 / 穿透 / 治疗 / 蜂蜜 / 火冰 / 毒针 / 投网 / 孢子 · 当前试玩规则")
	for i in range(10): _study_card(i, Vector2(40 + (i % 5) * 344, 136 + (i / 5) * 458))
	await _save("01_ten_new_cards")
	_new_board(Vector2i(1780, 840), "十张新卡 · 缩图与灰度", "各格：128×80 彩色 / 128×80 灰度 / 64×40 彩色 · 按真实像素呈现")
	for i in range(10):
		var x := 24 + (i % 5) * 350
		var y := 150 + (i / 5) * 320
		_label(board, cards[i].name, Vector2(x, y), Vector2(325, 32), 22)
		_image(board, i, Vector2(x, y + 50), Vector2(128, 80))
		_image(board, i, Vector2(x + 140, y + 50), Vector2(128, 80), true)
		_image(board, i, Vector2(x + 270, y + 70), Vector2(64, 40))
		_wrapped(board, cards[i].hook, Vector2(x, y + 150), Vector2(325, 84), 16, muted)
	await _save("02_thumbnail_and_grayscale")
	# 总览先放六张旧卡，再放十张新卡。
	cards.clear()
	textures.clear()
	_load_cards("res://assets/art_studies/card_story_v05/manifest.json")
	_load_cards("res://assets/art_studies/card_story_v06/manifest.json")
	_check(cards.size() == 16, "sixteen total")
	_new_board(Vector2i(1800, 1690), "草帽小姑娘 · 十六张情境卡", "每张一件不同的小事 · 插图、名称、费用与当前试玩定义一致")
	for i in range(16): _study_card(i, Vector2(44 + (i % 4) * 434, 136 + (i / 4) * 384), true)
	await _save("03_all_sixteen_cards")
	print("CARD_STORY_EXPANSION_PREVIEW: %d checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
