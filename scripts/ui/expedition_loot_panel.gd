class_name ExpeditionLootPanel
extends Control
## 战后搜刮台：只读快照，全部领取/摆放/丢弃意图由 ExpeditionGame 或主机裁定。

signal menu_requested
var action_sink: Callable
var input_blocked: Callable
var run: Dictionary = {}
var player_key := "p1"
var selected_token := ""
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
var context_column: VBoxContainer
var context_scroll: ScrollContainer
var share_box: VBoxContainer
var feedback_label: Label
var count_label: Label
var leave_button: Button
var workspace: BackpackWorkspace
var detail_card: PanelContainer
var detail_card_content: VBoxContainer
var corpse_detail_column: VBoxContainer
var _action_target: VBoxContainer
var _detail_host: VBoxContainer
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
var slot_frames: Dictionary = {}
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
	# 三栏改版：左+中＝工作台（装备纸娃娃+容器栈，紧凑配置），右＝上下文栏（尸体/物资）。
	workspace = BackpackWorkspace.new()
	workspace.name = "BackpackWorkspace"
	workspace.doll_width = 232
	workspace.stack_width = 348
	workspace.slot_min_sizes = {
		"helmet": Vector2(104, 104),
		"main_weapon": Vector2(84, 166),
		"armor": Vector2(104, 104),
		"off_weapon": Vector2(84, 166),
	}
	workspace.grid_min_height = 244
	workspace.show_hint = false
	workspace.setup(self, {
		"place": _on_workspace_place,
		"equip": _on_workspace_equip,
		"tidy": _on_workspace_tidy,
		"select": func(id: int) -> void: select_item("carried:%d" % id),
	})
	workspace.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(workspace)
	var loot := _section(body, 1.0)
	loot_heading = ExpeditionUI.label("搜刮", 19, ExpeditionUI.PAPER)
	loot.add_child(loot_heading)
	var filters := HBoxContainer.new()
	filters_container = filters
	filters.add_theme_constant_override("separation", 5)
	loot.add_child(filters)
	for i in range(3):
		var filter_button := ExpeditionUI.button(["全部", "装备 / 补给", "材料 / 货物"][i])
		filter_button.custom_minimum_size.y = 30
		filter_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filter_button.add_theme_font_size_override("font_size", 12)
		filter_button.pressed.connect(func() -> void: filter_index = i; _render_context())
		filters.add_child(filter_button)
		filter_buttons.append(filter_button)
	var sort_button := ExpeditionUI.button("按每格售价排序  ⇅")
	sort_control = sort_button
	sort_button.custom_minimum_size.y = 28
	sort_button.add_theme_font_size_override("font_size", 12)
	sort_button.pressed.connect(func() -> void:
		sort_value = not sort_value
		sort_button.text = "恢复发现顺序  ⇅" if sort_value else "按每格售价排序  ⇅"
		_render_context())
	loot.add_child(sort_button)
	context_scroll = ScrollContainer.new()
	context_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	context_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	loot.add_child(context_scroll)
	context_column = VBoxContainer.new()
	context_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_column.add_theme_constant_override("separation", 10)
	context_scroll.add_child(context_column)
	count_label = _wrapped("", 13, ExpeditionUI.MUTED)
	loot.add_child(count_label)
	# 浮动详情卡：选中物品时出现在右上角，不遮左侧工作台。
	detail_card = ExpeditionUI.panel(ExpeditionUI.PANEL, ExpeditionUI.GOLD, 14)
	detail_card.visible = false
	detail_card.z_index = 40
	detail_card.mouse_filter = Control.MOUSE_FILTER_STOP
	detail_card.anchor_left = 1.0
	detail_card.anchor_right = 1.0
	detail_card.anchor_top = 0.0
	detail_card.anchor_bottom = 0.0
	detail_card.offset_left = -356
	detail_card.offset_right = -16
	detail_card.offset_top = 96
	add_child(detail_card)
	var card_column := VBoxContainer.new()
	card_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_column.custom_minimum_size = Vector2(320, 420)
	detail_card.add_child(card_column)
	var card_header := HBoxContainer.new()
	card_column.add_child(card_header)
	var card_title := ExpeditionUI.label("物品详情", 14, ExpeditionUI.GOLD)
	card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_header.add_child(card_title)
	var card_close := ExpeditionUI.button("×")
	card_close.custom_minimum_size = Vector2(34, 30)
	card_close.pressed.connect(func() -> void:
		selected_token = ""
		_render_detail())
	card_header.add_child(card_close)
	var card_scroll := ScrollContainer.new()
	card_scroll.custom_minimum_size = Vector2(300, 0)
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_column.add_child(card_scroll)
	detail_card_content = VBoxContainer.new()
	detail_card_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_card_content.add_theme_constant_override("separation", 10)
	card_scroll.add_child(detail_card_content)
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
	loot_heading.text = "搜索尸体" if searchable else "现场物资"
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
	var totals: Dictionary = DeckBuilder.build(inventory)["totals"]
	summary_label.text = "生命 %d / %d     深度 %02d\n携带售价 %d 金币  ·  保险箱保护 %d 件\n下一场牌：装备 %d ｜ 胸挂 %d ｜ 背包 %d（保险箱不入堆）" % [int(player.get("hp", 0)), int(player.get("max_hp", 40)), int(run["current"]["row"]), inventory.carry_sell_value(), inventory.loadout_list("safe").size(), int(totals[1]), int(totals[2]), int(totals[3])]
	rule_label.text = ("个人战利品任选一件，装入成功才锁定选择。" if _choose_one() else "这里的个人物资都可领取，能带多少取决于你的空间。") + ("公共物资全队一份，先领取者获得。" if bool(run.get("coop", false)) else "公共物资不占个人选择次数。")
	if searchable:
		rule_label.text = "打开尸体后自动按顺序搜索全部区域；空格无需搜索，品质越高搜索越久。已发现的物品可直接装包。" + ("尸体物资全队一份。" if bool(run.get("coop", false)) else "")
	if get_viewport().gui_is_dragging():
		render_after_drag = true
		return
	_refresh_workspace()
	_render_context()
	_render_detail()
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
		var owner_label: String = str(ExpeditionBaseline.CONTAINER_DISPLAY.get(str(instance.get("container", "")), "携带物品"))
		if str(instance.get("container", "")) == "equipped":
			owner_label = "%s槽" % ExpeditionBaseline.SLOT_DISPLAY.get(str(instance.get("slot", "")), "装备")
		entries.append({"token": "carried:%d" % int(instance["instance_id"]), "def_id": instance["def_id"], "instance_id": int(instance["instance_id"]), "kind": "loot_manage", "source": owner_label, "available": true, "state": "已携带", "instance": instance})

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
	# 选择只重绘区域格与详情卡，不重建上下文栏——否则按下瞬间就释放拖动源控件。
	if _resolved().has("corpses"):
		for region_grid in source_grids.values():
			if is_instance_valid(region_grid):
				region_grid.queue_redraw()
	_render_detail()

