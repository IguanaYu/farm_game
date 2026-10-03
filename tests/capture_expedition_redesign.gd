extends SceneTree
## 独立内存档；真实 GUI 输入、拖放与布局检查。带窗口时同时保存预览。

class MemoryExpedition extends ExpeditionGame:
	func save() -> bool:
		return true

var failed := false
var screen: BattleScreen
var hub: ExpeditionHubPanel
var map_panel: ExpeditionMapPanel
var game: FarmGame
var shots := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error("EXPEDITION_UI_FAIL: " + message)

func _settle() -> void:
	for i in range(6):
		await process_frame

func _click(button: Button) -> void:
	_check(button != null and button.is_visible_in_tree() and not button.disabled, "clickable button")
	if button == null:
		return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await _settle()

func _key(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event, true)
	await _settle()

func _shot(caption: String, panel: Control) -> void:
	await _settle()
	var viewport_rect := root.get_visible_rect()
	_check(panel.get_global_rect().end.x <= viewport_rect.end.x + 1, caption + " fits width")
	_check(panel.get_global_rect().end.y <= viewport_rect.end.y + 1, caption + " fits height")
	for button in panel.find_children("*", "Button", true, false):
		if not button.is_visible_in_tree():
			continue
		var clipped := false
		var parent := button.get_parent()
		while parent != panel and parent != null:
			if parent is ScrollContainer:
				clipped = true
			parent = parent.get_parent()
		if not clipped:
			_check(button.get_global_rect().end.x <= viewport_rect.end.x + 1 and button.get_global_rect().end.y <= viewport_rect.end.y + 1, caption + " button fits: " + button.name)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://screenshots/expedition_redesign/%s.png" % caption)
	shots += 1

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://screenshots/expedition_redesign")
	game = FarmGame.new()
	game.set_debug_random_seed(20261003)
	game.new_game(1000)
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	hub = ExpeditionHubPanel.new()
	root.add_child(hub)
	hub.open(game)
	_check(hub.depart_button.disabled, "empty first-round deck blocks departure")
	await _shot("01_camp_first_visit", hub)
	inventory.grant_basic_kit()
	for item in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(item["instance_id"]), "chest")
	hub.open(game)
	_check(not hub.depart_button.disabled, "equipped deck permits departure")
	await _shot("02_camp_ready", hub)
	hub.close()

	screen = BattleScreen.new()
	root.add_child(screen)
	var deck: Array = []
	for id in ["slash", "shield_up", "heavy_strike", "brace", "observe", "rescue_signal", "cover", "slash", "brace", "observe"]:
		deck.append({"card_id": id, "source_instance_id": 0, "join_round": 1})
	var combat := CombatGame.create([{"key": "p1", "name": "农夫", "max_hp": 40, "deck": deck}], "normal", 20261003, null, deck)
	combat.start()
	screen.open_run(combat)
	await _shot("03_battle", screen)
	var card: Dictionary = combat.state["players"]["p1"]["hand"][0]
	var card_button: Button = screen.hand_row.get_child(0)
	await _click(card_button)
	_check(screen.selected_uid == int(card["uid"]), "real GUI selects card")
	_check(screen._legal_target(int(card["uid"]), "e1"), "attack accepts living enemy")
	_check(not screen._legal_target(int(card["uid"]), "p1"), "attack rejects own player")
	combat.state["enemies"][0]["block"] = 4
	_check(screen._target_preview(int(card["uid"]), "e1").contains("生命 −2"), "preview accounts for enemy block")
	screen._refresh()
	await _shot("04_target_preview", screen)
	var hp_before := int(combat.state["enemies"][0]["hp"])
	await _click(screen.target_controls["e1"])
	_check(int(combat.state["enemies"][0]["hp"]) == hp_before - 2, "real target click applies previewed damage")
	await _key(KEY_1)
	_check(screen.selected_uid >= 0, "number shortcut selects current hand")
	var energy := int(combat.state["players"]["p1"]["energy"])
	await _click(screen.target_controls["p1"])
	_check(int(combat.state["players"]["p1"]["block"]) == 6, "self-target defense works")
	_check(int(combat.state["players"]["p1"]["energy"]) == energy - 1, "defense consumes energy once")
	_check((screen.hand_row.get_child(0) as Button).disabled, "unaffordable card visibly disabled")
	await _key(KEY_2)
	_check(screen.selected_uid >= 0, "zero-cost card selectable")
	await _key(KEY_ESCAPE)
	_check(screen.selected_uid < 0, "escape cancels card without leaving battle")
	screen._open_pile("draw_pile", "抽牌堆")
	await _shot("05_pile_inspector", screen)
	await _key(KEY_E)
	_check(int(combat.state["round"]) == 1, "pile modal blocks end-turn shortcut")
	await _key(KEY_ESCAPE)
	_check(not screen.inspector_panel.visible, "escape closes pile inspector")
	await _key(KEY_E)
	_check(int(combat.state["round"]) == 2, "E advances round")
	await _shot("06_next_round", screen)

	# 拖放由真实输入驱动，释放到自己时调用与点击相同的裁定入口。
	var self_index := -1
	var player: Dictionary = combat.state["players"]["p1"]
	for i in range(player["hand"].size()):
		if CardDefs.get_card(str(player["hand"][i]["card_id"]))["target"] == "self":
			self_index = i
			break
	if self_index >= 0:
		var before := int(player["hand"].size())
		var source: Button = screen.hand_row.get_child(self_index)
		var start := source.get_global_rect().get_center()
		var press := InputEventMouseButton.new()
		press.position = start
		press.global_position = start
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		root.push_input(press, true)
		var move := InputEventMouseMotion.new()
		move.position = start + Vector2(0, -35)
		move.global_position = move.position
		move.relative = Vector2(0, -35)
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(move, true)
		await _settle()
		_check(root.gui_is_dragging(), "real mouse motion starts card drag")
		move = move.duplicate()
		move.position = screen.target_controls["p1"].get_global_rect().get_center()
		move.global_position = move.position
		root.push_input(move, true)
		await _settle()
		press = press.duplicate()
		press.position = move.position
		press.global_position = move.position
		press.pressed = false
		root.push_input(press, true)
		await _settle()
		_check(int(player["hand"].size()) < before, "real drag release plays card")
	else:
		_check(false, "self card available for drag test")

	# 发送中的客机意图不可重复提交；镜像不被界面改写。
	var sends := [0]
	screen.action_sink = func(_kind: String, _args: Dictionary) -> Variant:
		sends[0] += 1
		return null
	screen.combat_refresher = func() -> CombatGame: return combat
	screen._on_end_turn()
	screen._on_end_turn()
	_check(sends[0] == 1 and screen.pending_action, "async action locks duplicate submission")
	screen.pending_action = false
	screen.action_sink = Callable()
	screen.combat_refresher = Callable()
	for enemy in combat.state["enemies"]:
		enemy["hp"] = 0
		enemy["alive"] = false
	combat._events_check_outcome([])
	screen._refresh()
	await _shot("07_victory", screen)
	screen.visible = false

	var expedition := MemoryExpedition.new()
	expedition.game = game
	expedition.rng.seed = 20261003
	expedition.run = {
		"run_id": "ui-preview", "layer_id": "moss_stone_shallow", "rng_seed": 20261003,
		"player": {"hp": 28, "max_hp": 40, "extra_draw_next": false},
		"inventory": ExpeditionGame._snapshot_loadout(game), "next_instance_id": 2000,
		"map": ExpeditionGame._build_map("moss_stone_shallow"), "current": {"row": 0, "col": 0},
		"resolved": {}, "node_drops": [], "battle": {}, "phase": "map", "outcome": "",
		"carried_from_farm": ExpeditionGame._carried_ids(game), "consumed": [], "log": ["出发：向苔石浅洞前进。"]
	}
	map_panel = ExpeditionMapPanel.new()
	root.add_child(map_panel)
	map_panel.open(expedition)
	await _shot("08_route", map_panel)
	var route_button: Button = map_panel.route_view.buttons[1]
	await _click(route_button)
	_check(int(expedition.run["current"]["row"]) == 0, "route preview does not move")
	_check(map_panel.selected_route == Vector2i(1, 0), "real route click selects next node")
	await _shot("09_route_preview", map_panel)
	for button in map_panel.node_column.find_children("*", "Button", true, false):
		if button.text.contains("向这里前进"):
			await _click(button)
			break
	_check(int(expedition.run["current"]["row"]) == 1, "confirm route moves through domain")
	await _shot("10_encounter", map_panel)
	expedition.run["current"] = {"row": 2, "col": 0}
	expedition.run["phase"] = "node"
	expedition.run["resolved"]["r2c0"] = {"rewards": ["copper_scrap", "bandage"], "claimed": {}, "public": []}
	map_panel._refresh()
	await _shot("11_rewards", map_panel)
	map_panel._on_claim_reward("r2c0", "copper_scrap", "pack", false)
	map_panel._on_claim_reward("r2c0", "bandage", "pack", false)
	map_panel._on_leave_node()
	_check(not map_panel.overlay_panel.visible, "fully claimed rewards do not trigger false abandon confirmation")
	expedition.run["current"] = {"row": 7, "col": 0}
	expedition.run["phase"] = "node"
	expedition.run["resolved"]["r7c0"] = {}
	map_panel._refresh()
	var exit_found := false
	for button in map_panel.node_column.find_children("*", "Button", true, false):
		if button.text.contains("在此撤离"):
			exit_found = true
	_check(exit_found, "exit node provides extraction action")
	await _shot("12_exit", map_panel)
	map_panel._open_extract_confirm()
	await _shot("13_extraction", map_panel)
	_check(map_panel.overlay_scroll.size.y > 150 and map_panel.overlay_column.size.y > 150, "extraction modal content has visible height")
	map_panel._close_overlay()
	map_panel._show_settlement({"kind": "extract", "settlement_id": "preview", "gained": [{"name": "铜片"}], "protected": [{"name": "辉晶"}]})
	await _key(KEY_ESCAPE)
	_check(map_panel.overlay_panel.visible, "settlement cannot be dismissed before acknowledgement")
	await _shot("14_settlement", map_panel)
	map_panel._close_overlay()
	map_panel.close()
	# Ten-card hand and three enemies at smaller window size.
	var all_cards: Array = []
	for i in range(10):
		all_cards.append({"card_id": "slash", "source_instance_id": 0, "join_round": 1})
	var large := CombatGame.create([{"key": "p1", "name": "农夫", "max_hp": 40, "deck": all_cards}], "gate_keeper", 5)
	large.start()
	large.draw_extra(5)
	screen.open_run(large)
	root.size = Vector2i(1024, 640)
	await _shot("15_small_window_ten_cards", screen)
	var hand_scroll: ScrollContainer = screen.find_child("HandScroll", true, false)
	_check(screen.hand_row.size.x > hand_scroll.size.x, "ten-card hand can scroll")
	screen.queue_free()
	hub.queue_free()
	map_panel.queue_free()
	await _settle()
	print("EXPEDITION_UI_", "FAIL" if failed else "PASS", " / ", shots, " screens")
	quit(1 if failed else 0)
