extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var camera: Camera3D = world.get_node("FarmCamera")
	var physics: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	## R2：农场 3D 挂 FarmLocation 组节点下（外壳层共享相机/环境）；两组路径都兼容。
	var pick_root: Node = world.get_node_or_null("FarmLocation")
	if pick_root == null:
		pick_root = world
	for plot_id in range(1, 7):
		var plot: StaticBody3D = pick_root.get_node("Plot_%02d" % plot_id)
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
