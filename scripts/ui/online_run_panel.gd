class_name OnlineRunPanel
extends Control
## M3 线上局界面（W07）：展示服务器权威 run 快照（bridge.run_snapshot 镜像），
## 一切操作以意图经 bridge.run_action 发给服务器裁定；结算单到达即提示。
## 视角 member_key 由房间创建者关系推导（p1=创建者；单人局/无房=p1）。
## 布局沿 CoopClientPanel（2.6 客机界面）的结构，数据源换成线上桥。

signal close_requested

const CREAM := Color("#fff9ed")
const WARN_GOLD := Color("#9b713a")
const LIGHT_TEXT := Color("#e8f2d8")
const LIGHT_MUTED := Color("#a3b59b")

var bridge: OnlineFarmBridge
var member_key := "p1"
var status_label: Label
var state_label: Label
var body_column: VBoxContainer
var log_label: RichTextLabel
var battle_screen: BattleScreen
var loot_panel: ExpeditionLootPanel
var main_frame: CenterContainer
var _mirror_version := -1
var selected_route := Vector2i(-1,-1)
var route_detail: VBoxContainer
var action_row: HBoxContainer
var return_button: Button
var pending_action := false
var _receipt_applied := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	theme = ExpeditionUI.make_theme()
	_build()
	set_process(true)


func open(target_bridge: OnlineFarmBridge) -> void:
	bridge = target_bridge
	if not bridge.run_snapshot.is_connected(_on_run):
		bridge.run_snapshot.connect(_on_run)
	if not bridge.settlement_arrived.is_connected(_on_settlement):
		bridge.settlement_arrived.connect(_on_settlement)
	member_key = _resolve_member_key(bridge.mirror_room, bridge.mirror_run, int(bridge.client.account_id))
	battle_screen.player_key = member_key
	_mirror_version = -1
	visible = true
	_refresh()


func close() -> void:
	visible = false
	if battle_screen != null:
		battle_screen.visible = false
	if loot_panel != null:
		loot_panel.visible = false


## 服务器推送新局快照（含 req_ok 附带的）：置脏，下一帧重建。
func _on_run(_run: Dictionary, _version: int) -> void:
	_mirror_version = -1


func _on_settlement(settlement: Dictionary) -> void:
	_mirror_version = -1
	_flash("已收到结算单，正在核对农场入库记录。")


func _process(_delta: float) -> void:
	if bridge == null or not visible:
		return
	var applied := _settlement_applied()
	if applied != _receipt_applied:
		_receipt_applied = applied
		_mirror_version = -1
	if bridge.mirror_run_version != _mirror_version:
		_refresh()


func _resolve_member_key(room: Dictionary, run: Dictionary, account_id: int) -> String:
	if not bool(run.get("coop", false)):
		return "p1"
	if int(room.get("creator_account_id", 0)) == account_id:
		return "p1"
	return "p2"