func _render_context() -> void:
	## 上下文栏：尸体模式（_render_search）或物资大格子模式。
	if _resolved().has("corpses"):
		_render_search()
		return
	search_layout_key = ""
	source_grids.clear()
	region_buttons.clear()
	slot_frames.clear()
	ExpeditionUI.clear(context_column)
	for i in range(filter_buttons.size()):
		ExpeditionUI.decorate_button(filter_buttons[i], i == filter_index)
	loot_heading.text = "现场物资 · 像一个巨大的背包"
	var visible_entries: Array = []
	for entry in entries:
		if str(entry["kind"]) == "loot_manage":
			continue
		var category := str(ItemDefs.get_item(str(entry["def_id"])).get("category", ""))
		if filter_index == 1 and not category in ["weapon", "armor", "helmet", "tool", "supply"]:
			continue
		if filter_index == 2 and category in ["weapon", "armor", "helmet", "tool", "supply"]:
			continue
		visible_entries.append(entry)
	if sort_value:
		visible_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _value_per_cell(str(a["def_id"])) > _value_per_cell(str(b["def_id"])))
	var flow := BackpackWorkspace.FlowItemGrid.new()
	flow.workspace = workspace
	flow.cell = 44.0
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_column.add_child(flow)
	var flow_entries: Array = []
	for entry in visible_entries:
		var def := ItemDefs.get_item(str(entry["def_id"]))
		flow_entries.append({
			"instance_id": int(entry.get("instance_id", -1)),
			"def_id": str(entry["def_id"]),
			"name": str(def["name"]),
			"dims": def["size"],
			"art": item_art(str(entry["def_id"])),
			"tint": ItemDefs.quality_color(_entry_quality(entry)) if bool(entry["available"]) else ExpeditionUI.MUTED,
			"tooltip": "%s · %s · %s\n拖到左侧装备槽或容器格；点选查看详情。" % [def["name"], ItemDefs.quality_name(_entry_quality(entry)), str(entry["state"])],
			"payload_extra": {"loot_owner": get_instance_id(), "token": str(entry["token"])},
		})
	flow.set_items(flow_entries)
	flow.token_selected.connect(func(token: String) -> void:
		if token != "":
			select_item(token))
	if visible_entries.is_empty():
		context_column.add_child(_wrapped("这个分类下没有现场物资。\n可以切换分类，或整理已携带的物品。", 15, ExpeditionUI.MUTED))
	share_box = VBoxContainer.new()
	share_box.add_theme_constant_override("separation", 6)
	context_column.add_child(share_box)
	_render_share()
	count_label.text = "尚有 %d 件现场物资\n%s" % [_pending_count(), "个人选择已锁定；额外物资仍可领取。" if _choose_one() and not (_resolved().get("claimed", {}).get(player_key, []) as Array).is_empty() else "离开节点后，未拿走的物品会消失。"]

