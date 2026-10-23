class_name BattleScreen
extends Control
var layer_id := "moss_stone_shallow"
## 仅独立美术试玩使用；不修改 CombatGame 的敌人定义、数值或掉落。
var enemy_art_overrides: Dictionary = {}
var presentation_caption := ""
var cutout_motion_enabled := false
## 战斗界面（2.2 设计 D2.2-01/02/06）。规则裁定全部走 CombatGame；本脚本只消费事件、
## 展示状态、出牌轨迹、护盾/命中/恢复特效与浮动数字，不做第二次结算或阻塞输入。

signal battle_closed
signal inventory_mutated
signal settings_requested
signal presentation_refreshed

const FOREST := Color("#294f3c")
const CREAM := ExpeditionUI.TEXT
const BAD_RED := Color("#a4543f")
const GOOD_GREEN := Color("#3f7048")
const WARN_GOLD := Color("#9b713a")
const STATUS_ORDER := ["vulnerable", "weak", "poison", "strength", "dexterity"]
const STATUS_RULES := {
	"vulnerable": "受到的攻击伤害 ×1.5。层数表示持续时间，重复施加只延长时间。持有者行动阶段结束时减 1 层。",
	"weak": "造成的攻击伤害 ×0.75。层数表示持续时间，重复施加只延长时间。持有者行动阶段结束时减 1 层。",
	"poison": "持有者行动开始时受到当前层数点伤害，然后减 1 层。绕过格挡，不受力量、虚弱或易伤影响。3 层依次造成 3、2、1 点。",
	"strength": "每次攻击增加当前层数点基础伤害，多段攻击逐段增加。本场战斗持续，不自动衰减。",
	"dexterity": "每次普通格挡增加当前层数点。给队友格挡使用施放者的敏捷。本场战斗持续，不自动衰减。",
}

var combat: CombatGame
var last_combat: CombatGame
var run_mode := false
var defeat_close_text := "查看结算"
var compact_layout := false
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
var input_blocked: Callable = Callable()
var status_label: Label
var detail_label: Label
var log_label: RichTextLabel
var enemy_row: HBoxContainer
var hand_row: HBoxContainer
var player_panel: HBoxContainer
var battlefield: Control
var battlefield_ground: BattlefieldGround
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
var energy_pips: HBoxContainer
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
var feedback_generation := 0

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
		preview.add_child(ExpeditionUI.label(screen._card_definition(str(screen._hand_card(card_uid).get("card_id", ""))).get("name", "卡牌"), 18, ExpeditionUI.INK))
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

class StatusGlyph extends Control:
	var kind := "vulnerable"
	var tint := Color.WHITE
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var scale_factor := minf(size.x, size.y) / 20.0
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * scale_factor)
		match kind:
			"vulnerable":
				draw_polyline(PackedVector2Array([Vector2(9, 2), Vector2(2, 9), Vector2(7, 14)]), tint, 2, true)
				draw_polyline(PackedVector2Array([Vector2(12, 3), Vector2(18, 10), Vector2(10, 18)]), tint, 2, true)
				draw_line(Vector2(12, 5), Vector2(7, 11), tint, 2, true)
				draw_line(Vector2(7, 11), Vector2(12, 13), tint, 2, true)
			"weak":
				draw_line(Vector2(5, 3), Vector2(5, 10), tint, 2, true)
				draw_line(Vector2(5, 10), Vector2(14, 10), tint, 2, true)
				draw_line(Vector2(14, 10), Vector2(14, 17), tint, 2, true)
				draw_polyline(PackedVector2Array([Vector2(10, 13), Vector2(14, 17), Vector2(18, 13)]), tint, 2, true)
			"poison":
				draw_colored_polygon(PackedVector2Array([Vector2(10, 1), Vector2(4, 10), Vector2(16, 10)]), tint)
				draw_circle(Vector2(10, 11), 6, tint)
				draw_circle(Vector2(8, 11), 1.4, tint.darkened(0.65))
				draw_circle(Vector2(12, 11), 1.4, tint.darkened(0.65))
			"strength":
				draw_colored_polygon(PackedVector2Array([Vector2(10, 1), Vector2(4, 8), Vector2(8, 8), Vector2(8, 15), Vector2(12, 15), Vector2(12, 8), Vector2(16, 8)]), tint)
				draw_line(Vector2(4, 18), Vector2(16, 18), tint, 2, true)
			"dexterity":
				draw_colored_polygon(PackedVector2Array([Vector2(10, 2), Vector2(18, 5), Vector2(16, 13), Vector2(10, 19), Vector2(4, 13), Vector2(2, 5)]), tint)
				draw_line(Vector2(10, 6), Vector2(10, 14), tint.darkened(0.65), 2, true)
				draw_line(Vector2(6, 10), Vector2(14, 10), tint.darkened(0.65), 2, true)

class BattlefieldGround extends Control:
	var screen: BattleScreen
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		if screen == null or screen.target_controls.is_empty():
			return
		var left := INF
		var right := -INF
		var floor_y := 0.0
		for target in screen.target_controls.values():
			if not is_instance_valid(target) or not target.is_inside_tree():
				continue
			var rect: Rect2 = target.get_global_rect()
			left = minf(left, rect.get_center().x - global_position.x)
			right = maxf(right, rect.get_center().x - global_position.x)
			floor_y = rect.get_center().y - global_position.y + minf(rect.size.x, rect.size.y) * 0.39
		if not is_finite(left):
			return
		# One continuous ground plane connects both sides of the formation.
		var center := Vector2((left + right) / 2.0, floor_y)
		var radius := (right - left) / 2.0 + 105.0
		draw_set_transform(center, 0, Vector2(radius, 28))
		draw_circle(Vector2.ZERO, 1.0, Color("#29242c"))
		draw_set_transform(center + Vector2(0, 8), 0, Vector2(radius * 0.96, 20))
		var floor_color := Color("#40333b")
		if screen.layer_id == "iron_root_deeps":
			floor_color = Color("#37392e")
		elif screen.layer_id == "crystal_vein_deeps":
			floor_color = Color("#353345")
		elif screen.layer_id.begins_with("forest_ch1."):
			var area := ChapterOneDefs.area(screen.layer_id.trim_prefix("forest_ch1."))
			floor_color = Color(area.get("base", ExpeditionUI.SAGE)).darkened(0.38)
		draw_circle(Vector2.ZERO, 1.0, floor_color)
		draw_set_transform(Vector2.ZERO)
		for target in screen.target_controls.values():
			if is_instance_valid(target) and target.is_inside_tree():
				var rect: Rect2 = target.get_global_rect()
				var point := Vector2(rect.get_center().x - global_position.x, floor_y + 5)
				draw_set_transform(point, 0, Vector2(minf(rect.size.x, rect.size.y) * 0.32, 7))
				draw_circle(Vector2.ZERO, 1.0, Color("#0e1a20", 0.55))
		draw_set_transform(Vector2.ZERO)



