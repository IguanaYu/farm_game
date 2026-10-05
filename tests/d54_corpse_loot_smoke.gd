extends SceneTree
## 尸体搜索、权威计时、隐藏投影、实例转移与实际 UI；窗口运行同时生成截图。

class MemoryExpedition extends ExpeditionGame:
	func save() -> bool:
		return true

class CaptureTransport extends SessionTransport:
	var messages: Array = []
	func send(_peer: int, message: Dictionary) -> void:
		messages.append(message.duplicate(true))

class CaptureAuth extends AuthService:
	func peer_of_account(_account: int) -> int:
		return 123

var failed := false
var checks := 0
var clock_ms := 1000
var panel: ExpeditionLootPanel

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("D54_CORPSE_FAIL: " + message)

func _fresh(coop := false, skeleton := true, pair := false, gate := false) -> MemoryExpedition:
	var farm := FarmGame.new()
	farm.new_game(1000)
	var inventory := InventoryGame.new()
	inventory.bind(farm.state["expedition"])
	inventory.grant_basic_kit()
	for item in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(item["instance_id"]), "chest")
	var game := MemoryExpedition.new()
	game.game = farm
	game.run = ExpeditionGame.compose_run(farm, {}, "corpse-test", 1000, false, "test")
	game.rng.seed = 54
	game.search_clock = func() -> int: return clock_ms
	if coop:
		game.run["coop"] = true
		game.run["guest"] = {"name": "队友", "hp": 40, "max_hp": 40, "inventory": ExpeditionGame._snapshot_loadout(farm)}
	game.run["current"] = {"row": 8 if gate else (3 if skeleton else 1), "col": 0 if gate else (1 if skeleton or pair else 0)}
	game.run["phase"] = "node"
	game._resolve_node(game.current_node())
	var battle: Dictionary = game.start_battle()
	_check(bool(battle["ok"]), "battle starts")
	var combat: CombatGame = battle["combat"]
	if skeleton:
		_check(combat.state["enemies"][0]["def_id"] == "skeleton_scout" and combat.state["enemies"][0]["equipment"]["weapon"] == "copper_shortsword", "actual enemy loadout matches corpse")
	for enemy in combat.state["enemies"]:
		enemy["alive"] = false
		enemy["hp"] = 0
	combat._events_check_outcome([])
	_check(bool(game.finish_battle(combat)["ok"]), "victory enters corpse stage")
	_check(not game.finish_battle(combat)["ok"], "duplicate finish cannot duplicate corpse")
	return game

func _source_item(game: ExpeditionGame, def_id: String) -> Dictionary:
	for source in _resolved(game)["corpses"]:
		for region in source["regions"]:
			for item in region["items"]:
				if str(item["def_id"]) == def_id:
					return {"source": source["id"], "region": region["id"], "item": item}
	return {}

func _resolved(game: ExpeditionGame) -> Dictionary:
	return game.run["resolved"][game.node_id(int(game.run["current"]["row"]), int(game.run["current"]["col"]))]

func _search_all(game: ExpeditionGame, source: String, region: String, member := "p1") -> void:
	_check(game.loot_action(member, "search_start", {"source": source, "region": region})["ok"], "start " + region)
	for i in range(30):
		if game.run.get("loot_searches", {}).get(member, {}).is_empty():
			return
		clock_ms += int(game.run["loot_searches"][member]["duration"]) + 1
		_check(game.loot_action(member, "search_step", {})["ok"], "step " + region)
	_check(false, "search must finish")

