class_name CardPlaytest
extends Control
## 首页独立单人试玩：真实战斗与搜刮规则，临时配装，不落农场或局档。

const ENCOUNTERS := [
	{"name": "骷髅", "row": 3, "col": 1},
	{"name": "野怪", "row": 1, "col": 1},
	{"name": "守门战", "row": 8, "col": 0},
	{"name": "小泥团", "row": 1, "col": 0},
]

class PlaytestExpedition extends ExpeditionGame:
	func save() -> bool:
		return true
	func _settle_run(kind: String, _detail: int, _member_key := "") -> Dictionary:
		CorpseLootGame.cancel(run)
		run["phase"] = "finished"
		run["outcome"] = kind
		return {"ok": true, "outcome": kind, "reason": ""}

var farm: FarmGame
var expedition: ExpeditionGame
var battle: BattleScreen
var loot: ExpeditionLootPanel
var encounter_picker: OptionButton
var quality_picker: OptionButton
var test_quality := 0
var session_label: Label
var pause_view: CenterContainer
var pause_shade: ColorRect
var test_options: VBoxContainer
var battle_info: HBoxContainer
var encounter_index := 0
var battle_number := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ExpeditionUI.make_theme()
	_build()
	_reset_equipment()

func _build() -> void:
	var stage := Control.new()
	stage.name = "PlaytestStage"
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(stage)
	battle = BattleScreen.new()
	battle.defeat_close_text = "重试本场"
	battle.battle_closed.connect(_battle_closed)
	battle.settings_requested.connect(_open_settings)
	battle.input_blocked = func() -> bool: return pause_view != null and pause_view.visible
	stage.add_child(battle)
	loot = ExpeditionLootPanel.new()
	loot.action_sink = _loot_action
	loot.menu_requested.connect(_open_settings)
	stage.add_child(loot)
	loot.leave_button.text = "下一场 →"
	loot.battlefield.leave_text = "下一场 →"
	loot.input_blocked = func() -> bool: return pause_view.visible
	pause_shade = ColorRect.new()
	pause_shade.name = "PlaytestSettingsShade"
	pause_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_shade.color = Color(ExpeditionUI.INK, 0.76)
	pause_shade.visible = false
	pause_shade.z_index = 100
	add_child(pause_shade)
	pause_view = CenterContainer.new()
	pause_view.name = "PlaytestSettingsMenu"
	pause_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_view.visible = false
	pause_view.z_index = 101
	add_child(pause_view)
	var panel := ExpeditionUI.panel(ExpeditionUI.PANEL, ExpeditionUI.LINE, 20)
	panel.custom_minimum_size.x = 340
	pause_view.add_child(panel)
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 10)
	panel.add_child(choices)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	choices.add_child(heading)
	heading.add_child(ExpeditionUI.seal(36))
	heading.add_child(ExpeditionUI.label("设置", 26, ExpeditionUI.PAPER))
	session_label = ExpeditionUI.label("", 13, ExpeditionUI.MUTED)
	session_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	session_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(session_label)
	var resume := ExpeditionUI.button("继续游戏", true)
	resume.name = "PlaytestResumeButton"
	resume.pressed.connect(_close_settings)
	choices.add_child(resume)
	var replay := ExpeditionUI.button("重开本场")
	replay.name = "ReplayBattleButton"
	replay.tooltip_text = "恢复生命，保留本次装包的装备。"
	replay.pressed.connect(_begin_battle)
	choices.add_child(replay)
	battle_info = HBoxContainer.new()
	battle_info.add_theme_constant_override("separation", 10)
	choices.add_child(battle_info)
	for entry in [["操作说明", "PlaytestHelpButton", "help"], ["战斗记录", "PlaytestHistoryButton", "history"]]:
		var info := ExpeditionUI.button(str(entry[0]))
		info.name = str(entry[1])
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.pressed.connect(_show_battle_info.bind(str(entry[2])))
		battle_info.add_child(info)
	var home := ExpeditionUI.button("返回首页")
	home.name = "PlaytestHomeButton"
	home.tooltip_text = "结束试玩，清空本次试玩进度。"
	home.pressed.connect(_go_home)
	choices.add_child(home)
	var advanced := ExpeditionUI.button("试玩选项")
	advanced.name = "PlaytestOptionsButton"
	advanced.pressed.connect(func() -> void: test_options.visible = not test_options.visible)
	choices.add_child(advanced)
	test_options = VBoxContainer.new()
	test_options.name = "PlaytestOptions"
	test_options.visible = false
	test_options.add_theme_constant_override("separation", 10)
	choices.add_child(test_options)
	var encounter_row := HBoxContainer.new()
	test_options.add_child(encounter_row)
	var encounter_caption := ExpeditionUI.label("敌人", 15, ExpeditionUI.MUTED)
	encounter_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	encounter_row.add_child(encounter_caption)
	encounter_picker = OptionButton.new()
	encounter_picker.name = "PlaytestEncounterPicker"
	encounter_picker.custom_minimum_size = Vector2(180, 40)
	encounter_picker.tooltip_text = "切换敌人并重开本场。"
	for encounter in ENCOUNTERS:
		encounter_picker.add_item(encounter["name"])
	encounter_picker.item_selected.connect(_select_encounter)
	encounter_row.add_child(encounter_picker)
	var quality_row := HBoxContainer.new()
	test_options.add_child(quality_row)
	var quality_caption := ExpeditionUI.label("品质", 15, ExpeditionUI.MUTED)
	quality_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality_row.add_child(quality_caption)
	quality_picker = OptionButton.new()
	quality_picker.name = "PlaytestQualityPicker"
	quality_picker.custom_minimum_size = Vector2(180, 40)
	quality_picker.add_item("随机品质")
	for quality in range(1, 6):
		quality_picker.add_item(ItemDefs.quality_name(quality).split(" · ")[0])
	quality_picker.tooltip_text = "选择后恢复初始装备并重开本场；临时装备与敌人掉落使用该品质，便于测试颜色和搜索速度。"
	quality_picker.item_selected.connect(func(index: int) -> void:
		test_quality = index
		_reset_equipment())
	quality_row.add_child(quality_picker)
	var reset := ExpeditionUI.button("重置装备")
	reset.tooltip_text = "恢复初始装备并重开本场。"
	reset.name = "ResetPlaytestButton"
	reset.pressed.connect(_reset_equipment)
	test_options.add_child(reset)

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and pause_view.visible and event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed("pause"):
		_close_settings()
		get_viewport().set_input_as_handled()

