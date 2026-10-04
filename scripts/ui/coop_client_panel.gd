class_name CoopClientPanel
extends Control
## 合作局·客机界面（F-04 重做）。展示主机广播的局快照；所有操作以意图发给主机裁定：
## 地图投票、节点领取/事件/休整/离开、战斗出牌（p2 视角，复用 BattleScreen）、
## 分享、撤离投票、个人放弃。本面板 _process 泵网络。

signal close_requested

const FOREST := Color("#294f3c")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const BAD_RED := Color("#a4543f")
const WARN_GOLD := Color("#9b713a")
const LIGHT_TEXT := Color("#e8f2d8")
const LIGHT_MUTED := Color("#a3b59b")

var client: SessionClient
var status_label: Label
var state_label: Label
var body_column: VBoxContainer
var log_label: RichTextLabel
var battle_screen: BattleScreen
var loot_panel: ExpeditionLootPanel
var main_frame: CenterContainer
## 镜像版本：仅快照变化时重建界面，避免每帧重建按钮。
var _mirror_version := -1
var selected_route := Vector2i(-1,-1)
var route_detail: VBoxContainer
var settlement_receipt: Dictionary = {}
var live_actions: HBoxContainer
var return_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	theme = ExpeditionUI.make_theme()
	_build()
	set_process(true)


func open(target_client: SessionClient) -> void:
	client = target_client
	if not client.run_received.is_connected(_on_run):
		client.run_received.connect(_on_run)
	if not client.action_result_received.is_connected(_on_result):
		client.action_result_received.connect(_on_result)
	if not client.settlement_received.is_connected(_on_settlement):
		client.settlement_received.connect(_on_settlement)
	_mirror_version = -1
	visible = true
	_refresh()


func close() -> void:
	visible = false
	if battle_screen != null:
		battle_screen.visible = false
	if loot_panel != null:
		loot_panel.visible = false


func _process(_delta: float) -> void:
	if client == null:
		return
	client.poll()
	if visible and _mirror_dirty():
		_refresh()


func _mirror_dirty() -> bool:
	return client.mirror_serial != _mirror_version


func _mirror_serial_dirty() -> void:
	_mirror_version = -1


func _on_run(run: Dictionary) -> void:
	_mirror_serial_dirty()  # 新快照到达：置脏，下一帧重建


func _on_result(action_id: String, result: Dictionary) -> void:
	if loot_panel != null:
		loot_panel.acknowledge(action_id, result, client.mirror_serial)
	if battle_screen != null and battle_screen.visible and battle_screen.pending_action and action_id == battle_screen.pending_action_id:
		battle_screen.pending_acknowledged = true
		if not bool(result.get("ok", false)):
			battle_screen.pending_action = false
			battle_screen.status_label.text = "主机裁定：%s" % str(result.get("reason", ""))
		battle_screen.combat = _mirror_combat()
		battle_screen._refresh()
		for event in result.get("events", []):
			if str(event.get("type", "")) == "card_played" and str(event.get("owner", "")) == "p2":
				battle_screen.played_count += 1
		battle_screen._flash_events(result.get("events", []))
	if not bool(result.get("ok", true)):
		_flash("主机裁定：%s" % str(result.get("reason", "")))


func _on_settlement(settlement: Dictionary) -> void:
	settlement_receipt = settlement.duplicate(true)
	_mirror_serial_dirty()
	_flash("结算单已收到，正在核对农场入库记录。")


