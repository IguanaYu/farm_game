class_name ExpeditionLootPanel
extends Control
## 战后搜刮台：只读快照，全部领取/摆放/丢弃意图由 ExpeditionGame 或主机裁定。

signal menu_requested
var action_sink: Callable
var input_blocked: Callable
var run: Dictionary = {}
var player_key := "p1"
var selected_token := ""
var current_container := "pack"
var pending_action := false
var pending_action_id := ""
var pending_acknowledged := false
var pending_serial := -1
var pending_selected_id := -1
var snapshot_serial := -1
var screen_identity := ""
var action_message := ""
var action_sound := "ui_click"
var filter_index := 0
var sort_value := false
var entries: Array = []
var inventory: InventoryGame
var title_label: Label
var summary_label: Label
var rule_label: Label
var list_column: VBoxContainer
var detail_column: VBoxContainer
var bag_column: VBoxContainer
var feedback_label: Label
var count_label: Label
var leave_button: Button
var grid: ExpeditionLootGrid
var container_buttons: Dictionary = {}
var filter_buttons: Array[Button] = []
var modal: CenterContainer
var modal_content: VBoxContainer
var modal_shade: ColorRect
var workspace_frame: Control
var battlefield: CorpseLootStage
var return_button: Button
var search_source := ""
var search_region := ""
var scene_mode := true
var source_grid: CorpseSearchGrid
var source_grids: Dictionary = {}
var region_buttons: Dictionary = {}
var search_layout_key := ""
var render_after_drag := false
var ground_drops: VBoxContainer
var search_deadline := 0
var search_step := ""
var search_retry_at := 0
var leave_after_cancel := false
var revealed_seen: Dictionary = {}
var filters_container: Control
var sort_control: Control
var loot_heading: Label
var stop_search_pending := false

class LootButton extends Button:
	var loot_owner: Control
	var token := ""
	func _get_drag_data(_at_position: Vector2) -> Variant:
		var payload: Dictionary = loot_owner.drag_payload(token)
		if payload.is_empty():
			return null
		set_drag_preview(loot_owner.drag_preview(payload))
		return payload

static func is_loot_phase(snapshot: Dictionary) -> bool:
	if str(snapshot.get("phase", "")) != "node":
		return false
	var current: Dictionary = snapshot.get("current", {})
	var rows: Array = snapshot.get("map", {}).get("rows", [])
	var row := int(current.get("row", -1))
	var col := int(current.get("col", -1))
	if row < 0 or row >= rows.size() or col < 0 or col >= rows[row].size():
		return false
	var type := str(rows[row][col].get("type", ""))
	if type in ["gather", "chest"]:
		return true
	return type in ["battle", "elite", "gate"] and bool(snapshot.get("resolved", {}).get("r%dc%d" % [row, col], {}).get("battle_won", false))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = ExpeditionUI.make_theme()
	visible = false
	_build()

func _build() -> void:
	ExpeditionUI.backdrop(self)
	var frame := ExpeditionUI.frame(self, 24)
	workspace_frame = frame
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	frame.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	column.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(ExpeditionUI.label("EXPEDITION  /  FIELD SALVAGE", 12, ExpeditionUI.GOLD))
	title_label = ExpeditionUI.label("战场搜刮", 30)
	titles.add_child(title_label)
	summary_label = ExpeditionUI.label("", 15, ExpeditionUI.TEAL)
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(summary_label)
	return_button = ExpeditionUI.button("← 返回战场")
	return_button.pressed.connect(_return_to_battlefield)
	header.add_child(return_button)
	var menu := ExpeditionUI.button("☰  菜单")
	menu.pressed.connect(_open_menu)
	header.add_child(menu)
	rule_label = _wrapped("", 15, ExpeditionUI.MUTED)
	column.add_child(rule_label)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	column.add_child(body)
	var loot := _section(body, 1.0)
	loot_heading = ExpeditionUI.label("01  现场战利品", 19, ExpeditionUI.PAPER)
	loot.add_child(loot_heading)
	var filters := HBoxContainer.new()
	filters_container = filters
	filters.add_theme_constant_override("separation", 5)
	loot.add_child(filters)
	for i in range(3):
		var button := ExpeditionUI.button(["全部", "装备 / 补给", "材料 / 货物"][i])
		button.custom_minimum_size.y = 34
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(func() -> void: filter_index = i; _render_list())
		filters.add_child(button)
		filter_buttons.append(button)
	var sort_button := ExpeditionUI.button("按每格售价排序  ⇅")
	sort_control = sort_button
	sort_button.custom_minimum_size.y = 30
	sort_button.add_theme_font_size_override("font_size", 12)
	sort_button.pressed.connect(func() -> void:
		sort_value = not sort_value
		sort_button.text = "恢复发现顺序  ⇅" if sort_value else "按每格售价排序  ⇅"
		_render_list())
	loot.add_child(sort_button)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loot.add_child(scroll)
	list_column = VBoxContainer.new()
	list_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_column.add_theme_constant_override("separation", 10)
	scroll.add_child(list_column)
	count_label = _wrapped("", 13, ExpeditionUI.MUTED)
	loot.add_child(count_label)
	var detail := _section(body, 1.08)
	detail.add_child(ExpeditionUI.label("02  值不值得带", 19, ExpeditionUI.PAPER))
	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(detail_scroll)
	detail_column = VBoxContainer.new()
	detail_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_column.add_theme_constant_override("separation", 12)
	detail_scroll.add_child(detail_column)
	var bag := _section(body, 1.04)
	bag.add_child(ExpeditionUI.label("03  整理与装包", 19, ExpeditionUI.PAPER))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	bag.add_child(tabs)
	for container in ["chest", "pack", "safe"]:
		var button := ExpeditionUI.button(ExpeditionBaseline.CONTAINER_DISPLAY[container])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: current_container = container; _render_bag(); _render_detail())
		tabs.add_child(button)
		container_buttons[container] = button
	var bag_scroll := ScrollContainer.new()
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag.add_child(bag_scroll)
	bag_column = VBoxContainer.new()
	bag_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_column.add_theme_constant_override("separation", 12)
	bag_scroll.add_child(bag_column)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 20)
	column.add_child(footer)
	feedback_label = _wrapped("点选比较，拖入格子；拖动时按 R 旋转。", 14, ExpeditionUI.MUTED)
	feedback_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(feedback_label)
	leave_button = ExpeditionUI.button("完成搜刮，离开本节点 →", true)
	leave_button.custom_minimum_size = Vector2(275, 50)
	leave_button.pressed.connect(_confirm_leave)
	footer.add_child(leave_button)
	battlefield = CorpseLootStage.new()
	battlefield.loot_owner = self
	battlefield.corpse_selected.connect(_open_corpse)
	battlefield.leave_requested.connect(_confirm_leave)
	battlefield.menu_requested.connect(_open_menu)
	add_child(battlefield)
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0.02, 0.05, 0.07, 0.8)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_shade.visible = false
	add_child(modal_shade)
	modal = CenterContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.visible = false
	add_child(modal)
	var modal_panel := ExpeditionUI.panel(ExpeditionUI.PANEL, ExpeditionUI.GOLD, 24)
	modal_panel.custom_minimum_size.x = 490
	modal.add_child(modal_panel)
	modal_content = VBoxContainer.new()
	modal_content.add_theme_constant_override("separation", 15)
	modal_panel.add_child(modal_content)

