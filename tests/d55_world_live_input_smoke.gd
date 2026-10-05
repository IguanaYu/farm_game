extends SceneTree
## 世界/探险/战斗真实输入链路测试 d55（参考 capture_scene_alignment.gd 与
## capture_expedition_redesign.gd 的功能面，与其互补：那两个是带窗口的截图套件，
## 本脚本把同一批"真的点得动"链路纳入 headless 回归，并在带窗口时落 live/fixture 双类证据）。
## 覆盖：
## 1) 农场 3D 视口拾取真实点击——未开垦地块→扩地弹窗、空地块→选种弹窗、杂货铺→进商店、
##    客商→交易弹窗、楼梯→进营地、战备台→配装面板（d49 只验回调绑定，真实拾取由本脚本接管）；
## 2) 卖菜对账：真实点击 GuestConfirmSale 后金币增量 == 报价；
## 3) 真实拖放：引擎拖放流程把装备落到指定格子 [1,2]（d44 已有战利品拖放，此处为配装格）；
## 4) ESC 语义：访问面板开时一次 ESC 关面板不弹暂停；结算未确认前 ESC 不可关；
## 5) 战斗：真实点卡选中、真实点目标结算预览伤害、数字键选卡、ESC 取消、自保卡真实点自己；
## 6) 探险地图：真实点路线选中、"向这里前进"真实点击走领域层。
## 面板直开的部分属 fixture 口径（与截图套件一致）；世界点击/确认按钮/拖放/按键全走真实注入。
## 运行前后备份/恢复存档（d35 约定）；headless 跳过截图与 hover 断言。


class MemoryExpedition extends ExpeditionGame:
	func save() -> bool:
		return true


var failed := false
var out_dir := ""

