class_name LoadoutPanel
extends Control
## 战备首页 v0（2.1 设计 D2.1-03/04）：三容器、物品详情、牌组预览、准备检查。
## 2.1 为点击式放置；拖放／旋转／自动整理在 2.3 升级。
## 变更只在内存，关闭时由外界决定保存（演示物品先剔除）。

signal close_requested
signal save_requested
signal demo_battle_requested
signal depart_requested


## 拖放支持（2.3 D2.3-02）：仓库行与已放置物品可拖，容器盒为放置目标。
class DragButton extends Button:
	var payload: Dictionary = {}

	func _get_drag_data(_pos: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = text
		set_drag_preview(preview)
		return payload


class DropBox extends VBoxContainer:
	signal dropped(data: Dictionary)

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.has("instance_id")

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		dropped.emit(data)

const FOREST := Color("#294f3c")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const TEXT_MUTED := Color("#3f4a42")
const BAD_RED := Color("#a4543f")
const WARN_GOLD := Color("#9b713a")
const CELL_EMPTY := Color("#efe8d4")
const CELL_BORDER := Color("#d8cfb2")
const CATEGORY_COLOR := {
	"weapon": Color("#c08050"),
	"armor": Color("#7d9cb5"),
	"tool": Color("#c9b45c"),
	"supply": Color("#8fae72"),
	"material": Color("#a3a89f"),
	"rare_seed": Color("#c58fa5"),
	"cargo": Color("#9a86b8"),
}

var game: FarmGame
var inventory: InventoryGame
var selected_instance_id := -1
var filter := "all"
var dirty := false

var stats_label: Label
var warehouse_column: VBoxContainer
var detail_column: VBoxContainer
var deck_column: VBoxContainer
var check_column: VBoxContainer
var container_boxes: Dictionary = {}
var status_label: Label
var put_back_button: Button
var rotate_button: Button
var preset_option: OptionButton
var preset_name_edit: LineEdit
var presets_data: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process_unhandled_key_input(true)
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
	selected_instance_id = -1
	filter = "all"
	dirty = false
	status_label.text = ""
	presets_data = PresetStore.load_presets()
	_refresh_presets()
	visible = true
	_refresh()


func close() -> void:
	visible = false


func mark_saved() -> void:
	dirty = false


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.11, 0.20, 0.14, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := _panel(CREAM, Color("#d5c9aa"), 18)
	panel.custom_minimum_size = Vector2(1180, 660)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	title_row.add_child(_label("战备箱", 24, FOREST))
	var hint := _label("点击物品选中，再点一个容器放入（自动找位）；点已放入的物品可查看并放回。", 14, TEXT_MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(hint)

	stats_label = _label("", 16, TEXT_DARK)
	column.add_child(stats_label)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	# 左：仓库与筛选。
	warehouse_column = VBoxContainer.new()
	warehouse_column.add_theme_constant_override("separation", 6)
	warehouse_column.custom_minimum_size = Vector2(250, 0)
	body.add_child(warehouse_column)

	# 中：三个容器。
	var center_column := VBoxContainer.new()
	center_column.add_theme_constant_override("separation", 8)
	center_column.custom_minimum_size = Vector2(430, 0)
	body.add_child(center_column)
	for container in ExpeditionBaseline.CONTAINERS:
		var box := _build_container_box(container)
		center_column.add_child(box)
		container_boxes[container] = box

	# 右：详情／牌组／检查。
	var right_column := VBoxContainer.new()
	right_column.add_theme_constant_override("separation", 8)
	right_column.custom_minimum_size = Vector2(380, 0)
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right_column)
	detail_column = _section(right_column, "物品详情")
	deck_column = _section(right_column, "牌组预览（按加入回合）")
	check_column = _section(right_column, "出发前检查")

	# 配装预设行：保存/切换多套战备方案（交付遗留项）。
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	column.add_child(preset_row)
	preset_row.add_child(_label("配装预设", 15, FOREST))
	preset_option = OptionButton.new()
	preset_option.add_theme_font_size_override("font_size", 14)
	preset_option.custom_minimum_size = Vector2(170, 0)
	preset_row.add_child(preset_option)
	preset_name_edit = LineEdit.new()
	preset_name_edit.placeholder_text = "名称（留空自动编号）"
	preset_name_edit.max_length = LoadoutPresets.NAME_MAX_CHARS
	preset_name_edit.custom_minimum_size = Vector2(150, 0)
	preset_row.add_child(preset_name_edit)
	var save_preset_button := _small_button("存为预设", Color("#eaf4df"), Color("#87b06f"))
	save_preset_button.tooltip_text = "把当前三个容器的布局存成一套预设；同名覆盖旧内容。"
	save_preset_button.pressed.connect(func() -> void: save_preset(preset_name_edit.text))
	preset_row.add_child(save_preset_button)
	var apply_preset_button := _small_button("应用预设", Color("#ffd98a"), Color("#9b713a"))
	apply_preset_button.tooltip_text = "清空当前容器并按预设复原；缺失物品会逐件提示。"
	apply_preset_button.pressed.connect(apply_selected)
	preset_row.add_child(apply_preset_button)
	var delete_preset_button := _small_button("删除", Color("#fff5df"), Color("#d5b87d"))
	delete_preset_button.pressed.connect(delete_selected)
	preset_row.add_child(delete_preset_button)

	# 底部操作。
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	column.add_child(bottom)
	var kit_button := _button("领取／补领基础装备", Color("#eaf4df"), Color("#87b06f"))
	kit_button.pressed.connect(_on_grant_kit)
	bottom.add_child(kit_button)
	var demo_button := _button("载入演示物品", Color("#fff5df"), Color("#d5b87d"))
	demo_button.pressed.connect(_on_inject_demo)
	bottom.add_child(demo_button)
	var demo_battle := _button("演示战斗", Color("#ffd98a"), Color("#9b713a"))
	demo_battle.tooltip_text = "用基础套装打一场演示战斗（2.2）：不消耗物品、不写存档。"
	demo_battle.pressed.connect(func() -> void: demo_battle_requested.emit())
	bottom.add_child(demo_battle)
	var clear_button := _button("清空配置", Color("#fff5df"), Color("#d5b87d"))
	clear_button.pressed.connect(_on_clear_loadout)
	bottom.add_child(clear_button)
	put_back_button = _button("放回仓库", Color("#fff5df"), Color("#d5b87d"))
	put_back_button.visible = false
	put_back_button.pressed.connect(_on_put_back)
	bottom.add_child(put_back_button)
	rotate_button = _button("旋转（R）", Color("#fff5df"), Color("#d5b87d"))
	rotate_button.visible = false
	rotate_button.pressed.connect(_on_rotate)
	bottom.add_child(rotate_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	status_label = _label("", 14, BAD_RED)
	status_label.custom_minimum_size = Vector2(260, 0)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(status_label)
	var depart := _button("出发（单人）", Color("#ffd98a"), Color("#9b713a"))
	depart.tooltip_text = "校验通过后直接出发进洞窟；失败原因会显示在旁边。"
	depart.pressed.connect(func() -> void: depart_requested.emit())
	bottom.add_child(depart)
	var close_button := _button("返回", Color("#eaf4df"), Color("#87b06f"))
	close_button.pressed.connect(_on_close)
	bottom.add_child(close_button)


func _build_container_box(container: String) -> VBoxContainer:
	var box := DropBox.new()
	box.add_theme_constant_override("separation", 4)
	box.dropped.connect(_on_drop_into_container.bind(container))
	var header := HBoxContainer.new()
	box.add_child(header)
	var display: String = ExpeditionBaseline.CONTAINER_DISPLAY[container]
	var size: Vector2i = ExpeditionBaseline.CONTAINER_SIZE[container]
	var join_round: int = ExpeditionBaseline.JOIN_ROUND[container]
	var round_note := "第 1 回合加入牌库" if join_round == 1 else "第 %d 回合加入牌库" % join_round
	header.add_child(_label("%s（%d×%d，%s）" % [display, size.x, size.y, round_note], 15, FOREST))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var tidy_button := _small_button("自动整理", Color("#fff5df"), Color("#d5b87d"))
	tidy_button.pressed.connect(_on_auto_tidy.bind(container))
	header.add_child(tidy_button)
	var grid := GridContainer.new()
	grid.columns = size.x
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	box.add_child(grid)
	box.set_meta("grid", grid)
	return box


func _on_drop_into_container(data: Dictionary, container: String) -> void:
	var result := inventory.move_to_loadout(int(data["instance_id"]), container)
	if result["ok"]:
		dirty = true
		_flash("已放入%s（拖放）。" % ExpeditionBaseline.CONTAINER_DISPLAY[container])
	else:
		_flash(result["reason"])
	_refresh()


func _on_auto_tidy(container: String) -> void:
	var result := inventory.auto_tidy(container)
	if result["ok"]:
		dirty = true
		_flash("已整理%s（容器归属不变）。" % ExpeditionBaseline.CONTAINER_DISPLAY[container])
	else:
		_flash(result["reason"])
	_refresh()


func _section(parent: VBoxContainer, title: String) -> VBoxContainer:
	var box := _panel(Color("#f7f1de"), Color("#e2e4d4"), 10)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	box.add_child(column)
	column.add_child(_label(title, 16, FOREST))
	return column


# —— 交互 ————————————————————————————————————————————————————————


func _on_grant_kit() -> void:
	var result := inventory.grant_basic_kit()
	dirty = true
	if result["granted"].is_empty():
		_flash("基础装备已齐，无需补领。")
	else:
		var names: Array = []
		for def_id in result["granted"]:
			names.append(ItemDefs.get_item(def_id)["name"])
		_flash("已发放基础装备：%s（在仓库列表中，点它再放入容器）" % "、".join(names))
	_refresh()


func _on_inject_demo() -> void:
	var result := inventory.inject_demo_items()
	_flash("演示物品已放入仓库（带“演示”标记，关闭面板即弃，不会存档）。")
	_refresh()


func _on_clear_loadout() -> void:
	inventory.clear_loadout()
	dirty = true
	selected_instance_id = -1
	_flash("已把全部物品放回仓库。")
	_refresh()


func _on_rotate() -> void:
	if selected_instance_id < 0:
		return
	var result := inventory.rotate_instance(selected_instance_id)
	if result["ok"]:
		dirty = true
		_flash("已旋转（占格与牌数不变）。")
	else:
		_flash(result["reason"])
	_refresh()


func _on_put_back() -> void:
	if selected_instance_id < 0:
		return
	var result := inventory.move_to_warehouse(selected_instance_id)
	if result["ok"]:
		dirty = true
		_flash("已放回仓库。")
	else:
		_flash(result["reason"])
	_refresh()


func _on_select_instance(instance_id: int) -> void:
	selected_instance_id = instance_id
	_refresh()


func _on_container_clicked(container: String) -> void:
	## 点容器里的空白格区域＝尝试把当前选中物品放进该容器（自动找位）。
	if selected_instance_id < 0:
		_flash("先在左侧仓库选中一件物品。")
		return
	var result := inventory.move_to_loadout(selected_instance_id, container)
	if result["ok"]:
		dirty = true
		_flash("已放入%s。" % ExpeditionBaseline.CONTAINER_DISPLAY[container])
	else:
		_flash(result["reason"])
	_refresh()


func _on_filter(kind: String) -> void:
	filter = kind
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_on_rotate()


func _on_close() -> void:
	close_requested.emit()


func _flash(message: String) -> void:
	status_label.text = message


# —— 配装预设 ————————————————————————————————————————————————————


func preset_names() -> Array:
	var names: Array = []
	for preset in presets_data.get("presets", []):
		names.append(str(preset.get("name", "")))
	return names


func save_preset(raw_name: String) -> Dictionary:
	## 把当前三容器快照存为预设；同名覆盖。预设文件独立于农场档，立即落盘。
	var presets: Array = presets_data.get("presets", [])
	var name := LoadoutPresets.normalize_name(raw_name, presets.size() + 1)
	var captured := LoadoutPresets.capture(inventory)
	var replaced := false
	for preset in presets:
		if str(preset.get("name", "")) == name:
			preset["items"] = captured["items"]
			preset["updated_at"] = int(Time.get_unix_time_from_system())
			replaced = true
			break
	if not replaced:
		if presets.size() >= LoadoutPresets.MAX_PRESETS:
			_flash("预设已满（最多 %d 套）：先删除再保存。" % LoadoutPresets.MAX_PRESETS)
			return {"ok": false, "reason": "预设已满"}
		presets.append({"name": name, "items": captured["items"],
				"created_at": int(Time.get_unix_time_from_system())})
	presets_data["presets"] = presets
	if not PresetStore.save_presets(presets_data):
		_flash("预设文件写入失败：本次未保存。")
		return {"ok": false, "reason": "写入失败"}
	_refresh_presets(name)
	preset_name_edit.text = ""
	_flash("已%s预设「%s」（%d 件）。" % ["覆盖" if replaced else "保存", name, (captured["items"] as Array).size()])
	return {"ok": true, "reason": "", "name": name, "count": (captured["items"] as Array).size()}


func apply_selected() -> Dictionary:
	var index := preset_option.selected
	var presets: Array = presets_data.get("presets", [])
	if index < 0 or index >= presets.size():
		_flash("先在预设列表选中一套。")
		return {"ok": false, "reason": "未选中预设"}
	var preset: Dictionary = presets[index]
	var result := LoadoutPresets.apply(inventory, preset)
	if result["ok"]:
		dirty = true
		selected_instance_id = -1
	_refresh()
	_flash(LoadoutPresets.report(result, str(preset.get("name", ""))))
	return result


func delete_selected() -> Dictionary:
	var index := preset_option.selected
	var presets: Array = presets_data.get("presets", [])
	if index < 0 or index >= presets.size():
		_flash("先在预设列表选中一套。")
		return {"ok": false, "reason": "未选中预设"}
	var name := str(presets[index].get("name", ""))
	presets.remove_at(index)
	presets_data["presets"] = presets
	if not PresetStore.save_presets(presets_data):
		_flash("预设文件写入失败：本次未删除。")
		return {"ok": false, "reason": "写入失败"}
	_refresh_presets()
	_flash("已删除预设「%s」。" % name)
	return {"ok": true, "reason": ""}


func _refresh_presets(select_name: String = "") -> void:
	preset_option.clear()
	var presets: Array = presets_data.get("presets", [])
	if presets.is_empty():
		preset_option.add_item("（暂无预设）")
		preset_option.disabled = true
		preset_option.selected = 0
		return
	preset_option.disabled = false
	var select_index := 0
	for index in range(presets.size()):
		var preset: Dictionary = presets[index]
		var item_name := str(preset.get("name", ""))
		preset_option.add_item("%s（%d 件）" % [item_name, (preset.get("items", []) as Array).size()])
		if item_name == select_name:
			select_index = index
	preset_option.selected = select_index


# —— 刷新 ————————————————————————————————————————————————————————


func _refresh() -> void:
	_refresh_stats()
	_refresh_warehouse()
	for container in ExpeditionBaseline.CONTAINERS:
		_refresh_container(container)
	_refresh_detail()
	_refresh_deck()
	_refresh_check()


func _refresh_stats() -> void:
	var used := 0
	var total := 0
	for container in ExpeditionBaseline.CONTAINERS:
		var size: Vector2i = ExpeditionBaseline.CONTAINER_SIZE[container]
		total += size.x * size.y
		for instance in inventory.loadout_list(container):
			var def := ItemDefs.get_item(str(instance["def_id"]))
			used += def["size"].x * def["size"].y
	var preview := inventory.deck_preview()
	var value_text := str(inventory.carry_sell_value()) + " 金币"
	if inventory.has_basic_in_loadout():
		value_text += "（基础装备不计可售价值）"
	stats_label.text = "生命上限 %d ｜ 已用格数 %d/%d ｜ 首回合牌 %d 张 ｜ 后续加入牌 %d 张 ｜ 携带可售价值 %s ｜ 失败保护价值 %d 金币" % [
		ExpeditionBaseline.MAX_HP, used, total,
		int(preview["totals"][1]), int(preview["totals"][2]) + int(preview["totals"][3]),
		value_text, inventory.protected_value(),
	]


func _refresh_warehouse() -> void:
	for child in warehouse_column.get_children():
		warehouse_column.remove_child(child)
		child.queue_free()
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	warehouse_column.add_child(filter_row)
	var filters := [["all", "全部"], ["weapon", "武器"], ["armor", "防具"], ["tool", "工具"], ["supply", "补给"], ["material", "材料"], ["cargo", "货物"]]
	for entry in filters:
		var button := _small_button(entry[1], Color("#fff5df") if filter != entry[0] else Color("#e8f0d8"), Color("#d5b87d"))
		button.pressed.connect(_on_filter.bind(entry[0]))
		filter_row.add_child(button)
	var list_title := _label("装备／材料仓库", 15, FOREST)
	warehouse_column.add_child(list_title)
	var items: Array = inventory.warehouse_list()
	var shown := 0
	for instance in items:
		var def := ItemDefs.get_item(str(instance["def_id"]))
		if filter != "all" and str(def["category"]) != filter:
			continue
		shown += 1
		var row := DragButton.new()
		row.payload = {"instance_id": int(instance["instance_id"])}
		var demo_mark := "［演示］" if bool(instance.get("demo", false)) else ""
		row.text = "%s%s  %d×%d → %d 张牌" % [demo_mark, def["name"], def["size"].x, def["size"].y, def["cards"].size()]
		row.add_theme_font_size_override("font_size", 14)
		row.add_theme_color_override("font_color", Color("#35513d"))
		row.add_theme_color_override("font_hover_color", Color("#1f3327"))
		row.add_theme_color_override("font_pressed_color", Color("#1f3327"))
		var fill := Color("#fffbea") if int(instance["instance_id"]) != selected_instance_id else Color("#e8f0d8")
		var style := _style(fill, CATEGORY_COLOR.get(str(def["category"]), Color("#77a76d")), 8)
		row.add_theme_stylebox_override("normal", style)
		row.add_theme_stylebox_override("hover", style)
		row.add_theme_stylebox_override("pressed", style)
		row.pressed.connect(_on_select_instance.bind(int(instance["instance_id"])))
		warehouse_column.add_child(row)
	if shown == 0:
		warehouse_column.add_child(_label("（仓库是空的：先领取基础装备，或载入演示物品看看）", 13, TEXT_MUTED))


func _refresh_container(container: String) -> void:
	var box: VBoxContainer = container_boxes[container]
	var grid: GridContainer = box.get_meta("grid")
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var size: Vector2i = ExpeditionBaseline.CONTAINER_SIZE[container]
	var instances: Array = inventory.loadout_list(container)
	var cell_owner := {}
	for instance in instances:
		var def := ItemDefs.get_item(str(instance["def_id"]))
		for covered in ExpeditionBaseline.cells_of(def["size"], Vector2i(int(instance["cell"][0]), int(instance["cell"][1])), bool(instance.get("rotated", false))):
			cell_owner[ExpeditionBaseline.cell_key(covered)] = instance
	var dark := container == "safe"
	for y in range(size.y):
		for x in range(size.x):
			var cell := Button.new()
			cell.custom_minimum_size = Vector2(34, 30)
			var key := ExpeditionBaseline.cell_key(Vector2i(x, y))
			if cell_owner.has(key):
				var instance: Dictionary = cell_owner[key]
				var def := ItemDefs.get_item(str(instance["def_id"]))
				var fill: Color = CATEGORY_COLOR.get(str(def["category"]), CELL_EMPTY)
				if dark:
					fill = fill.darkened(0.18)
				var border := Color("#4a6f4a") if int(instance["instance_id"]) != selected_instance_id else Color("#2f4f2f")
				cell.add_theme_stylebox_override("normal", _style(fill, border, 3))
				cell.add_theme_stylebox_override("hover", _style(fill, border, 3))
				cell.add_theme_stylebox_override("pressed", _style(fill, border, 3))
				cell.tooltip_text = "%s%s" % [def["name"], "（演示）" if bool(instance.get("demo", false)) else ""]
				cell.pressed.connect(_on_select_instance.bind(int(instance["instance_id"])))
			else:
				var empty_fill = CELL_EMPTY.darkened(0.06) if dark else CELL_EMPTY
				cell.add_theme_stylebox_override("normal", _style(empty_fill, CELL_BORDER, 3))
				cell.add_theme_stylebox_override("hover", _style(empty_fill.lightened(0.05), CELL_BORDER, 3))
				cell.add_theme_stylebox_override("pressed", _style(empty_fill, CELL_BORDER, 3))
				cell.pressed.connect(_on_container_clicked.bind(container))
			grid.add_child(cell)


func _refresh_detail() -> void:
	for child in detail_column.get_children():
		detail_column.remove_child(child)
		child.queue_free()
	put_back_button.visible = false
	rotate_button.visible = false
	var instance := inventory.find_instance(selected_instance_id)
	if instance.is_empty():
		detail_column.add_child(_label("（选中一件物品查看详情）", 13, TEXT_MUTED))
		return
	var def := ItemDefs.get_item(str(instance["def_id"]))
	var demo_mark := "［演示］" if bool(instance.get("demo", false)) else ""
	detail_column.add_child(_label("%s%s（品质 %d）" % [demo_mark, def["name"], int(def["quality"])], 17, FOREST))
	detail_column.add_child(_label("类别：%s ｜ 占格：%d×%d%s" % [
		ExpeditionBaseline.CATEGORY_DISPLAY.get(str(def["category"]), "?"),
		def["size"].x, def["size"].y,
		"（已旋转）" if bool(instance.get("rotated", false)) else "",
	], 14, TEXT_DARK))
	var cards_text := ""
	var counts := {}
	for card_id in def["cards"]:
		counts[card_id] = int(counts.get(card_id, 0)) + 1
	for card_id in counts:
		if cards_text != "":
			cards_text += "、"
		cards_text += "%s×%d" % [CardDefs.get_card(card_id)["name"], counts[card_id]]
	detail_column.add_child(_label("来源牌（%d 张）：%s" % [def["cards"].size(), cards_text], 14, TEXT_DARK))
	if bool(def.get("basic_kit", false)):
		detail_column.add_child(_label("价值：基础装备，不计可售价值；不能出售、分享或用于制作。", 14, WARN_GOLD))
	else:
		detail_column.add_child(_label("可售价值：%d 金币 ｜ %s" % [int(def.get("base_value", 0)),
			"可放保险箱（失败时保留）" if bool(def.get("safe_allowed", false)) else "不可放保险箱"], 14, TEXT_DARK))
	detail_column.add_child(_label("当前归属：%s" % _owner_display(str(instance["container"])), 14, TEXT_DARK))
	var desc := _label(str(def.get("desc", "")), 13, TEXT_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(330, 0)
	detail_column.add_child(desc)
	if ExpeditionBaseline.JOIN_ROUND.has(str(instance["container"])):
		put_back_button.visible = true
		rotate_button.visible = true


func _refresh_deck() -> void:
	for child in deck_column.get_children():
		deck_column.remove_child(child)
		child.queue_free()
	var preview := inventory.deck_preview()
	if int(preview["totals"][1]) + int(preview["totals"][2]) + int(preview["totals"][3]) == 0:
		deck_column.add_child(_label("（三个容器都是空的：放入物品后这里显示会抽到什么牌）", 13, TEXT_MUTED))
		return
	for join_round in [1, 2, 3]:
		var source: String = {"1": "胸挂", "2": "背包", "3": "保险箱"}[str(join_round)]
		var text := "第 %d 回合（%s，共 %d 张）：" % [join_round, source, int(preview["totals"][join_round])]
		var parts: Array = []
		var order: Array = preview["rounds"][join_round].map(func(entry): return str(entry["card_id"]))
		for card_id in order:
			if card_id in parts:
				continue
			parts.append(card_id)
		var names: Array = []
		for card_id in parts:
			names.append("%s×%d" % [CardDefs.get_card(card_id)["name"], int(preview["counts"][join_round][card_id])])
		text += "、".join(names)
		var label := _label(text, 14, TEXT_DARK)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(330, 0)
		deck_column.add_child(label)
	deck_column.add_child(_label("战斗开始时按当前布局构建牌库；战斗中不会把新战利品塞进手牌。", 12, TEXT_MUTED))


func _refresh_check() -> void:
	for child in check_column.get_children():
		check_column.remove_child(child)
		child.queue_free()
	var check := inventory.loadout_check()
	if check["hard_blocks"].is_empty() and check["advises"].is_empty():
		check_column.add_child(_label("准备检查通过：点左下「出发（单人）」即可进入洞窟。", 14, Color("#3f7048")))
		return
	for problem in check["hard_blocks"]:
		var label := _label("⛔ %s" % problem, 13, BAD_RED)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(330, 0)
		check_column.add_child(label)
	for advice in check["advises"]:
		var label := _label("△ %s" % advice, 13, WARN_GOLD)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(330, 0)
		check_column.add_child(label)


func _owner_display(owner: String) -> String:
	if owner == "warehouse":
		return "装备／材料仓库"
	if ExpeditionBaseline.CONTAINER_DISPLAY.has(owner):
		return ExpeditionBaseline.CONTAINER_DISPLAY[owner]
	return owner


# —— 小构件 ——————————————————————————————————————————————————————


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


func _style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style


func _label(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(content: String, fill: Color, border: Color) -> Button:
	var button := Button.new()
	button.text = content
	button.add_theme_color_override("font_color", Color("#35513d"))
	button.add_theme_color_override("font_hover_color", Color("#1f3327"))
	button.add_theme_color_override("font_pressed_color", Color("#1f3327"))
	button.add_theme_color_override("font_disabled_color", Color("#5c6b5e"))
	button.add_theme_font_size_override("font_size", 15)
	var style := _style(fill, border, 12)
	style.content_margin_left = 12
	style.content_margin_right = 12
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	return button


func _small_button(content: String, fill: Color, border: Color) -> Button:
	var button := _button(content, fill, border)
	button.add_theme_font_size_override("font_size", 13)
	return button