func _render_detail() -> void:
	if detail_card == null or detail_card_content == null:
		return
	# 双宿主：物资模式＝右上浮动卡；尸体模式＝上下文栏底部常驻详情区
	# （悬浮卡会盖住尸体格挡拖放，reparent 方案在布局重建时会连坐释放控件，均弃用）。
	if _resolved().has("corpses"):
		if corpse_detail_column == null or not is_instance_valid(corpse_detail_column):
			return
		_detail_host = corpse_detail_column
		detail_card.visible = false
	else:
		_detail_host = detail_card_content
		detail_card.visible = not _entry(selected_token).is_empty() and workspace_frame.visible
	ExpeditionUI.clear(_detail_host)
	var entry := _entry(selected_token)
	if entry.is_empty():
		return
	var def := ItemDefs.get_item(str(entry["def_id"]))
	var quality := _entry_quality(entry)
	var tint := ItemDefs.quality_color(quality)
	var hero := ExpeditionUI.panel(Color("#13272e"), tint.darkened(0.4), 10)
	_detail_host.add_child(hero)
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
	# 动作区先挂：按钮永远在卡片顶部可见，长描述进滚动区。
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_detail_host.add_child(actions)
	_action_target = actions
	_detail_host.add_child(_wrapped(_purpose(def), 14, ExpeditionUI.TEXT))
	var counts: Dictionary = {}
	for id in def.get("cards", []):
		counts[str(id)] = int(counts.get(str(id), 0)) + 1
	_detail_host.add_child(ExpeditionUI.label("带入下一场的牌  ·  %d 张" % def["cards"].size(), 15, ExpeditionUI.GOLD))
	for id in counts:
		var card := CardDefs.get_card(str(id))
		var cargo := str(id) == "heavy_cargo"
		var card_panel := ExpeditionUI.panel(Color("#273232") if cargo else Color("#213940"), ExpeditionUI.LINE, 10)
		_detail_host.add_child(card_panel)
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
		_detail_host.add_child(_wrapped(comparison, 13, ExpeditionUI.TEAL))
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
		_detail_host.add_child(_wrapped("携带负担：%d 张笨重货物。\n%s完整牌组中货物占比约 %d%%；货物会挤占抽牌。" % [cargo_count, "当前" if carried else "拿走后", roundi(100.0 * new_cargo / maxi(1, total))], 13, ExpeditionUI.RED))
	_detail_host.add_child(_wrapped("可放保险箱，死亡 / 放弃时仍能保住。" if bool(def.get("safe_allowed", false)) else "不能放保险箱；撤离成功才能带回。", 13, ExpeditionUI.TEAL if bool(def.get("safe_allowed", false)) else ExpeditionUI.MUTED))
	if str(entry["kind"]) == "loot_manage":
		var instance: Dictionary = entry["instance"]
		var container_now := str(instance.get("container", ""))
		var join_note := "不入牌堆（保险箱只保死亡）"
		if container_now == "equipped":
			join_note = "%s槽 · 第 1 回合加入抽牌堆" % ExpeditionBaseline.SLOT_DISPLAY.get(str(instance.get("slot", "")), "装备")
		elif ExpeditionBaseline.JOIN_ROUND.has(container_now):
			join_note = "第 %d 回合加入抽牌堆" % int(ExpeditionBaseline.JOIN_ROUND[container_now])
		_detail_host.add_child(_wrapped("当前在%s · %s%s" % [entry["source"], join_note, " · 剩余 %d 次" % int(instance.get("uses_remaining", 1)) if str(def["category"]) == "supply" else ""], 13, ExpeditionUI.MUTED))
		var action_row := HBoxContainer.new()
		action_row.add_theme_constant_override("separation", 8)
		actions.add_child(action_row)
		if ExpeditionBaseline.CONTAINER_SIZE.has(container_now):
			var rotate := ExpeditionUI.button("原位旋转  R")
			rotate.disabled = pending_action
			rotate.pressed.connect(func() -> void: _request("loot_manage", {"operation": "rotate", "instance_id": int(entry["instance_id"])}, "物品已旋转。"))
			action_row.add_child(rotate)
		var discard := ExpeditionUI.button("丢到现场")
		discard.disabled = pending_action
		discard.pressed.connect(_confirm_drop.bind(entry))
		action_row.add_child(discard)
		if container_now == "equipped":
			var unequip := ExpeditionUI.button("卸下装备")
			unequip.disabled = pending_action
			unequip.pressed.connect(func() -> void: _request("loot_manage", {"operation": "unequip", "instance_id": int(entry["instance_id"])}, "已卸下装备，回到仓库。"))
			actions.add_child(unequip)
		else:
			var slot := _free_equip_slot_for(str(entry["def_id"]))
			if slot != "":
				var equip_button := ExpeditionUI.button("装备到%s槽 · 第 1 回合入牌" % ExpeditionBaseline.SLOT_DISPLAY[slot], true)
				equip_button.disabled = pending_action
				equip_button.pressed.connect(func() -> void: _request("loot_manage", {"operation": "equip", "instance_id": int(entry["instance_id"]), "slot": slot}, "已装备到%s槽。" % ExpeditionBaseline.SLOT_DISPLAY[slot]))
				actions.add_child(equip_button)
			if container_now != "chest":
				_add_take_button(entry, "chest", "移到胸挂 · 第 2 回合入牌")
		if bool(run.get("coop", false)) and not ItemDefs.is_basic(str(entry["def_id"])):
			var share := ExpeditionUI.button("分享这件物品给队友")
			share.disabled = pending_action or not (run.get("share_offer", {}) as Dictionary).is_empty()
			share.pressed.connect(func() -> void: _request("share_offer", {"instance_id": int(entry["instance_id"])}, "已向队友提出分享。"))
			actions.add_child(share)
	elif bool(entry["available"]):
		_add_take_button(entry, "pack", "捡回背包" if str(entry["kind"]) == "pick_drop" else "放入背包")
		var slot := _free_equip_slot_for(str(entry["def_id"]))
		if slot != "" and str(entry["kind"]) != "pick_drop":
			var equip_direct := ExpeditionUI.button("装备到%s槽 · 直接穿上" % ExpeditionBaseline.SLOT_DISPLAY[slot], true)
			equip_direct.disabled = pending_action
			equip_direct.pressed.connect(func() -> void: _take(entry, "equipped", Vector2i(-1, -1), false, slot))
			actions.add_child(equip_direct)
		if bool(def.get("safe_allowed", false)):
			_add_take_button(entry, "safe", "放保险箱 · 保护这件物品")
		_detail_host.add_child(_wrapped("也可以直接拖到左侧装备槽或容器格；拖动时按 R 旋转。", 12, ExpeditionUI.MUTED))
	else:
		_detail_host.add_child(_wrapped(str(entry["state"]), 16, ExpeditionUI.MUTED))


