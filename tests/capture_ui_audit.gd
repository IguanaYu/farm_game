extends SceneTree
## 全 UI 巡检：逐界面截图 + 按钮可达性审计（遮挡检测）。需带窗口运行（不要 --headless）。
## 巡检不修改真实存档——由外部脚本在运行前后备份/恢复 user:// 目录。
## 洞窟流程在内存里的新档上演练（world.game 换成 fresh FarmGame），不落盘真实进度。

var shot_dir := "res://screenshots/audit"


func _initialize() -> void:
	_run.call_deferred()


func _shot(tag: String, panel: Control = null) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [shot_dir, tag]
	root.get_viewport().get_texture().get_image().save_png(path)
	_audit(tag, panel)
	print("SHOT ", tag)


func _audit(tag: String, panel: Control) -> void:
	## 每个可见按钮在其中心做命中测试：命中的不是自己/祖先/子孙 = 被无关控件遮挡。
	## 自研命中测试：按绘制顺序取最上层包含该点且 mouse_filter != IGNORE 的控件。
	if panel == null:
		print("AUDIT %s: SKIPPED (no panel)" % tag)
		return
	var checked := 0
	for button in panel.find_children("*", "Button", true, false):
		if not button.is_visible_in_tree():
			continue
		var center: Vector2 = button.get_global_rect().get_center()
		if _clipped_out(button, center):
			continue
		checked += 1
		var holder: Array = [null]
		_walk_hit_impl(hud_root(), center, holder)
		var hit: Control = holder[0]
		if hit == null:
			print("AUDIT %s: MISS %s" % [tag, _desc(button)])
			continue
		if hit == button or hit.is_ancestor_of(button) or button.is_ancestor_of(hit):
			continue
		print("AUDIT %s: OCCLUDED %s <- %s" % [tag, _desc(button), _desc(hit)])
	print("AUDIT %s: checked %d buttons" % [tag, checked])


func _clipped_out(button: Control, center: Vector2) -> bool:
	## 按钮中心落在任一开启裁剪的祖先可视区外 = 当前滚动位置看不到，不参与审计。
	var node: Node = button.get_parent()
	while node is Control:
		var control: Control = node
		if control.clip_contents and not control.get_global_rect().has_point(center):
			return true
		node = node.get_parent()
	return false


func hud_root() -> Control:
	return root.get_node("FarmWorld/FarmCanvas/FarmHud") as Control


func _walk_hit_impl(control: Control, point: Vector2, holder: Array) -> void:
	if not control.is_visible_in_tree():
		return
	var contains := control.get_global_rect().has_point(point)
	if control.clip_contents and not contains:
		return
	if contains and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		holder[0] = control
	for child in control.get_children():
		if child is Control:
			_walk_hit_impl(child, point, holder)


func _desc(c: Control) -> String:
	var chain := ""
	var node: Node = c
	while node != null and chain.length() < 140:
		chain = "%s(%s) < %s" % [node.get_class(), node.name, chain]
		node = node.get_parent()
	return chain


