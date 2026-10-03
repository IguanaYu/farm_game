class_name BattleScreen
extends Control
## 战斗界面（2.2 设计 D2.2-01/02/06）。规则裁定全部走 CombatGame；本脚本只消费事件、
## 展示状态与轻量反馈（浮动数字），不做第二次结算。长动画不阻塞操作（本版无长动画）。

signal battle_closed
signal inventory_mutated

const FOREST := Color("#294f3c")
const CREAM := Color("#fff9ed")
const BAD_RED := Color("#a4543f")
const GOOD_GREEN := Color("#3f7048")
const WARN_GOLD := Color("#9b713a")

var combat: CombatGame
var last_combat: CombatGame
var run_mode := false
var game: FarmGame
var carried_hp := -1  # 两场之间生命延续（2.3 设计 §5：各场战斗生命延续，首场按出发状态）
var selected_uid := -1
## 本屏操作者（F-04）：单人/主机为 p1；客机界面用 p2 视角（手牌、能量、目标都按此取）。
var player_key := "p1"
## 合作局裁定入口（F-04）：设置后出牌/结束回合不再直改本地 CombatGame，
## 而是把意图交给会话层——主机＝host_action 直通裁定，客机＝send_action 发意图。
## combat_refresher 在裁定/镜像更新后取回最新战斗对象。
var action_sink: Callable = Callable()
var combat_refresher: Callable = Callable()
var status_label: Label
var detail_label: Label
var log_label: RichTextLabel
var enemy_row: HBoxContainer
var hand_row: HBoxContainer
var player_panel: VBoxContainer
var pile_panel: HBoxContainer
var end_button: Button
var overlay_panel: PanelContainer
var overlay_center: CenterContainer
var overlay_column: VBoxContainer
var overlay_label: Label
var chooser_column: VBoxContainer
var battle_column: VBoxContainer
var round_label: Label
var played_count := 0
var energy_label: Label
var hand_hint: Label
var log_box: VBoxContainer
var inspector_panel: PanelContainer
var inspector_center: CenterContainer
var inspector_column: VBoxContainer
var hovered_uid := -1
var hovered_target := ""
var target_controls: Dictionary = {}
var target_previews: Dictionary = {}
var pending_action := false
var pending_action_id := ""
var pending_acknowledged := false
var modal_shade: ColorRect
var drag_uid := -1

class CardButton extends Button:
	var card_uid := -1
	var screen: BattleScreen
	func _get_drag_data(_position: Vector2) -> Variant:
		if disabled or screen == null or not screen._can_act():
			return null
		screen.drag_uid = card_uid
		screen.selected_uid = card_uid
		screen._update_targets()
		screen._refresh_detail()
		var preview := ExpeditionUI.panel(ExpeditionUI.PAPER, ExpeditionUI.GOLD)
		preview.add_child(ExpeditionUI.label(CardDefs.get_card(str(screen._hand_card(card_uid).get("card_id", ""))).get("name", "卡牌"), 18, ExpeditionUI.INK))
		set_drag_preview(preview)
		return {"battle_card_uid": card_uid, "screen_id": screen.get_instance_id()}

class TargetButton extends Button:
	var unit_key := ""
	var screen: BattleScreen
	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and int(data.get("screen_id", 0)) == screen.get_instance_id() and screen._legal_target(int(data.get("battle_card_uid", -1)), unit_key)
	func _drop_data(_position: Vector2, data: Variant) -> void:
		screen.selected_uid = int(data["battle_card_uid"])
		screen._on_target_clicked(unit_key)



func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	theme = ExpeditionUI.make_theme()
	_build()


func open_run(combat: CombatGame, actor := "p1") -> void:
	pending_action = false
	hovered_uid = -1
	hovered_target = ""
	_close_inspector()
	run_mode = true
	player_key = actor
	self.combat = combat
	selected_uid = -1
	played_count = 0
	visible = true
	chooser_column.visible = false
	battle_column.visible = true
	overlay_panel.visible = false
	modal_shade.visible = false
	overlay_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.text = "洞窟内的战斗——必须分出胜负。"
	_refresh()