func _section(parent: Control, ratio: float) -> VBoxContainer:
	var panel := ExpeditionUI.panel(Color("#1b2d35ed"), ExpeditionUI.LINE, 18)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	return column

func _wrapped(content: String, font_size: int, color: Color) -> Label:
	var label := ExpeditionUI.label(content, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func display(snapshot: Dictionary, member_key := "p1", serial := -1) -> void:
	var next := str(snapshot.get("run_id", "")) + _node_key(snapshot)
	if screen_identity != next:
		scene_mode = true
		search_source = ""
		search_region = ""
		search_step = ""
		leave_after_cancel = false
		stop_search_pending = false
		revealed_seen.clear()
		screen_identity = next
		selected_token = ""
		current_container = "pack"
		filter_index = 0
		pending_action = false
		pending_action_id = ""
		pending_acknowledged = false
		pending_selected_id = -1
		_close_modal()
		feedback_label.text = "点选比较，拖入格子；拖动时按 R 旋转。"
		feedback_label.add_theme_color_override("font_color", ExpeditionUI.MUTED)
	run = snapshot
	player_key = member_key
	snapshot_serial = serial
	visible = is_loot_phase(run)
	if not visible:
		return
	var corpses: Array = _resolved().get("corpses", [])
	var searchable := not corpses.is_empty()
	filters_container.visible = not searchable
	sort_control.visible = not searchable
	loot_heading.text = "01  搜索尸体与背包" if searchable else "01  现场战利品"
	return_button.visible = searchable
	battlefield.visible = searchable and scene_mode
	workspace_frame.visible = not battlefield.visible
	if searchable:
		battlefield.display(run, corpses)
		var session: Dictionary = run.get("loot_searches", {}).get(player_key, {})
		if str(session.get("step", "")) != search_step:
			search_step = str(session.get("step", ""))
			search_deadline = Time.get_ticks_msec() + int(session.get("remaining", 0)) + 60
		else:
			search_deadline = mini(search_deadline, Time.get_ticks_msec() + int(session.get("remaining", 0)) + 60)
	if pending_acknowledged and snapshot_serial > pending_serial:
		pending_action = false
		pending_acknowledged = false
		if pending_selected_id >= 0:
			selected_token = "carried:%d" % pending_selected_id
			pending_selected_id = -1
	inventory = InventoryGame.new()
	inventory.bind({"inventory": _member_inventory()})
	_build_entries()
	if _entry(selected_token).is_empty():
		selected_token = ""
		for entry in entries:
			if bool(entry.get("available", false)) and (not searchable or (str(entry["kind"]) == "claim_corpse" and str(entry.get("source_id", "")) == search_source and str(entry.get("region_id", "")) == search_region)):
				selected_token = str(entry["token"])
				break
		if selected_token == "" and not entries.is_empty() and not searchable:
			selected_token = str(entries[0]["token"])
	var type := str(_node().get("type", ""))
	title_label.text = {"chest": "打开宝箱", "gather": "采集与搜刮"}.get(type, "战场搜刮 · 战斗胜利")
	var player: Dictionary = run.get("guest", {}) if player_key == "p2" else run.get("player", {})
	summary_label.text = "生命 %d / %d     深度 %02d\n携带售价 %d 金币  ·  已保护 %d 件" % [int(player.get("hp", 0)), int(player.get("max_hp", 40)), int(run["current"]["row"]), inventory.carry_sell_value(), inventory.loadout_list("safe").size()]
	rule_label.text = ("个人战利品任选一件，装入成功才锁定选择。" if _choose_one() else "这里的个人物资都可领取，能带多少取决于你的空间。") + ("公共物资全队一份，先领取者获得。" if bool(run.get("coop", false)) else "公共物资不占个人选择次数。")
	if searchable:
		rule_label.text = "打开尸体后自动按顺序搜索全部区域；空格无需搜索，品质越高搜索越久。已发现的物品可直接装包。" + ("尸体物资全队一份。" if bool(run.get("coop", false)) else "")
	if get_viewport().gui_is_dragging():
		render_after_drag = true
		return
	_render_list()
	_render_detail()
	_render_bag()
	leave_button.disabled = pending_action

func _node_key(snapshot: Dictionary) -> String:
	var current: Dictionary = snapshot.get("current", {})
	return "r%dc%d" % [int(current.get("row", -1)), int(current.get("col", -1))]

func _node() -> Dictionary:
	return run["map"]["rows"][int(run["current"]["row"])][int(run["current"]["col"])]

func _resolved() -> Dictionary:
	return run.get("resolved", {}).get(_node_key(run), {})

func _choose_one() -> bool:
	return bool(_resolved().get("choose_one", str(_node().get("type", "")) in ["battle", "elite", "gate"]))

func _member_inventory() -> Dictionary:
	return run.get("guest", {}).get("inventory", {}) if player_key == "p2" else run.get("inventory", {})

func _build_entries() -> void:
	entries.clear()
	var resolved := _resolved()
	for source in resolved.get("corpses", []):
		for region in source["regions"]:
			for item in region["items"]:
				if bool(item.get("revealed", false)) and not bool(item.get("taken", false)):
					var id := int(item["instance_id"])
					if not revealed_seen.has(id):
						revealed_seen[id] = true
						AudioKit.play(self, "open", -12)
					entries.append({"token": "corpse:%d" % int(item["instance_id"]), "def_id": item["def_id"], "instance_id": int(item["instance_id"]), "kind": "claim_corpse", "source_id": source["id"], "region_id": region["id"], "source": "%s · %s" % [source["name"], region["name"]], "available": true, "state": "已发现 · 可装包", "instance": item})
	var mine: Array = resolved.get("claimed", {}).get(player_key, [])
	var locked := _choose_one() and not mine.is_empty()
	for id in resolved.get("rewards", []):
		entries.append({"token": "reward:" + str(id), "def_id": str(id), "kind": "claim_reward", "source": "个人选择" if _choose_one() else "个人物资", "available": not locked and not mine.has(str(id)), "state": "已领取" if mine.has(str(id)) else ("已放弃 · 选择锁定" if locked else "待搜刮")})
	for id in resolved.get("public", []):
		entries.append({"token": "public:" + str(id), "def_id": str(id), "kind": "claim_public", "source": "公共物资 · 全队一份" if bool(run.get("coop", false)) else "额外物资", "available": true, "state": "待搜刮"})
	for instance in run.get("node_drops", []):
		var permitted := not ItemDefs.is_basic(str(instance["def_id"])) or str(instance.get("drop_owner", player_key)) == player_key
		entries.append({"token": "drop:%d" % int(instance["instance_id"]), "def_id": instance["def_id"], "instance_id": int(instance["instance_id"]), "kind": "pick_drop", "source": "现场丢弃 · 离开前可捡回", "available": permitted, "state": "可捡回" if permitted else "队友的基础装备", "instance": instance})
	for instance in inventory.all_instances():
		entries.append({"token": "carried:%d" % int(instance["instance_id"]), "def_id": instance["def_id"], "instance_id": int(instance["instance_id"]), "kind": "loot_manage", "source": ExpeditionBaseline.CONTAINER_DISPLAY.get(str(instance.get("container", "")), "携带物品"), "available": true, "state": "已携带", "instance": instance})

func _entry(token: String) -> Dictionary:
	for entry in entries:
		if str(entry["token"]) == token:
			return entry
	return {}

func select_item(token: String) -> void:
	if pending_action or modal.visible:
		return
	selected_token = token
	AudioKit.play(self, "ui_click", -8)
	if _resolved().has("corpses"):
		for region_grid in source_grids.values():
			if is_instance_valid(region_grid):
				region_grid.queue_redraw()
	else:
		_render_list()
	_render_detail()
	# 选择不重建网格，以免销毁拖动源。
	if is_instance_valid(grid):
		grid.selected_id = int(_entry(token).get("instance_id", -1)) if token.begins_with("carried:") else -1
		grid.queue_redraw()

func _render_list() -> void:
	if _resolved().has("corpses"):
		_render_search()
		return
	search_layout_key = ""
	source_grids.clear()
	region_buttons.clear()
	ExpeditionUI.clear(list_column)
	for i in range(filter_buttons.size()):
		ExpeditionUI.decorate_button(filter_buttons[i], i == filter_index)
	var visible_entries: Array = []
	for entry in entries:
		if str(entry["kind"]) == "loot_manage":
			continue
		var category := str(ItemDefs.get_item(str(entry["def_id"])).get("category", ""))
		if filter_index == 1 and not category in ["weapon", "armor", "tool", "supply"]:
			continue
		if filter_index == 2 and category in ["weapon", "armor", "tool", "supply"]:
			continue
		visible_entries.append(entry)
	if sort_value:
		visible_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _value_per_cell(str(a["def_id"])) > _value_per_cell(str(b["def_id"])))
	for entry in visible_entries:
		var def := ItemDefs.get_item(str(entry["def_id"]))
		var selected := str(entry["token"]) == selected_token
		var available := bool(entry["available"])
		var button := LootButton.new()
		button.loot_owner = self
		button.token = str(entry["token"])
		button.custom_minimum_size.y = 132
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ExpeditionUI.decorate_button(button)
		button.add_theme_stylebox_override("normal", ExpeditionUI.style(Color("#2a3e46") if selected else Color("#172a33"), ExpeditionUI.GOLD if selected else ExpeditionUI.LINE, 10, 12))
		button.tooltip_text = "点选查看详情；拖入右侧格子装包。" if available else str(entry["state"])
		button.pressed.connect(select_item.bind(str(entry["token"])))
		list_column.add_child(button)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 12)
		button.add_child(margin)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		margin.add_child(row)
		var art := ExpeditionArt.new()
		art.custom_minimum_size.x = 70
		art.subject = item_art(str(entry["def_id"]))
		art.tint = ItemDefs.quality_color(_entry_quality(entry)) if available else ExpeditionUI.MUTED
		row.add_child(art)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 4)
		row.add_child(info)
		info.add_child(_wrapped(str(entry["source"]), 11, ExpeditionUI.GOLD if available else ExpeditionUI.MUTED))
		info.add_child(_wrapped(str(def["name"]), 19, ExpeditionUI.PAPER if available else ExpeditionUI.MUTED))
		info.add_child(_wrapped("%d×%d 格  ·  %s" % [def["size"].x, def["size"].y, _price(def)], 13, ExpeditionUI.MUTED))
		var fit_note := "背包放不下 · 可先整理" if available and not _has_space(entry, "pack") else str(entry["state"])
		info.add_child(_wrapped(fit_note + "  ·  %d 张牌" % def["cards"].size(), 12, ExpeditionUI.TEAL if available and _has_space(entry, "pack") else ExpeditionUI.MUTED))
		ExpeditionUI.ignore_tree(margin)
	if visible_entries.is_empty():
		list_column.add_child(_wrapped("这个分类下没有现场物资。\n可以切换分类，或整理已携带的物品。", 15, ExpeditionUI.MUTED))
	count_label.text = "尚有 %d 件现场物资\n%s" % [_pending_count(), "个人选择已锁定；额外物资仍可领取。" if _choose_one() and not (_resolved().get("claimed", {}).get(player_key, []) as Array).is_empty() else "离开节点后，未拿走的物品会消失。"]

