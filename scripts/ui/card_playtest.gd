class_name CardPlaytest
extends Control
## 首页独立单人试玩：真实战斗与搜刮规则，临时配装，不落农场或局档。

const ENCOUNTERS := [
	{"name": "骷髅 · 武器与双包", "row": 3, "col": 1},
	{"name": "野怪 · 多具遗骸", "row": 1, "col": 1},
	{"name": "守门战 · 2×2 盾牌", "row": 8, "col": 0},
	{"name": "小泥团 · 入门战斗", "row": 1, "col": 0},
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
var encounter_index := 0
var battle_number := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ExpeditionUI.make_theme()
	_build()
	_reset_equipment()

func _build() -> void:
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	var toolbar := ExpeditionUI.panel(ExpeditionUI.INK, ExpeditionUI.LINE, 0)
	toolbar.get_theme_stylebox("panel").content_margin_left = 12
	toolbar.get_theme_stylebox("panel").content_margin_right = 12
	layout.add_child(toolbar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	toolbar.add_child(row)
	session_label = ExpeditionUI.label("单人卡牌试玩", 20, ExpeditionUI.GOLD)
	session_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(session_label)
	encounter_picker = OptionButton.new()
	encounter_picker.name = "PlaytestEncounterPicker"
	encounter_picker.custom_minimum_size = Vector2(225, 40)
	for encounter in ENCOUNTERS:
		encounter_picker.add_item(encounter["name"])
	encounter_picker.item_selected.connect(_select_encounter)
	row.add_child(encounter_picker)
	quality_picker = OptionButton.new()
	quality_picker.name = "PlaytestQualityPicker"
	quality_picker.custom_minimum_size = Vector2(146, 40)
	quality_picker.add_item("品质 · 随机掉落")
	for quality in range(1, 6):
		quality_picker.add_item("品质 · " + ItemDefs.quality_name(quality).split(" · ")[0])
	quality_picker.tooltip_text = "选择后恢复初始装备并重开本场；临时装备与敌人掉落使用该品质，便于测试颜色和搜索速度。"
	quality_picker.item_selected.connect(func(index: int) -> void:
		test_quality = index
		_reset_equipment())
	row.add_child(quality_picker)
	var replay := ExpeditionUI.button("重开本场")
	replay.name = "ReplayBattleButton"
	replay.tooltip_text = "恢复生命，保留本次试玩装包的装备，重新开打。"
	replay.pressed.connect(_begin_battle)
	row.add_child(replay)
	var reset := ExpeditionUI.button("恢复初始装备")
	reset.name = "ResetPlaytestButton"
	reset.pressed.connect(_reset_equipment)
	row.add_child(reset)
	var home := ExpeditionUI.button("返回首页")
	home.name = "PlaytestHomeButton"
	home.pressed.connect(_go_home)
	row.add_child(home)
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(stage)
	battle = BattleScreen.new()
	battle.compact_layout = true
	battle.defeat_close_text = "重试本场"
	battle.battle_closed.connect(_battle_closed)
	stage.add_child(battle)
	loot = ExpeditionLootPanel.new()
	loot.action_sink = _loot_action
	loot.menu_requested.connect(func() -> void: pause_view.visible = true)
	stage.add_child(loot)
	loot.leave_button.text = "完成搜刮，下一场战斗 →"
	loot.battlefield.leave_text = "下一场战斗 →"
	loot.input_blocked = func() -> bool: return pause_view.visible
	pause_view = CenterContainer.new()
	pause_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_view.visible = false
	stage.add_child(pause_view)
	var panel := ExpeditionUI.panel(ExpeditionUI.PANEL, ExpeditionUI.GOLD, 16)
	pause_view.add_child(panel)
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 12)
	panel.add_child(choices)
	choices.add_child(ExpeditionUI.label("单人卡牌试玩", 26, ExpeditionUI.GOLD))
	choices.add_child(ExpeditionUI.label("每场回满生命，搜到的装备可以带入下一场。", 18))
	choices.add_child(ExpeditionUI.label("返回首页后，本次试玩进度清空。", 18, ExpeditionUI.MUTED))
	var resume := ExpeditionUI.button("继续试玩", true)
	resume.pressed.connect(func() -> void: pause_view.visible = false)
	choices.add_child(resume)
	var back := ExpeditionUI.button("返回首页")
	back.pressed.connect(_go_home)
	choices.add_child(back)

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
	for def_id in ["copper_shortsword", "wooden_shield", "small_potion"]:
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
	pause_view.visible = false
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
		session_label.text = "单人卡牌试玩 · 第 %d 场" % battle_number
		battle.status_label.text = "装备已配好 · 打赢后搜索尸体，装包后继续下一场。" if battle_number == 1 else "本次装包已带入 · 每场回满生命，返回首页后清空试玩进度。"

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