func open_demo(target_game: FarmGame = null) -> void:
	pending_action = false
	_close_inspector()
	run_mode = false
	## 演示入口（2.2 起）：有真实库存时按当前布局构建牌组（2.3 D2.3-04），
	## 否则退回固定基础套装；不影响存档，但战后搜刮领取会写入内存库存（关闭战备时保存）。
	game = target_game
	combat = null
	selected_uid = -1
	played_count = 0
	visible = true
	chooser_column.visible = true
	battle_column.visible = false
	overlay_panel.visible = false
	modal_shade.visible = false
	overlay_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.text = "演示战斗：牌组按当前战备布局生成；胜利后可搜刮（2.3 样例奖励）。"


func _build() -> void:
	ExpeditionUI.backdrop(self)
	var frame := ExpeditionUI.frame(self)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	frame.add_child(column)

	chooser_column = VBoxContainer.new()
	chooser_column.add_theme_constant_override("separation", 20)
	column.add_child(chooser_column)
	chooser_column.add_child(_label("FIELD NOTES   /   试炼", 13, ExpeditionUI.GOLD))
	chooser_column.add_child(_label("在出发前，试一试你的牌组", 32, CREAM))
	chooser_column.add_child(_label("熟悉敌人的意图，安排攻击与防御。演练不会推进探险。", 16, ExpeditionUI.MUTED))
	for encounter_id in ["tutorial", "normal", "defensive"]:
		var button := ExpeditionUI.button(CombatGame.ENCOUNTERS[encounter_id]["name"])
		button.pressed.connect(_on_choose_encounter.bind(encounter_id))
		chooser_column.add_child(button)
	var quit_button := ExpeditionUI.button("返回战备")
	quit_button.pressed.connect(_on_close)
	chooser_column.add_child(quit_button)

	battle_column = VBoxContainer.new()
	battle_column.add_theme_constant_override("separation", 10)
	battle_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(battle_column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	battle_column.add_child(top)
	var titles := VBoxContainer.new()
	top.add_child(titles)
	titles.add_child(_label("CAVERN   /   遭遇战", 12, ExpeditionUI.GOLD))
	round_label = _label("", 25, CREAM)
	titles.add_child(round_label)
	status_label = _label("", 14, ExpeditionUI.MUTED)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(status_label)
	var history := ExpeditionUI.button("战斗记录")
	history.pressed.connect(func() -> void: log_box.visible = not log_box.visible)
	top.add_child(history)

	var stage := HBoxContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 20)
	battle_column.add_child(stage)
	var player_card := ExpeditionUI.panel(Color("#182c34bb"), ExpeditionUI.LINE, 14)
	player_card.custom_minimum_size.x = 200
	player_card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stage.add_child(player_card)
	player_panel = VBoxContainer.new()
	player_panel.add_theme_constant_override("separation", 9)
	player_card.add_child(player_panel)
	var enemy_center := CenterContainer.new()
	enemy_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.add_child(enemy_center)
	enemy_row = HBoxContainer.new()
	enemy_row.add_theme_constant_override("separation", 24)
	enemy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_center.add_child(enemy_row)

	var dock := ExpeditionUI.panel(Color("#172831ee"), ExpeditionUI.LINE, 12)
	battle_column.add_child(dock)
	var dock_column := VBoxContainer.new()
	dock_column.add_theme_constant_override("separation", 8)
	dock.add_child(dock_column)
	var hand_header := HBoxContainer.new()
	dock_column.add_child(hand_header)
	energy_label = _label("", 20, ExpeditionUI.GOLD)
	hand_header.add_child(energy_label)
	hand_hint = _label("", 13, ExpeditionUI.MUTED)
	hand_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hand_header.add_child(hand_hint)
	var scroll := ScrollContainer.new()
	scroll.name = "HandScroll"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 226
	dock_column.add_child(scroll)
	hand_row = HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", 10)
	hand_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(hand_row)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	battle_column.add_child(bottom)
	detail_label = _label("", 14, ExpeditionUI.TEXT)
	detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.custom_minimum_size.y = 44
	bottom.add_child(detail_label)
	end_button = ExpeditionUI.button("结束回合   [E]", true)
	end_button.pressed.connect(_on_end_turn)
	bottom.add_child(end_button)
	pile_panel = HBoxContainer.new()
	pile_panel.add_theme_constant_override("separation", 10)
	battle_column.add_child(pile_panel)

	log_box = VBoxContainer.new()
	log_box.visible = false
	battle_column.add_child(log_box)
	log_label = RichTextLabel.new()
	log_label.scroll_following = true
	log_label.custom_minimum_size.y = 75
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
	overlay_panel = ExpeditionUI.panel(ExpeditionUI.PAPER, ExpeditionUI.GOLD, 28)
	overlay_panel.custom_minimum_size.x = 480
	overlay_panel.visible = false
	overlay_center.add_child(overlay_panel)
	overlay_column = VBoxContainer.new()
	overlay_column.add_theme_constant_override("separation", 20)
	overlay_panel.add_child(overlay_column)
	overlay_label = _label("", 23, ExpeditionUI.INK)
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_column.add_child(overlay_label)
	inspector_center = CenterContainer.new()
	inspector_center.z_index = 100
	inspector_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inspector_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inspector_center)
	inspector_panel = ExpeditionUI.panel(ExpeditionUI.PANEL, ExpeditionUI.GOLD, 22)
	inspector_panel.custom_minimum_size.x = 520
	inspector_panel.visible = false
	inspector_center.add_child(inspector_panel)
	inspector_column = VBoxContainer.new()
	inspector_column.add_theme_constant_override("separation", 10)
	inspector_panel.add_child(inspector_column)


