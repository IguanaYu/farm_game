class_name BattleScreen
extends Control
## 战斗界面（2.2 设计 D2.2-01/02/06）。规则裁定全部走 CombatGame；本脚本只消费事件、
## 展示状态与轻量反馈（浮动数字），不做第二次结算。长动画不阻塞操作（本版无长动画）。

signal battle_closed
signal inventory_mutated

const FOREST := Color("#294f3c")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const TEXT_MUTED := Color("#788678")
const BAD_RED := Color("#a4543f")
const GOOD_GREEN := Color("#3f7048")
const WARN_GOLD := Color("#9b713a")
const CARD_BACK := Color("#f4e9cf")

var combat: CombatGame
var game: FarmGame
var carried_hp := -1  # 两场之间生命延续（2.3 设计 §5：各场战斗生命延续，首场按出发状态）
var selected_uid := -1
var status_label: Label
var detail_label: Label
var log_label: RichTextLabel
var enemy_row: HBoxContainer
var hand_row: HBoxContainer
var player_panel: VBoxContainer
var pile_panel: HBoxContainer
var end_button: Button
var overlay_panel: PanelContainer
var overlay_label: Label
var chooser_column: VBoxContainer
var battle_column: VBoxContainer
var round_label: Label
var played_count := 0


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


func open_demo(target_game: FarmGame = null) -> void:
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
	status_label.text = "演示战斗：牌组按当前战备布局生成；胜利后可搜刮（2.3 样例奖励）。"


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.09, 0.13, 0.10, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := _panel(Color("#223528"), Color("#6f9b71"), 18)
	panel.custom_minimum_size = Vector2(1150, 680)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	# —— 遭遇选择层 ——
	chooser_column = VBoxContainer.new()
	chooser_column.add_theme_constant_override("separation", 10)
	column.add_child(chooser_column)
	chooser_column.add_child(_label("选择一场遭遇（演示战斗）", 24, CREAM))
	for encounter_id in ["tutorial", "normal", "defensive"]:
		var button := _button(CombatGame.ENCOUNTERS[encounter_id]["name"], Color("#eaf4df"), Color("#87b06f"))
		button.pressed.connect(_on_choose_encounter.bind(encounter_id))
		chooser_column.add_child(button)
	var quit_button := _button("返回战备", Color("#fff5df"), Color("#d5b87d"))
	quit_button.pressed.connect(_on_close)
	chooser_column.add_child(quit_button)

	# —— 战斗层 ——
	battle_column = VBoxContainer.new()
	battle_column.add_theme_constant_override("separation", 6)
	battle_column.visible = false
	column.add_child(battle_column)
	var title_row := HBoxContainer.new()
	battle_column.add_child(title_row)
	round_label = _label("", 20, CREAM)
	title_row.add_child(round_label)
	status_label = _label("", 14, Color("#e8d9a8"))
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(status_label)

	enemy_row = HBoxContainer.new()
	enemy_row.add_theme_constant_override("separation", 12)
	enemy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	battle_column.add_child(_section("敌人（意图在回合开始确定，不因等待而变）", enemy_row))

	player_panel = VBoxContainer.new()
	player_panel.add_theme_constant_override("separation", 3)
	battle_column.add_child(player_panel)

	hand_row = HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", 8)
	hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	battle_column.add_child(_section("手牌（点击选牌，再点目标；右键取消）", hand_row))

	pile_panel = HBoxContainer.new()
	pile_panel.add_theme_constant_override("separation", 14)
	battle_column.add_child(pile_panel)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	battle_column.add_child(bottom)
	detail_label = _label("（选牌后这里显示预计效果）", 14, Color("#d8e8c8"))
	detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_label.custom_minimum_size = Vector2(560, 44)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(detail_label)
	end_button = _button("结束行动（能量 3）", Color("#ffd98a"), Color("#9b713a"))
	end_button.pressed.connect(_on_end_turn)
	bottom.add_child(end_button)

	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = false
	log_label.scroll_following = true
	log_label.custom_minimum_size = Vector2(0, 110)
	log_label.add_theme_font_size_override("normal_font_size", 13)
	log_label.add_theme_color_override("default_color", Color("#cfe2c2"))
	battle_column.add_child(log_label)

	# —— 终局层 ——
	overlay_panel = _panel(Color("#fff9ed"), Color("#d5c9aa"), 16)
	overlay_panel.visible = false
	overlay_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_label = _label("", 22, FOREST)
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_panel.add_child(overlay_label)
	var overlay_center := CenterContainer.new()
	overlay_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_center.add_child(overlay_panel)
	add_child(overlay_center)


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
	if game == null:
		return null
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	return inventory