## 武器/头盔/护甲的可装备槽位（优先空槽；武器占用时可换装，旧件自动回仓库）。
func _free_equip_slot_for(def_id: String) -> String:
	var category := str(ItemDefs.get_item(def_id).get("category", ""))
	if not ExpeditionBaseline.SLOT_CATEGORY.values().has(category):
		return ""
	var preferred: Array = ["armor"] if category == "armor" else (["helmet"] if category == "helmet" else ["main_weapon", "off_weapon"])
	for slot in preferred:
		if inventory.equipped_in(slot).is_empty():
			return slot
	return str(preferred[0])

func _add_take_button(entry: Dictionary, container: String, text: String) -> void:
	var fits := _has_space(entry, container)
	var button := ExpeditionUI.button(text, container == "pack")
	button.disabled = pending_action or not fits
	button.tooltip_text = "自动寻找空位，必要时旋转。" if fits else "放不下，请先整理、移动或丢弃现有物品。"
	button.pressed.connect(func() -> void: _take(entry, container))
	_action_target.add_child(button)
	if not fits:
		_action_target.add_child(_wrapped("%s没有合适空位 · 需要 %d×%d 格，可旋转。" % [ExpeditionBaseline.CONTAINER_DISPLAY[container], ItemDefs.get_item(str(entry["def_id"]))["size"].x, ItemDefs.get_item(str(entry["def_id"]))["size"].y], 12, ExpeditionUI.RED))