func _on_choose_encounter(encounter_id: String) -> void:
	var deck: Array = []
	var inventory := _inventory()
	if inventory != null:
		deck = DeckBuilder.build(inventory)["entries"]
	if deck.is_empty():
		deck = CombatGame.basic_kit_demo_deck()
	var start_hp := carried_hp if carried_hp > 0 else ExpeditionBaseline.MAX_HP
	var player := {"key": "p1", "name": "农夫", "max_hp": ExpeditionBaseline.MAX_HP, "hp": start_hp, "deck": deck}
	combat = CombatGame.create([player], encounter_id, 20261002, inventory)
	combat.state["players"]["p1"]["hp"] = start_hp
	combat.start()
	chooser_column.visible = false
	battle_column.visible = true
	_refresh()


func _inventory() -> InventoryGame:
	if combat != null:
		if combat.member_inventories.has(player_key):
			return combat.member_inventories[player_key]
		if combat.inventory != null:
			return combat.inventory
	if game == null:
		return null
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	return inventory


func _on_close() -> void:
	_close_inspector()
	visible = false
	last_combat = combat
	combat = null
	battle_closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.is_action_pressed("pause"):
		_cancel_selection()
		get_viewport().set_input_as_handled()
	elif _can_act() and not inspector_panel.visible:
		if event.keycode == KEY_E:
			_on_end_turn()
			get_viewport().set_input_as_handled()
		elif event.keycode >= KEY_0 and event.keycode <= KEY_9:
			var index: int = 9 if event.keycode == KEY_0 else event.keycode - KEY_1
			var hand: Array = combat.state["players"][player_key]["hand"]
			if index >= 0 and index < hand.size():
				_on_card_clicked(int(hand[index]["uid"]))
			get_viewport().set_input_as_handled()



func _input(event: InputEvent) -> void:
	if visible and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_cancel_selection()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and drag_uid >= 0:
		drag_uid = -1
		if not get_viewport().gui_is_drag_successful():
			selected_uid = -1
			_refresh()

func _cancel_selection() -> void:
	if inspector_panel.visible:
		_close_inspector()
	elif selected_uid >= 0:
		selected_uid = -1
		hovered_uid = -1
		hovered_target = ""
		_refresh()
	elif chooser_column.visible:
		_on_close()


func _on_card_clicked(uid: int) -> void:
	if not _can_act() or not _playable_card(uid):
		return
	if selected_uid == uid:
		var def := CardDefs.get_card(str(_hand_card(uid)["card_id"]))
		if str(def["target"]) == "self":
			_on_target_clicked(player_key)
			return
		selected_uid = -1
	else:
		selected_uid = uid
	hovered_uid = -1
	_refresh()


