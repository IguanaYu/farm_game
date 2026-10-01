class_name ExpeditionMapPanel
extends Control
## 洞窟探索主界面（2.4 设计 D2.4-01~07）：地图、节点内容、搜刮、撤离确认、
## 暂停菜单与结算展示。规则全部走 ExpeditionGame；本面板只展示与转发操作。

signal battle_start_requested(combat: CombatGame)
signal farm_save_requested
signal run_finished

const FOREST := Color("#294f3c")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const TEXT_MUTED := Color("#788678")
const BAD_RED := Color("#a4543f")
const WARN_GOLD := Color("#9b713a")
const GOOD_GREEN := Color("#3f7048")

var expedition: ExpeditionGame
var header_label: Label
var map_column: VBoxContainer
var node_column: VBoxContainer
var log_label: RichTextLabel
var overlay_panel: PanelContainer
var overlay_column: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var theme_root := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	theme_root.default_font = font
	theme_root.default_font_size = 15
	theme = theme_root
	_build()


func open(instance: ExpeditionGame) -> void:
	expedition = instance
	visible = true
	_refresh()


func close() -> void:
	visible = false
	expedition = null


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.12, 0.10, 0.92)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := _panel(Color("#20332a"), Color("#6f9b71"), 16)
	panel.custom_minimum_size = Vector2(1080, 700)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var title := _label("洞窟探索", 22, CREAM)
	title_row.add_child(title)
	var pause_button := _button("☰ 菜单", Color("#fff5df"), Color("#d5b87d"))
	pause_button.pressed.connect(_open_menu)
	title_row.add_child(pause_button)
	header_label = _label("", 15, Color("#e8d9a8"))
	header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titleRow(header_label, title_row)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 4)
	left.custom_minimum_size = Vector2(420, 0)
	body.add_child(left)
	left.add_child(_label("路线（自下向上，不回头）", 14, TEXT_MUTED))
	map_column = VBoxContainer.new()
	map_column.add_theme_constant_override("separation", 6)
	map_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(map_column)

	node_column = VBoxContainer.new()
	node_column.add_theme_constant_override("separation", 6)
	node_column.custom_minimum_size = Vector2(560, 0)
	node_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(node_column)

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = false
	log_label.scroll_following = true
	log_label.custom_minimum_size = Vector2(0, 90)
	log_label.add_theme_font_size_override("normal_font_size", 13)
	log_label.add_theme_color_override("default_color", Color("#cfe2c2"))
	column.add_child(log_label)

	overlay_panel = _panel(CREAM, Color("#d5c9aa"), 14)
	overlay_panel.visible = false
	overlay_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var overlay_center := CenterContainer.new()
	overlay_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_center.add_child(overlay_panel)
	add_child(overlay_center)
	overlay_column = VBoxContainer.new()
	overlay_column.add_theme_constant_override("separation", 8)
	overlay_panel.add_child(overlay_column)


func titleRow(label: Label, row: HBoxContainer) -> void:
	row.add_child(label)


# —— 刷新 ————————————————————————————————————————————————————————


func _refresh() -> void:
	if expedition == null or expedition.run.is_empty():
		return
	var run: Dictionary = expedition.run
	var inventory := expedition.run_inventory()
	var supplies := 0
	for container in ExpeditionBaseline.CONTAINERS:
		for instance in run["inventory"]["loadout"][container]:
			if str(ItemDefs.get_item(str(instance["def_id"])).get("category", "")) == "supply" and int(instance.get("uses_remaining", 1)) > 0:
				supplies += 1
	header_label.text = "%s ｜ 第 %d/%d 排 ｜ 生命 %d/%d ｜ 补给 %d ｜ 携带可售 %d 金币 ｜ 保护区 %d 金币" % [
		ExpeditionDefs.layer(str(run["layer_id"])).get("name", "?"),
		int(run["current"]["row"]), int(ExpeditionDefs.layer(str(run["layer_id"])).get("rows", 9)) - 1,
		int(run["player"]["hp"]), int(run["player"]["max_hp"]),
		supplies, inventory.carry_sell_value(), inventory.protected_value()]
	_refresh_map()
	_refresh_node()
	var entries: Array = run.get("log", [])
	log_label.text = "\n".join(entries.slice(maxi(0, entries.size() - 8), entries.size()))


