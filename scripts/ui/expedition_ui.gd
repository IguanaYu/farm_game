class_name ExpeditionUI
extends RefCounted
## 桑葚夜色、陶土印章与米白纸页；首页和探险共用，只负责展示。

const INK := Color("#201b25")
const PANEL := Color("#302735")
const RAISED := Color("#403443")
const LINE := Color("#69576a")
const PAPER := Color("#f1eadf")
const TEXT := Color("#f0e8de")
const MUTED := Color("#c1b0bd")
const ACCENT := Color("#df947a")
const SAGE := Color("#b1c5a0")
const LAVENDER := Color("#c4b1d9")
const RED := Color("#f09b90")
# Existing call sites use these names for emphasis and friendly states.
const GOLD := ACCENT
const TEAL := SAGE

class JournalPanel extends PanelContainer:
	func _ready() -> void:
		resized.connect(queue_redraw)
	func _draw() -> void:
		if size.x < 220 or size.y < 120:
			return
		var ink := Color(ExpeditionUI.ACCENT, 0.40)
		for point in [Vector2(9, 9), Vector2(size.x - 9, size.y - 9)]:
			var direction := 1.0 if point.x < size.x / 2 else -1.0
			draw_line(point, point + Vector2(15 * direction, 0), ink, 1, true)
			draw_line(point, point + Vector2(0, 15 * direction), ink, 1, true)
		# The small folded corner stays outside the panel's content.
		draw_colored_polygon(PackedVector2Array([Vector2(size.x - 17, 1), Vector2(size.x - 1, 1), Vector2(size.x - 1, 17)]), Color(ExpeditionUI.ACCENT, 0.25))
		draw_line(Vector2(18, size.y - 7), Vector2(minf(size.x - 18, 66), size.y - 7), Color(ExpeditionUI.MUTED, 0.24), 1)

class SeedSeal extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var unit := minf(size.x, size.y) / 64.0
		draw_set_transform((size - Vector2.ONE * 64 * unit) / 2, 0, Vector2.ONE * unit)
		var ink := ExpeditionUI.ACCENT
		draw_circle(Vector2(32, 32), 29, Color(ink, 0.09))
		draw_arc(Vector2(32, 32), 28, 0.12, PI * 1.19, 40, ink, 1.7, true)
		draw_arc(Vector2(32, 32), 28, PI * 1.24, TAU - 0.10, 28, ink, 1.7, true)
		draw_colored_polygon(PackedVector2Array([Vector2(32, 48), Vector2(23, 36), Vector2(32, 27), Vector2(41, 36)]), ink)
		draw_line(Vector2(32, 36), Vector2(32, 18), ExpeditionUI.PAPER, 2, true)
		draw_colored_polygon(PackedVector2Array([Vector2(30, 27), Vector2(19, 23), Vector2(17, 15), Vector2(27, 18)]), ExpeditionUI.PAPER)
		draw_colored_polygon(PackedVector2Array([Vector2(33, 25), Vector2(38, 14), Vector2(48, 12), Vector2(44, 22)]), ExpeditionUI.PAPER)
		draw_line(Vector2(25, 53), Vector2(39, 53), ink, 1.5, true)

static func seal(extent := 40) -> Control:
	var result := SeedSeal.new()
	result.custom_minimum_size = Vector2.ONE * extent
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return result

static func make_theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	result.default_font = font
	result.default_font_size = 18
	result.set_color("font_color", "Label", TEXT)
	result.set_color("font_color", "CheckButton", TEXT)
	for type in ["LineEdit","OptionButton"]:
		result.set_color("font_color",type,TEXT)
		result.set_stylebox("normal",type,style(PANEL,LINE,9,10))
		result.set_stylebox("focus",type,style(PANEL,GOLD,9,10))
		result.set_stylebox("hover",type,style(PANEL.lightened(0.1),GOLD,9,10))
	result.set_stylebox("panel", "PopupMenu", style(PANEL, LINE, 5, 10))
	result.set_stylebox("hover", "PopupMenu", style(RAISED, ACCENT, 4, 6))
	result.set_color("font_color", "PopupMenu", TEXT)
	result.set_stylebox("panel", "TooltipPanel", style(PAPER, LINE, 4, 10))
	result.set_color("font_color", "TooltipLabel", INK)
	return result

static func style(fill: Color, border := LINE, radius := 12, margin := 12) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(radius)
	if radius > 3:
		result.corner_radius_top_right = 3
		result.corner_radius_bottom_left = 3
	result.content_margin_left = margin
	result.content_margin_right = margin
	result.content_margin_top = margin
	result.content_margin_bottom = margin
	return result

static func panel(fill := PANEL, border := LINE, margin := 16) -> PanelContainer:
	var result := JournalPanel.new()
	var surface := style(fill, border, 10, margin)
	if margin > 4:
		surface.shadow_color = Color(INK, 0.22)
		surface.shadow_size = 5
		surface.shadow_offset = Vector2(0, 3)
	result.add_theme_stylebox_override("panel", surface)
	return result

static func label(content: String, font_size := 16, color := TEXT) -> Label:
	var result := Label.new()
	result.text = content
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func button(content: String, primary := false) -> Button:
	var result := Button.new()
	result.text = content
	result.custom_minimum_size.y = 42
	decorate_button(result, primary)
	return result

static func decorate_button(result: Button, primary := false) -> void:
	var fill := ACCENT if primary else RAISED
	var ink := INK if primary else TEXT
	result.add_theme_font_size_override("font_size", 18)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		result.add_theme_color_override(key, ink)
	result.add_theme_color_override("font_disabled_color", Color("#998b9a"))
	result.add_theme_stylebox_override("normal", style(fill, GOLD if primary else LINE, 9, 10))
	result.add_theme_stylebox_override("hover", style(fill.lightened(0.12), GOLD, 9, 10))
	result.add_theme_stylebox_override("pressed", style(fill.darkened(0.12), TEAL, 9, 10))
	result.add_theme_stylebox_override("disabled", style(Color("#2a242f"), Color("#514552"), 9, 10))
	var focus := style(Color.TRANSPARENT, GOLD, 9, 0)
	focus.set_border_width_all(2)
	result.add_theme_stylebox_override("focus", focus)
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func settings_button() -> Button:
	var result := button("")
	result.custom_minimum_size = Vector2(42, 42)
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result.tooltip_text = "设置 · Esc"
	var icon := BattleGlyph.make("settings", TEXT, 24)
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	icon.position = Vector2(-12, -12)
	result.add_child(icon)
	return result

static func bar(value: int, maximum: int, tint := TEAL) -> ProgressBar:
	var result := ProgressBar.new()
	result.max_value = maxi(1, maximum)
	result.value = value
	result.show_percentage = false
	result.custom_minimum_size.y = 7
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_stylebox_override("background", style(INK, Color.TRANSPARENT, 4, 0))
	result.add_theme_stylebox_override("fill", style(tint, Color.TRANSPARENT, 4, 0))
	return result

static func backdrop(parent: Control) -> void:
	var art := ExpeditionArt.new()
	art.name = "CaveBackdrop"
	art.subject = "cave"
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(art)

static func set_layer(parent: Node, id: String) -> void:
	for child in parent.get_children():
		if child is ExpeditionArt:
			child.layer_id = id
			child.queue_redraw()
		set_layer(child,id)

static func frame(parent: Control, padding := 24) -> MarginContainer:
	var result := MarginContainer.new()
	result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		result.add_theme_constant_override("margin_" + side, padding)
	parent.add_child(result)
	return result

static func clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

static func ignore_tree(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control:
			ignore_tree(child)
