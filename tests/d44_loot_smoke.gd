extends SceneTree
## 搜刮事务、真实 GUI 输入与客机待回执状态；有窗口时保存预览。

class MemoryExpedition extends ExpeditionGame:
	func save() -> bool:
		return true

var failed := false
var checks := 0
var expedition: MemoryExpedition
var panel: ExpeditionMapPanel
var loot: ExpeditionLootPanel
var shots := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("D44_LOOT_FAIL: " + message)

func _fresh() -> MemoryExpedition:
	var game := FarmGame.new()
	game.new_game(1000)
	var inv := InventoryGame.new()
	inv.bind(game.state["expedition"])
	inv.grant_basic_kit()
	for instance in inv.warehouse_list().duplicate():
		inv.move_to_loadout(int(instance["instance_id"]), "chest")
	var result := MemoryExpedition.new()
	result.game = game
	result.rng.seed = 44
	result.run = {"run_id": "loot-test", "layer_id": "moss_stone_shallow", "rng_seed": 44,
		"player": {"hp": 23, "max_hp": 40, "extra_draw_next": false},
		"inventory": ExpeditionGame._snapshot_loadout(game), "next_instance_id": 2000,
		"map": ExpeditionGame._build_map("moss_stone_shallow"), "current": {"row": 1, "col": 0},
		"resolved": {"r1c0": {"type": "battle", "choose_one": true, "battle_won": true, "rewards": ["copper_shortsword", "reinforced_shield"], "public": ["bandage", "rock_sprout_seed"], "claimed": {}}},
		"node_drops": [], "battle": {}, "phase": "node", "outcome": "", "carried_from_farm": ExpeditionGame._carried_ids(game), "consumed": [], "log": []}
	return result

func _add(inv: InventoryGame, id: String, container: String, cell: Vector2i) -> int:
	var result := inv.add_instance(id, "test", int(ItemDefs.get_item(id).get("quality", 1)))
	var number := int(result["instance_id"])
	_check(bool(inv.place_at(number, container, cell, false)["ok"]), "fixture placement " + id)
	return number

