class_name ForestPlaytest
extends CardPlaytest
## 美术在真实战斗/搜索/装包流程中的独立试玩。沿用卡牌试玩规则，不创建正式森林局。

var area_id := "trail"
var enemy_id := "forest_alpha_wolf"
var exploration: Control
var area_picker: OptionButton
var enemy_picker: OptionButton
var prop_row: HBoxContainer
var actor_art: ExpeditionArt
var enemy_caption: Label
var area_caption: Label
var inspection: AcceptDialog
var inspection_art: ExpeditionArt

func _ready() -> void:
	super._ready()
	_show_exploration()

func _build() -> void:
	super._build()
	encounter_picker.get_parent().hide()
	var return_to_forest := ExpeditionUI.button("返回林间")
	return_to_forest.name = "ReturnToForestButton"
	return_to_forest.pressed.connect(_show_exploration)
	test_options.get_parent().add_child(return_to_forest)
	exploration = Control.new()
	exploration.name = "ForestExploration"
	exploration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_node("PlaytestStage").add_child(exploration)
	ExpeditionUI.backdrop(exploration)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	ExpeditionUI.frame(exploration, 24).add_child(stack)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	stack.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	area_caption = ExpeditionUI.label("", 27, ExpeditionUI.PAPER)
	titles.add_child(area_caption)
	titles.add_child(ExpeditionUI.label("美术试玩 · 战斗与掉落沿用骷髅样例规则", 14, ExpeditionUI.PAPER))
	area_picker = OptionButton.new()
	area_picker.name = "ForestAreaPicker"
	for key in ChapterOneDefs.AREA_ORDER:
		area_picker.add_item(str(ChapterOneDefs.area(str(key))["name"]))
	area_picker.item_selected.connect(select_area)
	header.add_child(area_picker)
	var home := ExpeditionUI.button("返回首页")
	home.name = "ForestHomeButton"
	home.pressed.connect(_go_home)
	header.add_child(home)
	var clearing := HBoxContainer.new()
	clearing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clearing.alignment = BoxContainer.ALIGNMENT_CENTER
	clearing.add_theme_constant_override("separation", 160)
	stack.add_child(clearing)
	var farmer := ExpeditionArt.new()
	farmer.subject = "farmer"
	farmer.custom_minimum_size = Vector2(170, 170)
	farmer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clearing.add_child(farmer)
	var enemy_column := VBoxContainer.new()
	enemy_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clearing.add_child(enemy_column)
	actor_art = ExpeditionArt.new()
	actor_art.name = "ForestEnemyArt"
	actor_art.custom_minimum_size = Vector2(210, 190)
	enemy_column.add_child(actor_art)
	enemy_caption = ExpeditionUI.label("", 20, ExpeditionUI.PAPER)
	enemy_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_column.add_child(enemy_caption)
	var props_panel := ExpeditionUI.panel(Color(ExpeditionUI.PANEL, 0.92), ExpeditionUI.LINE, 12)
	stack.add_child(props_panel)
	var props_stack := VBoxContainer.new()
	props_panel.add_child(props_stack)
	props_stack.add_child(ExpeditionUI.label("林间物件 · 点击查看插图", 16, ExpeditionUI.SAGE))
	var scroll := ScrollContainer.new()
	scroll.name = "ForestPropsScroll"
	scroll.custom_minimum_size.y = 144
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	props_stack.add_child(scroll)
	prop_row = HBoxContainer.new()
	prop_row.add_theme_constant_override("separation", 10)
	scroll.add_child(prop_row)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	stack.add_child(footer)
	footer.add_child(ExpeditionUI.label("敌人外观", 15, ExpeditionUI.PAPER))
	enemy_picker = OptionButton.new()
	enemy_picker.name = "ForestEnemyPicker"
	enemy_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in ChapterOneDefs.ENEMIES:
		enemy_picker.add_item(str(ChapterOneDefs.ENEMIES[key]["name"]))
	enemy_picker.item_selected.connect(select_enemy)
	footer.add_child(enemy_picker)
	var fight := ExpeditionUI.button("开始战斗 →", true)
	fight.name = "ForestBattleButton"
	fight.pressed.connect(_begin_battle)
	footer.add_child(fight)
	inspection = AcceptDialog.new()
	inspection.name = "ForestPropInspection"
	inspection.ok_button_text = "返回林间"
	inspection_art = ExpeditionArt.new()
	inspection_art.custom_minimum_size = Vector2(300, 300)
	inspection.add_child(inspection_art)
	add_child(inspection)
	loot.leave_button.text = "返回林间 →"
	loot.battlefield.leave_text = "返回林间 →"