func _build() -> void:
	ExpeditionUI.backdrop(self)
	var shade := ColorRect.new()
	shade.color = Color(0.09, 0.13, 0.10, 0.12)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	main_frame = center
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := ExpeditionUI.panel(ExpeditionUI.PANEL, ExpeditionUI.LINE, 16)
	panel.custom_minimum_size = Vector2(1120, 730)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := _label("洞内探险",28,CREAM)
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
	log_label.custom_minimum_size = Vector2(0, 100)
	log_label.visible = false
	log_label.add_theme_font_size_override("normal_font_size", 13)
	log_label.add_theme_color_override("default_color", Color("#cfe2c2"))
	column.add_child(log_label)
	var bottom := HBoxContainer.new()
	action_row = bottom
	bottom.add_theme_constant_override("separation", 8)
	column.add_child(bottom)
	var signal_button := _small("建议撤离", Color("#e8f0d8"), Color("#87b06f"))
	signal_button.pressed.connect(func() -> void: _fire("signal", {"text": "建议撤离"}))
	bottom.add_child(signal_button)
	var abandon_button := _button("个人放弃（损失未保护物）", Color("#f0d9cf"), Color("#a4543f"))
	abandon_button.pressed.connect(func() -> void: _fire("abandon_member", {}))
	bottom.add_child(abandon_button)
	var close_button := _button("回营地休息 · 当前探险保留", Color("#fff5df"), Color("#d5b87d"))
	close_button.pressed.connect(_on_close)
	return_button = close_button
	column.add_child(close_button)
	## 战斗界面：本人视角，出牌/结束回合经 bridge 发服务器裁定（fire-and-forget；
	## battle_screen 走 pending 模式，回执后由 _fire_battle/新快照统一清 pending）。
	battle_screen = preload("res://scenes/battle_screen.tscn").instantiate()
	battle_screen.action_sink = func(kind: String, args: Dictionary) -> Variant:
		_fire_battle(kind, args)
		return "sent"
	battle_screen.combat_refresher = func() -> CombatGame: return _mirror_combat()
	add_child(battle_screen)
	loot_panel = ExpeditionLootPanel.new()
	loot_panel.z_index = 10
	loot_panel.action_sink = func(kind: String, args: Dictionary) -> Variant:
		_fire(kind, args)
		return "sent"
	loot_panel.menu_requested.connect(_on_close)
	add_child(loot_panel)


## 发送意图（fire-and-forget 协程）：失败闪提示；成功后新快照经推送/应答到达自动刷新。
func _fire(kind: String, args: Dictionary = {}) -> void:
	if pending_action:
		return
	pending_action = true
	_flash("等待操作确认……")
	var result: Dictionary = await bridge.run_action(kind,args)
	pending_action = false
	if bool(result.get("ok",false)):
		_flash("")
	if not bool(result.get("ok",false)):
		_flash("服务器裁定：%s" % str(result.get("reason", "操作未生效")))


## 战斗动作的 fire：回执（成功或失败）都解除 battle_screen 的 pending 锁。
func _fire_battle(kind: String, args: Dictionary = {}) -> void:
	var result: Dictionary = await bridge.run_action(kind, args)
	battle_screen.pending_action = false
	battle_screen.pending_acknowledged = false
	if not bool(result.get("ok", true)):
		battle_screen.status_label.text = "服务器裁定：%s" % str(result.get("reason", "操作未生效"))
	if battle_screen.visible:
		battle_screen.combat = _mirror_combat()
		battle_screen._refresh()
		if bool(result.get("ok",false)):
			battle_screen._flash_events(result.get("events",[]))


# —— 刷新 ————————————————————————————————————————————————————————


func _refresh() -> void:
	if bridge == null:
		return
	var run: Dictionary = bridge.mirror_run
	if run.is_empty():
		state_label.text = "等待开局……"
		return
	_mirror_version = bridge.mirror_run_version
	ExpeditionUI.set_layer(self,str(run.get("layer_id","moss_stone_shallow")))
	var over := str(run.get("phase",""))=="over" or str(run.get("outcome",""))!=""
	action_row.visible = not over
	return_button.visible = true
	return_button.text = "回洞口营地 · 整理收获" if over else "回营地休息 · 当前探险保留"
	main_frame.visible = not ExpeditionLootPanel.is_loot_phase(run)
	loot_panel.display(run, member_key, bridge.mirror_run_version)
	if battle_screen != null and battle_screen.visible and str(run.get("phase", "")) != "battle":
		battle_screen.visible = false
	var me := _member_view(run, member_key)
	var mate := _member_view(run, "p2" if member_key == "p1" else "p1")
	state_label.text = "%s ｜ 第 %d/8 排 ｜ 你的生命 %d/%d ｜ %s ｜ %s" % [
		ExpeditionDefs.layer(str(run.get("layer_id", ""))).get("name", "?"),
		int(run.get("current", {}).get("row", 0)),
		int(me.get("hp", 40)), int(me.get("max_hp", 40)),
		"队友 %d/%d" % [int(mate.get("hp",40)),int(mate.get("max_hp",40))] if bool(run.get("coop",false)) else "独自探险",
		_phase_text(str(run.get("phase", "")))
	]
	for child in body_column.get_children():
		body_column.remove_child(child)
		child.queue_free()
	match str(run.get("phase", "")):
		"map":
			_refresh_map()
		"node":
			if not ExpeditionLootPanel.is_loot_phase(run):
				_refresh_node()
		"battle":
			_open_battle()
		"over":
			var receipt: Dictionary = bridge.mirror_settlement
			if str(receipt.get("run_id","")) == str(run.get("run_id","")) and not receipt.is_empty():
				return_button.visible = false
				body_column.add_child(ExpeditionSettlement.build(receipt,_settlement_applied(),_on_close))
			else:
				body_column.add_child(_label("探险已结束，等待这次的结算单。",20,CREAM))
	var entries: Array = run.get("log", [])
	log_label.text = "\n".join(entries.slice(maxi(0, entries.size() - 8), entries.size()))


