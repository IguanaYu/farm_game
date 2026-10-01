class_name ExpeditionHubPanel
extends Control
## 洞窟入口概览面板（2.1 设计 D2.1-01）。2.1 只实现"无活动局／功能未开放"两态，
## 概览状态表的其余状态随 2.4／2.6 接入。

signal close_requested
signal open_loadout_requested
signal depart_requested
signal resume_requested

const FOREST := Color("#294f3c")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const TEXT_MUTED := Color("#788678")
const ACCENT_GOLD := Color("#9b713a")
const CAVE_DARK := Color("#33424e")

var game: FarmGame
var inventory: InventoryGame
var intro_label: Label
var intro_panel: PanelContainer
var status_label: Label
var depart_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var theme_root := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	theme_root.default_font = font
	theme_root.default_font_size = 18
	theme = theme_root
	_build()


func open(target_game: FarmGame) -> void:
	game = target_game
	inventory = InventoryGame.new()
	inventory.bind(game.state["expedition"])
	intro_panel.visible = not inventory.basic_kit_missing().is_empty()
	status_label.text = ""
	var has_run := str(game.state["expedition"].get("active_run_ref", "")) != ""
	depart_button.text = "继续探险" if has_run else "出发（单人）"
	visible = true


func _on_depart_clicked() -> void:
	if str(game.state["expedition"].get("active_run_ref", "")) != "":
		resume_requested.emit()
	else:
		depart_requested.emit()


func close() -> void:
	visible = false


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.11, 0.20, 0.14, 0.51)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := _panel(Color("#fff9ed"), Color("#d5c9aa"), 20)
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := _label("洞窟入口", 26, FOREST)
	title_row.add_child(title)
	var subtitle := _label("农场边缘的黑洞洞的入口，风里有矿石的味道。", 15, TEXT_MUTED)
	title_row.add_child(subtitle)
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var info := _panel(Color("#f2ecd9"), Color("#e2e4d4"), 12)
	column.add_child(info)
	var info_column := VBoxContainer.new()
	info_column.add_theme_constant_override("separation", 6)
	info.add_child(info_column)
	info_column.add_child(_label("最高到达层数：尚未解锁", 17, TEXT_DARK))
	info_column.add_child(_label("当前目标：先配好一套装备，看看它们会变成哪些牌", 17, TEXT_DARK))

	intro_panel = _panel(Color("#33492ef2"), Color("#7fa876"), 14)
	column.add_child(intro_panel)
	intro_label = _label("建议先配好装备：到战备箱领取基础装备，再考虑出发。", 16, Color("#e8f5df"))
	intro_panel.add_child(intro_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	var loadout_button := _button("战备配置", Color("#eaf4df"), Color("#87b06f"))
	loadout_button.pressed.connect(func() -> void:
		open_loadout_requested.emit()
	)
	buttons.add_child(loadout_button)
	depart_button = _button("出发（单人）", Color("#eaf4df"), Color("#87b06f"))
	depart_button.pressed.connect(_on_depart_clicked)
	buttons.add_child(depart_button)
	var team_button := _button("好友组队", Color("#f0efe6"), Color("#b9b9a6"))
	team_button.disabled = true
	team_button.tooltip_text = "联机合作将在 2.6 阶段开放。"
	buttons.add_child(team_button)

	var legend := _label("操作说明：点击洞窟入口看这里；战备箱直接打开个人配装；制作台即将开放。探险时携带物品会被本局占用。", 14, TEXT_MUTED)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.custom_minimum_size = Vector2(520, 0)
	column.add_child(legend)

	status_label = _label("", 14, Color("#a4543f"))
	column.add_child(status_label)

	var close_button := _button("关闭", Color("#fff5df"), Color("#d5b87d"))
	close_button.pressed.connect(func() -> void:
		close_requested.emit()
	)
	column.add_child(close_button)


func _panel(fill: Color, border: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _label(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(content: String, fill: Color, border: Color) -> Button:
	var button := Button.new()
	button.text = content
	button.add_theme_font_size_override("font_size", 17)
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	return button
