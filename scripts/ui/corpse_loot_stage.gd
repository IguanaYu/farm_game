class_name CorpseLootStage
extends Control
## 战后保留矿洞与敌人站位，点击倒下的敌人打开搜索区域。
signal corpse_selected(source_id: String)
signal leave_requested
signal menu_requested

var content: VBoxContainer
var layer_id := "moss_stone_shallow"
var loot_owner: Control
var leave_text := "继续探索 · 离开本节点 →"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ExpeditionArt.new()
	backdrop.subject = "cave"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var frame := ExpeditionUI.frame(self, 40)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 24)
	frame.add_child(content)

func display(run: Dictionary, sources: Array) -> void:
	if not is_node_ready():
		return
	(get_child(0) as ExpeditionArt).layer_id = str(run.get("layer_id", "moss_stone_shallow"))
	get_child(0).queue_redraw()
	ExpeditionUI.clear(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(ExpeditionUI.label("战斗胜利 · 清理战场", 32, ExpeditionUI.PAPER))
	titles.add_child(ExpeditionUI.label("点击倒下的敌人，自动按顺序搜索它身上的物品", 18, ExpeditionUI.MUTED))
	var menu := ExpeditionUI.button("☰ 菜单")
	menu.pressed.connect(func() -> void: menu_requested.emit())
	header.add_child(menu)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(row)
	var farmer := ExpeditionArt.new()
	farmer.subject = "farmer"
	farmer.custom_minimum_size = Vector2(140, 220)
	row.add_child(farmer)
	for source in sources:
		var button := ExpeditionUI.button("")
		button.name = "Corpse_" + str(source["id"])
		button.custom_minimum_size = Vector2(210, 250)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(func() -> void: corpse_selected.emit(str(source["id"])))
		row.add_child(button)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 12)
		margin.add_theme_constant_override("margin_right", 12)
		button.add_child(margin)
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		margin.add_child(column)
		var art := ExpeditionArt.new()
		art.subject = str(source["enemy_id"])
		art.fallen = true
		art.custom_minimum_size = Vector2(140, 160)
		column.add_child(art)
		var label := ExpeditionUI.label(str(source["name"]), 19, ExpeditionUI.PAPER)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
		var state := ExpeditionUI.label(status(source, run), 14, ExpeditionUI.GOLD)
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(state)
		ExpeditionUI.ignore_tree(margin)
	var below := Control.new()
	below.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(below)
	var footer := HBoxContainer.new()
	content.add_child(footer)
	var hint := ExpeditionUI.label("物品装包后才能带走 · 离开当前战场会放弃剩余物资", 15, ExpeditionUI.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)
	var leave := ExpeditionUI.button(leave_text, true)
	leave.pressed.connect(func() -> void: leave_requested.emit())
	footer.add_child(leave)

static func status(source: Dictionary, run: Dictionary) -> String:
	for session in run.get("loot_searches", {}).values():
		if str(session["source"]) == str(source["id"]):
			return "搜索中…"
	var complete := true
	var remaining := false
	var any_searched := false
	for region in source["regions"]:
		any_searched = any_searched or not (region["searched"] as Array).is_empty()
		complete = complete and region["searched"].size() == int(region["size"][0]) * int(region["size"][1])
		for item in region["items"]:
			remaining = remaining or not bool(item.get("taken", false))
	return "已搜空" if complete and not remaining else ("尚有物品" if remaining else ("继续搜索" if any_searched else "点击搜索"))