func _render_detail() -> void:
	ExpeditionUI.clear(detail_column)
	var entry := _entry(selected_token)
	if entry.is_empty():
		detail_column.add_child(_wrapped("搜索圆环转完后，物品才会显现。\n点击已经发现的物品查看属性，或直接拖进自己的背包。" if _resolved().has("corpses") else "搜刮完成。\n点选背包中的物品继续整理，或带着收获前进。", 19, ExpeditionUI.MUTED))
		return
	var def := ItemDefs.get_item(str(entry["def_id"]))
	var quality := _entry_quality(entry)
	var tint := ItemDefs.quality_color(quality)
	var hero := ExpeditionUI.panel(Color("#13272e"), tint.darkened(0.4), 10)
	detail_column.add_child(hero)
	var hero_row := HBoxContainer.new()
	hero.add_child(hero_row)
	var art := ExpeditionArt.new()
	art.subject = item_art(str(entry["def_id"]))
	art.tint = tint
	art.custom_minimum_size = Vector2(104, 116)
	hero_row.add_child(art)
	var title := VBoxContainer.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_row.add_child(title)
	title.add_child(_wrapped(ItemDefs.quality_name(quality), 12, tint))
	title.add_child(_wrapped(str(def["name"]), 25, ExpeditionUI.PAPER))
	title.add_child(_wrapped(ExpeditionBaseline.CATEGORY_DISPLAY.get(str(def["category"]), "物品"), 13, ExpeditionUI.MUTED))
	title.add_child(_wrapped("%d×%d 格   /   %s" % [def["size"].x, def["size"].y, _price(def)], 14, ExpeditionUI.GOLD))
	if bool(def.get("sellable", false)):
		title.add_child(ExpeditionUI.label("每格售价 %.1f 金币" % _value_per_cell(str(entry["def_id"])), 12, ExpeditionUI.MUTED))
	detail_column.add_child(_wrapped(_purpose(def), 14, ExpeditionUI.TEXT))
	var counts: Dictionary = {}
	for id in def.get("cards", []):
		counts[str(id)] = int(counts.get(str(id), 0)) + 1
	detail_column.add_child(ExpeditionUI.label("带入下一场的牌  ·  %d 张" % def["cards"].size(), 15, ExpeditionUI.GOLD))
	for id in counts:
		var card := CardDefs.get_card(str(id))
		var cargo := str(id) == "heavy_cargo"
		var card_panel := ExpeditionUI.panel(Color("#273232") if cargo else Color("#213940"), ExpeditionUI.LINE, 10)
		detail_column.add_child(card_panel)
		var row := HBoxContainer.new()
		card_panel.add_child(row)
		var cost := ExpeditionUI.label("%d\n能量" % int(card.get("cost", 0)), 13, ExpeditionUI.GOLD)
		cost.custom_minimum_size.x = 36
		row.add_child(cost)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(ExpeditionUI.label("%s ×%d" % [str(card.get("name", id)), int(counts[id])], 15, ExpeditionUI.RED if cargo else ExpeditionUI.TEXT))
		info.add_child(_wrapped(str(card.get("desc", "")), 12, ExpeditionUI.MUTED))
	var comparison := _comparison(entry)
	if comparison != "":
		detail_column.add_child(_wrapped(comparison, 13, ExpeditionUI.TEAL))
	var cargo_count := int(counts.get("heavy_cargo", 0))
	if cargo_count > 0:
		var deck: Array = DeckBuilder.build(inventory)["entries"]
		var old_cargo := 0
		for card in deck:
			if str(card["card_id"]) == "heavy_cargo":
				old_cargo += 1
		var carried := str(entry["kind"]) == "loot_manage"
		var total: int = deck.size() + (0 if carried else def["cards"].size())
		var new_cargo := old_cargo + (0 if carried else cargo_count)
		detail_column.add_child(_wrapped("携带负担：%d 张笨重货物。\n%s完整牌组中货物占比约 %d%%；货物会挤占抽牌。" % [cargo_count, "当前" if carried else "拿走后", roundi(100.0 * new_cargo / maxi(1, total))], 13, ExpeditionUI.RED))
	detail_column.add_child(_wrapped("可放保险箱，死亡 / 放弃时仍能保住。" if bool(def.get("safe_allowed", false)) else "不能放保险箱；撤离成功才能带回。", 13, ExpeditionUI.TEAL if bool(def.get("safe_allowed", false)) else ExpeditionUI.MUTED))
	if str(entry["kind"]) == "loot_manage":
		var instance: Dictionary = entry["instance"]
		detail_column.add_child(_wrapped("当前在%s · 第 %d 回合加入抽牌堆%s" % [entry["source"], int(ExpeditionBaseline.JOIN_ROUND.get(str(instance.get("container", "pack")), 2)), " · 剩余 %d 次" % int(instance.get("uses_remaining", 1)) if str(def["category"]) == "supply" else ""], 13, ExpeditionUI.MUTED))
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override("separation", 8)
		detail_column.add_child(actions)
		var rotate := ExpeditionUI.button("原位旋转  R")
		rotate.disabled = pending_action
		rotate.pressed.connect(func() -> void: _request("loot_manage", {"operation": "rotate", "instance_id": int(entry["instance_id"])}, "物品已旋转。"))
		actions.add_child(rotate)
		var discard := ExpeditionUI.button("丢到现场")
		discard.disabled = pending_action
		discard.pressed.connect(_confirm_drop.bind(entry))
		actions.add_child(discard)
		if str(instance.get("container", "")) != current_container:
			_add_take_button(entry, current_container, "移到" + str(ExpeditionBaseline.CONTAINER_DISPLAY[current_container]))
		if bool(run.get("coop", false)) and not ItemDefs.is_basic(str(entry["def_id"])):
			var share := ExpeditionUI.button("分享这件物品给队友")
			share.disabled = pending_action or not (run.get("share_offer", {}) as Dictionary).is_empty()
			share.pressed.connect(func() -> void: _request("share_offer", {"instance_id": int(entry["instance_id"])}, "已向队友提出分享。"))
			detail_column.add_child(share)
	elif bool(entry["available"]):
		_add_take_button(entry, "pack", "捡回背包" if str(entry["kind"]) == "pick_drop" else "放入背包")
		if bool(def.get("safe_allowed", false)):
			_add_take_button(entry, "safe", "放保险箱 · 保护这件物品")
		if current_container == "chest":
			_add_take_button(entry, "chest", "放入胸挂 · 首回合可用")
		detail_column.add_child(_wrapped("也可以把左侧物品拖到右侧指定位置。", 12, ExpeditionUI.MUTED))
	else:
		detail_column.add_child(_wrapped(str(entry["state"]), 16, ExpeditionUI.MUTED))