func _on_target_clicked(target_key: String) -> void:
	if not _can_act() or selected_uid < 0 or not _legal_target(selected_uid, target_key):
		return
	if action_sink.is_valid():
		## 合作局：出牌意图交会话裁定（主机直通／客机发送），本地只消费回执与镜像。
		var sent: Variant = action_sink.call("play_card", {"uid": selected_uid, "target": target_key})
		pending_action = not (sent is Dictionary)
		pending_action_id = str(sent) if sent is String else ""
		pending_acknowledged = false
		selected_uid = -1
		if combat_refresher.is_valid():
			combat = combat_refresher.call()
		if sent is Dictionary and not bool(sent.get("ok", true)):
			status_label.text = str(sent.get("reason", ""))
		elif not (sent is Dictionary):
			status_label.text = "已出牌，等待主机裁定……"
		if sent is Dictionary and bool(sent.get("ok", false)):
			played_count += 1
			AudioKit.play(self, "card_play")
			_refresh()
			_flash_events(sent.get("events", []))
		else:
			_refresh()
		return
	var result := combat.play_card(player_key, selected_uid, target_key)
	selected_uid = -1
	if not result["ok"]:
		status_label.text = result["reason"]
		_refresh()
		return
	played_count += 1
	AudioKit.play(self, "card_play")
	_refresh()
	_flash_events(result["events"])


func _on_end_turn() -> void:
	if not _can_act() or inspector_panel.visible:
		return
	selected_uid = -1
	hovered_uid = -1
	if action_sink.is_valid():
		var sent: Variant = action_sink.call("end_turn", {})
		pending_action = not (sent is Dictionary)
		pending_action_id = str(sent) if sent is String else ""
		pending_acknowledged = false
		if combat_refresher.is_valid():
			combat = combat_refresher.call()
		if sent is Dictionary:
			if bool(sent.get("waiting", false)):
				status_label.text = "已结束行动，等待队友……"
			elif not bool(sent.get("ok", true)):
				status_label.text = str(sent.get("reason", ""))
		else:
			status_label.text = "已请求结束行动，等待主机裁定……"
		_refresh()
		return
	var result := combat.end_turn(player_key)
	if result.get("waiting", false):
		status_label.text = "等待其他玩家结束……"
		return
	if not result["ok"]:
		status_label.text = result["reason"]
		return
	_refresh()
	_flash_events(result["events"])


# —— 刷新 ————————————————————————————————————————————————————————


func _refresh() -> void:
	if combat == null or combat.state.is_empty() or not combat.state["players"].has(player_key):
		return
	var player: Dictionary = combat.state["players"][player_key]
	if selected_uid >= 0 and _hand_card(selected_uid).is_empty():
		selected_uid = -1
	round_label.text = "第 %02d 回合  ·  %s" % [int(combat.state["round"]), "战斗结束" if combat.is_over() else "你的行动"]
	energy_label.text = "能量  %d / %d" % [int(player["energy"]), ExpeditionBaseline.ENERGY_PER_TURN]
	hand_hint.text = "手牌 %d  ·  点击选牌 / 拖到目标  ·  1–0 选牌  ·  右键取消" % player["hand"].size()
	end_button.text = "等待队友…" if bool(player.get("ended", false)) else "结束回合   [E]"
	end_button.disabled = not _can_act()
	_refresh_enemies()
	_refresh_player()
	_refresh_hand()
	_refresh_piles()
	_refresh_log()
	_refresh_detail()
	_update_targets()
	if combat.is_over():
		_close_inspector()
		_show_outcome()
		carried_hp = int(player["hp"]) if combat.state["outcome"] == "won" else -1


func _refresh_enemies() -> void:
	ExpeditionUI.clear(enemy_row)
	target_controls.clear()
	target_previews.clear()
	var intents: Dictionary = {}
	for entry in combat.enemy_intents():
		intents[entry["enemy_id"]] = entry["text"]
	for enemy in combat.state["enemies"]:
		var alive := bool(enemy["alive"])
		var key := str(enemy["id"])
		var card := VBoxContainer.new()
		card.custom_minimum_size.x = 174
		card.add_theme_constant_override("separation", 6)
		card.set_meta("unit_key", key)
		enemy_row.add_child(card)
		var intent := _label(str(intents.get(key, "已击败")) if alive else "已击败", 16, ExpeditionUI.RED if str(enemy.get("intent", {}).get("kind", "")) == "attack" else ExpeditionUI.TEAL)
		intent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		intent.tooltip_text = "结束回合后执行；意图在回合开始时确定。"
		if combat.state["players"].size() > 1 and alive:
			intent.text += " · " + ("你" if combat.intent_target(enemy) == player_key else "队友")
		card.add_child(intent)
		var target := _target_button(key)
		target.custom_minimum_size = Vector2(174, 146)
		target.disabled = not alive
		card.add_child(target)
		var art := ExpeditionArt.new()
		art.subject = str(enemy.get("def_id", "slime"))
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		target.add_child(art)
		if not alive:
			card.modulate.a = 0.4
		var name_label := _label(str(enemy["name"]), 17, CREAM)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(name_label)
		card.add_child(ExpeditionUI.bar(int(enemy["hp"]), int(enemy["max_hp"]), ExpeditionUI.RED))
		var hp := _label("%d / %d 生命  ·  %d 格挡" % [int(enemy["hp"]), int(enemy["max_hp"]), int(enemy["block"])], 13, ExpeditionUI.MUTED)
		hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(hp)
		if not enemy["statuses"].is_empty():
			card.add_child(_label(_status_text(enemy["statuses"]), 12, Color("#c5b5e4")))
		var preview := _label("", 12, ExpeditionUI.GOLD)
		preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		preview.custom_minimum_size.y = 20
		card.add_child(preview)
		target_previews[key] = preview


