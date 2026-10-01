extends SceneTree
## 2.5 界面截图：制作台与装备仓库。需带窗口运行。


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var hud: FarmHud = world.get_node("FarmCanvas/FarmHud")
	# 内存摆拍：给些材料与解锁（不写磁盘）。
	var crafting := CraftingGame.new()
	crafting.bind(world.game)
	var inventory := InventoryGame.new()
	inventory.bind(world.game.state["expedition"])
	inventory.grant_basic_kit()
	for def_id in ["copper_scrap", "copper_scrap", "fiber_clump", "fiber_clump", "iron_ore", "antique_ornament"]:
		inventory.add_instance(def_id, "test")
	world.game.state["expedition"]["crafting"]["plant_unlocks"] = ["rock_sprout"]
	hud.open_crafting()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d25_crafting.png")
	hud.crafting_panel.close()
	hud.open_equipment_warehouse()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d25_warehouse.png")
	hud.equipment_warehouse_panel.close()
	world.queue_free()
	quit(0)
