class_name ExpeditionMapPanel
extends Control
## 洞窟探索主界面（2.4 设计 D2.4-01~07）：地图、节点内容、搜刮、撤离确认、
## 暂停菜单与结算展示。规则全部走 ExpeditionGame；本面板只展示与转发操作。

signal battle_start_requested(combat: CombatGame)
signal farm_save_requested
signal run_finished

## 合作局会话裁定入口（F-04）：设置后所有推进/领取/撤离动作改走主机裁定，
## 双人同票才推进；单人局此入口为空，直接调本地 ExpeditionGame。
var host_action_sink: Callable = Callable()

const FOREST := Color("#294f3c")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const TEXT_MUTED := Color("#3f4a42")
# 暗底面板（主背景 #20332a）上的正文/说明用浅色；TEXT_DARK/TEXT_MUTED 只给奶油色覆盖层用。
const LIGHT_TEXT := Color("#e8f2d8")
const LIGHT_MUTED := Color("#a3b59b")
const BAD_RED := Color("#a4543f")
const WARN_GOLD := Color("#9b713a")
const GOOD_GREEN := Color("#3f7048")

var expedition: ExpeditionGame
var header_label: Label
var map_column: VBoxContainer
var node_column: VBoxContainer
var log_label: RichTextLabel
var overlay_panel: PanelContainer
var overlay_center: CenterContainer
var overlay_column: VBoxContainer
var route_view: ExpeditionRoute
var selected_route := Vector2i(-1, -1)
var log_box: VBoxContainer
var capacity_label: Label
var layer_title: Label
var overlay_scroll: ScrollContainer
var modal_shade: ColorRect
var settlement_visible := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	theme = ExpeditionUI.make_theme()
	_build()


func open(instance: ExpeditionGame) -> void:
	expedition = instance
	visible = true
	if not overlay_panel.visible:
		overlay_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()


func close() -> void:
	visible = false
	expedition = null


