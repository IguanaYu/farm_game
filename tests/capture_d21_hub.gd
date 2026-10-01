extends SceneTree
## 2.1-W5/W6 界面截图：洞窟入口概览的打开与关闭。


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	## 注意：需要带窗口运行（headless 下 viewport 无渲染纹理）。此前会话同此约定。
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var hud: FarmHud = world.get_node("FarmCanvas/FarmHud")
	hud.open_expedition_hub()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d21_expedition_hub.png")
	hud.close_expedition_panels()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d21_hub_closed_farm.png")
	world.queue_free()
	quit(0)