func _add_take_button(entry: Dictionary, container: String, text: String) -> void:
	var fits := _has_space(entry, container)
	var button := ExpeditionUI.button(text, container == "pack")
	button.disabled = pending_action or not fits
	button.tooltip_text = "自动寻找空位，必要时旋转。" if fits else "放不下，请先整理、移动或丢弃现有物品。"
	button.pressed.connect(func() -> void: _take(entry, container))
	detail_column.add_child(button)
	if not fits:
		detail_column.add_child(_wrapped("%s没有合适空位 · 需要 %d×%d 格，可旋转。" % [ExpeditionBaseline.CONTAINER_DISPLAY[container], ItemDefs.get_item(str(entry["def_id"]))["size"].x, ItemDefs.get_item(str(entry["def_id"]))["size"].y], 12, ExpeditionUI.RED))

func _render_bag() -> void:
	ExpeditionUI.clear(bag_column)
	for container in container_buttons:
		ExpeditionUI.decorate_button(container_buttons[container], container == current_container)
	var dimensions := ExpeditionBaseline.size_for(inventory.expedition, current_container)
	var items := inventory.loadout_list(current_container)
	var used := ExpeditionBaseline.occupancy_map(items, current_container).size()
	var free := ExpeditionBaseline.largest_free_rect(current_container, items, inventory.expedition)
	bag_column.add_child(ExpeditionUI.label("占用 %d / %d 格  ·  最大空位 %d×%d" % [used, dimensions.x * dimensions.y, free.x, free.y], 14, ExpeditionUI.TEXT))
	bag_column.add_child(ExpeditionUI.bar(used, dimensions.x * dimensions.y, ExpeditionUI.RED if used == dimensions.x * dimensions.y else ExpeditionUI.TEAL))
	grid = ExpeditionLootGrid.new()
	grid.loot_owner = self
	grid.container = current_container
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.item_selected.connect(func(id: int) -> void: select_item("carried:%d" % id))
	grid.placement_requested.connect(func(payload: Dictionary, cell: Vector2i) -> void: _take(_entry(str(payload["token"])), current_container, cell, bool(payload.get("rotated", false))))
	bag_column.add_child(grid)
	var display_items := items.duplicate(true)
	for instance in display_items:
		instance["loot_art"] = item_art(str(instance["def_id"]))
		instance["loot_tint"] = ItemDefs.quality_color(ItemDefs.quality_of(instance))
	grid.display(display_items, dimensions, int(_entry(selected_token).get("instance_id", -1)) if selected_token.begins_with("carried:") else -1)
	bag_column.add_child(_wrapped({"chest": "胸挂：装备的牌从第 1 回合加入，适合主力武器和防具。", "pack": "背包：物品的牌从第 2 回合加入；物资越多，牌组越厚。", "safe": "保险箱：允许的材料 / 种子可保住；其牌从第 3 回合加入。"}[current_container], 13, ExpeditionUI.GOLD))
	var tidy := ExpeditionUI.button("自动整理当前容器")
	tidy.disabled = pending_action or items.is_empty()
	tidy.pressed.connect(func() -> void: _request("loot_manage", {"operation": "tidy", "container": current_container}, "已整理%s；物品数量与归属保持不变。" % ExpeditionBaseline.CONTAINER_DISPLAY[current_container]))
	bag_column.add_child(tidy)
	bag_column.add_child(_wrapped("点选格子中的物品，在中栏查看、旋转、转移或丢弃。拖动时按 R 切换方向，绿色轮廓表示可放。", 12, ExpeditionUI.MUTED))
	var totals: Dictionary = DeckBuilder.build(inventory)["totals"]
	bag_column.add_child(_wrapped("下一场牌组\n首回合 %d 张  ·  第 2 回合 +%d  ·  第 3 回合 +%d" % [int(totals[1]), int(totals[2]), int(totals[3])], 13, ExpeditionUI.TEAL))
	_render_share()