func _build() -> void:
	ExpeditionUI.backdrop(self)
	var frame := ExpeditionUI.frame(self, 20)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 16)
	column.add_child(title_row)
	layer_title = _label("矿洞探索", 27, CREAM)
	layer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(layer_title)
	var journal := ExpeditionUI.button("探险记录")
	journal.pressed.connect(func() -> void: log_box.visible = not log_box.visible)
	title_row.add_child(journal)
	var pause := ExpeditionUI.button("☰  菜单")
	pause.pressed.connect(_open_menu)
	title_row.add_child(pause)
	header_label = _label("", 15, ExpeditionUI.GOLD)
	header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(header_label)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	var left := ExpeditionUI.panel(Color("#172a33dd"), ExpeditionUI.LINE, 14)
	left.custom_minimum_size.x = 370
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.9
	body.add_child(left)
	map_column = VBoxContainer.new()
	map_column.add_theme_constant_override("separation", 6)
	left.add_child(map_column)
	map_column.add_child(_label("路线图  /  向上深入", 16, CREAM))
	route_view = ExpeditionRoute.new()
	route_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	route_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	route_view.node_selected.connect(_select_route)
	map_column.add_child(route_view)
	map_column.add_child(_label("◆ 当前位置   ✓ 已完成   金色连线：下一步", 12, ExpeditionUI.MUTED))
	var right := ExpeditionUI.panel(Color("#1b2d35ed"), ExpeditionUI.LINE, 18)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var right_column := VBoxContainer.new()
	right_column.add_theme_constant_override("separation", 12)
	right.add_child(right_column)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.add_child(scroll)
	node_column = VBoxContainer.new()
	node_column.add_theme_constant_override("separation", 12)
	node_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(node_column)
	capacity_label = _label("", 12, ExpeditionUI.MUTED)
	capacity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_column.add_child(capacity_label)
	log_box = VBoxContainer.new()
	log_box.visible = false
	column.add_child(log_box)
	log_label = RichTextLabel.new()
	log_label.scroll_following = true
	log_label.custom_minimum_size.y = 70
	log_label.add_theme_font_size_override("normal_font_size", 13)
	log_label.add_theme_color_override("default_color", ExpeditionUI.MUTED)
	log_box.add_child(log_label)
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0.02, 0.05, 0.07, 0.62)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_shade.visible = false
	modal_shade.z_index = 90
	add_child(modal_shade)
	overlay_center = CenterContainer.new()
	overlay_center.z_index = 100
	overlay_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay_center)
	overlay_panel = ExpeditionUI.panel(CREAM, ExpeditionUI.GOLD, 22)
	overlay_panel.custom_minimum_size.x = 520
	overlay_panel.visible = false
	overlay_center.add_child(overlay_panel)
	overlay_scroll = ScrollContainer.new()
	overlay_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	overlay_scroll.custom_minimum_size = Vector2(470, 0)
	overlay_panel.add_child(overlay_scroll)
	overlay_column = VBoxContainer.new()
	overlay_column.add_theme_constant_override("separation", 10)
	overlay_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_scroll.add_child(overlay_column)
	overlay_column.minimum_size_changed.connect(func() -> void: _fit_overlay.call_deferred())


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
	layer_title.text = str(ExpeditionDefs.layer(str(run["layer_id"])).get("name", "矿洞探索"))
	header_label.text = "深度 %02d / %02d   ·   生命 %d/%d   ·   补给 %d   ·   携带价值 %d 金币   ·   保险箱 %d 金币%s%s" % [
		int(run["current"]["row"]), int(ExpeditionDefs.layer(str(run["layer_id"])).get("rows", 9)) - 1,
		int(run["player"]["hp"]), int(run["player"]["max_hp"]), supplies,
		inventory.carry_sell_value(), inventory.protected_value(), _coop_note(run), _vote_note(run)]
	if selected_route.x != int(run["current"]["row"]) + 1 or str(run["phase"]) != "map":
		selected_route = Vector2i(-1, -1)
	_refresh_map()
	_refresh_node()
	var capacities: Array[String] = []
	for container in ["pack", "safe"]:
		var dimensions := ExpeditionBaseline.size_for(inventory.expedition, container)
		var used := 0
		for instance in inventory.loadout_list(container):
			var item: Dictionary = ItemDefs.get_item(str(instance["def_id"]))
			used += int(item["size"].x * item["size"].y)
		var free := ExpeditionBaseline.largest_free_rect(container, inventory.loadout_list(container), inventory.expedition)
		capacities.append("%s %d/%d 格 · 最大空位 %d×%d" % [ExpeditionBaseline.CONTAINER_DISPLAY[container], used, dimensions.x * dimensions.y, free.x, free.y])
	capacity_label.text = "\n".join(capacities)
	var entries: Array = run.get("log", [])
	log_label.text = "\n".join(entries.slice(maxi(0, entries.size() - 8), entries.size()))


func _coop_note(run: Dictionary) -> String:
	if not bool(run.get("coop", false)):
		return ""
	var guest: Dictionary = run.get("guest", {})
	return " ｜ 队友 %d/%d" % [int(guest.get("hp", 0)), int(guest.get("max_hp", 0))]


## 选路投票进度（两人各自投了哪一格；非等待期返回空）。
func _vote_note(run: Dictionary) -> String:
	var votes: Dictionary = run.get("votes", {})
	var mine := str(votes.get("p1", ""))
	var theirs := str(votes.get("p2", ""))
	if mine == "" and theirs == "":
		return ""
	var next_row := int(run["current"]["row"]) + 1
	var parts: Array = []
	if mine != "" and int(mine.split(",")[0]) == next_row:
		parts.append("你已投第 %s 排·列 %s" % [mine.split(",")[0], mine.split(",")[1]])
	if theirs != "" and int(theirs.split(",")[0]) == next_row:
		parts.append("队友已投第 %s 排·列 %s" % [theirs.split(",")[0], theirs.split(",")[1]])
	if parts.is_empty():
		return ""
	return " ｜ " + "；".join(parts)


func _refresh_map() -> void:
	route_view.display(expedition.run)

func _select_route(row: int, col: int) -> void:
	selected_route = Vector2i(row, col)
	_refresh_node()