func select_area(index: int) -> void:
	area_id = str(ChapterOneDefs.AREA_ORDER[clampi(index, 0, ChapterOneDefs.AREA_ORDER.size() - 1)])
	enemy_id = str(ChapterOneDefs.area(area_id)["boss"])
	_show_exploration()

func select_enemy(index: int) -> void:
	var keys := ChapterOneDefs.ENEMIES.keys()
	enemy_id = str(keys[clampi(index, 0, keys.size() - 1)])
	_refresh_exploration()

func _show_exploration() -> void:
	_stop_search()
	_close_settings()
	battle.hide()
	loot.hide()
	exploration.show()
	_refresh_exploration()

func _refresh_exploration() -> void:
	ExpeditionUI.set_layer(exploration, "forest_ch1." + area_id)
	area_caption.text = "苔冠森林 · " + str(ChapterOneDefs.area(area_id)["name"])
	area_picker.select(ChapterOneDefs.AREA_ORDER.find(area_id))
	enemy_picker.select(ChapterOneDefs.ENEMIES.keys().find(enemy_id))
	actor_art.subject = "enemy." + enemy_id
	actor_art.queue_redraw()
	enemy_caption.text = str(ChapterOneDefs.ENEMIES[enemy_id]["name"])
	ExpeditionUI.clear(prop_row)
	for template_id in ChapterOneDefs.templates_for_area(area_id):
		var key := str(template_id)
		var record := ChapterOneDefs.template(key)
		var button := ExpeditionUI.button("")
		button.name = "ForestProp_" + key
		button.custom_minimum_size = Vector2(112, 124)
		button.tooltip_text = str(record["name"]) + " · 插图查看"
		button.pressed.connect(_inspect_prop.bind(key))
		prop_row.add_child(button)
		var column := VBoxContainer.new()
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(column)
		var art := ExpeditionArt.new()
		art.subject = "prop." + key
		art.custom_minimum_size = Vector2(100, 94)
		column.add_child(art)
		var label := ExpeditionUI.label(str(record["name"]), 14, ExpeditionUI.PAPER)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
		ExpeditionUI.ignore_tree(column)

func _inspect_prop(key: String) -> void:
	inspection.title = str(ChapterOneDefs.template(key)["name"]) + " · 插图查看"
	inspection_art.subject = "prop." + key
	inspection_art.queue_redraw()
	inspection.popup_centered(Vector2i(340, 360))

func _begin_battle() -> void:
	if exploration != null:
		exploration.hide()
	battle.layer_id = "forest_ch1." + area_id
	battle.enemy_art_overrides = {"e1": "enemy." + enemy_id}
	battle.presentation_caption = "森林美术试玩 / 骷髅规则"
	super._begin_battle()

func _battle_closed() -> void:
	loot.visual_layer_id = "forest_ch1." + area_id
	loot.enemy_art_overrides = battle.enemy_art_overrides.duplicate()
	super._battle_closed()

func _loot_action(kind: String, args: Dictionary) -> Dictionary:
	if kind == "leave_node":
		_show_exploration.call_deferred()
		return {"ok": true, "reason": "返回林间，保留本次装包。"}
	return super._loot_action(kind, args)