func _domain() -> void:
	var game := _fresh(true)
	var resolved := _resolved(game)
	_check(resolved["rewards"].is_empty() and not bool(resolved["choose_one"]), "new corpses replace choose one")
	_check(resolved["corpses"][0]["regions"].size() == 4, "equipment and two bags")
	var weapon: Dictionary = resolved["corpses"][0]["regions"][0]["items"][0]
	var id := int(weapon["instance_id"])
	_check(not game.loot_action("p1", "claim_corpse", {"instance_id": id})["ok"], "cannot take unknown")
	var view := game.visible_run()
	var public_region: Dictionary = view["resolved"]["r3c1"]["corpses"][0]["regions"][0]
	_check(public_region["items"].is_empty() and not view.has("rng_seed"), "projection does not disclose hidden item or generator")
	_check(game.loot_action("p1", "search_start", {"source": "e1", "region": "weapon"})["ok"], "start owner")
	_check(not game.loot_action("p1", "search_step", {"now": 999999999})["ok"], "client cannot fast forward clock")
	_check(not game.loot_action("p2", "search_start", {"source": "e1", "region": "weapon"})["ok"], "same region locked")
	_check(game.loot_action("p2", "search_start", {"source": "e1", "region": "pouch"})["ok"], "different regions parallel")
	_check(not game.leave_node()["ok"], "cannot leave while teammate searches")
	clock_ms += ItemDefs.search_ms(ItemDefs.quality_of(weapon)) + 1
	_check(game.loot_action("p1", "search_step", {})["ok"], "reveal weapon")
	_check(bool(weapon["revealed"]) and resolved["corpses"][0]["regions"][0]["searched"].size() == 3, "multi cell weapon revealed together")
	_check(game.visible_run()["resolved"]["r3c1"]["corpses"][0]["regions"][0]["items"].size() == 1, "revealed item shared")
	var inv := game.member_inventory("p1")
	for y in range(4):
		for x in range(4):
			inv.claim_reward("bandage", "pack", Vector2i(x, y))
	_check(not game.loot_action("p1", "claim_corpse", {"instance_id": id})["ok"] and not weapon["taken"], "full bag retains original corpse instance")
	_check(inv.warehouse_list().is_empty(), "failed placement leaves no orphan")
	for item in inv.loadout_list("pack").duplicate():
		inv.discard_instance(int(item["instance_id"]))
	weapon["quality"] = 3
	weapon["uses_remaining"] = 2
	_check(game.loot_action("p1", "claim_corpse", {"instance_id": id})["ok"], "take after space freed")
	_check(int(inv.find_instance(id)["quality"]) == 3 and int(inv.find_instance(id)["uses_remaining"]) == 2, "original id and attributes preserved")
	_check(not game.loot_action("p2", "claim_corpse", {"instance_id": id})["ok"], "no duplicate across players")
	_check(not game.loot_action("p1", "claim_corpse", {"instance_id": 1})["ok"], "cannot invent corpse item")
	_check(game.loot_action("p2", "search_cancel", {})["ok"], "cancel search")
	_check(not bool(resolved["corpses"][0]["regions"][2]["items"][0]["revealed"]), "cancelled item stays unknown even after elapsed time")
	_check(not game.loot_action("p2", "search_step", {})["ok"], "cancel invalidates step")
	_search_all(game, "e1", "pack")
	var pack: Dictionary = resolved["corpses"][0]["regions"][3]
	_check(pack["items"].size() == 2 and pack["items"][0]["instance_id"] != pack["items"][1]["instance_id"], "bag items independently identified")
	# JSON 重建保留已发现/已领取状态；运行期 epoch 不在成员投影中。
	var restored := MemoryExpedition.new()
	restored.run = JSON.parse_string(JSON.stringify(game.run))
	restored.search_clock = func() -> int: return clock_ms
	_check(bool(_resolved(restored)["corpses"][0]["regions"][0]["items"][0]["taken"]), "json restore preserves taken item")
	var ordinary := _fresh(false, false)
	_check(_resolved(ordinary)["corpses"].size() == 1, "normal monster creates body source")
	var body: Dictionary = _resolved(ordinary)["corpses"][0]["regions"][0]
	_search_all(ordinary, "e1", "body")
	_check(body["searched"].size() == 6, "empty cells scanned and search completed")
	var pair := _fresh(false, false, true)
	_check(_resolved(pair)["corpses"].size() == 2, "multiple enemies leave individual corpses")
	_search_all(pair, "e1", "body")
	_check(_resolved(pair)["corpses"][1]["regions"][0]["searched"].is_empty(), "other corpse progress independent")
	_search_all(pair, "e2", "body")
	# 正式守门战的加固盾：搜索与揭晓始终对应完整 2×2 占格。
	var shield_game := _fresh(false, false, false, true)
	var shield_source := _source_item(shield_game, "reinforced_shield")
	_check(not shield_source.is_empty(), "real gate encounter contains a 2x2 shield")
	var shield_region := CorpseLootGame.region_of(_resolved(shield_game), shield_source["source"], shield_source["region"])
	var visible_shield := CorpseLootGame.region_of(shield_game.visible_run()["resolved"]["r8c0"], shield_source["source"], shield_source["region"])
	_check(visible_shield["items"].is_empty() and visible_shield["unknown"][0]["size"] == [2, 2], "unknown shield shows merged 2x2 outline before identity")
	_check(visible_shield["unknown"][0].size() == 2 and visible_shield["unknown"][0].has("cell") and visible_shield["unknown"][0].has("size"), "unknown outline exposes geometry only")
	_check(not shield_region.has("unknown"), "visible outline does not mutate authoritative contents")
	_check(shield_game.loot_action("p1", "search_start", shield_source)["ok"], "start whole shield search")
	_check(shield_game.visible_run()["loot_searches"]["p1"]["footprint"]["size"] == [2, 2], "active search broadcasts whole 2x2 footprint")
	_check(not shield_game.loot_action("p1", "claim_corpse", {"instance_id": shield_source["item"]["instance_id"]})["ok"], "outline cannot be claimed before reveal")
	clock_ms += ItemDefs.search_ms(ItemDefs.quality_of(shield_source["item"])) + 1
	_check(shield_game.loot_action("p1", "search_step", {})["ok"], "one timer reveals the shield")
	visible_shield = CorpseLootGame.region_of(shield_game.visible_run()["resolved"]["r8c0"], shield_source["source"], shield_source["region"])
	_check(shield_region["searched"].size() == 4 and visible_shield["unknown"].is_empty() and visible_shield["items"].size() == 1, "four shield cells become one revealed item together")
	# 旋转后的长条物品也按实际朝向公开几何。
	var rotated_game := _fresh()
	var rotated_region: Dictionary = _resolved(rotated_game)["corpses"][0]["regions"][0]
	rotated_region["size"] = [3, 1]
	rotated_region["items"][0]["rotated"] = true
	rotated_game.loot_action("p1", "search_start", {"source": "e1", "region": "weapon"})
	_check(rotated_game.visible_run()["loot_searches"]["p1"]["footprint"]["size"] == [3, 1], "rotated source searches its actual 3x1 footprint")
	# 真实局档恢复清除未完成搜索，保留固定掉落与已揭晓/已取走标记。
	game.loot_action("p1", "search_start", {"source": "e1", "region": "armor"})
	var recovery_id := "d54-corpse-recovery-%d" % Time.get_ticks_usec()
	var saved := game.run.duplicate(true)
	saved["run_id"] = recovery_id
	game.game.state["expedition"]["active_run_ref"] = recovery_id
	_check(ExpeditionStore.save_run(recovery_id, saved), "save isolated recovery fixture")
	var resumed: Dictionary = ExpeditionGame.resume(game.game)
	_check(resumed["ok"] and resumed["run"].get("loot_searches", {}).is_empty(), "resume interrupts unfinished search")
	_check(_resolved(resumed["game"])["corpses"] == JSON.parse_string(JSON.stringify(_resolved(game)["corpses"])), "resume does not reroll or duplicate loot")
	DirAccess.remove_absolute(ExpeditionStore.run_path(recovery_id))
	# 本地主机广播与线上裁定入口共用同一权威规则。
	var host := SessionHost.new()
	var wire := CaptureTransport.new()
	host.transport = wire
	host.room = {"members": {1: {}, 2: {"online": true}}}
	host.expedition = _fresh(true)
	host._push_snapshot()
	_check(wire.messages[0]["run"]["resolved"]["r3c1"]["corpses"][0]["regions"][0]["items"].is_empty(), "host broadcast filters secret loot")
	var online := RoomService.new()
	_check(online._dispatch_action(host.expedition, "p1", "search_start", {"source": "e1", "region": "armor"})["ok"], "online action supports search")
	online.auth = CaptureAuth.new()
	var packets: Array = []
	online.send = func(_peer: int, packet: Dictionary) -> void: packets.append(packet)
	var box := RoomService._RunBox.new()
	box.game = host.expedition
	box.members = {"p1": {"account_id": 11}, "p2": {"account_id": 12}}
	online._runs_by_account[11] = box
	online._broadcast_run(box)
	_check(packets[0]["run"]["resolved"]["r3c1"]["corpses"][0]["regions"][0]["items"].is_empty(), "online push filters hidden items")
	var welcome: Dictionary = online.attach_on_login(11, "test")
	_check(welcome["run"]["resolved"]["r3c1"]["corpses"][0]["regions"][0]["items"].is_empty(), "reconnect welcome filters hidden items")
	host._mark_member_offline(2)
	_check(host.expedition.run.get("loot_searches", {}).is_empty(), "disconnect releases search lease")
	ExpeditionStore.backend = Callable()

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await process_frame
	var dir := "res://screenshots/corpse_loot"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	root.get_texture().get_image().save_png(dir + "/" + name + ".png")