func _refresh_map() -> void:
	for child in map_column.get_children():
		map_column.remove_child(child)
		child.queue_free()
	var run: Dictionary = expedition.run
	var rows: Array = run["map"]["rows"]
	var current_row := int(run["current"]["row"])
	for row_index in range(rows.size() - 1, -1, -1):
		var row_box := HBoxContainer.new()
		row_box.add_theme_constant_override("separation", 8)
		map_column.add_child(row_box)
		var row_label := _label("第 %d 排" % row_index, 13, TEXT_MUTED)
		row_label.custom_minimum_size = Vector2(52, 0)
		row_box.add_child(row_label)
		for col_index in range(rows[row_index].size()):
			var node: Dictionary = rows[row_index][col_index]
			var key := expedition.node_id(row_index, col_index)
			var resolved: Dictionary = run["resolved"].get(key, {})
			var button := Button.new()
			var mark := ""
			if bool(resolved.get("completed", false)):
				mark = "✓"
			if row_index == current_row:
				mark += "▶"
			button.text = "%s%s" % [mark, ExpeditionDefs.NODE_TYPE_DISPLAY.get(str(node["type"]), "?")]
			button.tooltip_text = "风险：%s ｜ %s" % [str(node.get("risk", "?")), str(node.get("hint", ""))]
			button.add_theme_font_size_override("font_size", 14)
			var fill := Color("#3a4a3c") if row_index != current_row else Color("#5d7a55")
			if str(node.get("risk", "")) == "high":
				fill = Color("#6b3f35")
			if row_index == current_row:
				fill = Color("#6d8f5d")
			var style := _style(fill, Color("#9db894"), 8)
			style.content_margin_left = 8
			style.content_margin_right = 8
			button.add_theme_stylebox_override("normal", style)
			button.add_theme_stylebox_override("hover", style)
			button.add_theme_stylebox_override("pressed", style)
			button.disabled = row_index != current_row + 1 or str(run["phase"]) != "map"
			button.pressed.connect(_on_move.bind(row_index, col_index))
			row_box.add_child(button)


func _refresh_node() -> void:
	for child in node_column.get_children():
		node_column.remove_child(child)
		child.queue_free()
	var run: Dictionary = expedition.run
	if str(run["phase"]) == "map":
		node_column.add_child(_label("选择下一排的节点继续前进。", 15, Color("#cfe2c2")))
		return
	var node := expedition.current_node()
	if node.is_empty():
		return
	var key := expedition.node_id(int(run["current"]["row"]), int(run["current"]["col"]))
	var resolved: Dictionary = run["resolved"].get(key, {})
	var title := _label("当前位置：%s（%s）" % [ExpeditionDefs.NODE_TYPE_DISPLAY.get(str(node["type"]), "?"), str(node.get("hint", ""))], 17, CREAM)
	node_column.add_child(title)
	match str(node["type"]):
		"start":
			node_column.add_child(_label("检查配装后出发。", 14, Color("#cfe2c2")))
		"battle", "elite", "gate":
			_refresh_battle_node(node, resolved, key)
		"gather", "chest":
			_refresh_reward_node(node, resolved, key)
		"event":
			_refresh_event_node(resolved, key)
		"rest_exit":
			_refresh_rest_node(resolved, key)
		"exit":
			node_column.add_child(_label("撤离站：可以带着现有收获回家，或继续深入。", 14, Color("#cfe2c2")))


func _refresh_battle_node(node: Dictionary, resolved: Dictionary, key: String) -> void:
	var run: Dictionary = expedition.run
	if not bool(resolved.get("battle_won", false)):
		var warn := str(node.get("risk", "")) == "high"
		node_column.add_child(_label("高风险：偏向装备与稀有资源，奖励候选更好但不保证都能带走。" if warn else "浅层敌人组合。", 14, BAD_RED if warn else TEXT_MUTED))
		var fight := _button("进入战斗", Color("#ffd98a"), Color("#9b713a"))
		fight.pressed.connect(_on_start_battle)
		node_column.add_child(fight)
		return
	_refresh_rewards_area(resolved, key, true)


