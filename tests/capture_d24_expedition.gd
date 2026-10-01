extends SceneTree
## 2.4 界面截图：探索地图、节点搜刮、撤离确认、回家结算。需带窗口运行。


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var hud: FarmHud = world.get_node("FarmCanvas/FarmHud")
	# 内存摆拍：基础套装入胸挂（不写磁盘）。
	var inventory := InventoryGame.new()
	inventory.bind(world.game.state["expedition"])
	inventory.grant_basic_kit()
	for instance in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	var depart := ExpeditionGame.depart(world.game, int(Time.get_unix_time_from_system()))
	if not depart["ok"]:
		push_error("CAPTURE_D24_DEPART_FAIL: " + str(depart["reason"]))
		quit(1)
		return
	hud.active_expedition = depart["game"]
	hud.map_panel.open(depart["game"])
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d24_map_start.png")

	var expedition: ExpeditionGame = depart["game"]
	expedition.move_to(1, 0)
	var first_battle := expedition.start_battle()
	for enemy in first_battle["combat"].state["enemies"]:
		enemy["hp"] = 0
		enemy["alive"] = false
	first_battle["combat"]._events_check_outcome([])
	expedition.finish_battle(first_battle["combat"])
	expedition.leave_node()
	expedition.move_to(2, 0)
	hud.map_panel._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d24_node_gather.png")

	expedition.leave_node()
	expedition.move_to(3, 0)
	expedition.leave_node()
	expedition.move_to(4, 0)
	hud.map_panel._refresh()
	hud.map_panel._open_extract_confirm()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d24_extract_confirm.png")
	hud.map_panel._close_overlay()

	var extract := expedition.extract()
	if extract["ok"]:
		hud.map_panel._show_settlement(extract["settlement"])
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("res://screenshots/d24_settlement.png")
	else:
		push_error("CAPTURE_D24_EXTRACT_FAIL: " + str(extract["reason"]))
	# 清理：应用结算后回到农场（不落盘农场档——capture 环境下磁盘存档由真实游玩产生）。
	world.queue_free()
	quit(0)
