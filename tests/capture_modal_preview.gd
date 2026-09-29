extends SceneTree


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var hud: FarmHud = world.get_node("FarmCanvas/FarmHud")
	var game: FarmGame = world.game
	var now: int = hud.view_now
	# 仅在内存里摆拍：不影响磁盘存档。
	for plot_id in range(1, 4):
		if game.plant(plot_id, now - 60) == "":
			game.water(plot_id, now - 30)
			game.get_plot(plot_id)["ready_at"] = now
	game.apply_fertilizer(1, "basic", now - 10)
	var result: Dictionary = game.harvest(1, now)
	hud.refresh(game.state)
	if result["ok"]:
		hud.show_harvest(result)
	else:
		push_error("CAPTURE_MODAL_FAIL: " + str(result))
		quit(1)
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://docs/harvest_preview.png")
	quit(0)