func _render_share() -> void:
	if not bool(run.get("coop", false)):
		return
	var offer: Dictionary = run.get("share_offer", {})
	if offer.is_empty():
		bag_column.add_child(_wrapped("合作搜刮：个人奖励各自领取。点选已携带物品可分享给队友。", 12, ExpeditionUI.MUTED))
		return
	if str(offer.get("from", "")) != player_key:
		var other_inventory: Dictionary = run.get("inventory", {}) if player_key == "p2" else run.get("guest", {}).get("inventory", {})
		var other := InventoryGame.new()
		other.bind({"inventory": other_inventory})
		var instance := other.find_instance(int(offer.get("instance_id", -1)))
		var button := ExpeditionUI.button("接受分享：%s" % str(ItemDefs.get_item(str(instance.get("def_id", ""))).get("name", "物品")))
		button.disabled = pending_action
		button.pressed.connect(func() -> void: _request("share_accept", {"container": current_container}, "已收到队友的物品。"))
		bag_column.add_child(button)
	else:
		bag_column.add_child(_wrapped("物品分享中，等待队友接收……", 13, ExpeditionUI.GOLD))
	var cancel := ExpeditionUI.button("取消分享")
	cancel.disabled = pending_action
	cancel.pressed.connect(func() -> void: _request("share_cancel", {}, "分享已取消。"))
	bag_column.add_child(cancel)

