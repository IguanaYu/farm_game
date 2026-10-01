extends SceneTree
## 2.1-W6 界面截图：战备首页三张状态（空配装／基础套装入胸挂／木盾挪背包）。
## 只在内存摆拍：不写磁盘存档。


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var hud: FarmHud = world.get_node("FarmCanvas/FarmHud")
	hud.open_loadout()
	var panel: LoadoutPanel = hud.loadout_panel
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d21_loadout_empty.png")

	panel.inventory.grant_basic_kit()
	for instance in panel.inventory.warehouse_list().duplicate():
		panel.inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	panel.selected_instance_id = -1
	panel._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d21_loadout_full_chest.png")

	for instance in panel.inventory.loadout_list("chest").duplicate():
		if str(instance["def_id"]) == "wooden_shield":
			panel.inventory.move_to_warehouse(int(instance["instance_id"]))
			panel.inventory.move_to_loadout(int(instance["instance_id"]), "pack")
	var moved_preview: Dictionary = panel.inventory.deck_preview()
	print("after shield move: r1=", moved_preview["totals"][1], " r2=", moved_preview["totals"][2])
	panel._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d21_loadout_shield_moved.png")

	# 关闭路径也走一次：剔除演示物品（这里没有演示物，验证不崩即可）。
	panel.close_requested.emit()
	world.queue_free()
	quit(0)
