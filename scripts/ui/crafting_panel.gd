class_name CraftingPanel
extends Control
## 制作台＋成长看板（2.5 设计 D2.5-03/04/06）。2.1 的制作台占位在此转正。
## 事务全部走 CraftingGame；本面板只展示与转发。出售与整理在装备仓库面板。

signal close_requested
signal save_requested

const FOREST := Color("#294f3c")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const TEXT_MUTED := Color("#3f4a42")
const BAD_RED := Color("#a4543f")
const WARN_GOLD := Color("#9b713a")
const GOOD_GREEN := Color("#3f7048")

var game: FarmGame
var crafting: CraftingGame
## M2：线上命令口（farm_hud.open_crafting 注入；空 Callable = 单机直改本地档）。
var online_request: Callable = Callable()
var status_label: Label
var recipes_column: VBoxContainer
var upgrades_column: VBoxContainer
var goals_column: VBoxContainer
var pending_label: Label
var coins_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var theme_root := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	theme_root.default_font = font
	theme_root.default_font_size = 16
	theme = theme_root
	_build()


func open(target_game: FarmGame) -> void:
	game = target_game
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
	panel.custom_minimum_size = Vector2(1020, 660)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := _label("制作台与成长", 22, FOREST)
	# 标题不换行：autowrap 标签在 HBox 里会被压到一字宽，竖排成单字列并把按钮拉高。
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_row.add_child(title)
	var info := _label("", 14, TEXT_DARK)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(info)
	coins_label = info
	var close_button := _button("返回", Color("#eaf4df"), Color("#87b06f"))
	close_button.pressed.connect(_on_close)
	title_row.add_child(close_button)
	pending_label = _label("", 13, WARN_GOLD)
	pending_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(pending_label)
	status_label = _label("", 13, BAD_RED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	recipes_column = _section(body, "配方（制作立即完成，不占用等待）", 400)
	upgrades_column = _section(body, "设施升级（永久保留）", 280)
	goals_column = _section(body, "成长看板（完成与领奖分开）", 280)


func _section(parent: HBoxContainer, title: String, width: int) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(width, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	box.add_child(_label(title, 15, FOREST))
	return box


func _refresh() -> void:
	## 快照会整体替换 game.state，长持有的绑定会变悬空：每次刷新先重绑（M2 实测坑）。
	crafting.bind(game)
	coins_label.text = "金币 %d ｜ 制作台" % int(game.state["coins"])
	var pending: Array = crafting._crafting().get("pending_items", [])
	if pending.is_empty():
		pending_label.text = "待领取区：空"
	else:
		var names: Array = []
		for entry in pending:
			names.append("%s×%d" % [ItemDefs.get_item(str(entry["def_id"]))["name"], int(entry.get("count", 1))])
		pending_label.text = "待领取区：%s  [领取能放下的部分]" % "、".join(names)
	_refresh_recipes()
	_refresh_upgrades()
	_refresh_goals()


func _refresh_recipes() -> void:
	for child in recipes_column.get_children().slice(1, recipes_column.get_child_count()):
		recipes_column.remove_child(child)
		child.queue_free()
	var counts := crafting.material_counts()
	for recipe_id in CraftingDefs.RECIPES:
		var recipe: Dictionary = CraftingDefs.RECIPES[recipe_id]
		var status := crafting.recipe_status(recipe_id)
		var row := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#f7f1de") if status["can_craft"] else Color("#efe9d8")
		style.set_border_width_all(1)
		style.border_color = Color("#e2e4d4")
		style.set_corner_radius_all(8)
		style.content_margin_left = 10
		style.content_margin_right = 10
		row.add_theme_stylebox_override("panel", style)
		recipes_column.add_child(row)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		row.add_child(column)
		var head := HBoxContainer.new()
		column.add_child(head)
		var title := _label("%s：%s" % [recipe["name"], str(recipe.get("desc", ""))], 14, TEXT_DARK)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.add_child(title)
		if not status["unlocked"]:
			head.add_child(_label("未解锁", 12, TEXT_MUTED))
		else:
			var button := _button("制作", Color("#eaf4df"), Color("#87b06f"))
			button.disabled = not status["can_craft"]
			button.pressed.connect(_on_craft.bind(recipe_id))
			head.add_child(button)
		var materials_text := ""
		for material in recipe["materials"]:
			var key := "%s:%s" % [str(material["kind"]), str(material["id"])]
			var display := str(material["id"])
			if str(material["kind"]) == "crop":
				display = PlantDefs.get_plant(str(material["id"])).get("display_name", str(material["id"]))
			else:
				display = ItemDefs.get_item(str(material["id"])).get("name", display)
			materials_text += "%s %d/%d  " % [display, int(counts.get(key, 0)), int(material["count"])]
		materials_text += "｜ 金币 %d（拥有 %d）" % [int(recipe["coins"]), int(game.state["coins"])]
		var materials := _label(materials_text, 12, TEXT_MUTED)
		materials.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(materials)


func _refresh_upgrades() -> void:
	for child in upgrades_column.get_children().slice(1, upgrades_column.get_child_count()):
		upgrades_column.remove_child(child)
		child.queue_free()
	var unlocked_upgrades: Array = crafting._crafting().get("unlocked_upgrades", [])
	for upgrade_id in CraftingDefs.UPGRADES:
		var upgrade: Dictionary = CraftingDefs.UPGRADES[upgrade_id]
		var gated := str(upgrade["target"]) == "chest"
		if gated and not unlocked_upgrades.has(upgrade_id):
			var gated_note := _label("%s：需先达成「深层材料」目标" % upgrade["desc"], 12, TEXT_MUTED)
			gated_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			upgrades_column.add_child(gated_note)
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := _label(str(upgrade["desc"]), 12, TEXT_DARK)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		var button := _button("升级", Color("#fff5df"), Color("#d5b87d"))
		button.pressed.connect(_on_upgrade.bind(upgrade_id))
		row.add_child(button)
		upgrades_column.add_child(row)
	var pending_button := _button("领取待领取区物品", Color("#ffd98a"), Color("#9b713a"))
	pending_button.pressed.connect(_on_claim_pending)
	upgrades_column.add_child(pending_button)


func _refresh_goals() -> void:
	for child in goals_column.get_children().slice(1, goals_column.get_child_count()):
		goals_column.remove_child(child)
		child.queue_free()
	for goal in crafting.goals_status():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := _label("%s\n%s" % [goal["name"], str(goal["reward_text"])], 12, GOOD_GREEN if goal["done"] else TEXT_MUTED)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		if goal["done"] and not goal["claimed"]:
			var button := _button("领奖", Color("#ffd98a"), Color("#9b713a"))
			button.pressed.connect(_on_claim_goal.bind(str(goal["id"])))
			row.add_child(button)
		elif goal["claimed"]:
			row.add_child(_label("已领", 12, GOOD_GREEN))
		goals_column.add_child(row)


func _on_craft(recipe_id: String) -> void:
	var result: Dictionary
	if _is_online():
		var reply: Dictionary = await online_request.call("craft.craft", {"recipe_id": recipe_id})
		result = _online_result(reply)
		if result.is_empty():
			return
	else:
		result = crafting.craft(recipe_id)
	if result["ok"]:
		var name_text: String = CraftingDefs.RECIPES[recipe_id]["name"]
		status_label.text = "制作了 %s%s。" % [name_text, "（仓库分区已满，进待领取区）" if result["to_pending"] else ""]
		if not _is_online():
			save_requested.emit()
	else:
		status_label.text = result["reason"]
	_refresh()


func _on_upgrade(upgrade_id: String) -> void:
	var result: Dictionary
	if _is_online():
		var reply: Dictionary = await online_request.call("craft.buy_upgrade", {"upgrade_id": upgrade_id})
		result = _online_result(reply)
		if result.is_empty():
			return
	else:
		result = crafting.buy_upgrade(upgrade_id)
	status_label.text = "升级完成，容量/布局立即生效。" if result["ok"] else result["reason"]
	if result["ok"] and not _is_online():
		save_requested.emit()
	_refresh()


func _on_claim_pending() -> void:
	var result: Dictionary
	if _is_online():
		var reply: Dictionary = await online_request.call("craft.claim_pending", {})
		result = _online_result(reply)
		if result.is_empty():
			return
	else:
		result = crafting.claim_pending()
	status_label.text = "领取 %d 件入仓，剩 %d 件待整理。" % [int(result["moved"]), int(result["remaining"])]
	if not _is_online():
		save_requested.emit()
	_refresh()


func _on_claim_goal(goal_id: String) -> void:
	var result: Dictionary
	if _is_online():
		var reply: Dictionary = await online_request.call("craft.claim_goal", {"goal_id": goal_id})
		result = _online_result(reply)
		if result.is_empty():
			return
	else:
		result = crafting.claim_goal(goal_id)
	status_label.text = "奖励已发放（物品入仓或待领取区）。" if result["ok"] else result["reason"]
	if result["ok"] and not _is_online():
		save_requested.emit()
	_refresh()


func _on_close() -> void:
	close_requested.emit()


func _is_online() -> bool:
	return online_request.is_valid()


## 线上应答 → 规则返回值；失败已写状态栏并返回 {}（调用方直接 return）。
func _online_result(reply: Dictionary) -> Dictionary:
	if reply.is_empty():
		status_label.text = "操作未完成：连接中断或超时，稍后重试。"
		return {}
	if str(reply.get("t", "")) == "req_err":
		status_label.text = str(reply.get("msg", "操作失败"))
		return {}
	var result: Variant = reply.get("result", null)
	return result if result is Dictionary else {}


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
	# 默认不换行：autowrap 标签在 HBox 里会被压到一字宽竖排；长文本处显式开启。
	return label


func _button(content: String, fill: Color, border: Color) -> Button:
	var button := Button.new()
	button.text = content
	button.add_theme_color_override("font_color", Color("#35513d"))
	button.add_theme_color_override("font_hover_color", Color("#1f3327"))
	button.add_theme_color_override("font_pressed_color", Color("#1f3327"))
	button.add_theme_color_override("font_disabled_color", Color("#5c6b5e"))
	button.add_theme_font_size_override("font_size", 14)
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 8
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	return button
