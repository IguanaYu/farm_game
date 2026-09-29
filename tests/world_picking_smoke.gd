extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var camera: Camera3D = world.get_node("FarmCamera")
	var physics: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for plot_id in range(1, 7):
		var plot: StaticBody3D = world.get_node("Plot_%02d" % plot_id)
		var screen := camera.unproject_position(plot.global_position + Vector3(0, 0.33, 0))
		var origin := camera.project_ray_origin(screen)
		var end := origin + camera.project_ray_normal(screen) * 100.0
		var hit: Dictionary = physics.intersect_ray(PhysicsRayQueryParameters3D.create(origin, end))
		if hit.is_empty() or hit["collider"] != plot:
			push_error("WORLD_PICKING_FAIL plot %d hit %s" % [plot_id, str(hit.get("collider", "none"))])
			quit(1)
			return
	print("WORLD_PICKING_PASS")
	quit(0)