func _refresh_node() -> void:
	for child in node_column.get_children():
		node_column.remove_child(child)
		child.queue_free()
	var run: Dictionary = expedition.run
	if str(run["phase"]) == "map":
		_refresh_route_preview()
		return
	var node := expedition.current_node()
	if node.is_empty():
		return
	var key := expedition.node_id(int(run["current"]["row"]), int(run["current"]["col"]))
	var resolved: Dictionary = run["resolved"].get(key, {})
	var art := ExpeditionArt.new()
	art.subject = _node_art(str(node["type"]))
	art.tint = ExpeditionUI.GOLD
	art.custom_minimum_size.y = 100
	node_column.add_child(art)
	var title := _label("%s  /  %s" % [ExpeditionDefs.NODE_TYPE_DISPLAY.get(str(node["type"]), "?"), str(node.get("hint", ""))], 22, CREAM)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
			node_column.add_child(_label("撤离站：带着收获回家，或继续挑战守门战。", 14, LIGHT_TEXT))
			var extract := _button("在此撤离（带着收获回家）", Color("#ffd98a"), WARN_GOLD)
			extract.pressed.connect(_open_extract_confirm)
			node_column.add_child(extract)
			var deeper := _button("继续深入", CREAM, GOOD_GREEN)
			deeper.pressed.connect(_on_leave_node)
			node_column.add_child(deeper)


func _refresh_battle_node(node: Dictionary, resolved: Dictionary, key: String) -> void:
	var run: Dictionary = expedition.run
	if not bool(resolved.get("battle_won", false)):
		var warn := str(node.get("risk", "")) == "high"
		node_column.add_child(_label("高风险：偏向装备与稀有资源，奖励候选更好但不保证都能带走。" if warn else "浅层敌人组合。", 14, BAD_RED if warn else LIGHT_MUTED))
		var fight := _button("进入战斗", Color("#ffd98a"), Color("#9b713a"))
		fight.pressed.connect(_on_start_battle)
		node_column.add_child(fight)
		return
	_refresh_rewards_area(resolved, key, true)


func _refresh_reward_node(_node: Dictionary, resolved: Dictionary, key: String) -> void:
	node_column.add_child(_label("候选物品（带走需要空间，离开时未带走的放弃）：", 14, LIGHT_MUTED))
	_refresh_rewards_area(resolved, key, false)