func _on_close() -> void:
	visible = false
	combat = null
	battle_closed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if selected_uid >= 0:
			selected_uid = -1
			_refresh()
		elif chooser_column.visible:
			_on_close()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		selected_uid = -1
		_refresh()


# —— 交互 ————————————————————————————————————————————————————————


func _on_card_clicked(uid: int) -> void:
	selected_uid = uid
	_refresh()


func _on_target_clicked(target_key: String) -> void:
	if selected_uid < 0:
		status_label.text = "先点一张手牌。"
		return
	var result := combat.play_card("p1", selected_uid, target_key)
	selected_uid = -1
	if not result["ok"]:
		status_label.text = result["reason"]
		_refresh()
		return
	played_count += 1
	_flash_events(result["events"])
	_refresh()


func _on_end_turn() -> void:
	var result := combat.end_turn("p1")
	if result.get("waiting", false):
		status_label.text = "等待其他玩家结束……"
		return
	if not result["ok"]:
		status_label.text = result["reason"]
		return
	_flash_events(result["events"])
	_refresh()


# —— 刷新 ————————————————————————————————————————————————————————


func _refresh() -> void:
	if combat == null or combat.state.is_empty():
		return
	var player: Dictionary = combat.state["players"]["p1"]
	round_label.text = "第 %d 回合 ｜ 生命 %d/%d ｜ 格挡 %d ｜ 能量 %d ｜ 手牌 %d" % [
		int(combat.state["round"]), int(player["hp"]), int(player["max_hp"]),
		int(player["block"]), int(player["energy"]), int(player["hand"].size())]
	end_button.text = "结束行动（剩余能量 %d）" % int(player["energy"])
	_refresh_enemies()
	_refresh_hand()
	_refresh_piles()
	_refresh_log()
	_refresh_detail()
	if combat.is_over():
		_show_outcome()
		if combat.state["outcome"] == "won":
			carried_hp = int(combat.state["players"]["p1"]["hp"])
		else:
			carried_hp = -1


func _refresh_enemies() -> void:
	for child in enemy_row.get_children():
		enemy_row.remove_child(child)
		child.queue_free()
	var intents: Dictionary = {}
	for entry in combat.enemy_intents():
		intents[entry["enemy_id"]] = entry["text"]
	for enemy in combat.state["enemies"]:
		var enemy_card := _panel(Color("#3a4a3c") if bool(enemy["alive"]) else Color("#2c332c"), Color("#7d8f77"), 12)
		enemy_card.custom_minimum_size = Vector2(220, 160)
		enemy_card.set_meta("unit_key", str(enemy["id"]))
		enemy_row.add_child(enemy_card)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 3)
		enemy_card.add_child(column)
		var title := str(enemy["name"]) if bool(enemy["alive"]) else "%s（已击败）" % enemy["name"]
		column.add_child(_label(title, 18, CREAM))
		column.add_child(_label("生命 %d/%d ｜ 格挡 %d" % [int(enemy["hp"]), int(enemy["max_hp"]), int(enemy["block"])], 15, Color("#f0d9b0")))
		column.add_child(_label("意图：%s" % intents.get(str(enemy["id"]), "—"), 14, Color("#f3b8a0")))
		column.add_child(_label(_status_text(enemy["statuses"]), 13, Color("#d9c9e8")))
		if bool(enemy["alive"]) and combat.state["phase"] == "player":
			var strike := _button("作为目标", Color("#fff0dc"), Color("#c58f6f"))
			strike.pressed.connect(_on_target_clicked.bind(str(enemy["id"])))
			column.add_child(strike)


func _refresh_hand() -> void:
	for child in hand_row.get_children():
		hand_row.remove_child(child)
		child.queue_free()
	var player: Dictionary = combat.state["players"]["p1"]
	for card in player["hand"]:
		var def := CardDefs.get_card(str(card["card_id"]))
		var button := Button.new()
		button.custom_minimum_size = Vector2(128, 108)
		button.text = "%s\n费用 %d\n%s" % [def["name"], int(def["cost"]), _target_display(str(def["target"]))]
		var source_text := ""
		if game != null and int(card.get("source_instance_id", 0)) > 0:
			source_text = "
" + DeckBuilder.source_summary(_inventory(), int(card["source_instance_id"]))
		button.tooltip_text = def["desc"] + source_text
		button.add_theme_font_size_override("font_size", 13)
		var fill := CARD_BACK if int(card["uid"]) != selected_uid else Color("#ffe9b0")
		var style := _style(fill, Color("#c9a86a") if int(card["uid"]) != selected_uid else Color("#9b713a"), 10)
		style.content_margin_left = 6
		style.content_margin_right = 6
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
		button.pressed.connect(_on_card_clicked.bind(int(card["uid"])))
		hand_row.add_child(button)
	if player["hand"].is_empty():
		hand_row.add_child(_label("（没有手牌，也可以直接结束回合）", 13, TEXT_MUTED))