func _refresh_reward_node(_node: Dictionary, resolved: Dictionary, key: String) -> void:
	node_column.add_child(_label("候选物品（带走需要空间，离开时未带走的放弃）：", 14, TEXT_MUTED))
	_refresh_rewards_area(resolved, key, false)


func _refresh_rewards_area(resolved: Dictionary, key: String, choose_one: bool) -> void:
	## choose_one：普通战斗个人奖励二选一（选中后另一件消失）；宝箱/采集全部可领。
	var run: Dictionary = expedition.run
	var inventory := expedition.run_inventory()
	var rewards: Array = resolved.get("rewards", [])
	var public_items: Array = resolved.get("public", [])
	var chosen := str(resolved.get("personal_choice", ""))
	if choose_one and chosen != "":
		rewards = [chosen]
	for def_id in rewards:
		var def := ItemDefs.get_item(str(def_id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var info := _label("%s（%d×%d，%d 张牌，%s）" % [def["name"], def["size"].x, def["size"].y, def["cards"].size(),
			"可售 %d 金币" % int(def.get("base_value", 0)) if bool(def.get("sellable", false)) else "不可售"], 14, TEXT_DARK)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var claim_pack := _button("放入背包", Color("#eaf4df"), Color("#87b06f"))
		claim_pack.pressed.connect(_on_claim_reward.bind(key, str(def_id), "pack", choose_one))
		row.add_child(claim_pack)
		if bool(def.get("safe_allowed", false)):
			var claim_safe := _button("放保险箱", Color("#fff5df"), Color("#d5b87d"))
			claim_safe.pressed.connect(_on_claim_reward.bind(key, str(def_id), "safe", choose_one))
			row.add_child(claim_safe)
		node_column.add_child(row)
	if not public_items.is_empty():
		node_column.add_child(_label("公共物资（不占个人选择次数）：", 13, TEXT_MUTED))
		for def_id in public_items:
			var def := ItemDefs.get_item(str(def_id))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var info := _label("%s" % def["name"], 14, TEXT_DARK)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			var claim := _button("领取", Color("#eaf4df"), Color("#87b06f"))
			claim.pressed.connect(_on_claim_public.bind(key, str(def_id)))
			row.add_child(claim)
			node_column.add_child(row)
	if not run["node_drops"].is_empty():
		node_column.add_child(_label("本节点丢弃区（离开后不可捡回）：", 13, WARN_GOLD))
		for instance in run["node_drops"]:
			var def := ItemDefs.get_item(str(instance["def_id"]))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var info := _label("%s（丢弃物）" % def["name"], 13, TEXT_MUTED)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			var pick := _button("捡回", Color("#fff5df"), Color("#d5b87d"))
			pick.pressed.connect(_on_pick_drop.bind(int(instance["instance_id"])))
			row.add_child(pick)
			node_column.add_child(row)
	var leave := _button("完成并离开本节点", Color("#ffd98a"), Color("#9b713a"))
	leave.pressed.connect(_on_leave_node)
	node_column.add_child(leave)


func _refresh_event_node(resolved: Dictionary, _key: String) -> void:
	var event: Dictionary = ExpeditionDefs.EVENTS.get(str(resolved.get("event_id", "")), {})
	if event.is_empty():
		node_column.add_child(_label("（这里很安静）", 14, TEXT_MUTED))
		return
	node_column.add_child(_label("事件：%s" % event["name"], 16, CREAM))
	node_column.add_child(_label(str(event["desc"]), 14, Color("#cfe2c2")))
	if bool(resolved.get("completed", false)):
		node_column.add_child(_label("已选择：%s（结果已固定）" % str(resolved.get("chosen_option", "")), 13, GOOD_GREEN))
		var leave := _button("完成并离开本节点", Color("#ffd98a"), Color("#9b713a"))
		leave.pressed.connect(_on_leave_node)
		node_column.add_child(leave)
		return
	for option in event.get("options", []):
		var button := _button(str(option["label"]), Color("#fff5df"), Color("#d5b87d"))
		button.pressed.connect(_on_choose_event.bind(str(option["id"])))
		node_column.add_child(button)


func _refresh_rest_node(resolved: Dictionary, _key: String) -> void:
	var run: Dictionary = expedition.run
	if not bool(resolved.get("rest_taken", false)):
		node_column.add_child(_label("免费小休整（二选一，确认后不能切换）：", 14, TEXT_MUTED))
		var heal := _button("休息：恢复 8 生命", Color("#eaf4df"), Color("#87b06f"))
		heal.pressed.connect(_on_rest.bind("heal"))
		node_column.add_child(heal)
		var prepare := _button("检查装备：下一场首回合多抽 1 张", Color("#fff5df"), Color("#d5b87d"))
		prepare.pressed.connect(_on_rest.bind("prepare"))
		node_column.add_child(prepare)
	else:
		node_column.add_child(_label("休整已完成。", 13, TEXT_MUTED))
	var extract := _button("在此撤离（带着收获回家）", Color("#ffd98a"), Color("#9b713a"))
	extract.pressed.connect(_open_extract_confirm)
	node_column.add_child(extract)
	var leave := _button("继续深入", Color("#eaf4df"), Color("#87b06f"))
	leave.pressed.connect(_on_leave_node)
	node_column.add_child(leave)


# —— 操作 ————————————————————————————————————————————————————————


func _on_move(row: int, col: int) -> void:
	var result := expedition.move_to(row, col)
	if not result["ok"]:
		_flash_overlay(result["reason"])
	_refresh()


func _on_start_battle() -> void:
	var result := expedition.start_battle()
	if not result["ok"]:
		_flash_overlay(result["reason"])
		return
	battle_start_requested.emit(result["combat"])


func battle_finished() -> void:
	## battle_screen 关闭后由外部调用：结算战斗并回到节点或显示结算。
	var result := expedition.finish_battle(expedition_battle_result)
	if not result["ok"]:
		_flash_overlay(result["reason"])
		_refresh()
		return
	if result.get("settlement", {}).has("settlement_id"):
		_show_settlement(result["settlement"])
	else:
		_refresh()


var expedition_battle_result: CombatGame


func report_battle_result(combat: CombatGame) -> void:
	expedition_battle_result = combat


func _on_claim_reward(key: String, def_id: String, container: String, choose_one: bool) -> void:
	var run: Dictionary = expedition.run
	var resolved: Dictionary = run["resolved"].get(key, {})
	var inventory := expedition.run_inventory()
	if choose_one:
		resolved["personal_choice"] = def_id
		run["resolved"][key] = resolved
	var result := inventory.claim_reward(def_id, container)
	if not result["ok"]:
		_flash_overlay(result["reason"])
		expedition.save()
		_refresh()
		return
	if choose_one:
		resolved["rewards"] = [def_id]
		run["resolved"][key] = resolved
	expedition.save()
	_refresh()


func _on_claim_public(key: String, def_id: String) -> void:
	var run: Dictionary = expedition.run
	var resolved: Dictionary = run["resolved"].get(key, {})
	var inventory := expedition.run_inventory()
	var result := inventory.claim_reward(def_id, "pack")
	if result["ok"]:
		resolved["public"] = []
		run["resolved"][key] = resolved
		expedition.save()
	else:
		_flash_overlay(result["reason"])
	_refresh()


func _on_pick_drop(instance_id: int) -> void:
	## 从节点公共区捡回：直接放回局内仓库（玩家再自行整理）。
	var run: Dictionary = expedition.run
	var inventory := expedition.run_inventory()
	var target := {}
	for instance in run["node_drops"]:
		if int(instance["instance_id"]) == instance_id:
			target = instance
	if target.is_empty():
		return
	run["node_drops"].erase(target)
	target["container"] = "warehouse"
	target["cell"] = [0, 0]
	run["inventory"]["warehouse"].append(target)
	expedition.save()
	_refresh()


func _on_leave_node() -> void:
	var run: Dictionary = expedition.run
	var resolved: Dictionary = run["resolved"].get(expedition.node_id(int(run["current"]["row"]), int(run["current"]["col"])), {})
	var pending := int(resolved.get("rewards", []).size()) + int(resolved.get("public", []).size())
	if pending > 0 or not run["node_drops"].is_empty():
		_confirm_overlay("还有 %d 件候选/公共物品未领取，离开后将放弃。确认离开？" % (pending + run["node_drops"].size()), func() -> void:
			var result := expedition.leave_node()
			if not result["ok"]:
				_flash_overlay(result["reason"])
			elif result.get("settlement", {}).has("settlement_id"):
				_show_settlement(result["settlement"])
			else:
				_refresh()
		)
		return
	var result := expedition.leave_node()
	if not result["ok"]:
		_flash_overlay(result["reason"])
	elif result.get("settlement", {}).has("settlement_id"):
		_show_settlement(result["settlement"])
	else:
		_refresh()


func _on_choose_event(option_id: String) -> void:
	var result := expedition.choose_event(option_id)
	if not result["ok"]:
		_flash_overlay(result["reason"])
	_refresh()


func _on_rest(option: String) -> void:
	var result := expedition.take_rest(option)
	if not result["ok"]:
		_flash_overlay(result["reason"])
	_refresh()


func _open_extract_confirm() -> void:
	## 撤离决策页（设计 D2.4-06）：已获得分组展示 + 三个按钮。
	var run: Dictionary = expedition.run
	var inventory := expedition.run_inventory()
	var carried: Array = run["carried_from_farm"]
	var brought := 0
	var brought_value := 0
	var gained := 0
	var gained_value := 0
	var protected_value := 0
	for instance in inventory.all_instances():
		if int(instance.get("uses_remaining", 1)) <= 0:
			continue
		var def := ItemDefs.get_item(str(instance["def_id"]))
		var value := int(def.get("base_value", 0)) if bool(def.get("sellable", false)) else 0
		if str(instance.get("container", "")) == "safe":
			protected_value += value
			continue
		if int(instance["instance_id"]) in carried:
			brought += 1
			brought_value += value
		else:
			gained += 1
			gained_value += value
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.add_child(_label("撤离决策", 20, FOREST))
	column.add_child(_label("带入旧装备：%d 件（可售 %d 金币）——返回时按\"释放占用\"处理，不重复发放" % [brought, brought_value], 14, TEXT_DARK))
	column.add_child(_label("新增战利品：%d 件（可售 %d 金币）——回家入库后自行出售" % [gained, gained_value], 14, TEXT_DARK))
	column.add_child(_label("保护区（保险箱，失败也保留）：%d 金币" % protected_value, 14, GOOD_GREEN))
	column.add_child(_label("当前生命 %d/%d；下一段风险更高、资源倾向更好。" % [int(run["player"]["hp"]), int(run["player"]["max_hp"])], 13, TEXT_MUTED))
	var go_home := _button("带着这些回家", Color("#ffd98a"), Color("#9b713a"))
	go_home.pressed.connect(func() -> void:
		_close_overlay()
		var result := expedition.extract()
		if result["ok"]:
			_show_settlement(result["settlement"])
		else:
			_flash_overlay(result["reason"])
	)
	column.add_child(go_home)
	var go_deep := _button("继续深入", Color("#eaf4df"), Color("#87b06f"))
	go_deep.pressed.connect(func() -> void:
		_close_overlay()
		var leave_result := expedition.leave_node()
		if not leave_result["ok"]:
			_flash_overlay(leave_result["reason"])
		_refresh()
	)
	column.add_child(go_deep)
	var back := _button("返回整理", Color("#fff5df"), Color("#d5b87d"))
	back.pressed.connect(_close_overlay)
	column.add_child(back)
	_show_overlay(column)


func _open_menu() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.add_child(_label("暂停菜单", 20, FOREST))
	var resume := _button("继续探险", Color("#eaf4df"), Color("#87b06f"))
	resume.pressed.connect(_close_overlay)
	column.add_child(resume)
	var back_farm := _button("返回农场并暂停（本局保留，可随时继续）", Color("#fff5df"), Color("#d5b87d"))
	back_farm.pressed.connect(func() -> void:
		expedition.save()
		_close_overlay()
		close()
		farm_save_requested.emit()
	)
	column.add_child(back_farm)
	var inventory := expedition.run_inventory()
	var unprotected := []
	for instance in inventory.all_instances():
		if str(instance.get("container", "")) != "safe" and int(instance.get("uses_remaining", 1)) > 0:
			unprotected.append(str(ItemDefs.get_item(str(instance["def_id"]))["name"]))
	var abandon := _button("主动放弃（损失全部未保护携带物）", Color("#f0d9cf"), Color("#a4543f"))
	abandon.pressed.connect(func() -> void:
		_close_overlay()
		_confirm_overlay("放弃将失去：%s。保险箱内物品保留。确认放弃？" % ("、".join(unprotected) if not unprotected.is_empty() else "（没有未保护携带物）"), func() -> void:
			var result := expedition.abandon()
			if result["ok"]:
				_show_settlement(result["settlement"])
			else:
				_flash_overlay(result["reason"])
		)
	)
	column.add_child(abandon)
	_show_overlay(column)


func _show_settlement(settlement: Dictionary) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	var kind_text := {"extract": "成功撤离回家", "gate_clear": "击败守门战，第一层通关", "death": "战斗失败……", "abandon": "已放弃本次探险"}
	column.add_child(_label(kind_text.get(str(settlement["kind"]), str(settlement["kind"])), 20, FOREST))
	for group in [["returned", "返还带入物品"], ["gained", "新增获得"], ["protected", "保险箱保留"], ["lost", "损失"], ["consumed", "已消耗补给"]]:
		var entries: Array = settlement.get(group[0], [])
		if entries.is_empty():
			continue
		if group[0] == "consumed":
			column.add_child(_label("%s：%d 件" % [group[1], entries.size()], 13, TEXT_MUTED))
			continue
		var names: Array = []
		for entry in entries:
			names.append(str(entry["name"]))
		column.add_child(_label("%s（%d）：%s" % [group[1], entries.size(), "、".join(names)], 14, TEXT_DARK if group[0] != "lost" else BAD_RED))
	column.add_child(_label("货物仍是货物，回家后自行出售才变金币。", 12, TEXT_MUTED))
	var done := _button("确认回家", Color("#eaf4df"), Color("#87b06f"))
	done.pressed.connect(func() -> void:
		_close_overlay()
		close()
		run_finished.emit()
		farm_save_requested.emit()
	)
	column.add_child(done)
	_show_overlay(column)


# —— 覆盖层 ————————————————————————————————————————————————


func _show_overlay(content: Control) -> void:
	for child in overlay_column.get_children():
		overlay_column.remove_child(child)
		child.queue_free()
	overlay_column.add_child(content)
	overlay_panel.visible = true


func _close_overlay() -> void:
	overlay_panel.visible = false


func _confirm_overlay(message: String, on_yes: Callable) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.add_child(_label(message, 15, TEXT_DARK))
	var yes := _button("确认", Color("#ffd98a"), Color("#9b713a"))
	yes.pressed.connect(func() -> void:
		_close_overlay()
		on_yes.call()
	)
	column.add_child(yes)
	var no := _button("再想想", Color("#fff5df"), Color("#d5b87d"))
	no.pressed.connect(_close_overlay)
	column.add_child(no)
	_show_overlay(column)


func _flash_overlay(message: String) -> void:
	var column := VBoxContainer.new()
	column.add_child(_label(message, 15, BAD_RED))
	var ok := _button("知道了", Color("#fff5df"), Color("#d5b87d"))
	ok.pressed.connect(_close_overlay)
	column.add_child(ok)
	_show_overlay(column)


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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(content: String, fill: Color, border: Color) -> Button:
	var button := Button.new()
	button.text = content
	button.add_theme_font_size_override("font_size", 15)
	var style := _style(fill, border, 12)
	style.content_margin_left = 10
	style.content_margin_right = 10
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	return button
