extends SceneTree
## 2.3 界面截图：拖放后的背包布局、旋转与整理。需带窗口运行。


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

	# 内存摆拍：基础套装入胸挂；搜刮样例进背包（铜剑、摆件、铁矿旋转、种子入保险箱）。
	panel.inventory.grant_basic_kit()
	for instance in panel.inventory.warehouse_list().duplicate():
		panel.inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	for def_id in ["copper_shortsword", "antique_ornament", "iron_ore"]:
		panel.inventory.claim_reward(def_id, "pack")
	panel.inventory.claim_reward("rock_sprout_seed", "safe")
	var ore := -1
	for instance in panel.inventory.loadout_list("pack"):
		if str(instance["def_id"]) == "iron_ore":
			ore = int(instance["instance_id"])
	if ore > 0:
		panel.inventory.rotate_instance(ore)
	panel.selected_instance_id = ore
	panel._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d23_loadout_after_loot.png")

	panel.inventory.auto_tidy("pack")
	panel._refresh()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d23_loadout_tidy.png")
	panel.close_requested.emit()
	world.queue_free()
	quit(0)