func _refresh_piles() -> void:
	for child in pile_panel.get_children():
		pile_panel.remove_child(child)
		child.queue_free()
	var player: Dictionary = combat.state["players"]["p1"]
	pile_panel.add_child(_label("抽牌堆 %d ｜ 弃牌堆 %d ｜ 已移除 %d" % [
		player["draw_pile"].size(), player["discard_pile"].size(), player["exhaust_pile"].size()], 14, Color("#cfe2c2")))
	var self_target := _button("以自己为目标", Color("#eaf4df"), Color("#87b06f"))
	self_target.pressed.connect(_on_target_clicked.bind("p1"))
	pile_panel.add_child(self_target)


func _refresh_log() -> void:
	var entries: Array = combat.combat_log()
	var recent: Array = entries.slice(maxi(0, entries.size() - 12), entries.size())
	log_label.text = "\n".join(recent)


func _refresh_detail() -> void:
	if selected_uid < 0:
		detail_label.text = "（选牌后这里显示预计效果）"
		return
	var card := _hand_card(selected_uid)
	if card.is_empty():
		detail_label.text = "（这张牌已经打出去了）"
		return
	var def := CardDefs.get_card(str(card["card_id"]))
	detail_label.text = "「%s」%s —— %s" % [def["name"], def["desc"], _preview_text(card)]


func _preview_text(card: Dictionary) -> String:
	var def := CardDefs.get_card(str(card["card_id"]))
	var target_key := _preview_target(str(def["target"]))
	if target_key == "":
		return "（点目标后显示预计数值）"
	var preview := combat.preview_play("p1", int(card["uid"]), target_key)
	if not bool(preview.get("ok", false)):
		return "（等待合法目标）"
	var parts: Array = []
	if preview.has("damage"):
		parts.append("预计伤害 %d" % int(preview["damage"]))
	if preview.has("block"):
		parts.append("预计格挡 +%d" % int(preview["block"]))
	if preview.has("heal"):
		parts.append("预计恢复 %d" % int(preview["heal"]))
	if preview.has("draw"):
		parts.append("抽 %d 张" % int(preview["draw"]))
	if preview.has("status"):
		parts.append("附加%s" % str(preview["status"]))
	if parts.is_empty():
		return "没有直接数值效果"
	return "；".join(parts)


func _preview_target(rule: String) -> String:
	match rule:
		"enemy":
			return _first_alive_enemy()
		"self", "ally":
			return "p1"
	return ""


func _first_alive_enemy() -> String:
	for enemy in combat.state["enemies"]:
		if bool(enemy["alive"]):
			return str(enemy["id"])
	return ""


func _show_outcome() -> void:
	var player: Dictionary = combat.state["players"]["p1"]
	var won: bool = str(combat.state["outcome"]) == "won"
	overlay_label.text = "%s\n\n历时 %d 回合 ｜ 剩余生命 %d/%d ｜ 本场出牌 %d 张" % [
		"战斗胜利！" if won else "战斗失败……",
		int(combat.state["round"]), int(player["hp"]), int(player["max_hp"]), played_count]
	overlay_panel.visible = true
	while overlay_panel.get_child_count() > 1:
		var extra: Node = overlay_panel.get_child(1)
		overlay_panel.remove_child(extra)
		extra.queue_free()
	var close_button := _button("返回", Color("#eaf4df"), Color("#87b06f"))
	close_button.pressed.connect(_on_close)
	overlay_panel.add_child(close_button)


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
				_popup_center("胜利！" if str(event["outcome"]) == "won" else "失败……", WARN_GOLD)


func _popup_on_unit(unit_key: String, text: String, color: Color) -> void:
	var anchor := _unit_anchor(unit_key)
	if anchor == null:
		return
	_popup_at(anchor, text, color)


func _popup_center(text: String, color: Color) -> void:
	_popup_at(self, text, color)


func _popup_at(anchor: Control, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.z_index = 50
	label.position = anchor.size / 2.0 + Vector2(randf_range(-30, 30), -20)
	add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 46.0, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)


func _unit_anchor(unit_key: String) -> Control:
	if unit_key == "p1":
		return player_panel
	for child in enemy_row.get_children():
		if str(child.get_meta("unit_key", "")) == unit_key:
			return child
	return null


# —— 工具 ————————————————————————————————————————————————————————


func _hand_card(uid: int) -> Dictionary:
	if combat == null:
		return {}
	for card in combat.state["players"]["p1"]["hand"]:
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
			return "→ 敌人"
		"self":
			return "→ 自己"
		"ally":
			return "→ 友方"
	return ""


func _section(title: String, content: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(_label(title, 14, TEXT_MUTED))
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(content)
	return box


func _panel(fill: Color, border: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
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
