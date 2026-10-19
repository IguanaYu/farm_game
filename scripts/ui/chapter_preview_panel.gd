extends Control
## 森林第一章开发预览（P0）：五区名称、占位背景与代表搜索物一览。
## 只读展示 ChapterOneDefs 登记 + ChapterArtRegistry 占位解析，不触任何玩法状态；
## 森林出发开关打开前，这是五区占位的唯一可见入口（开发计划 §5-P0、§2 开发入口约定）。

const MENU_SCENE := "res://scenes/main_menu.tscn"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = ExpeditionUI.INK
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.name = "Backdrop"
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	stack.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	header.add_child(titles)
	var title := ExpeditionUI.label("苔冠森林 · 内容预览（占位）", 24, ExpeditionUI.SAGE)
	title.name = "ChapterTitle"
	titles.add_child(title)
	var note := ExpeditionUI.label(
		"内容集 %s · 版本 %d · 章节 %s —— 出发开关未打开，正式入口在两区样例（P5）交付后开放" %
		[ChapterOneDefs.CONTENT_SET, ChapterOneDefs.CONTENT_VERSION, ChapterOneDefs.CHAPTER_ID],
		13, ExpeditionUI.MUTED)
	note.name = "DepartureNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(note)
	var back := ExpeditionUI.button("返回主菜单")
	back.name = "BackButton"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	header.add_child(back)

	var scroll := ScrollContainer.new()
	scroll.name = "PreviewScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	var areas := VBoxContainer.new()
	areas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	areas.add_theme_constant_override("separation", 10)
	areas.name = "AreaList"
	scroll.add_child(areas)

	for area_id in ChapterOneDefs.AREA_ORDER:
		areas.add_child(_build_area_card(str(area_id)))


func _build_area_card(area_id: String) -> PanelContainer:
	var area := ChapterOneDefs.area(area_id)
	var base: Color = area["base"]
	var card := PanelContainer.new()
	card.name = "AreaView_%s" % area_id
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = base.darkened(0.25)
	card_style.border_color = base
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(12)
	card_style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", card_style)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	card.add_child(stack)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	stack.add_child(head)
	var templates := ChapterOneDefs.templates_for_area(area_id)
	var boss: Dictionary = ChapterOneDefs.ENEMIES.get(str(area["boss"]), {})
	head.add_child(ExpeditionUI.label("%s（%s）· %d 类搜索物" % [str(area["name"]), area_id, templates.size()], 17, Color("#f2ead9")))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(ExpeditionUI.label("区域强敌：%s" % str(boss.get("name", "未登记")), 14, area["accent"]))

	var chips := FlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	stack.add_child(chips)
	for template_id in templates:
		chips.add_child(_build_prop_chip(template_id))
	return card


