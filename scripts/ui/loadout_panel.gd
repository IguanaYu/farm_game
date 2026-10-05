class_name LoadoutPanel
extends Control
## 战备首页 v0（2.1 设计 D2.1-03/04）：三容器、物品详情、牌组预览、准备检查。
## 2.1 为点击式放置；拖放／旋转／自动整理在 2.3 升级。
## 变更只在内存，关闭时由外界决定保存（演示物品先剔除）。

signal close_requested
signal save_requested
signal demo_battle_requested
signal depart_requested


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
## M2：线上命令口（farm_hud.open_loadout 注入；空 Callable = 单机直改本地档）。
var online_request: Callable = Callable()
var selected_instance_id := -1
var filter := "all"
var dirty := false
var pending_placement := false

var stats_label: Label
var warehouse_header: Label
var warehouse_grid: BackpackWorkspace.FlowItemGrid
var workspace: BackpackWorkspace
var detail_column: VBoxContainer
var deck_column: VBoxContainer
var check_column: VBoxContainer
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
	theme = LifeUI.make_theme()
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
	shade.color = Color(0.11,0.20,0.14,0.30)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := _panel(CREAM,Color("#c9ceb4"),14)
	panel.custom_minimum_size = Vector2(1160,710)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var title := _label("洞口战备箱",28,FOREST)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close_button := _button("回洞口营地 ×",Color("#e8efdb"),Color("#b2bd9d"))
	close_button.pressed.connect(_on_close)
	top.add_child(close_button)
	stats_label = _label("",18,TEXT_DARK)
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(stats_label)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",14)
	column.add_child(body)
	# 三栏改版：左＝装备纸娃娃，中＝容器栈（共享组件），右＝仓库大格子+详情/牌组/检查。
	workspace = BackpackWorkspace.new()
	workspace.name = "BackpackWorkspace"
	workspace.setup(self, {
		"place": _on_workspace_place,
		"equip": _on_workspace_equip,
		"tidy": func(container: String): _on_auto_tidy(container),
		"select": _on_select_instance,
	})
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(workspace)
	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size.x = 340
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	right_scroll.add_child(right)
	var filter_row := HFlowContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	right.add_child(filter_row)
	var filters := [["all", "全部"], ["weapon", "武器"], ["armor", "防具"], ["helmet", "头盔"], ["tool", "工具"], ["supply", "补给"], ["material", "材料"], ["cargo", "货物"]]
	for entry in filters:
		var filter_button := _small_button(entry[1], Color("#fff5df") if filter != entry[0] else Color("#e8f0d8"), Color("#d5b87d"))
		filter_button.pressed.connect(_on_filter.bind(entry[0]))
		filter_row.add_child(filter_button)
	warehouse_header = _label("装备／材料仓库", 15, FOREST)
	right.add_child(warehouse_header)
	warehouse_grid = BackpackWorkspace.FlowItemGrid.new()
	warehouse_grid.workspace = workspace
	warehouse_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warehouse_grid.entry_selected.connect(_on_select_instance)
	right.add_child(warehouse_grid)
	detail_column = _section(right,"物品详情", false)
	deck_column = _section(right,"牌组与加入回合", false)
	check_column = _section(right,"出发前检查", false)
	var presets := HBoxContainer.new()
	column.add_child(presets)
	preset_option = OptionButton.new()
	preset_option.custom_minimum_size.x = 190
	presets.add_child(preset_option)
	preset_name_edit = LineEdit.new()
	preset_name_edit.placeholder_text = "配装预设名称"
	preset_name_edit.max_length = LoadoutPresets.NAME_MAX_CHARS
	preset_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	presets.add_child(preset_name_edit)
	for entry in [["保存预设",func(): save_preset(preset_name_edit.text)],["应用预设",apply_selected],["删除预设",delete_selected]]:
		var button := _small_button(entry[0],Color("#e8efdb"),Color("#b2bd9d"))
		button.pressed.connect(entry[1])
		presets.add_child(button)
	var actions := HFlowContainer.new()
	column.add_child(actions)
	for entry in [["补领基础装备",_on_grant_kit],["清空配置",_on_clear_loadout]]:
		var button := _small_button(entry[0],Color("#e8efdb"),Color("#b2bd9d"))
		button.pressed.connect(entry[1])
		actions.add_child(button)
	put_back_button = _small_button("放回仓库",Color("#f1e8d3"),Color("#cfc4a6"))
	put_back_button.pressed.connect(_on_put_back)
	actions.add_child(put_back_button)
	rotate_button = _small_button("旋转 R",Color("#f1e8d3"),Color("#cfc4a6"))
	rotate_button.pressed.connect(_on_rotate)
	actions.add_child(rotate_button)
	if OS.is_debug_build():
		for entry in [["演示物品",_on_inject_demo],["演示战斗",func(): demo_battle_requested.emit()]]:
			var button := _small_button(entry[0],Color("#f1e8d3"),Color("#cfc4a6"))
			button.pressed.connect(entry[1])
			actions.add_child(button)
	var bottom := HBoxContainer.new()
	column.add_child(bottom)
	status_label = _label("",18,BAD_RED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(status_label)
	var depart := _button("准备妥当 · 单人出发 →",Color("#dce8c8"),Color("#839b6b"))
	depart.pressed.connect(func(): depart_requested.emit())
	bottom.add_child(depart)


func _section(parent: VBoxContainer, title: String, expand := true) -> VBoxContainer:
	var box := _panel(Color("#f7f1de"), Color("#e2e4d4"), 10)
	if expand:
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	box.add_child(column)
	column.add_child(_label(title, 16, FOREST))
	return column


func _on_auto_tidy(container: String) -> void:
	var result: Dictionary
	if _is_online():
		var reply: Dictionary = await online_request.call("inv.auto_tidy", {"container": container})
		result = _online_result(reply)
		if result.is_empty():
			return
	else:
		result = inventory.auto_tidy(container)
	if result["ok"]:
		dirty = true
		_flash("已整理%s（容器归属不变）。" % ExpeditionBaseline.CONTAINER_DISPLAY[container])
	else:
		_flash(result["reason"])
	_refresh()


# —— 工作台意图（BackpackWorkspace 经 Callable 回调到这里）—————————————————


func _on_workspace_place(payload: Dictionary, container: String, cell: Vector2i) -> void:
	place_item(payload, container, cell)


func _on_workspace_equip(payload: Dictionary, slot: String) -> void:
	## 拖入装备槽＝装备意图；旧占用由规则层自动换回仓库。
	workspace.busy = true
	var result: Dictionary
	if _is_online():
		var reply: Dictionary = await online_request.call("inv.equip", {"instance_id": int(payload["instance_id"]), "slot": slot})
		result = _online_result(reply)
	else:
		result = inventory.equip(int(payload["instance_id"]), slot)
	workspace.busy = false
	if result.is_empty():
		return
	if result["ok"]:
		dirty = true
		_flash("已装备到%s槽（牌第 1 回合入堆）。" % ExpeditionBaseline.SLOT_DISPLAY[slot])
	else:
		_flash(str(result.get("reason", "装备失败")))
	_refresh()


# —— 交互 ————————————————————————————————————————————————————————


func _on_grant_kit() -> void:
	var result: Dictionary
	if _is_online():
		var reply: Dictionary = await online_request.call("inv.grant_basic_kit", {})
		result = _online_result(reply)
		if result.is_empty():
			return
	else:
		result = inventory.grant_basic_kit()
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
	if _is_online():
		_flash("演示内容不在线上模式开放。")
		return
	var result := inventory.inject_demo_items()
	_flash("演示物品已放入仓库（带“演示”标记，关闭面板即弃，不会存档）。")
	_refresh()


func _on_clear_loadout() -> void:
	if _is_online():
		var reply: Dictionary = await online_request.call("inv.clear_loadout", {})
		if _online_result(reply).is_empty():
			return
	else:
		inventory.clear_loadout()
	dirty = true
	selected_instance_id = -1
	_flash("已把全部物品放回仓库。")
	_refresh()


func _on_rotate() -> void:
	if selected_instance_id < 0:
		return
	var result: Dictionary
	if _is_online():
		var reply: Dictionary = await online_request.call("inv.rotate", {"instance_id": selected_instance_id})
		result = _online_result(reply)
		if result.is_empty():
			return
	else:
		result = inventory.rotate_instance(selected_instance_id)
	if result["ok"]:
		dirty = true
		_flash("已旋转（占格与牌数不变）。")
	else:
		_flash(result["reason"])
	_refresh()


func _on_put_back() -> void:
	if selected_instance_id < 0:
		return
	var result: Dictionary
	if _is_online():
		var reply: Dictionary = await online_request.call("inv.move_to_warehouse", {"instance_id": selected_instance_id})
		result = _online_result(reply)
		if result.is_empty():
			return
	else:
		result = inventory.move_to_warehouse(selected_instance_id)
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
	var result: Dictionary
	if _is_online():
		var reply: Dictionary = await online_request.call("inv.move_to_loadout", {"instance_id": selected_instance_id, "container": container})
		result = _online_result(reply)
		if result.is_empty():
			return
	else:
		result = inventory.move_to_loadout(selected_instance_id, container)
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


func _is_online() -> bool:
	return online_request.is_valid()


## 线上应答 → 规则返回值；失败已提示并返回 {}（调用方直接 return）。
func _online_result(reply: Dictionary) -> Dictionary:
	if reply.is_empty():
		_flash("操作未完成：连接中断或超时，稍后重试。")
		return {}
	if str(reply.get("t", "")) == "req_err":
		_flash(str(reply.get("msg", "操作失败")))
		return {}
	var result: Variant = reply.get("result", null)
	return result if result is Dictionary else {}


func _flash(message: String) -> void:
	status_label.text = message


# —— 配装预设 ————————————————————————————————————————————————————


func preset_names() -> Array:
	var names: Array = []
	for preset in presets_data.get("presets", []):
		names.append(str(preset.get("name", "")))
	return names


func save_preset(raw_name: String) -> Dictionary:
	## 把当前装备槽+三容器快照存为预设；同名覆盖。预设文件独立于农场档，立即落盘。
	var presets: Array = presets_data.get("presets", [])
	var name := LoadoutPresets.normalize_name(raw_name, presets.size() + 1)
	var captured := LoadoutPresets.capture(inventory)
	var replaced := false
	for preset in presets:
		if str(preset.get("name", "")) == name:
			preset["items"] = captured["items"]
			preset["equipment"] = captured.get("equipment", [])
			preset["updated_at"] = int(Time.get_unix_time_from_system())
			replaced = true
			break
	if not replaced:
		if presets.size() >= LoadoutPresets.MAX_PRESETS:
			_flash("预设已满（最多 %d 套）：先删除再保存。" % LoadoutPresets.MAX_PRESETS)
			return {"ok": false, "reason": "预设已满"}
		presets.append({"name": name, "items": captured["items"], "equipment": captured.get("equipment", []),
				"created_at": int(Time.get_unix_time_from_system())})
	presets_data["presets"] = presets
	if not PresetStore.save_presets(presets_data):
		_flash("预设文件写入失败：本次未保存。")
		return {"ok": false, "reason": "写入失败"}
	var count: int = (captured["items"] as Array).size() + (captured.get("equipment", []) as Array).size()
	_refresh_presets(name)
	preset_name_edit.text = ""
	_flash("已%s预设「%s」（%d 件）。" % ["覆盖" if replaced else "保存", name, count])
	return {"ok": true, "reason": "", "name": name, "count": count}


func apply_selected() -> Dictionary:
	var index := preset_option.selected
	var presets: Array = presets_data.get("presets", [])
	if index < 0 or index >= presets.size():
		_flash("先在预设列表选中一套。")
		return {"ok": false, "reason": "未选中预设"}
	var preset: Dictionary = presets[index]
	var result: Dictionary
	if _is_online():
		var reply: Dictionary = await online_request.call("inv.apply_preset", {"preset": preset})
		result = _online_result(reply)
		if result.is_empty():
			return result
	else:
		result = LoadoutPresets.apply(inventory, preset)
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
		var count: int = (preset.get("items", []) as Array).size() + (preset.get("equipment", []) as Array).size()
		preset_option.add_item("%s（%d 件）" % [item_name, count])
		if item_name == select_name:
			select_index = index
	preset_option.selected = select_index


# —— 刷新 ————————————————————————————————————————————————————————


func _refresh() -> void:
	## 快照会整体替换 game.state，长持有的 expedition 绑定会变悬空：每次刷新先重绑。
	inventory.bind(game.state["expedition"])
	workspace.bind_inventory(func() -> InventoryGame: return inventory)
	workspace.busy = pending_placement
	_refresh_stats()
	workspace.refresh(inventory, selected_instance_id)
	_refresh_warehouse()
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
	stats_label.text = "生命上限 %d ｜ 容器已用格 %d/%d ｜ 第 1 回合牌（装备槽）%d 张 ｜ 胸挂/背包后续加入 %d 张 ｜ 携带可售价值 %s ｜ 保险箱保护 %d 金币" % [
		ExpeditionBaseline.MAX_HP, used, total,
		int(preview["totals"][1]), int(preview["totals"][2]) + int(preview["totals"][3]),
		value_text, inventory.protected_value(),
	]


func _refresh_warehouse() -> void:
	var items: Array = inventory.warehouse_list()
	var entries: Array = []
	for instance in items:
		var def := ItemDefs.get_item(str(instance["def_id"]))
		if filter != "all" and str(def["category"]) != filter:
			continue
		entries.append({
			"instance_id": int(instance["instance_id"]),
			"def_id": str(instance["def_id"]),
			"name": ("［演示］" if bool(instance.get("demo", false)) else "") + str(def["name"]),
			"dims": def["size"],
			"art": ExpeditionLootPanel.item_art(str(instance["def_id"])),
			"tint": ItemDefs.quality_color(ItemDefs.quality_of(instance)),
			"tooltip": "%s · %s · %d×%d 格 · %d 张牌\n点选查看，拖到装备槽或容器格。" % [
				def["name"], ItemDefs.quality_name(ItemDefs.quality_of(instance)),
				def["size"].x, def["size"].y, def["cards"].size()],
		})
	warehouse_header.text = "装备／材料仓库 · %d 件" % entries.size()
	warehouse_grid.set_items(entries)


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
	detail_column.add_child(_label("%s%s（%s）" % [demo_mark, def["name"], ItemDefs.quality_name(ItemDefs.quality_of(instance))], 17, FOREST))
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
	detail_column.add_child(_label("当前归属：%s" % _owner_display(str(instance["container"]), instance), 14, TEXT_DARK))
	var desc := _label(str(def.get("desc", "")), 13, TEXT_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(330, 0)
	detail_column.add_child(desc)
	if ExpeditionBaseline.JOIN_ROUND.has(str(instance["container"])):
		put_back_button.visible = true
	if ExpeditionBaseline.CONTAINER_SIZE.has(str(instance["container"])):
		rotate_button.visible = true


func _refresh_deck() -> void:
	for child in deck_column.get_children():
		deck_column.remove_child(child)
		child.queue_free()
	var preview := inventory.deck_preview()
	if int(preview["totals"][1]) + int(preview["totals"][2]) + int(preview["totals"][3]) == 0:
		deck_column.add_child(_label("（装备槽与容器都是空的：放入物品后这里显示会抽到什么牌）", 13, TEXT_MUTED))
		return
	for join_round in [1, 2, 3]:
		var source: String = {"1": "装备槽", "2": "胸挂", "3": "背包"}[str(join_round)]
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
	deck_column.add_child(_label("装备槽牌第 1 回合、胸挂第 2、背包第 3；保险箱的牌永不入堆（死亡时保留）。", 12, TEXT_MUTED))


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


func _owner_display(owner: String, instance := {}) -> String:
	if owner == "warehouse":
		return "装备／材料仓库"
	if owner == "equipped":
		return "%s槽（装备中）" % ExpeditionBaseline.SLOT_DISPLAY.get(str(instance.get("slot", "")), "装备")
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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", maxi(18,size))
	label.add_theme_color_override("font_color", color)
	return label


func _button(content: String, fill: Color, border: Color) -> Button:
	var button := Button.new()
	button.text = content
	button.custom_minimum_size.y = 38
	button.add_theme_color_override("font_color", Color("#35513d"))
	button.add_theme_color_override("font_hover_color", Color("#1f3327"))
	button.add_theme_color_override("font_pressed_color", Color("#1f3327"))
	button.add_theme_color_override("font_disabled_color", Color("#5c6b5e"))
	button.add_theme_font_size_override("font_size", 18)
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
	button.add_theme_font_size_override("font_size", 18)
	return button

func place_item(payload: Dictionary, container: String, cell: Vector2i) -> void:
	if pending_placement:
		return
	pending_placement = true
	workspace.busy = true
	var result: Dictionary
	if _is_online():
		var reply: Dictionary = await online_request.call("inv.place_at",{"instance_id":int(payload["instance_id"]),"container":container,"cell":{"x":cell.x,"y":cell.y},"rotated":bool(payload.get("rotated",false))})
		result = _online_result(reply)
	else:
		result = inventory.place_at(int(payload["instance_id"]),container,cell,bool(payload.get("rotated",false)))
	pending_placement = false
	workspace.busy = false
	if result.is_empty():
		return
	if bool(result.get("ok",false)):
		dirty = true
	_flash("已放入%s。" % ExpeditionBaseline.CONTAINER_DISPLAY[container] if bool(result.get("ok",false)) else str(result.get("reason","放置失败")))
	_refresh()