func _build() -> void:
	ExpeditionUI.backdrop(self)
	var shade := ColorRect.new()
	shade.color = Color(0.09,0.13,0.10,0.15)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	main_frame = center
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := _panel(ExpeditionUI.PANEL, ExpeditionUI.LINE, 16)
	panel.custom_minimum_size = Vector2(1120, 730)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := _label("洞内探险 · 与队友同行",26,CREAM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var journal := ExpeditionUI.button("探险记录")
	journal.pressed.connect(func(): log_label.visible = not log_label.visible)
	heading.add_child(journal)
	state_label = _label("", 15, Color("#e8d9a8"))
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(state_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	body_column = VBoxContainer.new()
	body_column.add_theme_constant_override("separation", 6)
	body_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body_column)
	status_label = _label("", 13, WARN_GOLD)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = false
	log_label.scroll_following = true
	log_label.custom_minimum_size = Vector2(0, 90)
	log_label.visible = false
	log_label.add_theme_font_size_override("normal_font_size", 13)
	log_label.add_theme_color_override("default_color", Color("#cfe2c2"))
	column.add_child(log_label)
	var bottom := HBoxContainer.new()
	live_actions = bottom
	bottom.add_theme_constant_override("separation", 8)
	column.add_child(bottom)
	var signal_button := _small("建议撤离", Color("#e8f0d8"), Color("#87b06f"))
	signal_button.pressed.connect(func() -> void:
		client.send_action("signal", {"text": "建议撤离"})
		_flash("已发信号：建议撤离。"))
	bottom.add_child(signal_button)
	var abandon_button := _button("个人放弃（损失未保护物）", Color("#f0d9cf"), Color("#a4543f"))
	abandon_button.pressed.connect(func() -> void: client.send_action("abandon_member", {}))
	bottom.add_child(abandon_button)
	var close_button := _button("回营地休息 · 当前探险保留", Color("#fff5df"), Color("#d5b87d"))
	close_button.pressed.connect(_on_close)
	column.add_child(close_button)
	return_button = close_button
	## 客机战斗界面：p2 视角，出牌/结束回合经会话意图发给主机（F-04）。
	battle_screen = preload("res://scenes/battle_screen.tscn").instantiate()
	battle_screen.player_key = "p2"
	battle_screen.action_sink = func(kind: String, args: Dictionary) -> Variant:
		return client.send_action(kind, args)
	battle_screen.combat_refresher = func() -> CombatGame: return _mirror_combat()
	add_child(battle_screen)
	loot_panel = ExpeditionLootPanel.new()
	loot_panel.z_index = 10
	loot_panel.action_sink = func(kind: String, args: Dictionary) -> Variant: return client.send_action(kind, args)
	loot_panel.menu_requested.connect(_on_close)
	add_child(loot_panel)


# —— 刷新 ————————————————————————————————————————————————————————


func _refresh() -> void:
	if client == null:
		return
	var run: Dictionary = client.mirror_run
	if run.is_empty():
		state_label.text = "等待主机开局……"
		return
	_mirror_version = client.mirror_serial
	ExpeditionUI.set_layer(self,str(run.get("layer_id","moss_stone_shallow")))
	live_actions.visible = str(run.get("phase","")) != "over"
	return_button.visible = true
	return_button.text = "回洞口营地 · 整理收获" if not live_actions.visible else "回营地休息 · 当前探险保留"
	main_frame.visible = not ExpeditionLootPanel.is_loot_phase(run)
	loot_panel.display(run, "p2", client.mirror_serial)
	if battle_screen != null and battle_screen.visible and str(run.get("phase", "")) != "battle":
		battle_screen.visible = false
	var me: Dictionary = run.get("guest", {})
	var host: Dictionary = run.get("player", {})
	state_label.text = "%s ｜ 第 %d/8 排 ｜ 你的生命 %d/%d ｜ 队友 %d/%d ｜ 阶段：%s" % [
		ExpeditionDefs.layer(str(run.get("layer_id", ""))).get("name", "?"),
		int(run.get("current", {}).get("row", 0)),
		int(me.get("hp", 40)), int(me.get("max_hp", 40)),
		int(host.get("hp", 40)), int(host.get("max_hp", 40)),
		_phase_text(str(run.get("phase", "")))]
	for child in body_column.get_children():
		body_column.remove_child(child)
		child.queue_free()
	match str(run.get("phase", "")):
		"map":
			_refresh_map_votes()
		"node":
			if not ExpeditionLootPanel.is_loot_phase(run):
				_refresh_node()
		"battle":
			_open_battle()
		"over":
			if str(settlement_receipt.get("run_id","")) == str(run.get("run_id","")) and not settlement_receipt.is_empty():
				return_button.visible = false
				var applied: bool = client.farm_game != null and client.farm_game.state["expedition"].get("applied_settlements",[]).has(str(settlement_receipt.get("settlement_id","")))
				body_column.add_child(ExpeditionSettlement.build(settlement_receipt,applied,_on_close))
			else:
				body_column.add_child(_label("探险已结束，等待本次结算单。",20,LIGHT_TEXT))
	var entries: Array = run.get("log", [])
	log_label.text = "\n".join(entries.slice(maxi(0, entries.size() - 8), entries.size()))


## 地图阶段：下一排每列一个投票按钮（F-04：不再固定列 0）。
func _refresh_map_votes() -> void:
	var run: Dictionary = client.mirror_run
	var next_row := int(run.get("current",{}).get("row",0))+1
	if selected_route.x != next_row:
		selected_route = Vector2i(-1,-1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",24)
	body_column.add_child(row)
	var route := ExpeditionRoute.new()
	route.custom_minimum_size = Vector2(460,450)
	route.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(route)
	route.display(run)
	var panel := ExpeditionUI.panel()
	panel.custom_minimum_size.x = 400
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(panel)
	route_detail = VBoxContainer.new()
	panel.add_child(route_detail)
	route.node_selected.connect(func(r,c): selected_route = Vector2i(r,c); _refresh_route_detail())
	_refresh_route_detail()

func _refresh_route_detail() -> void:
	ExpeditionUI.clear(route_detail)
	var run: Dictionary = client.mirror_run
	if selected_route.x < 0:
		var art := ExpeditionArt.new()
		art.subject = "start"
		art.stage_scene = true
		art.layer_id = str(run.get("layer_id","moss_stone_shallow"))
		art.custom_minimum_size.y = 210
		route_detail.add_child(art)
		route_detail.add_child(_label("下一步，走向哪里？",26,CREAM))
		route_detail.add_child(_label("先看节点，再投票；两人同票才前进。",18,LIGHT_MUTED))
	else:
		var node: Dictionary = run["map"]["rows"][selected_route.x][selected_route.y]
		var r := selected_route.x
		var c := selected_route.y
		route_detail.add_child(ExpeditionNodePreview.build(node,str(run.get("layer_id","moss_stone_shallow")),"投票前进 · 等待两人一致",func(): client.send_action("vote_move",{"row":r,"col":c})))
	for key in ["p2","p1"]:
		var vote := str(run.get("votes",{}).get(key,""))
		var text := ("你" if key=="p2" else "队友")+("正在选路" if vote=="" else "已选节点 "+vote)
		route_detail.add_child(_label(text,18,ExpeditionUI.TEAL))


func _refresh_node() -> void:
	var run: Dictionary = client.mirror_run
	var current: Dictionary = run.get("current", {})
	var key := "r%dc%d" % [int(current.get("row", 0)), int(current.get("col", 0))]
	var rows: Array = run.get("map", {}).get("rows", [])
	var node: Dictionary = {}
	if int(current.get("row", 0)) < rows.size():
		var row_nodes: Array = rows[int(current.get("row", 0))]
		if int(current.get("col", 0)) < row_nodes.size():
			node = row_nodes[int(current.get("col", 0))]
	var resolved: Dictionary = run.get("resolved", {}).get(key, {})
	var art := ExpeditionArt.new()
	art.stage_scene = true
	art.layer_id = str(run.get("layer_id","moss_stone_shallow"))
	art.subject = ExpeditionNodePreview.subject(node)
	art.custom_minimum_size.y = 220
	body_column.add_child(art)
	body_column.add_child(_label("当前位置：%s（%s）" % [ExpeditionDefs.NODE_TYPE_DISPLAY.get(str(node.get("type", "?")), "?"), str(node.get("hint", ""))], 17, CREAM))
	match str(node.get("type", "")):
		"battle", "elite", "gate":
			if bool(resolved.get("battle_won", false)):
				_refresh_claims(key, resolved, true)
			else:
				var fight := _button("进入战斗（与主机共同回合）", Color("#ffd98a"), Color("#9b713a"))
				fight.pressed.connect(func() -> void:
					client.send_action("start_battle", {})
					_flash("已请求开始战斗。"))
				body_column.add_child(fight)
		"gather", "chest":
			_refresh_claims(key, resolved, false)
		"event":
			_refresh_event(resolved)
		"rest_exit", "exit":
			_refresh_rest(resolved)
	_refresh_share()
	var leave := _button("离开本节点（未领候选放弃）", Color("#eaf4df"), Color("#87b06f"))
	leave.pressed.connect(func() -> void: client.send_action("leave_node", {}))
	body_column.add_child(leave)


func _refresh_claims(key: String, resolved: Dictionary, choose_one: bool) -> void:
	var claimed: Dictionary = resolved.get("claimed", {})
	var mine: Array = claimed.get("p2", [])
	var locked := choose_one and not mine.is_empty()
	var rewards: Array = resolved.get("rewards", [])
	if rewards.is_empty() and (resolved.get("public", []) as Array).is_empty():
		body_column.add_child(_label("这里的候选都已处理。", 14, LIGHT_MUTED))
		return
	for def_id in rewards:
		var def := ItemDefs.get_item(str(def_id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var already := locked or mine.has(str(def_id))
		var info := _label("%s（%d×%d，%s）%s" % [def["name"], def["size"].x, def["size"].y,
			"可售 %d 金币" % int(def.get("base_value", 0)) if bool(def.get("sellable", false)) else "不可售",
			"✓ 已领取" if already else ("已放弃（选择已锁定）" if locked else "")], 14, LIGHT_TEXT)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		if not already:
			var claim := _button("放入背包", Color("#eaf4df"), Color("#87b06f"))
			claim.pressed.connect(func() -> void:
				client.send_action("claim_reward", {"def_id": str(def_id), "container": "pack"})
				_flash("已请求领取 %s（主机裁定）。" % def["name"]))
			row.add_child(claim)
		body_column.add_child(row)
	for def_id in resolved.get("public", []):
		var def := ItemDefs.get_item(str(def_id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var info := _label("公共物资：%s（全队一份）" % def["name"], 14, LIGHT_TEXT)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var claim := _button("领取", Color("#eaf4df"), Color("#87b06f"))
		claim.pressed.connect(func() -> void:
			client.send_action("claim_public", {"def_id": str(def_id)})
			_flash("已请求领取公共物资 %s。" % def["name"]))
		row.add_child(claim)
		body_column.add_child(row)


func _refresh_event(resolved: Dictionary) -> void:
	var event: Dictionary = ExpeditionDefs.EVENTS.get(str(resolved.get("event_id", "")), {})
	if event.is_empty():
		body_column.add_child(_label("（这里很安静）", 14, LIGHT_MUTED))
		return
	body_column.add_child(_label("事件：%s" % event["name"], 16, CREAM))
	var desc := _label(str(event["desc"]), 14, Color("#cfe2c2"))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_column.add_child(desc)
	if bool(resolved.get("completed", false)):
		body_column.add_child(_label("已选择：%s（结果已固定）" % str(resolved.get("chosen_option", "")), 13, Color("#7fae72")))
		return
	for option in event.get("options", []):
		var button := _button(str(option.get("label", "?")), Color("#fff5df"), Color("#d5b87d"))
		button.pressed.connect(func() -> void:
			client.send_action("choose_event", {"option": str(option.get("id", ""))})
			_flash("已选择事件选项（主机裁定）。"))
		body_column.add_child(button)


func _refresh_rest(resolved: Dictionary) -> void:
	if not bool(resolved.get("rest_taken", false)):
		var heal := _button("休息：恢复 8 生命", Color("#eaf4df"), Color("#87b06f"))
		heal.pressed.connect(func() -> void: client.send_action("take_rest", {"option": "heal"}))
		body_column.add_child(heal)
		var prepare := _button("检查装备：下一场多抽 1 张", Color("#eaf4df"), Color("#87b06f"))
		prepare.pressed.connect(func() -> void: client.send_action("take_rest", {"option": "prepare"}))
		body_column.add_child(prepare)
	else:
		body_column.add_child(_label("休整已完成。", 13, LIGHT_MUTED))
	var extract := _button("投票撤离（带着收获回家）", Color("#ffd98a"), Color("#9b713a"))
	extract.pressed.connect(func() -> void:
		client.send_action("vote_extract", {"agree": true})
		_flash("已确认撤离（需队友也确认）。"))
	body_column.add_child(extract)


## 分享：待确认提议的接受/取消；自己可提出分享背包首件。
func _refresh_share() -> void:
	var run: Dictionary = client.mirror_run
	var offer: Dictionary = run.get("share_offer", {})
	if offer.is_empty():
		var share := _button("分享背包首件物品给队友", Color("#fff5df"), Color("#d5b87d"))
		share.pressed.connect(func() -> void:
			var pack: Array = (client.mirror_run.get("guest", {}).get("inventory", {}) as Dictionary).get("loadout", {}).get("pack", [])
			if pack.is_empty():
				_flash("背包里没有可分享的物品。")
				return
			client.send_action("share_offer", {"instance_id": int(pack[0]["instance_id"])})
			_flash("已提出分享（主机确认后转移）。"))
		body_column.add_child(share)
		return
	if str(offer.get("from", "")) == "p1":
		var accept := _button("接受队友的分享（放背包）", Color("#eaf4df"), Color("#87b06f"))
		accept.pressed.connect(func() -> void:
			client.send_action("share_accept", {"container": "pack"})
			_flash("已请求接受分享（主机裁定）。"))
		body_column.add_child(accept)
	else:
		body_column.add_child(_label("已向队友提出分享，等待对方处理……", 13, WARN_GOLD))
	var cancel := _button("取消分享", Color("#fff5df"), Color("#d5b87d"))
	cancel.pressed.connect(func() -> void: client.send_action("share_cancel", {}))
	body_column.add_child(cancel)


## 战斗阶段：用镜像 battle 快照重建 CombatGame 并以 p2 视角打开战斗界面。
func _open_battle() -> void:
	var combat := _mirror_combat()
	if combat == null:
		body_column.add_child(_label("战斗进行中，等待主机快照……", 15, LIGHT_TEXT))
		return
	if battle_screen.visible:
		if battle_screen.pending_acknowledged:
			battle_screen.pending_action = false
			battle_screen.pending_acknowledged = false
			battle_screen.status_label.text = "行动已完成。" if not bool(combat.state["players"]["p2"].get("ended", false)) else "已结束行动，等待队友……"
		battle_screen.combat = combat
		battle_screen._refresh()
	else:
		battle_screen.layer_id = str(client.mirror_run.get("layer_id","moss_stone_shallow"))
	battle_screen.open_run(combat, "p2")


func _mirror_combat() -> CombatGame:
	var battle: Dictionary = client.mirror_run.get("battle", {})
	if battle.is_empty():
		return null
	var combat := CombatGame.new()
	if not combat.load_dict(battle):
		return null
	return combat


func _phase_text(phase: String) -> String:
	match phase:
		"map":
			return "地图（投票选路）"
		"node":
			return "节点内（领取/事件/休整）"
		"battle":
			return "战斗（用下方战斗界面出牌）"
		"over":
			return "本局结束"
	return phase


func _flash(message: String) -> void:
	status_label.text = message


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
	label.add_theme_font_size_override("font_size", maxi(18,size))
	label.add_theme_color_override("font_color", color)
	return label


func _small(content: String, fill: Color, border: Color) -> Button:
	var button := _button(content, fill, border)
	button.add_theme_font_size_override("font_size", 18)
	return button


func _button(content: String, fill: Color, border: Color) -> Button:
	var button := Button.new()
	button.text = content
	button.custom_minimum_size.y = 42
	button.add_theme_color_override("font_color", Color("#35513d"))
	button.add_theme_color_override("font_hover_color", Color("#1f3327"))
	button.add_theme_color_override("font_pressed_color", Color("#1f3327"))
	button.add_theme_color_override("font_disabled_color", Color("#5c6b5e"))
	button.add_theme_font_size_override("font_size", 18)
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