func _refresh_workspace() -> void:
	## 工作台（装备槽+容器栈）按最新快照刷新；拖放期间由各格自绘 ghost。
	if workspace == null or inventory == null:
		return
	workspace.bind_inventory(func() -> InventoryGame: return inventory)
	workspace.busy = pending_action
	var selected_id := int(_entry(selected_token).get("instance_id", -1)) if selected_token.begins_with("carried:") else -1
	workspace.refresh(inventory, selected_id)


# —— 工作台意图（BackpackWorkspace 经 Callable 回调到这里）—————————————————


func _on_workspace_place(payload: Dictionary, container: String, cell: Vector2i) -> void:
	var entry := _entry(str(payload.get("token", "")))
	if entry.is_empty():
		return
	_take(entry, container, cell, bool(payload.get("rotated", false)))


func _on_workspace_equip(payload: Dictionary, slot: String) -> void:
	## 拖到装备槽：携带物走 loot_manage 装备；尸体/奖励物走领取+直装。
	var entry := _entry(str(payload.get("token", "")))
	if entry.is_empty() or pending_action:
		return
	if str(entry["kind"]) == "loot_manage":
		_request("loot_manage", {"operation": "equip", "instance_id": int(entry["instance_id"]), "slot": slot}, "已装备到%s槽（牌第 1 回合入堆）。" % ExpeditionBaseline.SLOT_DISPLAY[slot])
	elif bool(entry.get("available", false)):
		_take(entry, "equipped", Vector2i(-1, -1), false, slot)


func _on_workspace_tidy(container: String) -> void:
	_request("loot_manage", {"operation": "tidy", "container": container}, "已整理%s；物品数量与归属保持不变。" % ExpeditionBaseline.CONTAINER_DISPLAY[container])


func _render_share() -> void:
	if share_box == null or not is_instance_valid(share_box):
		return
	ExpeditionUI.clear(share_box)
	if not bool(run.get("coop", false)):
		return
	var offer: Dictionary = run.get("share_offer", {})
	if offer.is_empty():
		share_box.add_child(_wrapped("合作搜刮：个人奖励各自领取。点选已携带物品可分享给队友。", 12, ExpeditionUI.MUTED))
		return
	if str(offer.get("from", "")) != player_key:
		var other_inventory: Dictionary = run.get("inventory", {}) if player_key == "p2" else run.get("guest", {}).get("inventory", {})
		var other := InventoryGame.new()
		other.bind({"inventory": other_inventory})
		var instance := other.find_instance(int(offer.get("instance_id", -1)))
		var button := ExpeditionUI.button("接受分享：%s" % str(ItemDefs.get_item(str(instance.get("def_id", ""))).get("name", "物品")))
		button.disabled = pending_action
		button.pressed.connect(func() -> void: _request("share_accept", {"container": "pack"}, "已收到队友的物品。"))
		share_box.add_child(button)
	else:
		share_box.add_child(_wrapped("物品分享中，等待队友接收……", 13, ExpeditionUI.GOLD))
	var cancel := ExpeditionUI.button("取消分享")
	cancel.disabled = pending_action
	cancel.pressed.connect(func() -> void: _request("share_cancel", {}, "分享已取消。"))
	share_box.add_child(cancel)

