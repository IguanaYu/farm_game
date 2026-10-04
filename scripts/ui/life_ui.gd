class_name LifeUI
extends RefCounted
## The same controls serve the farm, connection forms and preparation rooms.
const PAPER := Color("#faf6e7")
const INK := Color("#405442")
const GREEN := Color("#728767")
const LINE := Color("#c9ceb4")

static func make_theme() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Noto Sans CJK SC"])
	t.default_font = font
	t.default_font_size = 20
	for type in ["Label","Button","OptionButton","LineEdit","CheckButton","CheckBox","TabContainer"]:
		t.set_color("font_color",type,INK)
		t.set_color("font_hover_color",type,INK)
		t.set_color("font_pressed_color",type,INK)
		t.set_color("font_disabled_color",type,Color("#929d8c"))
	for type in ["Button","OptionButton"]:
		t.set_stylebox("normal",type,style(PAPER,LINE))
		t.set_stylebox("hover",type,style(Color("#fffdf0"),GREEN))
		t.set_stylebox("pressed",type,style(Color("#e4ebd7"),GREEN))
		t.set_stylebox("disabled",type,style(Color("#e6e8dd"),LINE))
		t.set_stylebox("focus",type,style(Color.TRANSPARENT,GREEN,0))
	t.set_stylebox("normal","LineEdit",style(Color("#fffcf1"),LINE))
	t.set_stylebox("focus","LineEdit",style(Color("#fffcf1"),GREEN))
	t.set_stylebox("read_only","LineEdit",style(Color("#e6e8dd"),LINE))
	t.set_color("font_placeholder_color","LineEdit",Color("#8a9582"))
	t.set_color("caret_color","LineEdit",INK)
	t.set_color("selection_color","LineEdit",Color("#bacfa0"))
	t.set_stylebox("panel","PopupMenu",style(PAPER,LINE))
	t.set_color("font_color","PopupMenu",INK)
	t.set_stylebox("hover","PopupMenu",style(Color("#e3ebd5"),LINE))
	t.set_stylebox("panel","TabContainer",style(PAPER,LINE))
	t.set_stylebox("tab_selected","TabContainer",style(Color("#e2ebd4"),GREEN))
	t.set_stylebox("tab_unselected","TabContainer",style(PAPER,LINE))
	t.set_color("font_selected_color","TabContainer",INK)
	t.set_color("font_unselected_color","TabContainer",INK)
	return t

static func style(fill: Color, border := LINE, padding := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = padding
	s.content_margin_bottom = padding
	return s