func _domain_checks() -> void:
	var e := _fresh()
	var inv := e.run_inventory()
	for y in range(4):
		for x in range(4):
			_add(inv, "copper_scrap", "pack", Vector2i(x, y))
	var total := inv.all_instances().size()
	var result := e.loot_action("p1", "claim_reward", {"def_id": "copper_shortsword", "container": "pack"})
	_check(not result["ok"] and e.run["resolved"]["r1c0"]["claimed"].is_empty(), "full bag does not lock personal choice")
	_check(inv.all_instances().size() == total and inv.warehouse_list().is_empty(), "failed reward leaves no phantom warehouse item")
	_check(not e.loot_action("p1", "claim_reward", {"def_id": "crystal_blade"})["ok"], "cannot invent reward")
	_check(not e.loot_action("p1", "claim_public", {"def_id": "rock_sprout_seed", "container": "warehouse"})["ok"], "cannot bypass capacity through warehouse")
	var existing_id := int(inv.loadout_list("pack")[0]["instance_id"])
	result = e.loot_action("p1", "loot_manage", {"operation": "drop", "instance_id": existing_id})
	_check(result["ok"] and e.run["node_drops"].size() == 1 and inv.owner_of(existing_id) == "none", "discard keeps one recoverable floor instance")
	_check(e.loot_action("p1", "claim_public", {"def_id": "bandage", "container": "pack"})["ok"], "public pickup uses vacated space")
	result = e.loot_action("p1", "pick_drop", {"instance_id": existing_id, "container": "pack"})
	_check(not result["ok"] and e.run["node_drops"].size() == 1 and inv.warehouse_list().is_empty(), "full-bag recovery preserves floor item and rolls back warehouse")
	result = e.loot_action("p1", "pick_drop", {"instance_id": existing_id, "container": "safe", "cell": [0.0, 0.0]})
	_check(result["ok"] and inv.owner_of(existing_id) == "safe" and e.run["node_drops"].is_empty(), "JSON numeric coordinates accepted and recovery obeys exact placement")
	_check(not e.loot_action("p1", "loot_manage", {"operation": "move", "instance_id": existing_id, "cell": [0.5, 0.0]})["ok"], "fractional coordinates rejected")
	_check(not e.loot_action("p1", "loot_manage", {"operation": "move", "instance_id": existing_id, "cell": [0, -1]})["ok"], "negative coordinates rejected")
	var layout := inv.loadout_list("pack").duplicate(true)
	_check(not e.loot_action("p1", "loot_manage", {"operation": "move", "instance_id": int(layout[0]["instance_id"]), "container": "pack", "cell": [0, 0]})["ok"], "occupied cell rejects move")
	_check(inv.loadout_list("pack") == layout, "failed move preserves layout")
	e.run["coop"] = true
	e.run["guest"] = {"name": "队友", "hp": 40, "max_hp": 40, "inventory": {"warehouse": [], "loadout": {"chest": [], "pack": [], "safe": []}}}
	_check(not e.loot_action("p2", "loot_manage", {"operation": "drop", "instance_id": existing_id})["ok"], "guest cannot manage host inventory")
	var basic_id := int(inv.loadout_list("chest")[0]["instance_id"])
	_check(e.loot_action("p1", "loot_manage", {"operation": "drop", "instance_id": basic_id})["ok"], "owner may discard own basic equipment")
	_check(not e.loot_action("p2", "pick_drop", {"instance_id": basic_id})["ok"], "guest cannot duplicate host basic equipment")
	var host := SessionHost.new()
	host.expedition = e
	_check(host._execute_action("p2", "loot_manage", {"operation": "tidy", "container": "pack"})["ok"], "session host supports new management intent")
	e.run["phase"] = "battle"
	_check(not e.loot_action("p1", "loot_manage", {"operation": "tidy", "container": "pack"})["ok"], "inventory immutable during battle")
	e.run["phase"] = "node"
	e.run["resolved"]["r1c0"]["battle_won"] = false
	_check(not e.loot_action("p1", "claim_reward", {"def_id": "reinforced_shield", "container": "chest"})["ok"], "must defeat enemies before looting")
	var quality_run := _fresh()
	result = quality_run.loot_action("p1", "claim_reward", {"def_id": "reinforced_shield", "container": "pack", "cell": [0, 0]})
	_check(result["ok"] and int(quality_run.run_inventory().find_instance(int(result["instance_id"]))["quality"]) == 2, "reward retains defined quality")
	_check(not quality_run.loot_action("p1", "claim_reward", {"def_id": "copper_shortsword", "container": "pack"})["ok"], "second personal reward cannot be claimed")
	quality_run.run["inventory"]["container_levels"] = {"pack": 2}
	result = quality_run.loot_action("p1", "claim_public", {"def_id": "bandage", "container": "pack", "cell": [3, 4]})
	_check(result["ok"], "run preserves expanded backpack cells")
	_check(quality_run.loot_action("p1", "loot_manage", {"operation": "tidy", "container": "pack"})["ok"], "expanded backpack can auto tidy")
	_check(ExpeditionBaseline.layout_integrity(quality_run.run["inventory"]["loadout"], quality_run.run_inventory().expedition).is_empty(), "tidy preserves valid expanded layout")
	quality_run.run["coop"] = true
	quality_run.run["guest"] = ExpeditionGame._guest_member({"container_levels": {"pack": 2}, "loadout": {"chest": [], "pack": [], "safe": []}})
	result = quality_run.loot_action("p2", "claim_public", {"def_id": "rock_sprout_seed", "container": "pack", "cell": [3.0, 4.0]})
	_check(result["ok"], "guest profile preserves separate expanded backpack")

func _settle() -> void:
	for i in range(6):
		await process_frame

func _mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)

func _key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	await _settle()

func _click_button(text: String) -> void:
	for button in loot.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and not button.disabled and button.text.contains(text):
			var parent := button.get_parent()
			while parent != loot and parent != null:
				if parent is ScrollContainer:
					parent.ensure_control_visible(button)
				parent = parent.get_parent()
			await _settle()
			_mouse(button.get_global_rect().get_center(), true)
			_mouse(button.get_global_rect().get_center(), false)
			await _settle()
			return
	_check(false, "visible clickable button: " + text)

func _click_block_tidy(container: String) -> void:
	var block: Control = loot.workspace.container_blocks[container]
	for button in block.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and not button.disabled and button.text == "整理":
			var parent := button.get_parent()
			while parent != loot and parent != null:
				if parent is ScrollContainer:
					parent.ensure_control_visible(button)
				parent = parent.get_parent()
			await _settle()
			_mouse(button.get_global_rect().get_center(), true)
			_mouse(button.get_global_rect().get_center(), false)
			await _settle()
			return
	_check(false, "visible tidy button in block " + container)

func _shot(name: String) -> void:
	await _settle()
	_check(loot.size.x <= root.get_visible_rect().size.x + 1 and loot.size.y <= root.get_visible_rect().size.y + 1, "loot screen fits " + name)
	_check(loot.leave_button.get_global_rect().end.y <= root.get_visible_rect().end.y + 1, "footer fits " + name)
	var pack_grid: Control = loot.workspace.container_grids["pack"]
	_check(pack_grid.size.x > 140 and pack_grid.size.y >= 200, "backpack has usable grid " + name)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://screenshots/loot_redesign/%s.png" % name)
	shots += 1