func _member_view(run: Dictionary, key: String) -> Dictionary:
	if key == "p2" and bool(run.get("coop", false)):
		return run.get("guest", {})
	return run.get("player", {})


## 地图阶段：单人直选下一排；双人投票。
func _refresh_map() -> void:
	var run: Dictionary = bridge.mirror_run
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
	route_detail.add_theme_constant_override("separation",12)
	panel.add_child(route_detail)
	route.node_selected.connect(func(r,c): selected_route = Vector2i(r,c); _refresh_route_detail())
	_refresh_route_detail()


func _refresh_node() -> void:
	var run: Dictionary = bridge.mirror_run
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
				var fight := _button("进入战斗", Color("#ffd98a"), Color("#9b713a"))
				fight.pressed.connect(func() -> void: _fire("start_battle", {}))
				body_column.add_child(fight)
		"gather", "chest":
			_refresh_claims(key, resolved, false)
		"event":
			_refresh_event(resolved)
		"rest_exit", "exit":
			_refresh_rest(resolved)
	if bool(run.get("coop", false)):
		_refresh_share()
	var extract_hint := "离开节点（未领候选放弃）"
	var leave := _button(extract_hint, Color("#eaf4df"), Color("#87b06f"))
	leave.pressed.connect(func() -> void: _fire("leave_node", {}))
	body_column.add_child(leave)


func _refresh_claims(key: String, resolved: Dictionary, choose_one: bool) -> void:
	var claimed: Dictionary = resolved.get("claimed", {})
	var mine: Array = claimed.get(member_key, [])
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
			claim.pressed.connect(func() -> void: _fire("claim_reward", {"def_id": str(def_id), "container": "pack"}))
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
		claim.pressed.connect(func() -> void: _fire("claim_public", {"def_id": str(def_id)}))
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
		button.pressed.connect(func() -> void: _fire("choose_event", {"option": str(option.get("id", ""))}))
		body_column.add_child(button)


func _refresh_rest(resolved: Dictionary) -> void:
	if not bool(resolved.get("rest_taken", false)):
		var heal := _button("休息：恢复 8 生命", Color("#eaf4df"), Color("#87b06f"))
		heal.pressed.connect(func() -> void: _fire("take_rest", {"option": "heal"}))
		body_column.add_child(heal)
		var prepare := _button("检查装备：下一场多抽 1 张", Color("#eaf4df"), Color("#87b06f"))
		prepare.pressed.connect(func() -> void: _fire("take_rest", {"option": "prepare"}))
		body_column.add_child(prepare)
	else:
		body_column.add_child(_label("休整已完成。", 13, LIGHT_MUTED))
	var coop := bool(bridge.mirror_run.get("coop", false))
	var extract := _button("确认撤离（带着收获回家）" if not coop else "投票撤离（需两人确认）", Color("#ffd98a"), Color("#9b713a"))
	var action := "vote_extract" if coop else "extract"
	extract.pressed.connect(func() -> void: _fire(action, {"agree": true}))
	body_column.add_child(extract)


