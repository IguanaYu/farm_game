extends SceneTree


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var hud: FarmHud = world.get_node("FarmCanvas/FarmHud")
	hud.show_harvest(2, 3)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://docs/harvest_preview.png")
	quit(0)