const SAVE_FILES := ["farm_save_v1.json", "farm_save_v1.json.bak"]
const PREF_FILES := ["settings.cfg", "relay_prefs.cfg"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var backup := _backup_files(SAVE_FILES)
	var prefs_backup := _backup_files(PREF_FILES)
	_remove_files(SAVE_FILES)
	_remove_files(PREF_FILES)
	GameFlow.reset()
	if DisplayServer.get_name() != "headless":
		out_dir = ProjectSettings.globalize_path("res://").path_join("screenshots/world_live_20261004")
		DirAccess.make_dir_recursive_absolute(out_dir)

	# ———— 第一段：农场世界（真实场景 + 真实 3D 视口拾取）————
	GameFlow.mode = GameFlow.Mode.NEW_GAME
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	await _frames(8)
	if world.hud == null or world.game == null:
		_check(false, "农场世界初始化（HUD/游戏就绪）")
		_finish(backup, prefs_backup)
		return
	world.game.state["tutorial_step"] = 5
	world.game.state["coins"] = 800
	world._refresh_all()
	var now := int(Time.get_unix_time_from_system())
	world.game.plant(1, now)
	world.game.plant(2, now)
	world._debug_mature_all()
	await _shot("fixture_01_farm_home", "农场初始（种两块并催熟，无输入驱动）")

	# 未开垦地块 → 扩地弹窗（真实点击）
	await _click_world(world.farm_location.get_node("Plot_08"), Vector3(0, 0.1, 0))
	_check(world.hud.active_modal == "expansion", "真实点击未开垦地块弹出扩地弹窗")
	await _shot("live_02_expansion_by_plot_click", "扩地弹窗（真实点击地块打开）")
	world.hud._close_modal()

	# 已开垦空地块 → 选种弹窗（真实点击）
	await _click_world(world.farm_location.get_node("Plot_03"), Vector3(0, 0.1, 0))
	_check(world.hud.active_modal == "seed_picker", "真实点击空地块弹出选种弹窗")
	await _shot("live_03_seed_picker_by_plot_click", "选种弹窗（真实点击空地块打开）")
	world.hud._close_modal()

	# 杂货铺 → 进商店（点门换场景）
	await _click_world(world.farm_location.get_node("ShopBuilding"), Vector3(0, 1.5, 0))
	_check(world.router.current == "shop", "真实点击杂货铺切换进商店")
	await _shot("live_04_shop_by_building_click", "商店场景（真实点击杂货铺进入）")

	# 客商交易：收获两块地（参考流程）→ 直开篮子（fixture）→ 真实点击客商 → 真实点击卖出 → 金币对账
	world._do_harvest(1)
	world._do_harvest(2)
	world.hud.open_basket()
	world.hud._close_modal()
	var guest_id := int(world.game.state["market"]["guest_ids"][0])
	var batch: Dictionary = world.hud.selected_basket()
	_check(not batch.is_empty(), "篮子里有已收获批次")
	if not batch.is_empty():
		var batch_id := int(batch["id"])
		world.hud.market_sell_counts[batch_id] = 1
		world.hud._refresh_world_quotes()
		await _click_world(world.guest_slots[0], Vector3(0, 1, 0))
		_check(world.hud.active_modal == "guest" and world.hud.selected_guest_id == guest_id, "真实点击客商选中该客商")
		await _shot("live_05_guest_trade_by_click", "客商交易弹窗（真实点击客商打开）")
		var before_coins := int(world.game.state["coins"])
		var price: Dictionary = world.game.quote(batch, 1, guest_id)
		await _click_button(world.hud.find_child("GuestConfirmSale", true, false), "客商·确认卖出按钮")
		_check(int(world.game.state["coins"]) == before_coins + int(price["coins"]), "真实点击卖出后金币增量与报价一致")
		world.hud._close_modal()

	# ESC 语义：回农场后，访问面板开时一次真实 ESC 关面板、不弹暂停
	world.router.switch_to("farm", false)
	await _frames(4)
	world.hud.online_visit_panel.visible = true
	await _press_key(KEY_ESCAPE)
	_check(not world.hud.online_visit_panel.visible and not world.hud.pause_overlay.visible, "一次真实 ESC 关闭访问面板且不弹暂停")

	# 楼梯 → 进营地（点门换场景）
	await _click_world(world.farm_location.get_node("HillStairs"), Vector3(0, 1, 0))
	_check(world.router.current == "cave_camp", "真实点击山道楼梯进入洞窟营地")
	await _shot("live_06_camp_by_stairs_click", "洞窟营地（真实点击楼梯进入）")

	# 战备台 → 配装面板 → 真实拖放装备到指定格
	await _click_world(world.get_node("CaveCamp/WarBench"), Vector3(0, 1, 0))
	_check(world.hud.loadout_panel != null and world.hud.loadout_panel.visible, "真实点击战备台打开配装面板")
	world.hud.loadout_panel._on_grant_kit()
	var inv: InventoryGame = world.hud.loadout_panel.inventory
	for item in inv.warehouse_list().duplicate():
		inv.move_to_loadout(int(item["instance_id"]), "chest")
	world.hud.loadout_panel._refresh()
	await _frames(4)
	var grid: ExpeditionLootGrid = world.hud.loadout_panel.workspace.container_grids["chest"]
	var instance: Dictionary = inv.loadout_list("chest")[0]
	var equip_id := int(instance["instance_id"])
	await _drag_cell(grid.global_position + grid._item_rect(instance).get_center(), grid.global_position + grid.origin + Vector2(1.5, 2.5) * grid.cell_size, grid)
	_check(inv.find_instance(equip_id)["cell"] == [1, 2], "真实拖放把装备落到指定格 [1,2]")
	await _shot("live_07_loadout_after_drag", "配装面板（真实拖动装备落格后）")
	world.hud.loadout_panel.close()
	world.queue_free()
	await _frames(4)

	# ———— 第二段：战斗（真实点卡/点目标/快捷键）————
	await _battle_round()

	# ———— 第三段：出发台与地图（fixture 备装 + 真实点击路线）————
	var game := FarmGame.new()
	game.set_debug_random_seed(20261003)
	game.new_game(1000)
	var hub := ExpeditionHubPanel.new()
	root.add_child(hub)
	hub.open(game)
	_check(hub.depart_button.disabled, "首访空配装时出发按钮禁用")
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	# 三栏改版：武器/草帽上装备槽（第 1 回合有牌），其余入胸挂。
	for def_id in ["old_shortsword", "straw_hat"]:
		for item in inventory.warehouse_list().duplicate():
			if str(item["def_id"]) == def_id:
				inventory.equip(int(item["instance_id"]), "main_weapon" if def_id == "old_shortsword" else "helmet")
	for item in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(item["instance_id"]), "chest")
	hub.open(game)
	_check(not hub.depart_button.disabled, "装备上身出发按钮解禁")
	await _shot("fixture_08_hub_ready", "出发台（直开+直备，fixture 口径）")
	hub.close()

	var expedition := MemoryExpedition.new()
	expedition.game = game
	expedition.rng.seed = 20261003
	expedition.run = {
		"run_id": "d55", "layer_id": "moss_stone_shallow", "rng_seed": 20261003,
		"player": {"hp": 28, "max_hp": 40, "extra_draw_next": false},
		"inventory": ExpeditionGame._snapshot_loadout(game), "next_instance_id": 2000,
		"map": ExpeditionGame._build_map("moss_stone_shallow"), "current": {"row": 0, "col": 0},
		"resolved": {}, "node_drops": [], "battle": {}, "phase": "map", "outcome": "",
		"carried_from_farm": ExpeditionGame._carried_ids(game), "consumed": [], "log": ["出发：向苔石浅洞前进。"]
	}
	var map_panel := ExpeditionMapPanel.new()
	root.add_child(map_panel)
	map_panel.open(expedition)
	await _shot("fixture_09_route", "探险路线（直开，fixture 口径）")
	await _click_button(map_panel.route_view.buttons[1], "路线·第二个节点按钮")
	_check(int(expedition.run["current"]["row"]) == 0, "路线预览不移动当前位置")
	_check(map_panel.selected_route == Vector2i(1, 0), "真实点击路线选中下一节点")
	var confirmed := false
	for button in map_panel.node_column.find_children("*", "Button", true, false):
		if button.text.contains("向这里前进"):
			await _click_button(button, "路线·向这里前进按钮")
			confirmed = true
			break
	_check(confirmed and int(expedition.run["current"]["row"]) == 1, "真实点击前进按钮走领域层移动")
	await _shot("live_10_encounter_by_confirm_click", "遭遇页（真实点击前进进入）")

	# 结算未确认前真实 ESC 不可关闭
	map_panel._show_settlement({"kind": "extract", "settlement_id": "d55", "gained": [{"name": "铜片"}], "protected": [{"name": "辉晶"}]})
	await _press_key(KEY_ESCAPE)
	_check(map_panel.overlay_panel.visible, "结算未确认前真实 ESC 无法关闭")
	await _shot("fixture_11_settlement", "撤离结算（直开，fixture 口径）")
	map_panel._close_overlay()
	map_panel.close()
	hub.queue_free()
	map_panel.queue_free()
	await _frames(4)

	_finish(backup, prefs_backup)