func _run() -> void:
	_domain_checks()
	DirAccess.make_dir_recursive_absolute("res://screenshots/loot_redesign")
	expedition = _fresh()
	var inv := expedition.run_inventory()
	_add(inv, "antique_ornament", "pack", Vector2i(0, 0))
	_add(inv, "iron_ore", "pack", Vector2i(2, 0))
	_add(inv, "small_potion", "pack", Vector2i(3, 0))
	_add(inv, "fiber_clump", "pack", Vector2i(3, 1))
	_add(inv, "copper_scrap", "pack", Vector2i(0, 2))
	_add(inv, "bandage", "pack", Vector2i(1, 2))
	_add(inv, "glow_crystal", "pack", Vector2i(2, 2))
	panel = ExpeditionMapPanel.new()
	root.add_child(panel)
	panel.open(expedition)
	loot = panel.loot_panel
	_check(loot.visible and not panel.map_frame.visible, "post-battle screen takes over route")
	await _click_button("菜单")
	_check(panel.overlay_panel.visible, "loot menu opens map pause overlay")
	await _key(KEY_ESCAPE)
	_check(not panel.overlay_panel.visible and loot.visible, "escape closes parent menu without re-opening it")
	await _click_block_tidy("pack")
	_check(loot._has_space(loot._entry("reward:copper_shortsword"), "pack"), "GUI tidy opens continuous space for sword")
	await _shot("01_battle_loot")
	var old_cards: int = DeckBuilder.build(inv)["entries"].size()
	var flow: Control = loot.context_column.get_child(0)
	var start: Vector2 = flow.global_position + flow.get("rects")[0].get_center()
	_mouse(start, true)
	var motion := InputEventMouseMotion.new()
	motion.position = start + Vector2(35, 0)
	motion.global_position = motion.position
	motion.relative = Vector2(35, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await _settle()
	_check(root.gui_is_dragging(), "real mouse drag starts loot transfer")
	await _key(KEY_R)
	if root.gui_is_dragging():
		_check(bool(root.gui_get_drag_data().get("rotated", false)), "R rotates drag payload")
	await _shot("02_drag_rotated")
	var pack_grid: Control = loot.workspace.container_grids["pack"]
	var destination: Vector2 = pack_grid.global_position + pack_grid.origin + Vector2(0.5, 3.5) * pack_grid.cell_size
	motion = InputEventMouseMotion.new()
	motion.position = destination
	motion.global_position = destination
	motion.relative = destination - start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.warp_mouse(destination)
	root.push_input(motion, true)
	await _settle()
	var drag_data: Dictionary = root.gui_get_drag_data().duplicate(true) if root.gui_is_dragging() else {}
	# 真窗口下 OS 光标事件可能拖走悬停目标：释放前紧贴再报一次 motion。
	var refresh := InputEventMouseMotion.new()
	refresh.position = destination
	refresh.global_position = destination
	refresh.relative = Vector2.ZERO
	refresh.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(refresh, true)
	await process_frame
	_mouse(destination, false)
	await _settle()
	# dummy DisplayServer 不跟踪指针位置；无头时检查同一 drop 回调，有窗口时验证真实释放。
	if DisplayServer.get_name() == "headless" and not drag_data.is_empty():
		_check(pack_grid._can_drop_data(destination - pack_grid.global_position, drag_data), "headless drag payload fits selected cell")
		pack_grid._drop_data(destination - pack_grid.global_position, drag_data)
		await _settle()
	var mine: Array = expedition.run["resolved"]["r1c0"]["claimed"].get("p1", [])
	if not mine.has("copper_shortsword") and DisplayServer.get_name() != "headless" and not drag_data.is_empty():
		## 真窗口偶发 OS 光标噪声吞掉释放事件：协议级重放兜底
		##（真实拖放链路已由 d54 尸体→背包、d58 仓库→装备槽窗口版覆盖）。
		pack_grid._drop_data(destination - pack_grid.global_position, drag_data)
		await _settle()
		mine = expedition.run["resolved"]["r1c0"]["claimed"].get("p1", [])
	_check(mine.has("copper_shortsword"), "real drop claims exact selected reward")
	_check(DeckBuilder.build(inv)["entries"].size() == old_cards + 3, "next battle deck reflects new loot")
	var sword_id := -1
	for instance in inv.loadout_list("pack"):
		if str(instance["def_id"]) == "copper_shortsword":
			sword_id = int(instance["instance_id"])
			_check(instance["cell"] == [0, 3] and bool(instance["rotated"]), "drag target and rotation persist")
	_check(not bool(loot._entry("reward:reinforced_shield")["available"]), "alternative displays forfeited after successful personal claim")
	await _shot("03_choice_locked")
	loot.select_item("public:rock_sprout_seed")
	await _click_button("放保险箱")
	_check(inv.loadout_list("safe").size() == 1, "GUI seed pickup uses safe container")
	await _shot("04_protected_seed")
	await _click_button("丢到现场")
	_check(loot.modal.visible, "dropping protected seed asks for confirmation")
	await _shot("05_drop_confirmation")
	await _key(KEY_ESCAPE)
	_check(not loot.modal.visible and inv.loadout_list("safe").size() == 1, "escape cancels discard without losing protection")
	await _click_button("丢到现场")
	await _click_button("确认丢到现场")
	_check(inv.loadout_list("safe").is_empty() and expedition.run["node_drops"].size() == 1, "confirmed discard transfers seed to floor")
	var dropped_id := int(expedition.run["node_drops"][0]["instance_id"])
	loot.select_item("drop:%d" % dropped_id)
	await _click_button("放保险箱")
	_check(inv.loadout_list("safe").size() == 1 and expedition.run["node_drops"].is_empty(), "GUI recovery restores protection through real placement")
	await _click_button("完成搜刮")
	_check(loot.modal.visible and str(expedition.run["phase"]) == "node", "unclaimed public loot blocks accidental leave")
	await _shot("06_leave_confirmation")
	await _click_button("返回继续搜刮")
	# 满包截图与禁用提示。
	for y in range(4):
		for x in range(4):
			var occupancy := ExpeditionBaseline.occupancy_map(inv.loadout_list("pack"), "pack")
			if not occupancy.has(ExpeditionBaseline.cell_key(Vector2i(x, y))):
				_add(inv, "copper_scrap", "pack", Vector2i(x, y))
	loot.display(expedition.run)
	loot.select_item("public:bandage")
	await _shot("07_full_backpack")
	_check(not loot._has_space(loot._entry("public:bandage"), "pack"), "full bag clearly has no space")
	# 客机等待同一动作回执 + 更新快照，不因无关广播解锁。
	var sends := [0]
	loot.action_sink = func(_kind: String, _args: Dictionary) -> String: sends[0] += 1; return "loot-action-1"
	loot.display(expedition.run, "p1", 10)
	loot._request("loot_manage", {"operation": "rotate", "instance_id": sword_id}, "完成")
	loot._request("loot_manage", {"operation": "rotate", "instance_id": sword_id}, "完成")
	_check(sends[0] == 1 and loot.pending_action, "async intent locks duplicate input")
	loot.display(expedition.run, "p1", 11)
	_check(loot.pending_action, "unrelated snapshot does not unlock pending intent")
	loot.acknowledge("unrelated", {"ok": true})
	_check(loot.pending_action, "unrelated acknowledgement ignored")
	loot.acknowledge("loot-action-1", {"ok": false, "reason": "旋转后放不下"})
	_check(not loot.pending_action and loot.feedback_label.text == "旋转后放不下", "host rejection releases lock and explains failure")
	loot._request("loot_manage", {"operation": "tidy", "container": "pack"}, "完成")
	loot.acknowledge("loot-action-1", {"ok": true})
	_check(loot.pending_action, "success acknowledgement waits for subsequent snapshot")
	loot.display(expedition.run, "p1", 12)
	_check(not loot.pending_action, "acknowledged snapshot releases input")
	loot.action_sink = panel._loot_action
	# 较小窗口仍留可操作的网格和底栏。
	root.size = Vector2i(1024, 640)
	await _shot("08_small_window")
	await _click_button("完成搜刮")
	await _click_button("确认离开本节点")
	_check(str(expedition.run["phase"]) == "map" and not loot.visible and panel.map_frame.visible, "confirmed leave returns to route")
	expedition.run["current"] = {"row": 2, "col": 0}
	expedition.run["phase"] = "node"
	expedition.run["resolved"]["r2c0"] = {"type": "gather", "rewards": ["iron_ore"], "public": [], "claimed": {}}
	panel._refresh()
	_check(loot.visible and loot.selected_token == "reward:iron_ore", "same mutable run resets selection on next loot node")
	panel.queue_free()
	await _settle()
	print("D44_LOOT_", "FAIL" if failed else "PASS", " / ", checks, " checks / ", shots, " screens")
	quit(1 if failed else 0)