func _has_space(entry: Dictionary, container: String) -> bool:
	var def := ItemDefs.get_item(str(entry["def_id"]))
	if container == "safe" and not bool(def.get("safe_allowed", false)):
		return false
	return inventory.find_first_fit(container, def["size"]) != null

func _take(entry: Dictionary, container: String, cell := Vector2i(-1, -1), rotated := false, slot := "") -> void:
	if entry.is_empty() or not bool(entry.get("available", false)):
		return
	var args := {"container": container, "def_id": str(entry["def_id"])}
	if entry.has("instance_id"):
		args["instance_id"] = int(entry["instance_id"])
	if slot != "":
		args["slot"] = slot
	if cell.x >= 0:
		args["cell"] = [cell.x, cell.y]
		args["rotated"] = rotated
	if str(entry["kind"]) == "loot_manage":
		args["operation"] = "move"
	var item_name: String = str(ItemDefs.get_item(str(entry["def_id"]))["name"])
	var note := "已装入%s。" % ExpeditionBaseline.CONTAINER_DISPLAY.get(container, container)
	if container == "equipped":
		note = "已装备到%s槽（牌第 1 回合入堆）。" % ExpeditionBaseline.SLOT_DISPLAY.get(slot, slot)
	_request(str(entry["kind"]), args, "%s%s" % [item_name, note])

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
	return {"loot_owner": get_instance_id(), "workspace_owner": get_instance_id(), "token": token, "def_id": str(entry["def_id"]), "quality": _entry_quality(entry), "instance_id": int(entry.get("instance_id", -1)) if str(entry["kind"]) == "loot_manage" else -1, "rotated": bool(entry.get("instance", {}).get("rotated", false))}

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

func _region_of(source: Dictionary, region_id: String) -> Dictionary:
	for region in source.get("regions", []):
		if str(region["id"]) == region_id:
			return region
	return {}


## 掉落装备/容器区域的固定框架：标题＋搜索按钮＋CorpseSearchGrid（紧凑小格）。
func _build_region_frame(region_id: String, title: String, is_slot: bool) -> PanelContainer:
	var panel := ExpeditionUI.panel(Color("#13262e"), ExpeditionUI.LINE, 6)
	panel.name = "SearchRegion_" + region_id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_slot:
		slot_frames[region_id] = panel
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var label := ExpeditionUI.label(title, 13 if is_slot else 14)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var button := ExpeditionUI.button("搜索")
	button.custom_minimum_size = Vector2(54, 28)
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(_search_region.bind(region_id))
	header.add_child(button)
	region_buttons[region_id] = button
	var region_grid := CorpseSearchGrid.new()
	region_grid.loot_owner = self
	region_grid.compact = true
	column.add_child(region_grid)
	source_grids[region_id] = region_grid
	return panel


## 空装备槽占位框（敌人没穿/没掉落：不建区域，扫不到）。
func _build_empty_slot_frame(slot: String) -> PanelContainer:
	var panel := ExpeditionUI.panel(Color("#0f1f26"), Color("#22333a"), 6)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := ExpeditionUI.label("%s — 空" % ExpeditionBaseline.SLOT_DISPLAY[slot], 12, ExpeditionUI.MUTED)
	label.custom_minimum_size.y = 64
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