func _has_space(entry: Dictionary, container: String) -> bool:
	var def := ItemDefs.get_item(str(entry["def_id"]))
	if container == "safe" and not bool(def.get("safe_allowed", false)):
		return false
	return inventory.find_first_fit(container, def["size"]) != null

func _take(entry: Dictionary, container: String, cell := Vector2i(-1, -1), rotated := false) -> void:
	if entry.is_empty() or not bool(entry.get("available", false)):
		return
	var args := {"container": container, "def_id": str(entry["def_id"])}
	if entry.has("instance_id"):
		args["instance_id"] = int(entry["instance_id"])
	if cell.x >= 0:
		args["cell"] = [cell.x, cell.y]
		args["rotated"] = rotated
	if str(entry["kind"]) == "loot_manage":
		args["operation"] = "move"
	current_container = container
	_request(str(entry["kind"]), args, "%s已装入%s。" % [ItemDefs.get_item(str(entry["def_id"]))["name"], ExpeditionBaseline.CONTAINER_DISPLAY[container]])

func _request(kind: String, args: Dictionary, success_text: String) -> void:
	if pending_action or not action_sink.is_valid():
		return
	pending_action = true
	pending_acknowledged = false
	pending_serial = snapshot_serial
	action_message = success_text
	action_sound = "open" if kind in ["claim_reward", "claim_public", "pick_drop", "share_accept", "claim_corpse"] else "ui_click"
	feedback_label.text = "正在处理……"
	var result: Variant = action_sink.call(kind, args)
	if result is String and result != "":
		pending_action_id = result
		display(run, player_key, snapshot_serial)
	elif result is Dictionary:
		_consume_result(result)
		display(run, player_key, snapshot_serial)
	else:
		_consume_result({"ok": false, "reason": "连接暂不可用，请重试。"})
		display(run, player_key, snapshot_serial)

func acknowledge(action_id: String, result: Dictionary, serial := -1) -> void:
	if not pending_action or action_id != pending_action_id:
		return
	# 主机按回执→快照发送。先前的无关快照不能充当这次行动的提交结果。
	if bool(result.get("ok", false)):
		pending_serial = maxi(snapshot_serial, serial)
	_consume_result(result, true)
	display(run, player_key, snapshot_serial)

func _consume_result(result: Dictionary, wait_snapshot := false) -> void:
	var ok := bool(result.get("ok", false))
	if not ok:
		leave_after_cancel = false
		search_retry_at = Time.get_ticks_msec() + 500
	if not action_message.begins_with("搜索继续"):
		AudioKit.play(self, action_sound if ok else "warn", -6)
	pending_acknowledged = ok and wait_snapshot
	pending_action = ok and wait_snapshot and snapshot_serial <= pending_serial
	feedback_label.text = action_message if ok else str(result.get("reason", "操作失败，请重试。"))
	feedback_label.add_theme_color_override("font_color", ExpeditionUI.TEAL if ok else ExpeditionUI.RED)
	if ok and result.has("instance_id"):
		if wait_snapshot:
			pending_selected_id = int(result["instance_id"])
		else:
			selected_token = "carried:%d" % int(result["instance_id"])

func drag_payload(token: String) -> Dictionary:
	var entry := _entry(token)
	if entry.is_empty() or pending_action or modal.visible or not bool(entry.get("available", false)):
		return {}
	return {"loot_owner": get_instance_id(), "token": token, "def_id": str(entry["def_id"]), "quality": _entry_quality(entry), "instance_id": int(entry.get("instance_id", -1)) if str(entry["kind"]) == "loot_manage" else -1, "rotated": bool(entry.get("instance", {}).get("rotated", false))}

func drag_preview(payload: Dictionary) -> Control:
	var tint := ItemDefs.quality_color(ItemDefs.quality_of(payload))
	var panel := ExpeditionUI.panel(tint.darkened(0.8), tint, 8)
	var row := VBoxContainer.new()
	panel.add_child(row)
	var art := ExpeditionArt.new()
	art.subject = item_art(str(payload["def_id"]))
	art.tint = tint
	art.custom_minimum_size = Vector2(64, 64)
	row.add_child(art)
	row.add_child(ExpeditionUI.label(str(ItemDefs.get_item(str(payload["def_id"]))["name"]), 13, tint))
	row.add_child(ExpeditionUI.label("R 旋转", 11, ExpeditionUI.GOLD))
	ExpeditionUI.ignore_tree(panel)
	return panel

func _pending_count() -> int:
	var total := 0
	for entry in entries:
		if str(entry["kind"]) != "loot_manage" and bool(entry["available"]):
			total += 1
	return total

func _confirm_leave() -> void:
	if _has_unknown():
		_confirm("还有未搜索的区域", "战场上还有未搜索的区域或未拿走的物品。\n离开后无法找回，确认继续探索？", "确认离开本节点", _cancel_and_leave)
		return
	if _pending_count() > 0:
		_confirm("还有物资留在现场", "还有 %d 件候选 / 公共物资 / 丢弃物未带走。\n离开后这些物品会消失，确认继续？" % _pending_count(), "确认离开本节点", func() -> void: _request("leave_node", {}, "搜刮完成，继续探索。"))
	else:
		_request("leave_node", {}, "搜刮完成，继续探索。")

func _confirm_drop(entry: Dictionary) -> void:
	var protected := str(entry.get("instance", {}).get("container", "")) == "safe"
	_confirm("腾出空间", "将「%s」丢到现场？\n离开前可以捡回。%s" % [ItemDefs.get_item(str(entry["def_id"]))["name"], "丢弃后这件物品将失去保险箱保护。" if protected else "离开节点后将无法找回。"], "确认丢到现场", func() -> void: _request("loot_manage", {"operation": "drop", "instance_id": int(entry["instance_id"])}, "物品留在现场；离开前可以捡回。"))

