class_name ExpeditionHubPanel
extends Control
## 探险营地：层级介绍、牌组与出发检查、整备和继续探险入口。

signal close_requested
signal open_loadout_requested
signal open_equipment_warehouse_requested
signal open_room_requested
signal depart_requested
signal resume_requested

const CREAM := Color("#fff9ed")

var game: FarmGame
var inventory: InventoryGame
var intro_label: Label
var intro_panel: PanelContainer
var status_label: Label
var depart_button: Button
var overview_labels: Array = []
var deck_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	theme = ExpeditionUI.make_theme()
	_build()


func open(target_game: FarmGame) -> void:
	game = target_game
	inventory = InventoryGame.new()
	inventory.bind(game.state["expedition"])
	intro_panel.visible = not inventory.basic_kit_missing().is_empty()
	status_label.text = ""
	_refresh_overview()
	var has_run := str(game.state["expedition"].get("active_run_ref", "")) != ""
	depart_button.text = "继续 →" if has_run else "出发 →"
	var check := inventory.loadout_check()
	depart_button.disabled = not has_run and not check["hard_blocks"].is_empty()
	depart_button.tooltip_text = "、".join(check["hard_blocks"]) if depart_button.disabled else "从苔石浅洞开始探险"
	var deck := DeckBuilder.build(inventory)
	deck_label.text = "%d 张牌 · 生命 %d" % [deck["entries"].size(), ExpeditionBaseline.MAX_HP]
	deck_label.tooltip_text = "首回合入堆 %d 张" % int(deck["totals"][1])
	visible = true


func _refresh_overview() -> void:
	## 概览两行随存档刷新：携带价值与出发检查（替代旧版静态占位文案）。
	var has_run := str(game.state["expedition"].get("active_run_ref", "")) != ""
	var carry_line := "携带 %d 金 · 保护 %d 金" % [inventory.carry_sell_value(), inventory.protected_value()]
	var check := inventory.loadout_check()
	var check_line := "准备就绪"
	if not check["hard_blocks"].is_empty():
		check_line = "、".join(check["hard_blocks"])
	elif not check["advises"].is_empty():
		check_line = "准备就绪 · %d 项配装建议" % check["advises"].size()
	if has_run:
		check_line = "探险进行中"
	overview_labels[0].text = carry_line
	overview_labels[1].text = check_line
	overview_labels[1].tooltip_text = "、".join(check["advises"])


func _on_depart_clicked() -> void:
	if str(game.state["expedition"].get("active_run_ref", "")) != "":
		resume_requested.emit()
	else:
		depart_requested.emit()


func close() -> void:
	visible = false


func _build() -> void:
	var workspace := ExpeditionUI.panel(Color(ExpeditionUI.PANEL, 0.96), ExpeditionUI.LINE, 20)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	workspace.offset_left = -600
	workspace.offset_right = -24
	workspace.offset_top = 112
	workspace.offset_bottom = 756
	add_child(workspace)
	var frame := MarginContainer.new()
	workspace.add_child(frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 18)
	scroll.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var overline := _label("探险营地", 24, CREAM)
	overline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(overline)
	var close_button := ExpeditionUI.button("×")
	close_button.tooltip_text = "收起"
	close_button.pressed.connect(func() -> void: close_requested.emit())
	top.add_child(close_button)

	var chapters := VBoxContainer.new()
	chapters.add_theme_constant_override("separation", 10)
	column.add_child(chapters)
	var layer_number := 0
	for layer_id in ExpeditionDefs.LAYER_ORDER:
		layer_number += 1
		var chapter := ExpeditionUI.panel(Color(ExpeditionUI.RAISED, 0.85), ExpeditionUI.LINE, 12)
		chapter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chapters.add_child(chapter)
		var chapter_row := HBoxContainer.new()
		chapter_row.add_theme_constant_override("separation", 14)
		chapter.add_child(chapter_row)
		chapter_row.add_child(_label("%02d" % layer_number, 12, ExpeditionUI.GOLD))
		var art := ExpeditionArt.new()
		art.subject = ["start", "ore_golem", "crystal"][layer_number - 1]
		art.tint = [ExpeditionUI.TEAL, Color("#a9b7a5"), Color("#b4a6d2")][layer_number - 1]
		art.custom_minimum_size = Vector2(64, 64)
		chapter_row.add_child(art)
		var details := VBoxContainer.new()
		details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		details.add_theme_constant_override("separation", 5)
		chapter_row.add_child(details)
		var title := _label(str(ExpeditionDefs.layer(layer_id)["name"]).replace("（第三层）", "").replace("（第二层）", ""), 21, CREAM)
		details.add_child(title)
		var note := _label(["苔石 · 铜屑", "铁矿 · 根须", "辉晶 · 古物"][layer_number - 1], 13, ExpeditionUI.MUTED)
		chapter.tooltip_text = ["从这里出发", "通关浅层后深入", "通关铁根后深入"][layer_number - 1]
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(note)

	var overview := ExpeditionUI.panel(Color(ExpeditionUI.INK, 0.94), ExpeditionUI.LINE, 18)
	column.add_child(overview)
	column.move_child(overview, 1)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 10)
	overview.add_child(details)
	deck_label = _label("", 16, ExpeditionUI.GOLD)
	details.add_child(deck_label)
	overview_labels = []
	for i in range(2):
		var line := _label("", 14, ExpeditionUI.MUTED)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(line)
		overview_labels.append(line)
	intro_panel = ExpeditionUI.panel(ExpeditionUI.RAISED, ExpeditionUI.TEAL, 10)
	intro_label = _label("先配装，领取基础装备", 14, ExpeditionUI.TEXT)
	intro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_panel.add_child(intro_label)
	details.add_child(intro_panel)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	details.add_child(buttons)
	var loadout := ExpeditionUI.button("配装")
	loadout.tooltip_text = "装备槽第 1 回合入牌，胸挂第 2 回合，背包第 3 回合。保险箱不入牌，失败仍保留。"
	loadout.pressed.connect(func() -> void: open_loadout_requested.emit())
	buttons.add_child(loadout)
	var warehouse := ExpeditionUI.button("仓库")
	warehouse.pressed.connect(func() -> void: open_equipment_warehouse_requested.emit())
	buttons.add_child(warehouse)
	var team := ExpeditionUI.button("组队")
	team.pressed.connect(func() -> void: open_room_requested.emit())
	buttons.add_child(team)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	depart_button = ExpeditionUI.button("出发 →", true)
	depart_button.pressed.connect(_on_depart_clicked)
	buttons.add_child(depart_button)
	status_label = _label("", 14, ExpeditionUI.RED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)



func _label(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label



func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed("pause"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