func _render_search() -> void:
	var sources: Array = _resolved().get("corpses", [])
	var source: Dictionary = {}
	for value in sources:
		if str(value["id"]) == search_source:
			source = value
	if source.is_empty():
		ExpeditionUI.clear(context_column)
		count_label.text = "点击战场上的尸体开始搜索。"
		return
	loot_heading.text = "搜索 %s" % str(source.get("name", "尸体"))
	var layout_key := screen_identity + ":" + search_source
	if search_layout_key != layout_key:
		search_layout_key = layout_key
		source_grids.clear()
		region_buttons.clear()
		slot_frames.clear()
		ExpeditionUI.clear(context_column)
		var picker := OptionButton.new()
		picker.custom_minimum_size.y = 34
		for i in range(sources.size()):
			picker.add_item(str(sources[i]["name"]))
			if str(sources[i]["id"]) == search_source:
				picker.select(i)
		picker.item_selected.connect(func(index: int) -> void: _open_corpse(str(sources[index]["id"])))
		context_column.add_child(picker)
		var humanoid := false
		for region in source["regions"]:
			if ExpeditionBaseline.EQUIP_SLOTS.has(str(region["id"])):
				humanoid = true
		if humanoid:
			context_column.add_child(_wrapped("掉落装备 · 先扫这里（主武→副武→头盔→护甲）", 12, ExpeditionUI.GOLD))
			var equip_grid := GridContainer.new()
			equip_grid.columns = 2
			equip_grid.add_theme_constant_override("h_separation", 8)
			equip_grid.add_theme_constant_override("v_separation", 8)
			context_column.add_child(equip_grid)
			for slot in ExpeditionBaseline.EQUIP_SLOTS:
				if _region_of(source, slot).is_empty():
					equip_grid.add_child(_build_empty_slot_frame(slot))
				else:
					equip_grid.add_child(_build_region_frame(slot, ExpeditionBaseline.SLOT_DISPLAY[slot], true))
		for region in source["regions"]:
			var id := str(region["id"])
			if ExpeditionBaseline.EQUIP_SLOTS.has(id) or id == "ground":
				continue
			context_column.add_child(_build_region_frame(id, str(region["name"]), false))
		if not _region_of(source, "ground").is_empty():
			context_column.add_child(_build_region_frame("ground", "地上 · 最后搜索", false))
		ground_drops = VBoxContainer.new()
		ground_drops.add_theme_constant_override("separation", 4)
		context_column.add_child(ground_drops)
		share_box = VBoxContainer.new()
		share_box.add_theme_constant_override("separation", 6)
		context_column.add_child(share_box)
		corpse_detail_column = VBoxContainer.new()
		corpse_detail_column.add_theme_constant_override("separation", 10)
		context_column.add_child(corpse_detail_column)
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
		_refresh_workspace()
		_render_context()
		_render_detail()
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
		"weapon": return "提供攻击牌。装备到主/副武器槽可从第 1 回合使用；拖到装备槽即换装。"
		"helmet": return "提供防御与辅助牌。装备到头盔槽可从第 1 回合使用。"
		"armor": return "提供防御牌。装备到护甲槽可从第 1 回合使用；比较实际牌效再决定是否替换。"
		"supply": return "战斗中打出补给牌才会恢复生命，并消耗来源物品。搜刮时装包不会立即使用。"
		"rare_seed": return "撤离后可带回农场种植。优先放入保险箱，可以保护新的种子。"
		"cargo": return "适合带回出售。需要在金币收益、占格和战斗负担之间取舍。"
		"material": return "可带回用于制作；能否出售与保护以这件物品的说明为准。"
		_: return "提供抽牌或辅助牌，放在哪个容器决定它何时加入战斗。"

func _comparison(entry: Dictionary) -> String:
	var def := ItemDefs.get_item(str(entry["def_id"]))
	var category := str(def.get("category", ""))
	if not category in ["weapon", "armor", "helmet", "tool"]:
		return ""
	# 对比口径：装备槽与胸挂里的同类物品（第 1/2 回合来源）。
	var candidates: Array = inventory.equipped_list().duplicate()
	candidates.append_array(inventory.loadout_list("chest"))
	for instance in candidates:
		var other := ItemDefs.get_item(str(instance["def_id"]))
		if str(other.get("category", "")) != category or int(instance["instance_id"]) == int(entry.get("instance_id", -1)):
			continue
		var before := _card_strength(other)
		var after := _card_strength(def)
		var metric := "最大单牌伤害" if category == "weapon" else ("最大单牌格挡" if category == "armor" else "最大单牌抽牌")
		return "对比身上的%s\n占格 %d → %d  ·  %s %d → %d\n牌效以卡牌描述为准；换装后旧件自动回仓库。" % [other["name"], other["cards"].size(), def["cards"].size(), metric, before, after]
	return "身上暂没有同类物品可比较。"

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