## 战斗段：真实点卡选中、真实点目标结算、数字键、ESC 取消、自保卡真实点自己。
func _battle_round() -> void:
	var screen := BattleScreen.new()
	root.add_child(screen)
	var deck: Array = []
	for id in ["slash", "shield_up", "heavy_strike", "brace", "observe", "rescue_signal", "cover", "slash", "brace", "observe"]:
		deck.append({"card_id": id, "source_instance_id": 0, "join_round": 1})
	var combat := CombatGame.create([{"key": "p1", "name": "农夫", "max_hp": 40, "deck": deck}], "normal", 20261003, null, deck)
	combat.start()
	screen.open_run(combat)
	await _shot("fixture_12_battle_round1", "战斗首回合（直开，fixture 口径）")

	var slash_index := _hand_index(combat, "slash")
	_check(slash_index >= 0, "手牌里有挥砍卡")
	if slash_index >= 0:
		var card: Dictionary = combat.state["players"]["p1"]["hand"][slash_index]
		await _click_button(screen.hand_row.get_node_or_null("Card_%d" % int(card["uid"])) as Button, "手牌·挥砍卡")
		_check(screen.selected_uid == int(card["uid"]), "真实点击手牌选中该卡")
		# 与参考测试同口径：先给敌人 4 点格挡，挥砍 6 伤破挡后实际 -2（同时验证挡格参与结算）。
		combat.state["enemies"][0]["block"] = 4
		var hp_before := int(combat.state["enemies"][0]["hp"])
		await _click_button(screen.target_controls["e1"], "目标·第一个敌人")
		_check(int(combat.state["enemies"][0]["hp"]) == hp_before - 2, "真实点击目标结算预览伤害（生命 -2）")
		await _shot("live_13_strike_by_target_click", "出手后（真实点卡+真实点目标）")
	await _press_key(KEY_1)
	_check(screen.selected_uid >= 0, "数字键 1 选中首张手牌")
	await _press_key(KEY_ESCAPE)
	_check(screen.selected_uid < 0, "真实 ESC 取消选卡不离开战斗")
	var shield_index := _hand_index(combat, "shield_up")
	if shield_index >= 0:
		var shield_card: Dictionary = combat.state["players"]["p1"]["hand"][shield_index]
		await _click_button(screen.hand_row.get_node_or_null("Card_%d" % int(shield_card["uid"])) as Button, "手牌·举盾卡")
		await _click_button(screen.target_controls["p1"], "目标·自己")
		_check(int(combat.state["players"]["p1"]["block"]) > 0, "真实点击自己结算自保格挡")
	screen.queue_free()
	await _frames(2)


func _hand_index(combat: CombatGame, card_id: String) -> int:
	var hand: Array = combat.state["players"]["p1"]["hand"]
	for i in range(hand.size()):
		if str(hand[i]["card_id"]) == card_id:
			return i
	return -1


# —— 真实输入注入（与 d54 同配方）—————————————————————————————————


## 3D 真实点击：相机投影 → 鼠标 move/press/release 全走 root.push_input（真实视口拾取）。
func _click_world(body: Node3D, offset: Vector3) -> void:
	await _frames(3)
	var at: Vector2 = root.get_camera_3d().unproject_position(body.global_position + offset)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	await _frames(3)
	var press := InputEventMouseButton.new()
	press.position = at
	press.global_position = at
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	await _frames(3)
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await _frames(3)