func _refresh_share() -> void:
	var run: Dictionary = bridge.mirror_run
	var offer: Dictionary = run.get("share_offer", {})
	if offer.is_empty():
		var share := _button("分享背包首件物品给队友", Color("#fff5df"), Color("#d5b87d"))
		share.pressed.connect(func() -> void:
			var pack: Array = (_member_view(run, member_key).get("inventory", {}) as Dictionary).get("loadout", {}).get("pack", [])
			if pack.is_empty():
				_flash("背包里没有可分享的物品。")
				return
			_fire("share_offer", {"instance_id": int(pack[0]["instance_id"])})
		)
		body_column.add_child(share)
		return
	if str(offer.get("from", "")) != member_key:
		var accept := _button("接受队友的分享（放背包）", Color("#eaf4df"), Color("#87b06f"))
		accept.pressed.connect(func() -> void: _fire("share_accept", {"container": "pack"}))
		body_column.add_child(accept)
	else:
		body_column.add_child(_label("已向队友提出分享，等待对方处理……", 13, WARN_GOLD))
	var cancel := _button("取消分享", Color("#fff5df"), Color("#d5b87d"))
	cancel.pressed.connect(func() -> void: _fire("share_cancel", {}))
	body_column.add_child(cancel)


## 战斗阶段：用镜像 battle 快照重建 CombatGame 并以本人视角打开战斗界面。
func _open_battle() -> void:
	battle_screen.layer_id = str(bridge.mirror_run.get("layer_id","moss_stone_shallow"))
	var combat := _mirror_combat()
	if combat == null:
		body_column.add_child(_label("战斗进行中，等待服务器快照……", 15, LIGHT_TEXT))
		return
	if battle_screen.visible:
		## 新快照=权威推进：解除上一动作的 pending 锁（队友动作也会推快照）。
		battle_screen.pending_action = false
		battle_screen.pending_acknowledged = false
		battle_screen.combat = combat
		battle_screen._refresh()
	else:
		battle_screen.open_run(combat, member_key)


func _mirror_combat() -> CombatGame:
	var battle: Dictionary = bridge.mirror_run.get("battle", {})
	if battle.is_empty():
		return null
	var combat := CombatGame.new()
	if not combat.load_dict(battle):
		return null
	return combat


func _phase_text(phase: String) -> String:
	match phase:
		"map":
			return "地图"
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

func _refresh_route_detail() -> void:
	ExpeditionUI.clear(route_detail)
	var run: Dictionary = bridge.mirror_run
	var coop := bool(run.get("coop",false))
	var votes: Dictionary = run.get("votes",{})
	if selected_route.x < 0:
		var art := ExpeditionArt.new()
		art.subject = "start"
		art.stage_scene = true
		art.layer_id = str(run.get("layer_id","moss_stone_shallow"))
		art.custom_minimum_size.y = 210
		route_detail.add_child(art)
		route_detail.add_child(_label("下一步，走向哪里？",26,CREAM))
		var hint := _label("先查看节点，再确认前进。"+("两人选择同一处才会前进。" if coop else ""),18,LIGHT_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		route_detail.add_child(hint)
	else:
		var node: Dictionary = run["map"]["rows"][selected_route.x][selected_route.y]
		var r := selected_route.x
		var c := selected_route.y
		route_detail.add_child(ExpeditionNodePreview.build(node,str(run.get("layer_id","moss_stone_shallow")),"投票前进 · 等待两人一致" if coop else "向这里前进 →",func(): _fire("vote_move" if coop else "move_to",{"row":r,"col":c})))
	if coop:
		for key in ["p1","p2"]:
			var vote := str(votes.get(key,""))
			var text := ("你" if key==member_key else "队友")+("正在选路" if vote=="" else "已选择 "+vote)
			route_detail.add_child(_label(text,18,ExpeditionUI.TEAL))


func _settlement_applied() -> bool:
	if bridge == null:
		return false
	var receipt: Dictionary = bridge.mirror_settlement
	return not receipt.is_empty() and bridge.game.state.get("expedition",{}).get("applied_settlements",[]).has(str(receipt.get("settlement_id","")))