func _confirm(title: String, content: String, action: String, callback: Callable) -> void:
	ExpeditionUI.clear(modal_content)
	modal_content.add_child(ExpeditionUI.label(title, 24, ExpeditionUI.GOLD))
	modal_content.add_child(_wrapped(content, 16, ExpeditionUI.TEXT))
	var yes := ExpeditionUI.button(action, true)
	yes.pressed.connect(func() -> void: _close_modal(); callback.call())
	modal_content.add_child(yes)
	var no := ExpeditionUI.button("返回继续搜刮")
	no.pressed.connect(_close_modal)
	modal_content.add_child(no)
	modal_shade.visible = true
	modal.visible = true
	modal.mouse_filter = Control.MOUSE_FILTER_STOP

func _close_modal() -> void:
	if modal == null:
		return
	modal_shade.visible = false
	modal.visible = false
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if input_blocked.is_valid() and bool(input_blocked.call()):
		return
	if event.keycode == KEY_ESCAPE:
		if modal.visible:
			_close_modal()
		elif _resolved().has("corpses") and not scene_mode:
			_return_to_battlefield()
		else:
			_open_menu()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R and not modal.visible and not pending_action:
		if get_viewport().gui_is_dragging():
			var data: Variant = get_viewport().gui_get_drag_data()
			if data is Dictionary and int(data.get("loot_owner", -1)) == get_instance_id():
				data["rotated"] = not bool(data.get("rotated", false))
				get_viewport().set_input_as_handled()
		elif selected_token.begins_with("carried:"):
			_request("loot_manage", {"operation": "rotate", "instance_id": int(_entry(selected_token).get("instance_id", -1))}, "物品已旋转。")
			get_viewport().set_input_as_handled()

func _open_corpse(id: String) -> void:
	if pending_action:
		return
	search_source = id
	selected_token = ""
	scene_mode = false
	for source in _resolved().get("corpses", []):
		if str(source["id"]) == id:
			search_region = str(source["regions"][0]["id"])
			break
	_request("search_start", {"source": search_source, "region": search_region}, "开始搜索，已发现的物品可以直接装包。")

func _return_to_battlefield() -> void:
	if pending_action:
		return
	scene_mode = true
	_request("search_cancel", {}, "搜索已暂停，已发现的物品仍在原处。")

func _open_menu() -> void:
	stop_search_pending = true
	if not pending_action and not run.get("loot_searches", {}).get(player_key, {}).is_empty():
		stop_search_pending = false
		_request("search_cancel", {}, "搜索已暂停。")
	menu_requested.emit()

func _render_search() -> void:
	var sources: Array = _resolved().get("corpses", [])
	var source: Dictionary = {}
	for value in sources:
		if str(value["id"]) == search_source:
			source = value
	if source.is_empty():
		count_label.text = "点击战场上的尸体开始搜索。"
		return
	var layout_key := screen_identity + ":" + search_source
	if search_layout_key != layout_key:
		search_layout_key = layout_key
		source_grids.clear()
		region_buttons.clear()
		ExpeditionUI.clear(list_column)
		var picker := OptionButton.new()
		picker.custom_minimum_size.y = 36
		for i in range(sources.size()):
			picker.add_item(str(sources[i]["name"]))
			if str(sources[i]["id"]) == search_source:
				picker.select(i)
		picker.item_selected.connect(func(index: int) -> void: _open_corpse(str(sources[index]["id"])))
		list_column.add_child(picker)
		var regions := GridContainer.new()
		regions.columns = 2 if source["regions"].size() > 1 else 1
		regions.add_theme_constant_override("h_separation", 8)
		regions.add_theme_constant_override("v_separation", 8)
		list_column.add_child(regions)
		for region in source["regions"]:
			var id := str(region["id"])
			var panel := ExpeditionUI.panel(Color("#13262e"), ExpeditionUI.LINE, 6)
			panel.name = "SearchRegion_" + id
			panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			regions.add_child(panel)
			var column := VBoxContainer.new()
			column.add_theme_constant_override("separation", 6)
			panel.add_child(column)
			var header := HBoxContainer.new()
			column.add_child(header)
			var title := ExpeditionUI.label(str(region["name"]), 14)
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			header.add_child(title)
			var button := ExpeditionUI.button("搜索")
			button.custom_minimum_size = Vector2(54, 30)
			button.add_theme_font_size_override("font_size", 12)
			button.pressed.connect(_search_region.bind(id))
			header.add_child(button)
			region_buttons[id] = button
			var region_grid := CorpseSearchGrid.new()
			region_grid.loot_owner = self
			region_grid.compact = source["regions"].size() > 1
			column.add_child(region_grid)
			source_grids[id] = region_grid
		ground_drops = VBoxContainer.new()
		list_column.add_child(ground_drops)
	ExpeditionUI.clear(ground_drops)
	for entry in entries:
		if str(entry["kind"]) == "pick_drop":
			var button := LootButton.new()
			button.loot_owner = self
			button.token = str(entry["token"])
			button.text = "捡回 · " + str(ItemDefs.get_item(str(entry["def_id"]))["name"])
			button.pressed.connect(select_item.bind(str(entry["token"])))
			ground_drops.add_child(button)
	var checked := 0
	var total := 0
	for region in source["regions"]:
		var id := str(region["id"])
		var session := {}
		for member in run.get("loot_searches", {}):
			var candidate: Dictionary = run["loot_searches"][member]
			if str(candidate["source"]) == search_source and str(candidate["region"]) == id:
				session = candidate.duplicate(true)
				session["viewer_owner"] = member == player_key
		var complete: bool = region["searched"].size() == int(region["size"][0]) * int(region["size"][1])
		var button: Button = region_buttons[id]
		button.text = "完成" if complete else ("暂停" if bool(session.get("viewer_owner", false)) else ("队友" if not session.is_empty() else "搜索"))
		button.disabled = pending_action or complete or (not session.is_empty() and not bool(session.get("viewer_owner", false)))
		ExpeditionUI.decorate_button(button, bool(session.get("viewer_owner", false)))
		button.add_theme_font_size_override("font_size", 12)
		for style_key in ["normal", "hover", "pressed", "disabled"]:
			var button_style := button.get_theme_stylebox(style_key).duplicate() as StyleBoxFlat
			button_style.content_margin_top = 5
			button_style.content_margin_bottom = 5
			button_style.content_margin_left = 6
			button_style.content_margin_right = 6
			button.add_theme_stylebox_override(style_key, button_style)
		var region_grid: CorpseSearchGrid = source_grids[id]
		region_grid.display(region, session)
		if id == search_region:
			source_grid = region_grid
		checked += region["searched"].size()
		total += int(region["size"][0]) * int(region["size"][1])
	count_label.text = "已检查 %d / %d 格 · 点击物品查看，拖动装包\n品质：白 → 蓝 → 紫 → 金 → 红" % [checked, total]

