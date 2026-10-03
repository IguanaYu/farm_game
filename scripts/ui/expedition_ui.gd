class_name ExpeditionUI
extends RefCounted
## 洞窟界面的共用视觉语言；只负责展示。

const INK := Color("#101d25")
const PANEL := Color("#1b2d35")
const LINE := Color("#3a5159")
const PAPER := Color("#f4e8cf")
const TEXT := Color("#eee5d2")
const MUTED := Color("#a2b5b6")
const GOLD := Color("#e5bd78")
const TEAL := Color("#7ac7b3")
const RED := Color("#eb9a86")

static func make_theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	result.default_font = font
	result.default_font_size = 16
	result.set_color("font_color", "Label", TEXT)
	result.set_color("font_color", "CheckButton", TEXT)
	return result

static func style(fill: Color, border := LINE, radius := 12, margin := 12) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(radius)
	result.content_margin_left = margin
	result.content_margin_right = margin
	result.content_margin_top = margin
	result.content_margin_bottom = margin
	return result

static func panel(fill := PANEL, border := LINE, margin := 16) -> PanelContainer:
	var result := PanelContainer.new()
	result.add_theme_stylebox_override("panel", style(fill, border, 14, margin))
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
	var fill := GOLD if primary else Color("#253c44")
	var ink := INK if primary else TEXT
	result.add_theme_font_size_override("font_size", 15)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		result.add_theme_color_override(key, ink)
	result.add_theme_color_override("font_disabled_color", Color("#a1b1b7"))
	result.add_theme_stylebox_override("normal", style(fill, GOLD if primary else LINE, 9, 10))
	result.add_theme_stylebox_override("hover", style(fill.lightened(0.12), GOLD, 9, 10))
	result.add_theme_stylebox_override("pressed", style(fill.darkened(0.12), TEAL, 9, 10))
	result.add_theme_stylebox_override("disabled", style(Color("#1b2930"), Color("#2e4148"), 9, 10))
	var focus := style(Color.TRANSPARENT, GOLD, 9, 0)
	focus.set_border_width_all(2)
	result.add_theme_stylebox_override("focus", focus)
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

static func bar(value: int, maximum: int, tint := TEAL) -> ProgressBar:
	var result := ProgressBar.new()
	result.max_value = maxi(1, maximum)
	result.value = value
	result.show_percentage = false
	result.custom_minimum_size.y = 7
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_stylebox_override("background", style(Color("#101b22"), Color.TRANSPARENT, 4, 0))
	result.add_theme_stylebox_override("fill", style(tint, Color.TRANSPARENT, 4, 0))
	return result

static func backdrop(parent: Control) -> void:
	var art := ExpeditionArt.new()
	art.subject = "cave"
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(art)

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