func _open_settings() -> void:
	battle_info.visible = battle.visible
	test_options.visible = false
	pause_shade.show()
	pause_view.show()
	(find_child("PlaytestResumeButton", true, false) as Button).grab_focus()

func _close_settings() -> void:
	pause_view.hide()
	pause_shade.hide()
	if battle.combat != null:
		battle._refresh()

func _show_battle_info(kind: String) -> void:
	_close_settings()
	if kind == "help":
		battle._open_help()
	else:
		battle._open_history()

func _stop_search() -> void:
	if expedition != null:
		CorpseLootGame.cancel(expedition.run)
	loot.run["loot_searches"] = {}
	loot.pending_action = false
	loot.stop_search_pending = false

func _reset_equipment() -> void:
	_stop_search()
	farm = FarmGame.new()
	farm.new_game(int(Time.get_unix_time_from_system()))
	var inventory := InventoryGame.new()
	inventory.bind(farm.state["expedition"])
	inventory.grant_basic_kit()
	inventory.add_instance("copper_shortsword", "playtest")
	inventory.add_instance("small_potion", "playtest")
	# 三栏改版：武器/盾/草帽上装备槽（第 1 回合即可抽到），药水入胸挂。
	inventory.equip(_first_id(inventory, "old_shortsword"), "main_weapon")
	inventory.equip(_first_id(inventory, "copper_shortsword"), "off_weapon")
	inventory.equip(_first_id(inventory, "wooden_shield"), "armor")
	inventory.equip(_first_id(inventory, "straw_hat"), "helmet")
	for def_id in ["small_potion", "pack_tools"]:
		for item in inventory.warehouse_list():
			if str(item["def_id"]) == def_id:
				inventory.move_to_loadout(int(item["instance_id"]), "chest")
				break
	expedition = null
	battle_number = 0
	_begin_battle()

func _select_encounter(index: int) -> void:
	encounter_index = clampi(index, 0, ENCOUNTERS.size() - 1)
	encounter_picker.select(encounter_index)
	_begin_battle()

func _begin_battle() -> void:
	_stop_search()
	_close_settings()
	loot.visible = false
	var carried: Dictionary = expedition.run["inventory"].duplicate(true) if expedition != null else {}
	var next_id := int(expedition.run["next_instance_id"]) if expedition != null else 0
	battle_number += 1
	expedition = PlaytestExpedition.new()
	expedition.bind(farm)
	expedition.run = ExpeditionGame.compose_run(farm, {}, "playtest-%d-%d" % [get_instance_id(), battle_number], int(Time.get_unix_time_from_system()), false, "单人卡牌试玩")
	if not carried.is_empty():
		expedition.run["inventory"] = carried
		expedition.run["next_instance_id"] = next_id
	expedition.rng.seed = int(expedition.run["rng_seed"])
	if test_quality > 0:
		for item in expedition.run_inventory().all_instances():
			if str(ItemDefs.get_item(str(item["def_id"])).get("category", "")) in ["weapon", "armor", "tool"]:
				item["quality"] = test_quality
	var encounter: Dictionary = ENCOUNTERS[encounter_index]
	expedition.run["current"] = {"row": encounter["row"], "col": encounter["col"]}
	expedition.run["phase"] = "node"
	expedition._resolve_node(expedition.current_node())
	var reply := expedition.start_battle()
	if bool(reply.get("ok", false)):
		battle.open_run(reply["combat"])
		session_label.text = "试玩 · %02d" % battle_number
		session_label.tooltip_text = "每场回满生命，装包的装备带入下一场。返回首页后清空试玩进度。"
		battle.status_label.text = ""

func _battle_closed() -> void:
	if battle.last_combat == null:
		return
	var result := expedition.finish_battle(battle.last_combat)
	if bool(result.get("ok", false)) and str(result.get("outcome", "")) == "won":
		if test_quality > 0:
			var current: Dictionary = expedition.run["current"]
			for source in expedition.run["resolved"][expedition.node_id(int(current["row"]), int(current["col"]))].get("corpses", []):
				for region in source["regions"]:
					for item in region["items"]:
						if str(ItemDefs.get_item(str(item["def_id"])).get("category", "")) in ["weapon", "armor", "tool"]:
							item["quality"] = test_quality
		loot.display(expedition.visible_run())
	else:
		_begin_battle()

func _loot_action(kind: String, args: Dictionary) -> Dictionary:
	if kind == "leave_node":
		_begin_battle.call_deferred()
		return {"ok": true, "reason": "进入下一场，保留本次装包。"}
	var result := expedition.loot_action("p1", kind, args)
	loot.display(expedition.visible_run())
	return result

func _go_home() -> void:
	_stop_search()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _first_id(inventory: InventoryGame, def_id: String) -> int:
	for item in inventory.warehouse_list():
		if str(item["def_id"]) == def_id:
			return int(item["instance_id"])
	return -1