func _search_region(id: String) -> void:
	if pending_action or modal.visible:
		return
	var session: Dictionary = run.get("loot_searches", {}).get(player_key, {})
	if str(session.get("source", "")) == search_source and str(session.get("region", "")) == id:
		_request("search_cancel", {}, "搜索已暂停。")
		return
	search_region = id
	_request("search_start", {"source": search_source, "region": id}, "搜索中 · 已发现的物品可直接装包。")

func _has_unknown() -> bool:
	for source in _resolved().get("corpses", []):
		for region in source["regions"]:
			if region["searched"].size() < int(region["size"][0]) * int(region["size"][1]):
				return true
	return false

func _cancel_and_leave() -> void:
	leave_after_cancel = true
	_request("search_cancel", {}, "搜索结束。")

func _process(_delta: float) -> void:
	if render_after_drag and not get_viewport().gui_is_dragging():
		render_after_drag = false
		_render_list()
		_render_detail()
		_render_bag()
	if pending_action:
		return
	if stop_search_pending:
		stop_search_pending = false
		if str(run.get("phase", "")) == "node" and not run.get("loot_searches", {}).get(player_key, {}).is_empty():
			_request("search_cancel", {}, "搜索已暂停。")
		return
	if not is_visible_in_tree() or modal.visible:
		return
	if input_blocked.is_valid() and bool(input_blocked.call()):
		return
	if leave_after_cancel:
		leave_after_cancel = false
		_request("leave_node", {}, "搜刮完成，继续探索。")
		return
	if scene_mode or get_viewport().gui_is_dragging() or Time.get_ticks_msec() < search_retry_at:
		return
	var session: Dictionary = run.get("loot_searches", {}).get(player_key, {})
	if not session.is_empty():
		if str(session["source"]) != search_source:
			_request("search_cancel", {}, "旧区域的搜索已暂停。")
		elif str(session["region"]) != search_region:
			# 权威按顺序自动接续到下一区域，视图跟随而不是取消。
			search_region = str(session["region"])
		elif Time.get_ticks_msec() >= search_deadline:
			_request("search_step", {}, "搜索继续 · 已发现物品可装包。")

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		stop_search_pending = true

func _price(def: Dictionary) -> String:
	return "售价 %d 金币" % int(def.get("base_value", 0)) if bool(def.get("sellable", false)) else "不可出售"

func _value_per_cell(id: String) -> float:
	var def := ItemDefs.get_item(id)
	return float(def.get("base_value", 0)) / maxi(1, def["size"].x * def["size"].y) if bool(def.get("sellable", false)) else 0.0

func _purpose(def: Dictionary) -> String:
	match str(def.get("category", "")):
		"weapon": return "提供攻击牌。放入胸挂可从首回合使用；拿走后不会自动替换旧武器。"
		"armor": return "提供防御牌。比较实际牌效再决定是否替换，品质不会额外提高格挡。"
		"supply": return "战斗中打出补给牌才会恢复生命，并消耗来源物品。搜刮时装包不会立即使用。"
		"rare_seed": return "撤离后可带回农场种植。优先放入保险箱，可以保护新的种子。"
		"cargo": return "适合带回出售。需要在金币收益、占格和战斗负担之间取舍。"
		"material": return "可带回用于制作；能否出售与保护以这件物品的说明为准。"
		_: return "提供抽牌或辅助牌，放在哪个容器决定它何时加入战斗。"

func _comparison(entry: Dictionary) -> String:
	var def := ItemDefs.get_item(str(entry["def_id"]))
	var category := str(def.get("category", ""))
	if not category in ["weapon", "armor", "tool"]:
		return ""
	for instance in inventory.loadout_list("chest"):
		var other := ItemDefs.get_item(str(instance["def_id"]))
		if str(other.get("category", "")) != category or int(instance["instance_id"]) == int(entry.get("instance_id", -1)):
			continue
		var before := _card_strength(other)
		var after := _card_strength(def)
		var metric := "最大单牌伤害" if category == "weapon" else ("最大单牌格挡" if category == "armor" else "最大单牌抽牌")
		return "对比胸挂中的%s\n占格 %d → %d  ·  %s %d → %d\n牌效以卡牌描述为准；替换需要手动移走旧物品。" % [other["name"], other["cards"].size(), def["cards"].size(), metric, before, after]
	return "胸挂中暂没有同类物品可比较。"

func _card_strength(def: Dictionary) -> int:
	var kind: String = {"weapon": "damage", "armor": "block", "tool": "draw"}.get(str(def.get("category", "")), "damage")
	var maximum := 0
	for id in def.get("cards", []):
		for effect in CardDefs.get_card(str(id)).get("effects", []):
			if str(effect.get("kind", "")) == kind:
				maximum = maxi(maximum, int(effect.get("value", 0)))
	return maximum

static func item_art(id: String) -> String:
	var category := str(ItemDefs.get_item(id).get("category", ""))
	if id.contains("crystal") or id.contains("radiant"):
		return "crystal"
	if id == "bandage" or id == "rescue_kit":
		return "bandage"
	return {"weapon": "attack", "armor": "shield", "helmet": "helmet", "tool": "tools", "supply": "heal", "rare_seed": "seed", "cargo": "relic", "material": "fiber" if id == "fiber_clump" else "ore"}.get(category, "crystal")

func _entry_quality(entry: Dictionary) -> int:
	return ItemDefs.quality_of(entry.get("instance", {"def_id": entry.get("def_id", "")}))

static func item_tint(id: String, quality := -1) -> Color:
	return ItemDefs.quality_color(ItemDefs.quality_of({"def_id": id}) if quality < 0 else quality)