func _refresh_rewards_area(resolved: Dictionary, key: String, choose_one: bool) -> void:
	## choose_one：普通战斗个人奖励二选一（选中后另一件消失）；宝箱/采集全部可领。
	## 领取状态以规则层 resolved.claimed 为准（F-02）：本人已领的不再出按钮。
	var run: Dictionary = expedition.run
	var inventory := expedition.run_inventory()
	var rewards: Array = resolved.get("rewards", [])
	var public_items: Array = resolved.get("public", [])
	var claimed: Dictionary = resolved.get("claimed", {})
	var mine: Array = claimed.get("p1", [])
	var choice_locked := choose_one and not mine.is_empty()
	for def_id in rewards:
		var def := ItemDefs.get_item(str(def_id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var already := choice_locked or mine.has(str(def_id))
		var suffix := "✓ 已领取" if mine.has(str(def_id)) else ("已放弃（选择已锁定）" if choice_locked else "")
		var info := _label("%s（%d×%d，%d 张牌，%s）%s" % [def["name"], def["size"].x, def["size"].y, def["cards"].size(),
			"可售 %d 金币" % int(def.get("base_value", 0)) if bool(def.get("sellable", false)) else "不可售", suffix], 14, LIGHT_TEXT)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		if not already:
			var claim_pack := _button("放入背包", Color("#eaf4df"), Color("#87b06f"))
			claim_pack.pressed.connect(_on_claim_reward.bind(key, str(def_id), "pack", choose_one))
			row.add_child(claim_pack)
			if bool(def.get("safe_allowed", false)):
				var claim_safe := _button("放保险箱", Color("#fff5df"), Color("#d5b87d"))
				claim_safe.pressed.connect(_on_claim_reward.bind(key, str(def_id), "safe", choose_one))
				row.add_child(claim_safe)
		var reward_card := ExpeditionUI.panel(Color("#233941"), ExpeditionUI.LINE, 12)
		reward_card.add_child(row)
		node_column.add_child(reward_card)
	if not public_items.is_empty():
		node_column.add_child(_label("公共物资（不占个人选择次数）：", 13, LIGHT_MUTED))
		for def_id in public_items:
			var def := ItemDefs.get_item(str(def_id))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var info := _label("%s" % def["name"], 14, LIGHT_TEXT)
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
			var info := _label("%s（丢弃物）" % def["name"], 13, LIGHT_MUTED)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			var pick := _button("捡回", Color("#fff5df"), Color("#d5b87d"))
			pick.pressed.connect(_on_pick_drop.bind(int(instance["instance_id"])))
			row.add_child(pick)
			node_column.add_child(row)
	_refresh_share_area()
	var leave := _button("完成并离开本节点", Color("#ffd98a"), Color("#9b713a"))
	leave.pressed.connect(_on_leave_node)
	node_column.add_child(leave)


## 合作局的分享区（F-04）：待确认提议的接受/取消；自己可提出分享首件背包物。
func _refresh_share_area() -> void:
	if not bool(expedition.run.get("coop", false)):
		return
	var offer: Dictionary = expedition.run.get("share_offer", {})
	if offer.is_empty():
		var share := _button("分享背包首件物品给队友", Color("#fff5df"), Color("#d5b87d"))
		share.pressed.connect(func() -> void:
			var pack: Array = expedition.run_inventory().loadout_list("pack")
			if pack.is_empty():
				_flash_overlay("背包里没有可分享的物品。")
				return
			if host_action_sink.is_valid():
				var offered: Dictionary = _arbitrate("share_offer", {"instance_id": int(pack[0]["instance_id"])})
				if not offered.is_empty() and not bool(offered.get("ok", true)):
					_flash_overlay(str(offered.get("reason", "")))
				return
			var result := expedition.share_offer("p1", int(pack[0]["instance_id"]))
			if not result["ok"]:
				_flash_overlay(result["reason"])
			_refresh()
		)
		node_column.add_child(share)
		return
	if str(offer.get("from", "")) == "p2":
		var item_name := str(ItemDefs.get_item(str(expedition.member_inventory("p2").find_instance(int(offer.get("instance_id", 0))).get("def_id", ""))).get("name", "?"))
		var accept := _button("接受队友分享：%s（放背包）" % item_name, Color("#eaf4df"), Color("#87b06f"))
		accept.pressed.connect(func() -> void:
			if host_action_sink.is_valid():
				var taken: Dictionary = _arbitrate("share_accept", {"container": "pack"})
				if not taken.is_empty() and not bool(taken.get("ok", true)):
					_flash_overlay(str(taken.get("reason", "")))
				return
			var result := expedition.share_accept("p1", "pack")
			if not result["ok"]:
				_flash_overlay(result["reason"])
			_refresh()
		)
		node_column.add_child(accept)
	else:
		node_column.add_child(_label("已向队友提出分享，等待对方处理……", 13, WARN_GOLD))
	var cancel := _button("取消分享", Color("#fff5df"), Color("#d5b87d"))
	cancel.pressed.connect(func() -> void:
		if host_action_sink.is_valid():
			_arbitrate("share_cancel", {})
			return
		expedition.share_cancel()
		_refresh()
	)
	node_column.add_child(cancel)


func _refresh_event_node(resolved: Dictionary, _key: String) -> void:
	var event: Dictionary = ExpeditionDefs.EVENTS.get(str(resolved.get("event_id", "")), {})
	if event.is_empty():
		node_column.add_child(_label("（这里很安静）", 14, LIGHT_MUTED))
		return
	node_column.add_child(_label("事件：%s" % event["name"], 16, CREAM))
	var event_desc := _label(str(event["desc"]), 14, Color("#cfe2c2"))
	event_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node_column.add_child(event_desc)
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
		node_column.add_child(_label("免费小休整（二选一，确认后不能切换）：", 14, LIGHT_MUTED))
		var heal := _button("休息：恢复 8 生命", Color("#eaf4df"), Color("#87b06f"))
		heal.pressed.connect(_on_rest.bind("heal"))
		node_column.add_child(heal)
		var prepare := _button("检查装备：下一场首回合多抽 1 张", Color("#fff5df"), Color("#d5b87d"))
		prepare.pressed.connect(_on_rest.bind("prepare"))
		node_column.add_child(prepare)
	else:
		node_column.add_child(_label("休整已完成。", 13, LIGHT_MUTED))
	var extract := _button("在此撤离（带着收获回家）", Color("#ffd98a"), Color("#9b713a"))
	extract.pressed.connect(_open_extract_confirm)
	node_column.add_child(extract)
	var leave := _button("继续深入", Color("#eaf4df"), Color("#87b06f"))
	leave.pressed.connect(_on_leave_node)
	node_column.add_child(leave)


# —— 操作 ————————————————————————————————————————————————————————


## 合作局动作统一入口：经 sink 交给 SessionHost 裁定并广播镜像；返回结果字典。
## 单人局返回空字典（调用方走本地路径）。
func _arbitrate(kind: String, args: Dictionary = {}) -> Dictionary:
	if not host_action_sink.is_valid():
		return {}
	var result: Dictionary = host_action_sink.call(kind, args)
	_refresh()
	return result


## 统一结果消费：失败弹原因；带回结算则展示结算。
func _handle_run_result(result: Dictionary) -> void:
	if result.is_empty():
		return
	if not bool(result.get("ok", true)):
		_flash_overlay(str(result.get("reason", "")))
		return
	if result.has("settlements"):
		var host_settle: Dictionary = result["settlements"].get("p1", {})
		if not host_settle.is_empty() and host_settle.has("settlement_id"):
			_show_settlement(host_settle)
			return
	if result.has("settlement") and (result["settlement"] as Dictionary).has("settlement_id"):
		_show_settlement(result["settlement"])


func _on_move(row: int, col: int) -> void:
	if host_action_sink.is_valid():
		## 合作局：投票经主机裁定，同票才前进；投票进度显示在顶栏（_vote_note）。
		var voted: Dictionary = _arbitrate("vote_move", {"row": row, "col": col})
		if not voted.is_empty() and not bool(voted.get("ok", true)):
			_flash_overlay(str(voted.get("reason", "")))
		return
	var result := expedition.move_to(row, col)
	if not result["ok"]:
		_flash_overlay(result["reason"])
	_refresh()


func _on_start_battle() -> void:
	if host_action_sink.is_valid():
		var started: Dictionary = _arbitrate("start_battle", {})
		if bool(started.get("ok", false)) and started.has("combat"):
			battle_start_requested.emit(started["combat"])
		elif not started.is_empty() and not bool(started.get("ok", true)):
			_flash_overlay(str(started.get("reason", "")))
		return
	var result := expedition.start_battle()
	if not result["ok"]:
		_flash_overlay(result["reason"])
		return
	battle_start_requested.emit(result["combat"])


func battle_finished() -> void:
	## battle_screen 关闭后由外部调用：结算战斗并回到节点或显示结算。
	if host_action_sink.is_valid():
		## 合作局：结束战斗也走裁定（主机结算＋向客机下发结算单）。
		_handle_run_result(_arbitrate("finish_battle", {}))
		return
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


func _on_claim_reward(key: String, def_id: String, container: String, _choose_one: bool) -> void:
	## 领取走规则层事务（F-02）；合作局经主机裁定（F-04）。
	if host_action_sink.is_valid():
		var claimed: Dictionary = _arbitrate("claim_reward", {"def_id": def_id, "container": container})
		if not claimed.is_empty() and not bool(claimed.get("ok", true)):
			_flash_overlay(str(claimed.get("reason", "")))
		return
	var result := expedition.claim_node_reward("p1", key, def_id, container)
	if not result["ok"]:
		_flash_overlay(str(result["reason"]))
		_refresh()
		return
	_refresh()


func _on_claim_public(key: String, def_id: String) -> void:
	if host_action_sink.is_valid():
		var claimed: Dictionary = _arbitrate("claim_public", {"def_id": def_id})
		if not claimed.is_empty() and not bool(claimed.get("ok", true)):
			_flash_overlay(str(claimed.get("reason", "")))
		return
	var result := expedition.claim_node_public("p1", key, def_id)
	if not result["ok"]:
		_flash_overlay(str(result["reason"]))
	_refresh()


func _on_pick_drop(instance_id: int) -> void:
	## 从节点公共区捡回（规则层事务；合作局经主机裁定）。
	if host_action_sink.is_valid():
		var picked: Dictionary = _arbitrate("pick_drop", {"instance_id": instance_id})
		if not picked.is_empty() and not bool(picked.get("ok", true)):
			_flash_overlay(str(picked.get("reason", "")))
		return
	var result := expedition.pick_node_drop("p1", instance_id)
	if not result["ok"]:
		_flash_overlay(str(result["reason"]))
	_refresh()


func _leave_node_now() -> void:
	## 离开节点（确认弹窗后的实际动作）：合作局经主机裁定。
	if host_action_sink.is_valid():
		_handle_run_result(_arbitrate("leave_node", {}))
		return
	var result := expedition.leave_node()
	if not result["ok"]:
		_flash_overlay(result["reason"])
	elif result.get("settlement", {}).has("settlement_id"):
		_show_settlement(result["settlement"])
	else:
		_refresh()


func _on_leave_node() -> void:
	var run: Dictionary = expedition.run
	var resolved: Dictionary = run["resolved"].get(expedition.node_id(int(run["current"]["row"]), int(run["current"]["col"])), {})
	var mine: Array = resolved.get("claimed", {}).get("p1", [])
	var node := expedition.current_node()
	var choice_locked := str(node.get("type", "")) in ["battle", "elite", "gate"] and not mine.is_empty()
	var pending := int(resolved.get("public", []).size())
	if not choice_locked:
		for id in resolved.get("rewards", []):
			if not mine.has(str(id)):
				pending += 1
	if pending > 0 or not run["node_drops"].is_empty():
		_confirm_overlay("还有 %d 件候选/公共物品未领取，离开后将放弃。确认离开？" % (pending + run["node_drops"].size()), func() -> void:
			_leave_node_now()
		)
		return
	_leave_node_now()


func _on_choose_event(option_id: String) -> void:
	if host_action_sink.is_valid():
		var chosen: Dictionary = _arbitrate("choose_event", {"option": option_id})
		if not chosen.is_empty() and not bool(chosen.get("ok", true)):
			_flash_overlay(str(chosen.get("reason", "")))
		return
	var result := expedition.choose_event(option_id)
	if not result["ok"]:
		_flash_overlay(result["reason"])
	_refresh()


func _on_rest(option: String) -> void:
	if host_action_sink.is_valid():
		var rested: Dictionary = _arbitrate("take_rest", {"option": option})
		if not rested.is_empty() and not bool(rested.get("ok", true)):
			_flash_overlay(str(rested.get("reason", "")))
		return
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
	var decision_title := _label("撤离决策", 20, FOREST)
	decision_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(decision_title)
	for line in [
		_label("带入装备：%d 件（可售 %d 金币），回家后返还仓库。" % [brought, brought_value], 14, TEXT_DARK),
		_label("新增战利品：%d 件（可售 %d 金币），带回后可出售或制作。" % [gained, gained_value], 14, TEXT_DARK),
		_label("保护区（保险箱，失败也保留）：%d 金币" % protected_value, 14, GOOD_GREEN),
		_label("当前生命 %d/%d；下一段风险更高、资源倾向更好。" % [int(run["player"]["hp"]), int(run["player"]["max_hp"])], 13, TEXT_MUTED),
	]:
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(line)
	var go_home := _button("带着这些回家", Color("#ffd98a"), Color("#9b713a"))
	go_home.pressed.connect(func() -> void:
		_close_overlay()
		if host_action_sink.is_valid():
			## 合作局：撤离是共同确认——先投自己一票，等队友也确认才结算。
			var voted: Dictionary = _arbitrate("vote_extract", {"agree": true})
			if bool(voted.get("waiting", false)):
				_flash_overlay("你已确认撤离；等队友也确认后一起回家。")
			else:
				_handle_run_result(voted)
			return
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
		if host_action_sink.is_valid():
			var declined: Dictionary = _arbitrate("vote_extract", {"agree": false})
			if not declined.is_empty() and not bool(declined.get("ok", true)):
				_flash_overlay(str(declined.get("reason", "")))
			_leave_node_now()
			return
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
			if host_action_sink.is_valid():
				## 合作局：个人放弃（只结算本人，队友继续）。
				_handle_run_result(_arbitrate("abandon_member", {}))
				return
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
	var kind_text := {"extract": "成功撤离回家", "gate_clear": "击败最后的守门者，探险完成", "death": "战斗失败……", "abandon": "已放弃本次探险"}
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
		var group_line := _label("%s（%d）：%s" % [group[1], entries.size(), "、".join(names)], 14, TEXT_DARK if group[0] != "lost" else BAD_RED)
		group_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(group_line)
	var note := _label("货物仍是货物，回家后自行出售才变金币。", 12, TEXT_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	var done := _button("确认回家", Color("#eaf4df"), Color("#87b06f"))
	done.pressed.connect(func() -> void:
		_close_overlay()
		close()
		run_finished.emit()
		farm_save_requested.emit()
	)
	column.add_child(done)
	_show_overlay(column)
	settlement_visible = true


# —— 覆盖层 ————————————————————————————————————————————————


func _show_overlay(content: Control) -> void:
	settlement_visible = false
	for child in overlay_column.get_children():
		overlay_column.remove_child(child)
		child.queue_free()
	overlay_column.add_child(content)
	overlay_panel.visible = true
	modal_shade.visible = true
	overlay_scroll.custom_minimum_size.y = minf(520, get_viewport_rect().size.y - 100)
	_fit_overlay.call_deferred()
	# 覆盖层弹出时恢复拦截：点在面板外的点击不应穿透到地图按钮。
	overlay_center.mouse_filter = Control.MOUSE_FILTER_STOP


func _close_overlay() -> void:
	settlement_visible = false
	overlay_panel.visible = false
	modal_shade.visible = false
	overlay_center.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _confirm_overlay(message: String, on_yes: Callable) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	var message_label := _label(message, 15, TEXT_DARK)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message_label)
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
	var message_label := _label(message, 15, BAD_RED)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message_label)
	var ok := _button("知道了", Color("#fff5df"), Color("#d5b87d"))
	ok.pressed.connect(_close_overlay)
	column.add_child(ok)
	_show_overlay(column)


# —— 小构件 ——————————————————————————————————————————————————————




func _label(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	# 默认不换行：autowrap 标签在 HBox 里会被压到一字宽竖排；长文本处显式开启。
	return label


func _button(content: String, fill: Color, _border: Color) -> Button:
	return ExpeditionUI.button(content, fill == Color("#ffd98a"))


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.is_action_pressed("pause"):
		if overlay_panel.visible:
			if not settlement_visible:
				_close_overlay()
		elif selected_route.x >= 0:
			selected_route = Vector2i(-1, -1)
			_refresh_node()
		else:
			_open_menu()
		get_viewport().set_input_as_handled()

func _node_art(type: String) -> String:
	return {"battle": "attack", "elite": "attack", "gate": "shield", "chest": "chest", "gather": "crystal", "event": "draw", "rest_exit": "rest", "exit": "exit"}.get(type, "start")

func _refresh_route_preview() -> void:
	if selected_route.x < 0:
		var art := ExpeditionArt.new()
		art.subject = "start"
		art.custom_minimum_size.y = 160
		node_column.add_child(art)
		node_column.add_child(_label("下一步，走向哪里？", 26, CREAM))
		var note := _label("点击路线图上下一排的节点，查看风险和遭遇，再确认前进。\n休整站可恢复生命，也能带着战利品安全撤离。", 16, LIGHT_MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		node_column.add_child(note)
		return
	var node: Dictionary = expedition.run["map"]["rows"][selected_route.x][selected_route.y]
	var art := ExpeditionArt.new()
	art.subject = _node_art(str(node["type"]))
	art.tint = ExpeditionUI.RED if str(node.get("risk", "")) == "high" else ExpeditionUI.GOLD
	art.custom_minimum_size.y = 140
	node_column.add_child(art)
	node_column.add_child(_label("下一站 · %s" % ExpeditionDefs.NODE_TYPE_DISPLAY.get(str(node["type"]), "?"), 26, CREAM))
	node_column.add_child(_label(ExpeditionRoute.risk_text(str(node.get("risk", "none"))), 15, art.tint))
	var hint := _label(str(node.get("hint", "")), 16, LIGHT_TEXT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node_column.add_child(hint)
	var encounter_id := str(node.get("encounter", ""))
	if CombatGame.ENCOUNTERS.has(encounter_id):
		var names: Array[String] = []
		for id in CombatGame.ENCOUNTERS[encounter_id]["enemies"]:
			names.append(str(CombatGame.ENEMIES[id]["name"]))
		var enemies := _label("可能遭遇：" + "、".join(names), 14, LIGHT_MUTED)
		enemies.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		node_column.add_child(enemies)
	var go := ExpeditionUI.button("确认选路 / 投票前进" if bool(expedition.run.get("coop", false)) else "向这里前进   →", true)
	go.pressed.connect(_on_move.bind(selected_route.x, selected_route.y))
	node_column.add_child(go)

func _fit_overlay() -> void:
	if overlay_panel.visible:
		overlay_scroll.custom_minimum_size.y = minf(get_viewport_rect().size.y - 110, overlay_column.get_combined_minimum_size().y + 8)