func _mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)

func _drag_item(game: ExpeditionGame, item: Dictionary) -> void:
	await process_frame
	await process_frame
	var source := panel.source_grid
	var start := source.global_position + source.origin + (Vector2(item["cell"][0], item["cell"][1]) + Vector2(0.5, 0.5)) * source.cell_size
	var cards_before: int = DeckBuilder.build(game.run_inventory())["entries"].size()
	_mouse(start, true)
	var motion := InputEventMouseMotion.new()
	motion.position = start + Vector2(35, 0)
	motion.global_position = motion.position
	motion.relative = Vector2(35, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await process_frame
	await process_frame
	_check(root.gui_is_dragging(), "real drag begins on discovered source grid")
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	root.push_input(key, true)
	await process_frame
	var payload: Dictionary = root.gui_get_drag_data().duplicate(true) if root.gui_is_dragging() else {}
	_check(bool(payload.get("rotated", false)), "source drag rotates with R")
	var destination := panel.grid.global_position + panel.grid.origin + Vector2(0.5, 1.5) * panel.grid.cell_size
	motion = InputEventMouseMotion.new()
	motion.position = destination
	motion.global_position = destination
	motion.relative = destination - start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.warp_mouse(destination)
	root.push_input(motion, true)
	await process_frame
	await process_frame
	_mouse(destination, false)
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless" and not payload.is_empty():
		_check(panel.grid._can_drop_data(destination - panel.grid.global_position, payload), "headless corpse drag fits destination")
		panel.grid._drop_data(destination - panel.grid.global_position, payload)
		await process_frame
	var carried := game.run_inventory().find_instance(int(item["instance_id"]))
	_check(bool(item["taken"]) and not carried.is_empty(), "real release transfers original corpse instance")
	if not carried.is_empty():
		_check(carried["cell"] == [0, 1] and bool(carried["rotated"]), "corpse drag preserves exact placement and rotation")
	_check(DeckBuilder.build(game.run_inventory())["entries"].size() == cards_before + ItemDefs.get_item(str(item["def_id"]))["cards"].size(), "multi cell item adds its cards to next battle deck")

func _run() -> void:
	_domain()
	var game := _fresh()
	game.search_clock = Callable()
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	panel = ExpeditionLootPanel.new()
	holder.add_child(panel)
	panel.action_sink = func(kind: String, args: Dictionary) -> Dictionary:
		var result := game.loot_action("p1", kind, args) if kind != "leave_node" else game.leave_node()
		panel.display(game.visible_run())
		return result
	panel.display(game.visible_run())
	_check(panel.battlefield.visible and not panel.workspace_frame.visible, "victory opens clickable battlefield")
	await _shot("01_battlefield")
	panel._open_corpse("e1")
	_check(not panel.scene_mode and panel.source_grid != null, "corpse opens grid")
	_check(panel._entry("corpse:1003").is_empty(), "UI cannot select unknown loot")
	await create_timer(0.35).timeout
	await _shot("02_searching")
	await create_timer(float(ItemDefs.search_ms(ItemDefs.quality_of(_resolved(game)["corpses"][0]["regions"][0]["items"][0]))) / 1000.0).timeout
	_check(not panel.entries.filter(func(item): return str(item["kind"]) == "claim_corpse").is_empty(), "UI timer completes authoritative search")
	await _shot("03_weapon_revealed")
	await _drag_item(game, _resolved(game)["corpses"][0]["regions"][0]["items"][0])
	await _shot("08_weapon_dragged")
	panel._return_to_battlefield()
	_check(panel.battlefield.visible and game.run.get("loot_searches", {}).is_empty(), "closing search returns to corpse scene")
	panel._open_corpse("e1")
	panel.search_region = "pack"
	panel._request("search_start", {"source": "e1", "region": "pack"}, "开始搜索背包。")
	await create_timer(0.4).timeout
	await _shot("04_bag_search")
	holder.visible = false
	await process_frame
	await process_frame
	_check(game.run.get("loot_searches", {}).is_empty(), "closing enclosing panel cancels unfinished search")
	holder.visible = true
	panel.display(game.visible_run())
	panel._request("search_start", {"source": "e1", "region": "pack"}, "继续搜索背包。")
	await create_timer(3.6).timeout
	await _shot("05_bag_revealed")
	for entry in panel.entries:
		if str(entry.get("region_id", "")) == "pack":
			panel.select_item(str(entry["token"]))
			break
	await _shot("06_bag_item_detail")
	root.size = Vector2i(1024, 640)
	await process_frame
	await _shot("07_small_window")
	panel._confirm_leave()
	_check(panel.modal.visible, "unsearched regions require leave confirmation")
	panel._close_modal()
	var pair := _fresh(false, false, true)
	panel.display(pair.visible_run())
	await _shot("09_two_corpses")
	var shield_game := _fresh(false, false, false, true)
	shield_game.search_clock = Callable()
	var shield_source := _source_item(shield_game, "reinforced_shield")
	panel.action_sink = func(kind: String, args: Dictionary) -> Dictionary:
		var result := shield_game.loot_action("p1", kind, args) if kind != "leave_node" else shield_game.leave_node()
		panel.display(shield_game.visible_run())
		return result
	root.size = Vector2i(1280, 800)
	panel.display(shield_game.visible_run())
	panel._open_corpse(shield_source["source"])
	await create_timer(0.35).timeout
	_check(panel.source_grid._active_rect().size.is_equal_approx(Vector2.ONE * panel.source_grid.cell_size * 2), "UI searches the entire 2x2 shield block")
	_check(panel.source_grid._id(panel.source_grid._active_rect().get_center()) == -1, "unknown multigrid outline cannot be selected or dragged")
	await _shot("10_shield_searching")
	await create_timer(float(ItemDefs.search_ms(ItemDefs.quality_of(shield_source["item"]))) / 1000.0).timeout
	_check(bool(shield_source["item"]["revealed"]), "UI timer reveals the whole shield")
	var shield_rect: Rect2 = panel.source_grid._rect(shield_source["item"])
	_check(shield_rect.size.is_equal_approx(Vector2.ONE * panel.source_grid.cell_size * 2), "revealed shield keeps the same full footprint")
	for y in range(2):
		for x in range(2):
			_check(panel.source_grid._id(shield_rect.position + Vector2(x + 0.5, y + 0.5) * panel.source_grid.cell_size) == int(shield_source["item"]["instance_id"]), "all four shield cells select the same instance")
	await _shot("11_shield_revealed")
	await _drag_item(shield_game, shield_source["item"])
	await _shot("12_shield_dragged")
	holder.queue_free()
	await process_frame
	await process_frame
	print("D54_CORPSE_LOOT_%s checks=%d" % ["FAIL" if failed else "PASS", checks])
	quit(1 if failed else 0)
