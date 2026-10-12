class_name LifeUI
extends RefCounted
## The same controls serve the farm, connection forms and preparation rooms.
const PAPER := ExpeditionUI.PAPER
const INK := ExpeditionUI.INK
const GREEN := Color("#8d718a") # Compatibility name for the shared accent.
const LINE := Color("#c9bac8")
const SOFT := Color("#e8dde4")
const MUTED := Color("#756477")

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
		t.set_color("font_disabled_color",type,MUTED)
	for type in ["Button","OptionButton"]:
		t.set_stylebox("normal",type,style(PAPER,LINE))
		t.set_stylebox("hover",type,style(Color("#fff4e9"),GREEN))
		t.set_stylebox("pressed",type,style(SOFT,GREEN))
		t.set_stylebox("disabled",type,style(Color("#dfd6db"),LINE))
		t.set_stylebox("focus",type,style(Color.TRANSPARENT,GREEN,0))
	t.set_stylebox("normal","LineEdit",style(Color("#fff4e9"),LINE))
	t.set_stylebox("focus","LineEdit",style(Color("#fff4e9"),GREEN))
	t.set_stylebox("read_only","LineEdit",style(SOFT,LINE))
	t.set_color("font_placeholder_color","LineEdit",MUTED)
	t.set_color("caret_color","LineEdit",INK)
	t.set_color("selection_color","LineEdit",Color("#d5b8c9"))
	t.set_stylebox("panel","PopupMenu",style(PAPER,LINE))
	t.set_color("font_color","PopupMenu",INK)
	t.set_stylebox("hover","PopupMenu",style(SOFT,LINE))
	t.set_stylebox("panel","TabContainer",style(PAPER,LINE))
	t.set_stylebox("tab_selected","TabContainer",style(SOFT,GREEN))
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
	s.corner_radius_top_right = 3
	s.corner_radius_bottom_left = 3
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = padding
	s.content_margin_bottom = padding
	return s
