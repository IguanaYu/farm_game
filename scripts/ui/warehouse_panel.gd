class_name WarehousePanel
extends Control
## 装备／材料仓库（2.5 设计 D2.5-02）：分区容量、筛选、出售、移入战备、待领取区。
## 出售走 CraftingGame.sell_instance（金币入农场档）；移入战备复用 InventoryGame。

signal close_requested
signal save_requested
signal open_loadout_requested

const FOREST := Color("#294f3c")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const TEXT_MUTED := Color("#788678")
const BAD_RED := Color("#a4543f")
const WARN_GOLD := Color("#9b713a")

var game: FarmGame
var inventory: InventoryGame
var crafting: CraftingGame
var filter := "all"
var status_label: Label
var list_column: VBoxContainer
var header_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var theme_root := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	theme_root.default_font = font
	theme_root.default_font_size = 14
	theme = theme_root
	_build()


func open(target_game: FarmGame) -> void:
	game = target_game
	inventory = InventoryGame.new()
	inventory.bind(game.state["expedition"])
	crafting = CraftingGame.new()
	crafting.bind(game)
	status_label.text = ""
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.11, 0.20, 0.14, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := _panel(CREAM, Color("#d5c9aa"), 16)
	panel.custom_minimum_size = Vector2(900, 620)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	title_row.add_child(_label("装备／材料仓库", 22, FOREST))
	var close_button := _button("返回", Color("#eaf4df"), Color("#87b06f"))
	close_button.pressed.connect(_on_close)
	title_row.add_child(close_button)
	header_label = _label("", 13, TEXT_DARK)
	column.add_child(header_label)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	column.add_child(filter_row)
	for entry in [["all", "全部"], ["weapon", "武器"], ["armor", "防具"], ["tool", "工具"], ["supply", "补给"], ["material", "材料"], ["cargo", "货物"]]:
		var button := _small_button(str(entry[1]), Color("#fff5df") if filter != entry[0] else Color("#e8f0d8"), Color("#d5b87d"))
		button.pressed.connect(_on_filter.bind(str(entry[0])))
		filter_row.add_child(button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	list_column = VBoxContainer.new()
	list_column.add_theme_constant_override("separation", 4)
	list_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_column)
	status_label = _label("", 13, BAD_RED)
	column.add_child(status_label)


func _refresh() -> void:
	var equipment_used := 0
	var resource_used := 0
	for instance in inventory.warehouse_list():
		if ExpeditionBaseline.warehouse_zone(str(instance["def_id"])) == "equipment":
			equipment_used += 1
		else:
			resource_used += 1
	var cap := ExpeditionBaseline.warehouse_capacity(game.state["expedition"])
	header_label.text = "装备区 %d/%d ｜ 资源区 %d/%d ｜ 金币 %d ｜ 稀有种子在种子区，作物在作物区" % [
		equipment_used, cap, resource_used, cap, int(game.state["coins"])]
	for child in list_column.get_children():
		list_column.remove_child(child)
		child.queue_free()
	var shown := 0
	var grouped := {}
	for instance in inventory.warehouse_list():
		var def := ItemDefs.get_item(str(instance["def_id"]))
		if filter != "all" and str(def["category"]) != filter:
			continue
		shown += 1
		var key := str(instance["def_id"])
		if not grouped.has(key):
			grouped[key] = {"def": def, "count": 0, "zone": ExpeditionBaseline.warehouse_zone(key)}
		grouped[key]["count"] += 1
	for key in grouped:
		var entry: Dictionary = grouped[key]
		var def: Dictionary = entry["def"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := _label("%s×%d（%d×%d → %d 张牌，%s，%s）" % [
			def["name"], int(entry["count"]), def["size"].x, def["size"].y, def["cards"].size(),
			"可售 %d" % int(def.get("base_value", 0)) if bool(def.get("sellable", false)) else "不可售",
			"装备区" if str(entry["zone"]) == "equipment" else "资源区"], 13, TEXT_DARK)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var loadout_button := _small_button("移入战备", Color("#eaf4df"), Color("#87b06f"))
		loadout_button.pressed.connect(_on_into_loadout.bind(key))
		row.add_child(loadout_button)
		if bool(def.get("sellable", false)):
			var sell_button := _small_button("出售 1 件", Color("#fff5df"), Color("#d5b87d"))
			sell_button.pressed.connect(_on_sell.bind(key))
			row.add_child(sell_button)
		list_column.add_child(row)
	if shown == 0:
		list_column.add_child(_label("（仓库是空的：下洞带回物品，或先去制作台）", 13, TEXT_MUTED))
	var pending: Array = game.state["expedition"].get("crafting", {}).get("pending_items", [])
	if not pending.is_empty():
		var pending_row := HBoxContainer.new()
		pending_row.add_theme_constant_override("separation", 6)
		var names: Array = []
		for entry in pending:
			names.append("%s×%d" % [ItemDefs.get_item(str(entry["def_id"]))["name"], int(entry.get("count", 1))])
		var info := _label("待领取区：%s" % "、".join(names), 13, WARN_GOLD)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pending_row.add_child(info)
		var claim := _small_button("领取", Color("#ffd98a"), Color("#9b713a"))
		claim.pressed.connect(_on_claim_pending)
		pending_row.add_child(claim)
		list_column.add_child(pending_row)


func _on_filter(kind: String) -> void:
	filter = kind
	_refresh()


func _on_into_loadout(def_id: String) -> void:
	## 快捷移入战备：先试胸挂、再背包（找合法空位，不挤旧物）。
	var target := -1
	for instance in inventory.warehouse_list():
		if str(instance["def_id"]) == def_id:
			target = int(instance["instance_id"])
			break
	if target < 0:
		return
	var result := inventory.move_to_loadout(target, "chest")
	if not result["ok"]:
		result = inventory.move_to_loadout(target, "pack")
	if result["ok"]:
		status_label.text = "已移入战备（%s）。去战备箱查看牌组变化。" % ItemDefs.get_item(def_id)["name"]
		save_requested.emit()
	else:
		status_label.text = result["reason"]
	_refresh()


func _on_sell(def_id: String) -> void:
	var result := crafting.sell_instance(def_id)
	if result["ok"]:
		status_label.text = "出售 1 件 %s，+%d 金币（货物出售才变金币）。" % [ItemDefs.get_item(def_id)["name"], int(result["coins"])]
		save_requested.emit()
	else:
		status_label.text = result["reason"]
	_refresh()


func _on_claim_pending() -> void:
	var result := crafting.claim_pending()
	status_label.text = "领取 %d 件，剩 %d 件（先整理仓库再领）。" % [int(result["moved"]), int(result["remaining"])]
	save_requested.emit()
	_refresh()


func _on_close() -> void:
	close_requested.emit()


func _panel(fill: Color, border: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _label(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(content: String, fill: Color, border: Color) -> Button:
	var button := _small_button(content, fill, border)
	button.add_theme_font_size_override("font_size", 15)
	return button


func _small_button(content: String, fill: Color, border: Color) -> Button:
	var button := Button.new()
	button.text = content
	button.add_theme_font_size_override("font_size", 13)
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 6
	style.content_margin_right = 6
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	return button