func _build_prop_chip(template_id: String) -> PanelContainer:
	var spec := ChapterArtRegistry.prop(template_id)
	var record := ChapterOneDefs.template(template_id)
	var guarded := str(record.get("risk", "none")) == "guarded"
	var chip := PanelContainer.new()
	chip.name = "PropChip_%s" % template_id
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(spec["base"]).darkened(0.45)
	chip_style.border_color = Color(spec["accent"]) if guarded else Color(spec["base"])
	chip_style.set_border_width_all(3 if guarded else 1)
	chip_style.set_corner_radius_all(9)
	chip_style.set_content_margin_all(6)
	chip.add_theme_stylebox_override("panel", chip_style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	chip.add_child(row)
	var glyph := PlaceholderGlyph.new()
	glyph.spec = spec
	glyph.custom_minimum_size = Vector2(34, 34)
	glyph.tooltip_text = str(spec["art_id"])
	row.add_child(glyph)
	var text := str(spec["name"])
	if text == "":
		text = template_id
	if guarded:
		text += " ·风险"
	var name_label := ExpeditionUI.label(text, 14, ExpeditionUI.TEXT)
	row.add_child(name_label)
	return chip


## 占位图形：按 ChapterArtRegistry 的 shape 参数画简化轮廓（开发计划 §3 搜索对象行）。
class PlaceholderGlyph extends Control:
	var spec: Dictionary = {}

	func _draw() -> void:
		if spec.is_empty() or size.x <= 0:
			return
		var base: Color = spec.get("base", Color("#6b7280"))
		var accent: Color = spec.get("accent", Color("#aeb6c2"))
		var center := size / 2.0
		var radius := minf(size.x, size.y) * 0.38
		match str(spec.get("shape", "box")):
			"nest":
				draw_arc(center, radius, 0, TAU, 24, accent, 3.0, true)
				draw_circle(center, radius * 0.45, accent.darkened(0.2))
			"pool":
				draw_set_transform(center, 0.0, Vector2(1.0, 0.55))
				draw_circle(Vector2.ZERO, radius, base.lightened(0.1))
				draw_arc(Vector2.ZERO, radius, 0, TAU, 24, accent, 2.5, true)
			"wood":
				draw_rect(Rect2(center - Vector2(radius, radius * 0.6), Vector2(radius * 2.0, radius * 1.2)), base.lightened(0.15))
				draw_circle(center + Vector2(radius * 0.9, 0), radius * 0.45, accent)
			"plant":
				draw_line(center + Vector2(0, radius), center - Vector2(0, radius * 0.4), accent, 3.0, true)
				draw_circle(center - Vector2(0, radius * 0.55), radius * 0.5, base.lightened(0.2))
				draw_circle(center + Vector2(radius * 0.35, -radius * 0.1), radius * 0.3, base.lightened(0.35))
			"sarcophagus":
				draw_rect(Rect2(center - Vector2(radius * 0.62, radius), Vector2(radius * 1.24, radius * 2.0)), base.lightened(0.12))
				draw_line(center - Vector2(radius * 0.62, radius * 0.25), center + Vector2(radius * 0.62, radius * 0.25), accent, 2.5, true)
			"remains":
				draw_circle(center - Vector2(0, radius * 0.25), radius * 0.55, base.lightened(0.25))
				draw_rect(Rect2(center - Vector2(radius * 0.32, radius * 0.1), Vector2(radius * 0.64, radius * 0.9)), base.lightened(0.15))
				draw_circle(center - Vector2(radius * 0.18, radius * 0.32), 2.2, accent)
				draw_circle(center + Vector2(radius * 0.18, radius * 0.32), 2.2, accent)
			"camp":
				draw_colored_polygon(PackedVector2Array([
					center + Vector2(-radius, radius * 0.8), center + Vector2(0, -radius * 0.8), center + Vector2(radius, radius * 0.8),
				]), base.lightened(0.15))
				draw_line(center + Vector2(0, -radius * 0.8), center + Vector2(0, radius * 0.8), accent, 2.0, true)
			"wisp":
				draw_circle(center, radius * 0.35, accent)
				draw_arc(center, radius, 0, TAU, 20, Color(accent, 0.5), 2.0, true)
			"gem":
				draw_colored_polygon(PackedVector2Array([
					center + Vector2(0, -radius), center + Vector2(radius * 0.85, -radius * 0.2),
					center + Vector2(radius * 0.5, radius * 0.9), center + Vector2(-radius * 0.5, radius * 0.9),
					center + Vector2(-radius * 0.85, -radius * 0.2),
				]), base.lightened(0.15))
				draw_polyline(PackedVector2Array([
					center + Vector2(-radius * 0.85, -radius * 0.2), center + Vector2(0, radius * 0.15), center + Vector2(radius * 0.85, -radius * 0.2),
				]), accent, 2.0, true)
			_:
				draw_rect(Rect2(center - Vector2(radius, radius * 0.85), Vector2(radius * 2.0, radius * 1.7)), base.lightened(0.12))
				draw_rect(Rect2(center - Vector2(radius, radius * 0.85), Vector2(radius * 2.0, radius * 1.7)), accent, false, 2.0)
				draw_line(center + Vector2(0, -radius * 0.2), center + Vector2(0, radius * 0.2), accent, 2.0, true)