func _refresh_hand() -> void:
	ExpeditionUI.clear(hand_row)
	var player: Dictionary = combat.state["players"][player_key]
	var index := 0
	for card in player["hand"]:
		index += 1
		var def := CardDefs.get_card(str(card["card_id"]))
		var uid := int(card["uid"])
		var button := CardButton.new()
		button.screen = self
		button.card_uid = uid
		button.name = "Card_%d" % uid
		button.custom_minimum_size = Vector2(150, 206)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.disabled = not _playable_card(uid)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var accent := _card_color(str(card["card_id"]))
		var selected := uid == selected_uid
		button.add_theme_stylebox_override("normal", ExpeditionUI.style(Color("#f6ecd7") if selected else ExpeditionUI.PAPER, ExpeditionUI.GOLD if selected else accent, 10, 0))
		button.add_theme_stylebox_override("hover", ExpeditionUI.style(Color("#fff3dc"), ExpeditionUI.GOLD, 10, 0))
		button.add_theme_stylebox_override("pressed", ExpeditionUI.style(Color("#e4d2b2"), ExpeditionUI.GOLD, 10, 0))
		button.add_theme_stylebox_override("disabled", ExpeditionUI.style(Color("#b3b6ad"), Color("#6b7b7b"), 10, 0))
		button.add_theme_stylebox_override("focus", ExpeditionUI.style(Color.TRANSPARENT, ExpeditionUI.GOLD, 10, 0))
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 10)
		button.add_child(margin)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 4)
		margin.add_child(content)
		var title := HBoxContainer.new()
		content.add_child(title)
		var cost := _label(str(def["cost"]), 23, accent.darkened(0.35))
		title.add_child(cost)
		var name_label := _label(str(def["name"]), 15, ExpeditionUI.INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		title.add_child(name_label)
		var art := ExpeditionArt.new()
		art.subject = _card_subject(str(card["card_id"]))
		art.tint = accent
		art.custom_minimum_size.y = 67
		content.add_child(art)
		var desc := _label(_short_effect(def), 14, ExpeditionUI.INK)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(desc)
		var footer := _label("%s  ·  %s" % [_target_display(str(def["target"])), "消耗" if str(def["after"]) == "exhaust_source" else ("本场移除" if str(def["after"]) == "exhaust" else "弃牌")], 11, Color("#655e50"))
		content.add_child(footer)
		var hotkey := _label("已选中 · 点击目标" if selected else ("能量不足" if int(def["cost"]) > int(player["energy"]) else "[%d]" % (index % 10)), 11, accent.darkened(0.4))
		content.add_child(hotkey)
		ExpeditionUI.ignore_tree(margin)
		button.tooltip_text = str(def["desc"])
		var source_inventory := _inventory()
		if source_inventory != null and int(card.get("source_instance_id", 0)) > 0:
			button.tooltip_text += "\n" + DeckBuilder.source_summary(source_inventory, int(card["source_instance_id"]))
		button.pressed.connect(_on_card_clicked.bind(uid))
		button.mouse_entered.connect(func() -> void:
			hovered_uid = uid
			var tween := margin.create_tween()
			tween.tween_property(margin, "modulate", Color(1.06, 1.06, 1.03), 0.12)
			_refresh_detail())
		button.mouse_exited.connect(func() -> void:
			hovered_uid = -1
			var tween := margin.create_tween()
			tween.tween_property(margin, "modulate", Color.WHITE, 0.12)
			_refresh_detail())
		hand_row.add_child(button)
	if player["hand"].is_empty():
		hand_row.add_child(_label("手牌已用完，结束回合后重新抽牌。", 16, ExpeditionUI.MUTED))


func _refresh_piles() -> void:
	ExpeditionUI.clear(pile_panel)
	var player: Dictionary = combat.state["players"][player_key]
	for entry in [["draw_pile", "抽牌堆"], ["discard_pile", "弃牌堆"], ["exhaust_pile", "已移除"]]:
		var button := ExpeditionUI.button("%s  %d" % [entry[1], player[entry[0]].size()])
		button.custom_minimum_size.y = 34
		button.pressed.connect(_open_pile.bind(str(entry[0]), str(entry[1])))
		pile_panel.add_child(button)
	var note := _label("结束回合：弃掉手牌 → 敌人行动 → 恢复能量并抽牌", 12, ExpeditionUI.MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pile_panel.add_child(note)


func _refresh_log() -> void:
	var entries: Array = combat.combat_log()
	var recent: Array = entries.slice(maxi(0, entries.size() - 12), entries.size())
	log_label.text = "\n".join(recent)


func _refresh_detail() -> void:
	var uid := selected_uid if selected_uid >= 0 else hovered_uid
	var card := _hand_card(uid)
	if card.is_empty():
		detail_label.text = "先观察敌人上方的意图，再安排本回合的攻击与格挡。"
		return
	var def := CardDefs.get_card(str(card["card_id"]))
	var target := hovered_target
	if target == "" and str(def["target"]) == "self":
		target = player_key
	var suffix := _target_preview(uid, target) if target != "" else "选择高亮目标查看实际效果"
	detail_label.text = "%s  ·  %s" % [def["name"], suffix]




func _ally_key() -> String:
	if combat == null:
		return ""
	for other_key in combat.state["players"]:
		if str(other_key) != player_key:
			return str(other_key)
	return ""



func _show_outcome() -> void:
	var player: Dictionary = combat.state["players"][player_key]
	var won: bool = str(combat.state["outcome"]) == "won"
	overlay_label.text = "%s\n\n历时 %d 回合 ｜ 剩余生命 %d/%d ｜ 本场出牌 %d 张" % [
		"战斗胜利！" if won else "战斗失败……",
		int(combat.state["round"]), int(player["hp"]), int(player["max_hp"]), played_count]
	overlay_panel.visible = true
	modal_shade.visible = true
	status_label.text = "遭遇已结束，确认后继续探索。"
	# 结算弹出时恢复拦截：点在面板外不应穿透到已结束的战斗按钮。
	overlay_center.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in overlay_column.get_children():
		if child != overlay_label:
			overlay_column.remove_child(child)
			child.queue_free()
	var close_button := _button("继续探索" if run_mode else "返回战备", Color("#eaf4df"), Color("#87b06f"))
	close_button.pressed.connect(_on_close)
	overlay_column.add_child(close_button)


# —— 事件反馈（轻量浮动数字）———————————————————————————————


func _flash_events(events: Array) -> void:
	for event in events:
		match str(event.get("type", "")):
			"damage":
				_popup_on_unit(str(event["target"]), "-%d" % int(event["amount"]), BAD_RED if int(event.get("to_hp", 0)) > 0 else Color("#9aa5b5"))
			"block":
				_popup_on_unit(str(event["target"]), "+%d 格挡" % int(event["amount"]), Color("#8fb6d8"))
			"heal":
				_popup_on_unit(str(event["target"]), "+%d 生命" % int(event["amount"]), GOOD_GREEN)
			"poison":
				_popup_on_unit(str(event["target"]), "毒 -%d" % int(event["amount"]), Color("#a5679f"))
			"outcome":
				AudioKit.play(self, "victory" if str(event["outcome"]) == "won" else "defeat")
				_popup_center("胜利！" if str(event["outcome"]) == "won" else "失败……", WARN_GOLD)


func _popup_on_unit(unit_key: String, text: String, color: Color) -> void:
	var anchor := _unit_anchor(unit_key)
	if anchor == null:
		return
	_popup_at(anchor, text, color)


func _popup_center(text: String, color: Color) -> void:
	_popup_at(self, text, color)


func _popup_at(anchor: Control, text: String, color: Color) -> void:
	var label := _label(text, 24, color)
	label.z_index = 50
	label.position = anchor.get_global_rect().get_center() - global_position + Vector2(-30, -20)
	add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 65, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)


func _unit_anchor(unit_key: String) -> Control:
	if str(unit_key).begins_with("p"):
		return player_panel
	for child in enemy_row.get_children():
		if str(child.get_meta("unit_key", "")) == unit_key:
			return child
	return null


# —— 工具 ————————————————————————————————————————————————————————


func _hand_card(uid: int) -> Dictionary:
	if combat == null or not combat.state.get("players", {}).has(player_key):
		return {}
	for card in combat.state["players"][player_key]["hand"]:
		if int(card["uid"]) == uid:
			return card
	return {}


func _status_text(statuses: Dictionary) -> String:
	if statuses.is_empty():
		return "状态：无"
	var parts: Array = []
	for status in statuses:
		parts.append("%s×%d" % [CardDefs.STATUS_DISPLAY.get(status, status), int(statuses[status]["stacks"])])
	return "状态：" + "、".join(parts)


func _target_display(rule: String) -> String:
	match rule:
		"enemy":
			return "敌人"
		"self":
			return "自己"
		"ally":
			return "友方"
		"rescue":
			return "倒地队友"
	return ""





func _label(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(content: String, _fill: Color, _border: Color) -> Button:
	return ExpeditionUI.button(content, true)


func _can_act() -> bool:
	if combat == null or combat.state.is_empty() or not combat.state["players"].has(player_key):
		return false
	var player: Dictionary = combat.state["players"][player_key]
	return not combat.is_over() and combat.state["phase"] == "player" and int(player["hp"]) > 0 and not bool(player.get("ended", false)) and not pending_action

func _playable_card(uid: int) -> bool:
	var card := _hand_card(uid)
	if card.is_empty() or not _can_act():
		return false
	return int(CardDefs.get_card(str(card["card_id"]))["cost"]) <= int(combat.state["players"][player_key]["energy"])

func _legal_target(uid: int, key: String) -> bool:
	return _playable_card(uid) and bool(combat.preview_play(player_key, uid, key).get("ok", false))

func _target_button(key: String) -> TargetButton:
	var button := TargetButton.new()
	button.screen = self
	button.unit_key = key
	button.name = "Target_" + key
	ExpeditionUI.decorate_button(button)
	button.pressed.connect(_on_target_clicked.bind(key))
	button.mouse_entered.connect(func() -> void:
		hovered_target = key
		_refresh_detail())
	button.mouse_exited.connect(func() -> void:
		hovered_target = ""
		_refresh_detail())
	target_controls[key] = button
	return button

func _update_targets() -> void:
	for key in target_controls:
		var button: Button = target_controls[key]
		var legal := selected_uid >= 0 and _legal_target(selected_uid, str(key))
		button.add_theme_stylebox_override("normal", ExpeditionUI.style(Color("#263e43aa") if legal else Color("#1b2d3500"), ExpeditionUI.GOLD if legal else Color("#3a515933"), 14, 10))
		button.tooltip_text = _target_preview(selected_uid, str(key)) if legal else "选择一张适用于这个目标的牌"
		if target_previews.has(key):
			target_previews[key].text = _target_preview(selected_uid, str(key)) if legal else ""

func _refresh_player() -> void:
	ExpeditionUI.clear(player_panel)
	var player: Dictionary = combat.state["players"][player_key]
	player_panel.add_child(_label("探险者 / 你", 13, ExpeditionUI.GOLD))
	var self_target := _target_button(player_key)
	self_target.text = "以自己为目标"
	self_target.custom_minimum_size.y = 48
	player_panel.add_child(self_target)
	player_panel.add_child(_label("%d / %d 生命" % [int(player["hp"]), int(player["max_hp"])], 23, CREAM))
	player_panel.add_child(ExpeditionUI.bar(int(player["hp"]), int(player["max_hp"])))
	player_panel.add_child(_label("格挡  %d" % int(player["block"]), 16, Color("#99bdd5")))
	player_panel.add_child(_label(_status_text(player["statuses"]), 12, ExpeditionUI.MUTED))
	var ally := _ally_key()
	if ally != "":
		var friend: Dictionary = combat.state["players"][ally]
		var target := _target_button(ally)
		target.text = "队友 %d/%d%s" % [int(friend["hp"]), int(friend["max_hp"]), " · 倒地" if bool(friend.get("downed", false)) else ""]
		player_panel.add_child(target)
		player_panel.add_child(_label("已结束行动" if bool(friend.get("ended", false)) else "正在行动", 12, ExpeditionUI.MUTED))

func _target_preview(uid: int, key: String) -> String:
	if combat == null or uid < 0 or key == "":
		return ""
	var preview := combat.preview_play(player_key, uid, key)
	if not bool(preview.get("ok", false)):
		return "目标不适用"
	var parts: Array[String] = []
	if preview.has("damage"):
		var unit: Dictionary = combat._find_unit(key)
		var damage := int(preview["damage"])
		var blocked := mini(int(unit.get("block", 0)), damage)
		var hp_loss := maxi(0, damage - blocked)
		parts.append("伤害 %d · 生命 −%d%s" % [damage, hp_loss, " · 击败" if hp_loss >= int(unit.get("hp", 999)) else ""])
	if preview.has("block"):
		parts.append("格挡 +%d" % int(preview["block"]))
	if preview.has("heal"):
		parts.append("生命 +%d" % int(preview["heal"]))
	if preview.has("draw"):
		parts.append("抽 %d 张牌" % int(preview["draw"]))
	if preview.has("status"):
		parts.append("附加%s" % str(preview["status"]))
	if str(CardDefs.get_card(str(_hand_card(uid).get("card_id", ""))).get("target", "")) == "rescue":
		parts.append("救起队友")
	return " / ".join(parts) if not parts.is_empty() else "整理货物，本场移除"

func _card_subject(id: String) -> String:
	if CardDefs.is_attack_card(id):
		return "attack"
	if CardDefs.is_defense_card(id):
		return "shield"
	for effect in CardDefs.get_card(id).get("effects", []):
		if str(effect["kind"]) in ["heal", "rescue"]:
			return "heal"
	return "cargo" if id == "heavy_cargo" else "draw"

func _card_color(id: String) -> Color:
	match _card_subject(id):
		"attack": return Color("#ba795c")
		"shield": return Color("#668ba2")
		"heal": return Color("#709776")
		_: return Color("#9a88b0")

func _short_effect(def: Dictionary) -> String:
	var parts: Array[String] = []
	for effect in def.get("effects", []):
		match str(effect["kind"]):
			"damage": parts.append("造成 %d 伤害" % int(effect["value"]))
			"block": parts.append("获得 %d 格挡" % int(effect["value"]))
			"heal": parts.append("恢复 %d 生命" % int(effect["value"]))
			"draw": parts.append("抽 %d 张牌" % int(effect["value"]))
			"status": parts.append("%s %d 层" % [CardDefs.STATUS_DISPLAY.get(str(effect["status"]), ""), int(effect.get("stacks", 1))])
			"rescue": parts.append("救起队友至 %d 生命" % int(effect["value"]))
	return "\n".join(parts) if not parts.is_empty() else "整理货物\n本场移除这张牌"

func _open_pile(key: String, caption: String) -> void:
	ExpeditionUI.clear(inspector_column)
	inspector_column.add_child(_label(caption, 25, CREAM))
	inspector_column.add_child(_label("按牌名汇总，不透露抽牌顺序。", 13, ExpeditionUI.MUTED))
	var counts := {}
	for card in combat.state["players"][player_key][key]:
		var id := str(card["card_id"])
		counts[id] = int(counts.get(id, 0)) + 1
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 260)
	inspector_column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for id in counts:
		var def := CardDefs.get_card(str(id))
		var line := _label("%s ×%d   /   %d 能量\n%s" % [def["name"], counts[id], int(def["cost"]), def["desc"]], 14, ExpeditionUI.TEXT)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(line)
	if counts.is_empty():
		list.add_child(_label("这里暂时没有卡牌。", 16, ExpeditionUI.MUTED))
	var close_button := ExpeditionUI.button("返回战斗   [Esc]")
	close_button.pressed.connect(_close_inspector)
	inspector_column.add_child(close_button)
	inspector_center.mouse_filter = Control.MOUSE_FILTER_STOP
	inspector_panel.visible = true
	modal_shade.visible = true

func _close_inspector() -> void:
	if inspector_panel != null:
		inspector_panel.visible = false
		modal_shade.visible = overlay_panel.visible
		inspector_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