func _run() -> void:
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	var hud: FarmHud = world.hud

	# —— A. 真实档界面（只读打开，不点保存类按钮） ——
	await _shot("01_farm_base", hud)
	hud.open_shop()
	await _shot("02_modal_shop", hud.modal_overlay)
	hud.open_market()
	await _shot("03_modal_market", hud.modal_overlay)
	hud.open_warehouse()
	await _shot("04_modal_warehouse_crops", hud.modal_overlay)
	hud.open_warehouse("seeds")
	await _shot("05_modal_warehouse_seeds", hud.modal_overlay)
	hud.open_breeder()
	await _shot("06_modal_breeder", hud.modal_overlay)
	hud._close_modal()
	hud.expedition_hub_panel.open(world.game)
	await _shot("07_hub", hud.expedition_hub_panel)
	hud.expedition_hub_panel.close()
	hud.loadout_panel.open(world.game)
	await _shot("08_loadout_real", hud.loadout_panel)
	hud.loadout_panel.close()
	hud.open_crafting()
	await _shot("09_crafting_real", hud.crafting_panel)
	hud.crafting_panel.close()
	hud.open_equipment_warehouse()
	await _shot("10_eqwarehouse_real", hud.equipment_warehouse_panel)
	hud.equipment_warehouse_panel.close()

	# —— B. 换内存新档演练洞窟全流程（不点任何会写真实档的按钮之外的东西） ——
	var fresh := FarmGame.new()
	fresh.new_game(int(Time.get_unix_time_from_system()))
	world.game = fresh
	hud.game = fresh
	world._refresh_all()
	await _shot("11_farm_fresh", hud)
	hud.loadout_panel.open(fresh)
	await _shot("12_loadout_empty", hud.loadout_panel)
	var inv := InventoryGame.new()
	inv.bind(fresh.state["expedition"])
	inv.grant_basic_kit()
	for instance in inv.warehouse_list().duplicate():
		inv.move_to_loadout(int(instance["instance_id"]), "chest")
	inv.inject_demo_items()
	hud.loadout_panel._refresh()
	await _shot("13_loadout_kit", hud.loadout_panel)
	hud.loadout_panel.close()

	# 走新接线的出发路径
	hud._on_loadout_depart_requested()
	await _shot("14_map_start", hud.map_panel)
	hud.map_panel._open_menu()
	await _shot("15_map_menu", hud.map_panel.overlay_panel)
	hud.map_panel._close_overlay()
	hud.map_panel._flash_overlay("（样式巡检）提示文案示例：背包空间不足。")
	await _shot("16_map_flash", hud.map_panel.overlay_panel)
	hud.map_panel._close_overlay()

	var expedition: ExpeditionGame = hud.active_expedition
	var types := ["battle", "gather", "chest", "event", "rest_exit", "elite", "gather", "exit"]
	var rows: Array = expedition.run["map"]["rows"]
	for row_index in range(1, rows.size()):
		var risk := "high" if types[row_index - 1] == "elite" else "normal"
		rows[row_index] = [{"type": types[row_index - 1], "risk": risk, "hint": "巡检摆拍"}]

	# 第 1 排：战斗节点 → 战斗三连 → 战后搜刮
	expedition.move_to(1, 0)
	hud.map_panel._refresh()
	await _shot("17_map_battle_node", hud.map_panel)
	var started := expedition.start_battle()
	var combat: CombatGame = started["combat"]
	var p1: Dictionary = combat.state["players"]["p1"]
	print("BATTLE_STATE round=%d phase=%s energy=%d hand=%d draw=%d" % [int(combat.state["round"]), str(combat.state["phase"]), int(p1["energy"]), (p1["hand"] as Array).size(), (p1["draw_pile"] as Array).size()])
	hud._on_run_battle_start(combat)
	await _shot("18_battle_round1", hud.battle_screen)
	for enemy in combat.state["enemies"]:
		enemy["hp"] = 0
		enemy["alive"] = false
	combat._events_check_outcome([])
	hud.battle_screen._refresh()
	var olabel: Label = hud.battle_screen.overlay_label
	await process_frame
	await process_frame
	print("OUTCOME_LABEL visible=%s text_len=%d rect=%s" % [str(olabel.visible), olabel.text.length(), str(olabel.get_global_rect())])
	for child in hud.battle_screen.overlay_panel.get_children():
		print("OVERLAY_CHILD %s visible=%s text_len=%d rect=%s" % [child.get_class(), str(child.visible) if child is Control else "?", (child as Label).text.length() if child is Label else -1, str((child as Control).get_global_rect())])
	await _shot("19_battle_over", hud.battle_screen.overlay_panel)
	hud.battle_screen._on_close()
	await _shot("20_map_battle_rewards", hud.map_panel)
	expedition.leave_node()

	# 第 2 排：采集 + 离开确认弹窗
	expedition.move_to(2, 0)
	hud.map_panel._refresh()
	await _shot("21_map_gather", hud.map_panel)
	hud.map_panel._on_leave_node()
	await _shot("22_leave_confirm", hud.map_panel.overlay_panel)
	hud.map_panel._close_overlay()
	expedition.leave_node()

	# 第 3 排：宝箱
	expedition.move_to(3, 0)
	hud.map_panel._refresh()
	await _shot("23_map_chest", hud.map_panel)
	expedition.leave_node()

	# 第 4 排：事件
	expedition.move_to(4, 0)
	hud.map_panel._refresh()
	await _shot("24_map_event", hud.map_panel)
	expedition.leave_node()

	# 第 5 排：休整撤离站 + 撤离决策 + 结算
	expedition.move_to(5, 0)
	hud.map_panel._refresh()
	await _shot("25_map_rest", hud.map_panel)
	hud.map_panel._open_extract_confirm()
	await _shot("26_extract_confirm", hud.map_panel.overlay_panel)
	hud.map_panel._close_overlay()
	var extracted := expedition.extract()
	if extracted["ok"]:
		hud.map_panel._show_settlement(extracted["settlement"])
		await _shot("27_settlement", hud.map_panel.overlay_panel)
		hud.map_panel._close_overlay()
	else:
		push_error("AUDIT_EXTRACT_FAIL: " + str(extracted["reason"]))
	hud.map_panel.close()
	hud._on_run_finished()

	# —— C. 联机房间页（只打开，不创建） ——
	hud.room_panel.open(fresh)
	await _shot("28_room_panel", hud.room_panel)
	hud.room_panel.close()

	world.queue_free()
	await process_frame
	print("UI_AUDIT_DONE")
	quit(0)