## 2D 按钮真实点击：窗口内/hover 命中证据断言仅带窗口时执行（headless 无意义，d54 坑）。
func _click_button(button: Button, label: String) -> void:
	if button == null:
		_check(false, label + "：按钮不存在")
		return
	_check(button.is_visible_in_tree() and not button.disabled, label + "：可点击前提（可见且未禁用）")
	var center := button.get_global_rect().get_center()
	if DisplayServer.get_name() != "headless":
		_check(Rect2(Vector2.ZERO, Vector2(root.size)).grow(-2).has_point(center), label + "：按钮中心在窗口内")
		root.warp_mouse(center)
		var motion := InputEventMouseMotion.new()
		motion.position = center
		motion.global_position = center
		root.push_input(motion, true)
		await process_frame
		var hovered: Control = root.gui_get_hovered_control()
		if hovered != null and hovered != button and not button.is_ancestor_of(hovered):
			_check(false, label + "：hover 命中的不是目标按钮（被 " + str(hovered.get_path()) + " 挡住）")
	root.warp_mouse(center)
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await _frames(2)


## 真实拖放：press/motion/release 全走 root.push_input（headless 下 Input.parse_input_event 不派发，
## d44 坑）；headless 的 dummy 显示服务不跟踪指针、真实释放可能不派发 drop——与 d44 同口径，
## 用同一 _can_drop_data/_drop_data 回调把载荷落到目标格（带窗口时上面已是全真实释放）。
func _drag_cell(start: Vector2, end: Vector2, grid: ExpeditionLootGrid) -> void:
	root.warp_mouse(start)
	var press := InputEventMouseButton.new()
	press.position = start
	press.global_position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	var move := InputEventMouseMotion.new()
	move.position = start + Vector2(20, -30)
	move.global_position = move.position
	move.relative = Vector2(20, -30)
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(move, true)
	await _frames(4)
	_check(root.gui_is_dragging(), "真实拖动开始（引擎拖放流程）")
	var drag_data: Dictionary = root.gui_get_drag_data().duplicate(true) if root.gui_is_dragging() else {}
	move = move.duplicate()
	move.position = end
	move.global_position = end
	move.relative = end - (start + Vector2(20, -30))
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.warp_mouse(end)
	root.push_input(move, true)
	await _frames(4)
	press = press.duplicate()
	press.position = end
	press.global_position = end
	press.pressed = false
	root.push_input(press, true)
	await _frames(4)
	if DisplayServer.get_name() == "headless" and not drag_data.is_empty():
		var local := end - grid.global_position
		if grid._can_drop_data(local, drag_data):
			grid._drop_data(local, drag_data)
			await _frames(2)


## 合成按键 press/release 走完整输入链。
func _press_key(keycode: int) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame


# —— 截图与证据 ——————————————————————————————————————————————————


func _shot(tag: String, note: String) -> void:
	# headless 也要等帧：截图类节奏（等布局/动画收敛）对后续点击同样必要，只跳过存图。
	await _frames(4)
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(out_dir.path_join(tag + ".png"))
	print("SHOT " + tag + " | " + note)


# —— 存档隔离（d35 约定）———————————————————————————————————————


func _backup_files(names: Array) -> Dictionary:
	var backup := {}
	for save_name in names:
		var path: String = "user://" + str(save_name)
		if FileAccess.file_exists(path):
			backup[str(save_name)] = FileAccess.get_file_as_bytes(path)
	return backup


func _remove_files(names: Array) -> void:
	var dir := DirAccess.open("user://")
	for save_name in names:
		if dir != null and FileAccess.file_exists("user://" + str(save_name)):
			dir.remove(str(save_name))


func _restore_files(backup: Dictionary) -> void:
	var dir := DirAccess.open("user://")
	for save_name in backup.keys():
		var file := FileAccess.open("user://" + str(save_name), FileAccess.WRITE)
		file.store_buffer(backup[str(save_name)])
		file.close()
	for save_name in ["farm_save_v1.json", "farm_save_v1.json.bak", "settings.cfg", "relay_prefs.cfg"]:
		if not backup.has(str(save_name)) and dir != null and FileAccess.file_exists("user://" + str(save_name)):
			dir.remove(str(save_name))


func _frames(n: int) -> void:
	for i in n:
		await process_frame
		await physics_frame


func _finish(backup: Dictionary, prefs_backup: Dictionary) -> void:
	_restore_files(backup)
	_restore_files(prefs_backup)
	if failed:
		push_error("D55_WORLD_LIVE_FAIL")
	else:
		print("D55_WORLD_LIVE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