func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	theme = ExpeditionUI.make_theme()
	_build()
	resized.connect(func() -> void:
		if combat != null:
			_refresh.call_deferred())


func open_run(combat: CombatGame, actor := "p1") -> void:
	_clear_feedback()
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
	status_label.text = ""
	_refresh()


func open_demo(target_game: FarmGame = null) -> void:
	_clear_feedback()
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
	status_label.text = ""


func _build() -> void:
	ExpeditionUI.backdrop(self)
	var frame := ExpeditionUI.frame(self)
	if compact_layout:
		frame.add_theme_constant_override("margin_top", 4)
		frame.add_theme_constant_override("margin_bottom", 4)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	frame.add_child(column)

	chooser_column = VBoxContainer.new()
	chooser_column.add_theme_constant_override("separation", 20)
	column.add_child(chooser_column)
	chooser_column.add_child(_label("牌组试炼", 32, CREAM))
	for encounter_id in ["tutorial", "normal", "defensive"]:
		var button := ExpeditionUI.button(CombatGame.ENCOUNTERS[encounter_id]["name"])
		button.pressed.connect(_on_choose_encounter.bind(encounter_id))
		chooser_column.add_child(button)
	var quit_button := ExpeditionUI.button("返回战备")
	quit_button.pressed.connect(_on_close)
	chooser_column.add_child(quit_button)

	battle_column = VBoxContainer.new()
	battle_column.add_theme_constant_override("separation", 5 if compact_layout else 8)
	battle_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(battle_column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	battle_column.add_child(top)
	var titles := VBoxContainer.new()
	top.add_child(titles)
	round_label = _label("", 25, CREAM)
	titles.add_child(round_label)
	status_label = _label("", 14, ExpeditionUI.MUTED)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(status_label)
	var settings := ExpeditionUI.settings_button()
	settings.name = "BattleSettingsButton"
	settings.pressed.connect(_open_settings)
	top.add_child(settings)

	battlefield = Control.new()
	battlefield.name = "Battlefield"
	battlefield.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_column.add_child(battlefield)
	battlefield_ground = BattlefieldGround.new()
	battlefield_ground.screen = self
	battlefield_ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battlefield.add_child(battlefield_ground)
	var formation_center := CenterContainer.new()
	formation_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battlefield.add_child(formation_center)
	var formation := HBoxContainer.new()
	formation.add_theme_constant_override("separation", 112)
	formation_center.add_child(formation)
	player_panel = HBoxContainer.new()
	player_panel.add_theme_constant_override("separation", 20)
	formation.add_child(player_panel)
	enemy_row = HBoxContainer.new()
	enemy_row.add_theme_constant_override("separation", 20)
	enemy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	formation.add_child(enemy_row)

	var dock := ExpeditionUI.panel(Color(ExpeditionUI.INK, 0.94), ExpeditionUI.LINE, 12)
	battle_column.add_child(dock)
	var dock_column := VBoxContainer.new()
	dock_column.add_theme_constant_override("separation", 8)
	dock.add_child(dock_column)
	var hand_header := HBoxContainer.new()
	hand_header.add_theme_constant_override("separation", 8)
	dock_column.add_child(hand_header)
	hand_header.add_child(BattleGlyph.make("energy", ExpeditionUI.GOLD, 22))
	energy_label = _label("", 20, ExpeditionUI.GOLD)
	hand_header.add_child(energy_label)
	energy_pips = HBoxContainer.new()
	energy_pips.add_theme_constant_override("separation", 5)
	hand_header.add_child(energy_pips)
	hand_hint = _label("", 13, ExpeditionUI.MUTED)
	hand_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hand_header.add_child(hand_hint)
	var scroll := ScrollContainer.new()
	scroll.name = "HandScroll"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 218
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
	detail_label.custom_minimum_size.y = 28
	bottom.add_child(detail_label)
	end_button = ExpeditionUI.button("结束回合", true)
	end_button.tooltip_text = "E · 弃掉手牌，敌人行动，然后恢复能量并抽牌。"
	end_button.pressed.connect(_on_end_turn)
	bottom.add_child(end_button)
	pile_panel = HBoxContainer.new()
	pile_panel.add_theme_constant_override("separation", 10)
	bottom.add_child(pile_panel)
	bottom.move_child(pile_panel, 0)

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
	modal_shade.color = Color(ExpeditionUI.INK, 0.68)
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
	_clear_feedback()
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
	_clear_feedback()
	_close_inspector()
	visible = false
	last_combat = combat
	combat = null
	battle_closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if input_blocked.is_valid() and bool(input_blocked.call()):
		return
	if event.is_action_pressed("pause"):
		if inspector_panel.visible or selected_uid >= 0 or chooser_column.visible or overlay_panel.visible:
			_cancel_selection()
		else:
			_open_settings()
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
	if input_blocked.is_valid() and bool(input_blocked.call()):
		return
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
	var immediate := _immediate_target(uid)
	if immediate != "":
		selected_uid = uid
		hovered_uid = -1
		_on_target_clicked(immediate)
		return
	if selected_uid == uid:
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
		if sent is Dictionary and bool(sent.get("ok", false)):
			_flash_events(sent.get("events", []))
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
	_clear_feedback()
	ExpeditionUI.set_layer(self,layer_id)
	if combat == null or combat.state.is_empty() or not combat.state["players"].has(player_key):
		return
	var player: Dictionary = combat.state["players"][player_key]
	var small := size.y < 680
	battlefield.custom_minimum_size.y = 232 if small else 332
	var hand_scroll := find_child("HandScroll", true, false) as ScrollContainer
	hand_scroll.custom_minimum_size.y = 178 if small else 218
	battle_column.add_theme_constant_override("separation", 8 if small else 12)
	if selected_uid >= 0 and _hand_card(selected_uid).is_empty():
		selected_uid = -1
	round_label.text = "回合 %02d" % int(combat.state["round"])
	if presentation_caption != "":
		round_label.text += " · " + presentation_caption
	energy_label.text = "%d / %d" % [int(player["energy"]), ExpeditionBaseline.ENERGY_PER_TURN]
	ExpeditionUI.clear(energy_pips)
	for i in range(ExpeditionBaseline.ENERGY_PER_TURN):
		var pip := ExpeditionUI.panel(ExpeditionUI.GOLD if i < int(player["energy"]) else ExpeditionUI.LINE, Color.TRANSPARENT, 0)
		pip.custom_minimum_size = Vector2(18, 6)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		energy_pips.add_child(pip)
	hand_hint.text = "%d 张手牌" % player["hand"].size()
	end_button.text = "等待队友…" if bool(player.get("ended", false)) else "结束回合"
	end_button.disabled = not _can_act()
	_refresh_enemies()
	_refresh_player()
	_refresh_hand()
	_refresh_piles()
	_refresh_log()
	_refresh_detail()
	_update_targets()
	_refresh_ground.call_deferred()
	if combat.is_over():
		_close_inspector()
		_show_outcome()
		carried_hp = int(player["hp"]) if combat.state["outcome"] == "won" else -1
	presentation_refreshed.emit()


func _refresh_enemies() -> void:
	ExpeditionUI.clear(enemy_row)
	target_controls.clear()
	target_previews.clear()
	for enemy in combat.state["enemies"]:
		var alive := bool(enemy["alive"])
		var key := str(enemy["id"])
		var card := VBoxContainer.new()
		card.custom_minimum_size.x = _actor_width()
		card.add_theme_constant_override("separation", 4 if size.y < 680 else 6)
		card.set_meta("unit_key", key)
		enemy_row.add_child(card)
		var intent_row := HBoxContainer.new()
		intent_row.name = "EnemyIntent_" + key
		intent_row.custom_minimum_size.y = 28
		intent_row.alignment = BoxContainer.ALIGNMENT_CENTER
		intent_row.add_theme_constant_override("separation", 6)
		var intent: Dictionary = combat.intent_preview(enemy)
		var intent_kind := str(intent.get("kind", ""))
		var intent_color := ExpeditionUI.RED if intent_kind == "attack" else ExpeditionUI.TEAL
		if alive and not intent.is_empty() and intent_kind != "none":
			intent_row.add_child(BattleGlyph.make(intent_kind, intent_color, 20))
			var variable_strikes := _intent_varies(intent)
			var intent_value := str(int(intent.get("value", 0)))
			if variable_strikes:
				intent_value = str(intent.get("text", "")).trim_prefix("攻击 ").replace(" + ", "\n")
			elif int(intent.get("times", 1)) > 1:
				intent_value += "×%d" % int(intent["times"])
			var value_label := _label(intent_value, 12 if variable_strikes else 21, intent_color)
			value_label.name = "IntentValue_" + key
			if variable_strikes:
				value_label.custom_minimum_size.x = _actor_width() - 28
				value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				value_label.max_lines_visible = 2
				value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			intent_row.add_child(value_label)
			if str(intent.get("status", "")) != "" and not variable_strikes:
				intent_row.add_child(_label(str(CardDefs.STATUS_DISPLAY.get(str(intent["status"]), "")), 13, Color("#c5b5e4")))
			if combat.state["players"].size() > 1 and intent_kind == "attack" and not variable_strikes:
				intent_row.add_child(_label("→ 你" if str(intent.get("target", "")) == player_key else "→ 队友", 13, ExpeditionUI.MUTED))
			intent_row.tooltip_text = combat.intent_text(enemy) + "\n按当前状态预览；× 表示每段伤害与攻击段数。\n结束玩家共同行动阶段后执行；已计入届时的易伤衰减。"
			if variable_strikes and str(intent.get("status", "")) != "":
				intent_row.tooltip_text += "\n每段攻击后附带%s %d 层。" % [CardDefs.STATUS_DISPLAY.get(str(intent["status"]), "状态"), int(intent.get("status_stacks", 1))]
		else:
			var reason := str(intent.get("text", "—"))
			if reason.contains("中毒"):
				reason = "中毒倒下"
			intent_row.add_child(_label("已击败" if not alive else reason, 16, ExpeditionUI.MUTED))
			intent_row.tooltip_text = str(intent.get("text", ""))
		card.add_child(intent_row)
		var target := _target_button(key)
		target.custom_minimum_size = Vector2(_actor_width(), 80 if size.y < 680 else 185)
		target.disabled = not alive
		card.add_child(target)
		var art := ExpeditionArt.new()
		art.show_shadow = false
		art.layer_id = layer_id
		art.subject = str(enemy_art_overrides.get(key, enemy.get("def_id", "slime")))
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		target.add_child(art)
		if not alive:
			card.modulate.a = 0.4
		var display_name := str(enemy["name"])
		if enemy_art_overrides.has(key):
			display_name = str(ChapterArtRegistry.resolve(art.subject).get("name", display_name))
		var name_label := _label(display_name, 17, CREAM)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(name_label)
		card.add_child(ExpeditionUI.bar(int(enemy["hp"]), int(enemy["max_hp"]), ExpeditionUI.RED))
		card.add_child(_unit_stats(enemy, true))
		card.add_child(_status_chips(enemy["statuses"], key))
		var preview := _label("", 12, ExpeditionUI.GOLD)
		preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		preview.custom_minimum_size.y = 20
		preview.max_lines_visible = 2
		preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		card.add_child(preview)
		target_previews[key] = preview


func _intent_varies(intent: Dictionary) -> bool:
	var strikes: Array = intent.get("strikes", [])
	if strikes.size() < 2:
		return false
	var first: Dictionary = strikes[0]
	for strike in strikes:
		if int(strike.get("amount", 0)) != int(first.get("amount", 0)) or str(strike.get("target", "")) != str(first.get("target", "")):
			return true
	return false


func _actor_width() -> float:
	var count: int = combat.state["players"].size() + combat.state["enemies"].size()
	return clampf((size.x - 48 - 112 - maxi(0, count - 2) * 20) / count, 120, 220)

func _refresh_ground() -> void:
	await get_tree().process_frame
	if is_instance_valid(battlefield_ground):
		battlefield_ground.queue_redraw()

func _refresh_hand() -> void:
	ExpeditionUI.clear(hand_row)
	var player: Dictionary = combat.state["players"][player_key]
	var index := 0
	for card in player["hand"]:
		index += 1
		var def := _card_definition(str(card["card_id"]))
		var uid := int(card["uid"])
		var button := CardButton.new()
		button.screen = self
		button.card_uid = uid
		button.name = "Card_%d" % uid
		button.custom_minimum_size = Vector2(132, 174) if size.y < 680 else Vector2(148, 216)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.disabled = not _playable_card(uid)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var accent := _card_color(str(card["card_id"]))
		var source := _card_source(card)
		var quality_tint := ItemDefs.quality_color(ItemDefs.quality_of(source))
		var selected := uid == selected_uid
		button.add_theme_stylebox_override("normal", ExpeditionUI.style(Color("#f8e6d9") if selected else ExpeditionUI.PAPER, ExpeditionUI.GOLD if selected else quality_tint.darkened(0.25), 10, 0))
		button.add_theme_stylebox_override("hover", ExpeditionUI.style(Color("#fff4e9"), ExpeditionUI.GOLD, 10, 0))
		button.add_theme_stylebox_override("pressed", ExpeditionUI.style(Color("#dfcec9"), ExpeditionUI.GOLD, 10, 0))
		button.add_theme_stylebox_override("disabled", ExpeditionUI.style(Color("#b4abb5"), Color("#786a7b"), 10, 0))
		button.add_theme_stylebox_override("focus", ExpeditionUI.style(Color.TRANSPARENT, ExpeditionUI.GOLD, 10, 0))
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 10)
		button.add_child(margin)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 6)
		margin.add_child(content)
		var title := HBoxContainer.new()
		content.add_child(title)
		var cost_badge := ExpeditionUI.panel(accent.darkened(0.1), Color.TRANSPARENT, 0)
		cost_badge.custom_minimum_size = Vector2(30, 30)
		title.add_child(cost_badge)
		var cost := _label(str(def["cost"]), 21, ExpeditionUI.PAPER)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_badge.add_child(cost)
		var name_label := _label(str(def["name"]), 15, ExpeditionUI.INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		title.add_child(name_label)
		var art := ExpeditionArt.new()
		art.subject = _card_subject(str(card["card_id"]))
		if bool(ChapterArtRegistry.card(str(card["card_id"])).get("ready", false)):
			art.subject = "card." + str(card["card_id"])
		elif bool(ChapterArtRegistry.item(str(source.get("def_id", ""))).get("ready", false)):
			art.subject = "item." + str(source["def_id"])
		art.tint = accent
		art.custom_minimum_size.y = 42 if size.y < 680 else 78
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.add_child(art)
		var desc := _label(_short_effect(def).replace(" · ", "\n"), 15 if size.y < 680 else 17, ExpeditionUI.INK)
		desc.name = "CardEffect"
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(desc)
		var footer := HBoxContainer.new()
		content.add_child(footer)
		var rule := _label(CardPresentation.special_rule(def), 11, Color("#655e50"))
		rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(rule)
		var hotkey := _label(str(index % 10), 11, Color("#837a67"))
		footer.add_child(hotkey)
		ExpeditionUI.ignore_tree(margin)
		button.tooltip_text = CardPresentation.full_text(def) + "\n来自：" + str(card.get("preview_source_name", ItemDefs.get_item(str(source.get("def_id", ""))).get("name", "基础牌组"))) + " · " + ItemDefs.quality_name(ItemDefs.quality_of(source))
		button.set_meta("source_quality", ItemDefs.quality_of(source))
		if int(def["cost"]) > int(player["energy"]):
			button.tooltip_text += "\n能量不足"
		var source_inventory := _inventory()
		if source_inventory != null and int(card.get("source_instance_id", 0)) > 0:
			button.tooltip_text += "\n" + DeckBuilder.source_summary(source_inventory, int(card["source_instance_id"]))
		button.set_meta("base_tooltip", button.tooltip_text)
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
		hand_row.add_child(_label("手牌用尽", 16, ExpeditionUI.MUTED))
	_refresh_card_values()


func _refresh_piles() -> void:
	ExpeditionUI.clear(pile_panel)
	var player: Dictionary = combat.state["players"][player_key]
	for entry in [["draw_pile", "抽牌", "cards"], ["discard_pile", "弃牌", "discard"], ["exhaust_pile", "移除", "exhaust"]]:
		var button := ExpeditionUI.button("%s %d" % [entry[1], player[entry[0]].size()])
		button.custom_minimum_size.y = 34
		button.add_theme_font_size_override("font_size", 14)
		button.tooltip_text = "查看" + str(entry[1]) + "堆"
		button.pressed.connect(_open_pile.bind(str(entry[0]), str(entry[1])))
		pile_panel.add_child(button)


func _refresh_log() -> void:
	var entries: Array = combat.combat_log()
	var recent: Array = entries.slice(maxi(0, entries.size() - 12), entries.size())
	log_label.text = "\n".join(recent)


func _open_history() -> void:
	inspector_panel.custom_minimum_size.x = 520
	ExpeditionUI.clear(inspector_column)
	inspector_column.add_child(_label("战斗记录",25,CREAM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460,300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector_column.add_child(scroll)
	var content := _label("\n".join(combat.combat_log()),18,ExpeditionUI.TEXT)
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var close_button := ExpeditionUI.button("返回战斗 · Esc")
	close_button.pressed.connect(_close_inspector)
	inspector_column.add_child(close_button)
	inspector_center.mouse_filter = Control.MOUSE_FILTER_STOP
	inspector_center.show()
	inspector_panel.show()
	modal_shade.show()


func _open_settings() -> void:
	if settings_requested.get_connections().size() > 0:
		settings_requested.emit()
		return
	ExpeditionUI.clear(inspector_column)
	inspector_panel.custom_minimum_size.x = 340
	inspector_column.add_child(_label("设置", 25, CREAM))
	for entry in [["继续战斗", "BattleResumeButton", _close_inspector], ["操作说明", "BattleHelpButton", _open_help], ["战斗记录", "BattleHistoryButton", _open_history]]:
		var choice := ExpeditionUI.button(str(entry[0]), str(entry[0]) == "继续战斗")
		choice.name = str(entry[1])
		choice.pressed.connect(entry[2])
		inspector_column.add_child(choice)
	inspector_center.mouse_filter = Control.MOUSE_FILTER_STOP
	inspector_center.show()
	inspector_panel.show()
	modal_shade.show()

func _open_help() -> void:
	inspector_panel.custom_minimum_size.x = 520
	ExpeditionUI.clear(inspector_column)
	inspector_column.add_child(_label("战斗指南", 25, CREAM))
	for entry in [["attack", "攻击 · 拖向敌人，或点牌后选择目标。"], ["shield", "格挡 · 抵消攻击伤害，持有者下次行动开始清空。"], ["heart", "恢复 · 自身牌点击即用，友方牌可选队友。"], ["energy", "能量 · 左上角是费用，每回合恢复。"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(BattleGlyph.make(str(entry[0]), ExpeditionUI.GOLD, 22))
		row.add_child(_label(str(entry[1]), 16, ExpeditionUI.TEXT))
		inspector_column.add_child(row)
	inspector_column.add_child(_label("敌人头顶：下一次行动。悬停卡牌：来源与完整规则。", 14, ExpeditionUI.MUTED))
	inspector_column.add_child(_label("状态图标悬停可查看层数、效果和衰减时机。\n易伤 / 虚弱在持有者行动结束减层；中毒在行动开始先伤害再减层。\n力量 / 敏捷持续本场战斗；所有状态在战斗结束清除。", 13, ExpeditionUI.MUTED))
	inspector_column.add_child(_label("1–0 选牌 · E 结束回合 · 右键取消 · Esc 取消 / 设置", 14, ExpeditionUI.MUTED))
	var close_button := ExpeditionUI.button("返回战斗")
	close_button.pressed.connect(_close_inspector)
	inspector_column.add_child(close_button)
	inspector_center.mouse_filter = Control.MOUSE_FILTER_STOP
	inspector_center.show()
	inspector_panel.show()
	modal_shade.show()


func _refresh_detail() -> void:
	_refresh_card_values()
	_update_targets()
	var uid := selected_uid if selected_uid >= 0 else hovered_uid
	var card := _hand_card(uid)
	if card.is_empty():
		detail_label.text = ""
		return
	var def := _card_definition(str(card["card_id"]))
	var target := hovered_target
	if target == "" and str(def["target"]) == "self":
		target = player_key
	if selected_uid < 0:
		detail_label.text = ""
		return
	var suffix := _target_preview(uid, target) if target != "" else "选择目标"
	detail_label.text = "%s · %s" % [def["name"], suffix]




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
	overlay_label.text = "%s\n\n%d 回合 · 生命 %d/%d" % ["胜利" if won else "败北", int(combat.state["round"]), int(player["hp"]), int(player["max_hp"])]
	overlay_panel.visible = true
	modal_shade.visible = true
	status_label.text = ""
	# 结算弹出时恢复拦截：点在面板外不应穿透到已结束的战斗按钮。
	overlay_center.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in overlay_column.get_children():
		if child != overlay_label:
			overlay_column.remove_child(child)
			child.queue_free()
	var close_button := _button(("搜刮战场" if won else defeat_close_text) if run_mode else "返回战备", Color("#eaf4df"), Color("#87b06f"))
	close_button.pressed.connect(_on_close)
	overlay_column.add_child(close_button)


# —— 事件反馈（轻量浮动数字）———————————————————————————————


func _flash_events(events: Array) -> void:
	_present_events.call_deferred(events.duplicate(true), feedback_generation)

func _present_events(events: Array, generation: int) -> void:
	# 等布局完成后定位，避免刷新手牌/敌人时将特效放到上一帧的位置。
	await get_tree().process_frame
	if generation != feedback_generation or not is_visible_in_tree():
		return
	var attack_card := ""
	for event in events:
		if generation != feedback_generation or not is_visible_in_tree():
			return
		var kind := str(event.get("type", ""))
		var unit := str(event.get("target", event.get("who", event.get("owner", ""))))
		if kind == "card_played":
			attack_card = str(event.get("card_id", ""))
		var motion: BattleCutoutMotion
		if kind == "damage" and cutout_motion_enabled and not SettingsStore.get_reduce_motion():
			motion = _animate_attack(str(event.get("source", "")), unit, attack_card)
			if motion != null:
				await get_tree().create_timer(BattleCutoutMotion.IMPACT_TIME).timeout
				if generation != feedback_generation or not is_visible_in_tree():
					return
		if kind in ["card_played", "damage", "block", "heal", "poison", "draw", "rescue", "status"]:
			_spawn_effect(kind, unit)
		match str(event.get("type", "")):
			"damage":
				_popup_on_unit(unit, "-%d 生命" % int(event.get("to_hp", 0)) if int(event.get("to_hp", 0)) > 0 else "格挡 %d" % int(event["amount"]), Color("#ff9d85") if int(event.get("to_hp", 0)) > 0 else Color("#b3daff"))
			"block":
				_popup_on_unit(unit, "+%d 格挡" % int(event["amount"]), Color("#a4dbff"))
			"heal":
				_popup_on_unit(unit, "+%d 生命" % int(event["amount"]), Color("#a7f0ae"))
			"draw":
				_popup_on_unit(unit, "+%d 抽牌" % int(event["count"]), Color("#ffe5a0"))
			"status":
				_popup_on_unit(unit, "%s +%d" % [CardDefs.STATUS_DISPLAY.get(str(event["status"]), event["status"]), int(event["stacks"])], Color("#dac1ff"))
			"rescue":
				_popup_on_unit(unit, "救起 · %d 生命" % int(event["hp"]), Color("#a7f0ae"))
			"poison":
				_popup_on_unit(str(event["target"]), "毒 -%d" % int(event["amount"]), Color("#a5679f"))
			"outcome":
				AudioKit.play(self, "victory" if str(event["outcome"]) == "won" else "defeat")
				_popup_center("胜利！" if str(event["outcome"]) == "won" else "失败……", WARN_GOLD)
		if is_instance_valid(motion):
			await get_tree().create_timer(BattleCutoutMotion.DURATION - BattleCutoutMotion.IMPACT_TIME).timeout


func _unit_art(key: String) -> ExpeditionArt:
	var anchor := _unit_anchor(key)
	if anchor != null:
		for child in anchor.get_children():
			if child is ExpeditionArt:
				return child
	return null


func _animate_attack(source: String, target: String, card_id := "") -> BattleCutoutMotion:
	var source_art := _unit_art(source)
	var target_art := _unit_art(target)
	if source_art == null or target_art == null or source_art == target_art:
		return null
	var motion := BattleCutoutMotion.new()
	motion.source_art = source_art
	motion.target_art = target_art
	motion.ranged = "archer" in source_art.subject or str(_card_definition(card_id).get("motion", "")) == "projectile"
	motion.add_to_group("battle_feedback_%d" % get_instance_id())
	add_child(motion)
	return motion


func _popup_on_unit(unit_key: String, text: String, color: Color) -> void:
	var anchor := _unit_anchor(unit_key)
	if anchor == null:
		return
	_popup_at(anchor, text, color)
	if SettingsStore.get_reduce_motion():
		return
	var pulse := anchor.create_tween()
	pulse.tween_property(anchor,"modulate",color.lightened(0.35),0.07)
	pulse.tween_property(anchor,"modulate",Color.WHITE,0.18)


func _popup_center(text: String, color: Color) -> void:
	_popup_at(self, text, color)


func _popup_at(anchor: Control, text: String, color: Color) -> void:
	var label := _label(text, 28, color)
	label.add_theme_color_override("font_outline_color", Color("#101f2b"))
	label.add_theme_constant_override("outline_size", 7)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.x = 220
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_to_group("battle_feedback_%d" % get_instance_id())
	label.z_index = 50
	var stack := 0
	for child in get_children():
		if child is Label and child.get_meta("popup_unit", 0) == anchor.get_instance_id():
			stack += 1
	label.set_meta("popup_unit", anchor.get_instance_id())
	label.position = anchor.get_global_rect().get_center() - global_position + Vector2(-110, -55 + (stack % 3) * 30)
	add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	if not SettingsStore.get_reduce_motion():
		tween.tween_property(label, "position:y", label.position.y - 65, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)


func _unit_anchor(unit_key: String) -> Control:
	if target_controls.has(unit_key) and is_instance_valid(target_controls[unit_key]):
		return target_controls[unit_key]
	if str(unit_key).begins_with("p"):
		return player_panel
	for child in enemy_row.get_children():
		if str(child.get_meta("unit_key", "")) == unit_key:
			return child
	return null

func _spawn_effect(kind: String, unit: String) -> void:
	var anchor := _unit_anchor(unit)
	if anchor == null:
		return
	var effect := BattleEffect.new()
	effect.kind = kind
	effect.tint = {"damage": Color("#ffb086"), "poison": Color("#c196eb"), "block": Color("#74cfff"), "heal": Color("#8de8a5"), "rescue": Color("#8de8a5"), "draw": Color("#ffe08e"), "status": Color("#cda2ff")}.get(kind, ExpeditionUI.GOLD)
	effect.center = anchor.get_global_rect().get_center() - global_position
	effect.from = hand_row.get_global_rect().get_center() - global_position
	effect.reduce_motion = SettingsStore.get_reduce_motion()
	effect.add_to_group("battle_feedback_%d" % get_instance_id())
	add_child(effect)

func _clear_feedback() -> void:
	feedback_generation += 1
	for child in get_children():
		if child.is_in_group("battle_feedback_%d" % get_instance_id()):
			remove_child(child)
			child.queue_free()

func _card_source(card: Dictionary) -> Dictionary:
	if str(card.get("source_def_id", "")) != "":
		return {"def_id": card["source_def_id"], "quality": int(card.get("source_quality", 1))}
	var source_inventory := _inventory()
	if source_inventory != null:
		return source_inventory.find_instance(int(card.get("source_instance_id", 0)))
	return {}

func _immediate_target(uid: int) -> String:
	var card := _hand_card(uid)
	if card.is_empty():
		return ""
	var rule := str(_card_definition(str(card["card_id"])).get("target", ""))
	if rule == "self":
		return player_key if _legal_target(uid, player_key) else ""
	if rule == "ally":
		var legal: Array = []
		for key in combat.state["players"]:
			if _legal_target(uid, str(key)):
				legal.append(str(key))
		if legal.size() == 1:
			return legal[0]
	return ""


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
		return ""
	var parts: Array = []
	for status in STATUS_ORDER:
		var stacks := int(statuses.get(status, {}).get("stacks", 0))
		if stacks > 0:
			parts.append("%s×%d" % [CardDefs.STATUS_DISPLAY.get(status, status), stacks])
	return " · ".join(parts)


func _status_chips(statuses: Dictionary, unit_key: String) -> CenterContainer:
	var center := CenterContainer.new()
	center.name = "UnitStatuses_" + unit_key
	center.custom_minimum_size.y = 20
	var grid := GridContainer.new()
	grid.columns = clampi(int(_actor_width() / 38.0), 1, 5)
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 2)
	center.add_child(grid)
	for status in STATUS_ORDER:
		var stacks := int(statuses.get(status, {}).get("stacks", 0))
		if stacks <= 0:
			continue
		var tint: Color = {"vulnerable": Color("#edaa90"), "weak": Color("#d4c18c"), "poison": Color("#b4cb84"), "strength": Color("#e8b270"), "dexterity": Color("#99c8d9")}.get(status, Color("#c5b5e4"))
		var chip := PanelContainer.new()
		chip.name = "Status_" + unit_key + "_" + str(status)
		chip.add_theme_stylebox_override("panel", ExpeditionUI.style(Color(tint, 0.10), Color(tint, 0.35), 3, 2))
		chip.tooltip_text = "%s · %d 层\n%s\n战斗结束时清除。" % [CardDefs.STATUS_DISPLAY.get(status, status), stacks, STATUS_RULES.get(status, "")]
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		grid.add_child(chip)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		chip.add_child(row)
		var glyph := StatusGlyph.new()
		glyph.kind = str(status)
		glyph.tint = tint
		glyph.custom_minimum_size = Vector2(16, 16)
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(glyph)
		row.add_child(_label(str(stacks), 12, tint))
		ExpeditionUI.ignore_tree(row)
	return center


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
	label.add_theme_font_size_override("font_size", maxi(12,size))
	label.add_theme_color_override("font_color", color)
	return label


func _button(content: String, _fill: Color, _border: Color) -> Button:
	return ExpeditionUI.button(content, true)


func _can_act() -> bool:
	if input_blocked.is_valid() and bool(input_blocked.call()):
		return false
	if combat == null or combat.state.is_empty() or not combat.state["players"].has(player_key):
		return false
	var player: Dictionary = combat.state["players"][player_key]
	return not combat.is_over() and combat.state["phase"] == "player" and int(player["hp"]) > 0 and not bool(player.get("ended", false)) and not pending_action

func _playable_card(uid: int) -> bool:
	var card := _hand_card(uid)
	if card.is_empty() or not _can_act():
		return false
	return int(_card_definition(str(card["card_id"]))["cost"]) <= int(combat.state["players"][player_key]["energy"])

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
	var context := _card_preview(selected_uid) if selected_uid >= 0 else {}
	for key in target_controls:
		var button: Button = target_controls[key]
		var legal := selected_uid >= 0 and _legal_target(selected_uid, str(key))
		button.add_theme_stylebox_override("normal", ExpeditionUI.style(Color(ExpeditionUI.RAISED, 0.35) if legal else Color.TRANSPARENT, ExpeditionUI.GOLD if legal else Color.TRANSPARENT, 14, 0))
		button.add_theme_stylebox_override("hover", ExpeditionUI.style(Color(ExpeditionUI.RAISED, 0.50) if legal else Color.TRANSPARENT, ExpeditionUI.GOLD if legal else Color(ExpeditionUI.SAGE, 0.35), 14, 0))
		button.add_theme_stylebox_override("pressed", ExpeditionUI.style(Color(ExpeditionUI.RAISED, 0.50), ExpeditionUI.TEAL, 14, 0))
		button.add_theme_stylebox_override("disabled", ExpeditionUI.style(Color.TRANSPARENT, Color.TRANSPARENT, 14, 0))
		button.tooltip_text = _target_preview(selected_uid, str(key)) if legal else "选择一张适用于这个目标的牌"
		if target_previews.has(key):
			var preview: Dictionary = combat.preview_play(player_key, selected_uid, str(key)) if legal else context
			var own_effects: Array = []
			for effect in preview.get("effects", []):
				if str(effect.get("target", effect.get("who", player_key))) == str(key):
					own_effects.append(effect)
			var own_lines := _preview_effect_lines({"effects": own_effects}, str(key), true, true)
			target_previews[key].text = " / ".join(own_lines)
			if not legal and not own_lines.is_empty():
				button.tooltip_text = "本牌对%s的效果：%s" % [_preview_target_name(str(key)), " / ".join(own_lines)]

func _refresh_player() -> void:
	ExpeditionUI.clear(player_panel)
	_add_player_actor(player_key)
	var ally := _ally_key()
	if ally != "":
		_add_player_actor(ally)

func _add_player_actor(key: String) -> void:
	var player: Dictionary = combat.state["players"][key]
	var card := VBoxContainer.new()
	card.custom_minimum_size.x = _actor_width()
	card.add_theme_constant_override("separation", 4 if size.y < 680 else 6)
	card.set_meta("unit_key", key)
	player_panel.add_child(card)
	var activity := _label("倒地" if bool(player.get("downed", false)) else ("已行动" if bool(player.get("ended", false)) else ""), 14, ExpeditionUI.MUTED)
	activity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	activity.custom_minimum_size.y = 28
	card.add_child(activity)
	var target := _target_button(key)
	target.custom_minimum_size = Vector2(_actor_width(), 80 if size.y < 680 else 185)
	card.add_child(target)
	var portrait := ExpeditionArt.new()
	portrait.subject = "farmer"
	portrait.modulate = Color.WHITE if key == player_key else Color("#abcbd8")
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target.add_child(portrait)
	if bool(player.get("downed", false)):
		portrait.modulate.a = 0.4
	var caption := _label("你" if key == player_key else "队友", 17, ExpeditionUI.GOLD if key == player_key else ExpeditionUI.TEXT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(caption)
	card.add_child(ExpeditionUI.bar(int(player["hp"]), int(player["max_hp"])))
	card.add_child(_unit_stats(player, true))
	card.add_child(_status_chips(player["statuses"], key))
	var preview := _label("", 12, ExpeditionUI.GOLD)
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.custom_minimum_size.y = 20
	preview.max_lines_visible = 2
	preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(preview)
	target_previews[key] = preview

func _unit_stats(unit: Dictionary, centered := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if centered:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(BattleGlyph.make("heart", ExpeditionUI.RED, 16))
	row.add_child(_label("%d/%d" % [int(unit["hp"]), int(unit["max_hp"])], 16, ExpeditionUI.TEXT))
	if int(unit["block"]) > 0:
		row.add_child(BattleGlyph.make("shield", Color("#99bdd5"), 16))
		row.add_child(_label(str(int(unit["block"])), 16, Color("#99bdd5")))
	row.tooltip_text = "生命 %d/%d · 格挡 %d\n格挡在持有者下次行动开始时清除；中毒绕过格挡。" % [int(unit["hp"]), int(unit["max_hp"]), int(unit["block"])]
	return row

func _target_preview(uid: int, key: String) -> String:
	if combat == null or uid < 0 or key == "":
		return ""
	var preview := combat.preview_play(player_key, uid, key)
	if not bool(preview.get("ok", false)):
		return "目标不适用"
	var parts := _preview_effect_lines(preview, key, true)
	return " / ".join(parts) if not parts.is_empty() else "整理货物，本场移除"


## 每个效果直接使用引擎模拟事件，避免混合牌把自身格挡算在敌人身上，
## 也避免多段攻击在格挡抵扣、先加状态再攻击时出现第二套 UI 算法。
func _preview_effect_lines(preview: Dictionary, selected_target: String, show_result: bool, compact := false) -> Array[String]:
	var parts: Array[String] = []
	var effects: Array = preview.get("effects", [])
	var hp_losses := {}
	var index := 0
	while index < effects.size():
		var effect: Dictionary = effects[index]
		var kind := str(effect.get("kind", effect.get("type", "")))
		var recipient := str(effect.get("target", effect.get("who", player_key)))
		var amount := int(effect.get("amount", effect.get("count", 0)))
		var line := ""
		if kind == "damage":
			var hits := 1
			var hp_loss := int(effect.get("to_hp", 0))
			var blocked := int(effect.get("blocked", 0))
			# 相邻且同值的攻击展示每段 × 段数；不同值保留效果先后顺序。
			while index + hits < effects.size():
				var next: Dictionary = effects[index + hits]
				if str(next.get("type", "")) != "damage" or str(next.get("target", "")) != recipient or int(next.get("amount", 0)) != amount:
					break
				hp_loss += int(next.get("to_hp", 0))
				blocked += int(next.get("blocked", 0))
				hits += 1
			line = "%d%s 伤害" % [amount, "×%d" % hits if hits > 1 else ""]
			if show_result:
				if compact:
					line = ("" if hits == 1 else "%d×%d · " % [amount, hits]) + "生命 −%d" % hp_loss
				else:
					line += " · 生命 −%d" % hp_loss
				if blocked > 0 and not compact:
					line += " · 格挡 %d" % blocked
				hp_losses[recipient] = int(hp_losses.get(recipient, 0)) + hp_loss
				if int(hp_losses[recipient]) >= int(combat._find_unit(recipient).get("hp", 999)):
					line += " · 击败"
			index += hits - 1
		elif kind == "block":
			line = "格挡 +%d" % amount
		elif kind == "heal":
			line = "生命 +%d" % amount
		elif kind == "draw":
			line = "抽牌 %d" % amount
		elif kind == "status":
			line = "%s +%d" % [CardDefs.STATUS_DISPLAY.get(str(effect.get("status", "")), "状态"), int(effect.get("stacks", 0))]
		elif kind == "rescue":
			line = "救起 · %d 生命" % int(effect.get("hp", 0))
		if line != "":
			if recipient != selected_target:
				line = _preview_target_name(recipient) + "：" + line
			parts.append(line)
		index += 1
	return parts


func _preview_target_name(key: String) -> String:
	if key == player_key:
		return "自己"
	if combat.state["players"].has(key):
		return "队友"
	return str(combat._find_unit(key).get("name", "目标"))

func _card_definition(id: String) -> Dictionary:
	return combat.card_definition(id) if combat != null else CardDefs.get_card(id)

func _card_subject(id: String) -> String:
	for effect in _card_definition(id).get("effects", []):
		if str(effect["kind"]) == "damage":
			return "attack"
		if str(effect["kind"]) == "block":
			return "shield"
	for effect in _card_definition(id).get("effects", []):
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
	return CardPresentation.effect_text(def)


func _card_preview(uid: int) -> Dictionary:
	if combat == null:
		return {}
	var candidates: Array[String] = []
	if hovered_target != "":
		candidates.append(hovered_target)
	candidates.append(player_key)
	for enemy in combat.state["enemies"]:
		if bool(enemy.get("alive", false)):
			candidates.append(str(enemy["id"]))
	for key in combat.state["players"]:
		if str(key) != player_key:
			candidates.append(str(key))
	for key in candidates:
		var preview := combat.preview_play(player_key, uid, key)
		if bool(preview.get("ok", false)):
			preview["selected_target"] = key
			return preview
	return {}


func _refresh_card_values() -> void:
	if hand_row == null or combat == null:
		return
	for button in hand_row.get_children():
		if not button is CardButton:
			continue
		var card := _hand_card(button.card_uid)
		if card.is_empty():
			continue
		var def := _card_definition(str(card["card_id"]))
		var preview := _card_preview(button.card_uid)
		var lines: Array[String] = []
		if bool(preview.get("ok", false)):
			lines = _preview_effect_lines(preview, str(preview["selected_target"]), false)
		var desc := button.find_child("CardEffect", true, false) as Label
		if desc != null:
			desc.text = "\n".join(lines) if not lines.is_empty() else CardPresentation.effect_text(def).replace(" · ", "\n")
		button.tooltip_text = str(button.get_meta("base_tooltip", CardPresentation.full_text(def)))
		if bool(preview.get("ok", false)):
			button.tooltip_text += "\n当前目标：%s\n当前效果：%s\n伤害已计入力量、虚弱和目标易伤；格挡已计入施放者敏捷。\n悬停目标可更新卡面数值，伤害在目标格挡抵扣前显示。" % [_preview_target_name(str(preview["selected_target"])), " / ".join(lines)]

func _open_pile(key: String, caption: String) -> void:
	inspector_panel.custom_minimum_size.x = 520
	ExpeditionUI.clear(inspector_column)
	inspector_column.add_child(_label(caption, 25, CREAM))
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
		var def := _card_definition(str(id))
		var line := _label("%s ×%d · %d 能量\n%s" % [def["name"], counts[id], int(def["cost"]), CardPresentation.effect_text(def)], 16, ExpeditionUI.TEXT)
		line.mouse_filter = Control.MOUSE_FILTER_PASS
		line.tooltip_text = CardPresentation.full_text(def)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(line)
	if counts.is_empty():
		list.add_child(_label("空", 16, ExpeditionUI.MUTED))
	var close_button := ExpeditionUI.button("返回战斗")
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
