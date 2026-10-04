extends SceneTree

const OUT := "E:/gpt/worktree/6bc4/farm/screenshots/visual_audit_2026-10-04"
var facts: Dictionary = {"source_commit": "2064954", "isolated_user_data": true, "network_connected": false, "shots": []}

func _initialize() -> void:
	_run.call_deferred()

func _settle() -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw

func _shot(tag: String) -> void:
	await _settle()
	root.get_texture().get_image().save_png(OUT.path_join(tag + ".png"))
	facts["shots"].append(tag)
	print("VISUAL_SHOT ", tag)

func _camera_fact(world: Node3D) -> Dictionary:
	var cam := root.get_camera_3d()
	return {"location": world.router.current, "camera": str(cam.get_path()) if cam != null else "none", "farm_visible": world.farm_location.visible}

func _esc() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	await _settle()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await _shot("01_main_menu")
	menu._on_online()
	await _shot("02_online_login")
	menu.queue_free()
	await process_frame
	GameFlow.mode = GameFlow.Mode.NEW_GAME
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await _shot("03_farm_tutorial")
	world.game.state["tutorial_step"] = 5
	world.game.state["coins"] = 800
	world._refresh_all()
	await _shot("04_farm_clear")
	world.game.plant(1, int(Time.get_unix_time_from_system()))
	world.game.plant(2, int(Time.get_unix_time_from_system()))
	world._debug_mature_all()
	world._refresh_all()
	await _shot("05_farm_mature")
	world.hud.open_seed_picker(3)
	await _shot("06_seed_picker")
	world.hud._close_modal()
	world.hud.open_warehouse()
	await _shot("07_warehouse")
	world.hud._close_modal()
	world.hud.open_breeder()
	await _shot("08_breeder")
	world.hud._close_modal()
	world.hud.open_crafting()
	await _shot("09_crafting")
	world.hud.crafting_panel.close()
	world.router.switch_to("shop")
	await _shot("10_shop_clear")
	world.hud.open_shop()
	await _shot("11_shop_purchase")
	world.hud._close_modal()
	world.hud.open_market()
	await _shot("12_shop_market")
	world.hud._close_modal()
	world.router.switch_to("cave_camp")
	await _shot("13_cave_camp")
	world.hud.expedition_hub_panel.open(world.game)
	await _shot("14_cave_departure")
	world.hud.expedition_hub_panel.close()
	world.hud.loadout_panel.open(world.game)
	await _shot("15_loadout")
	world.hud.loadout_panel.close()
	world.hud.room_panel.open(world.game)
	await _shot("16_offline_room")
	world.hud.room_panel.close()
	world.router.switch_to("farm", false)
	var directory: OnlineVisitPanel = world.hud.online_visit_panel
	directory.visible = true
	directory.status_label.text = "视觉巡检演示条目（未连接服务器）"
	for entry in [{"account_id": 1, "nick": "小满", "online": false, "visits_open": true}, {"account_id": 2, "nick": "阿禾", "online": true, "visits_open": true}, {"account_id": 3, "nick": "小翠", "online": false, "visits_open": false}]:
		directory.list_column.add_child(directory._entry(entry))
	await _shot("17_directory_demo")
	await _esc()
	facts["directory_escape"] = {"directory_visible": directory.visible, "pause_visible": world.hud.pause_overlay.visible}
	await _shot("18_directory_after_escape")
	directory.close()
	world.hud._close_pause()
	var snapshot: Dictionary = world.game.state.duplicate(true)
	world.enter_visit({"account_id": 1, "nick": "小满", "online": false}, snapshot)
	await _shot("19_friend_yard")
	facts["friend_yard"] = _camera_fact(world)
	facts["friend_yard"]["house_collision_layer"] = world.visit_yard.get_node("VisitHouse").collision_layer
	facts["friend_yard"]["gate_collision_layer"] = world.visit_yard.get_node("VisitGate").collision_layer
	facts["friend_yard"]["owned_in_snapshot"] = world.game.owned_plot_ids()
	facts["friend_yard"]["rendered_owned_plots"] = []
	for slot in world.visit_yard.get_children():
		if str(slot.name).begins_with("VisitPlot_") and slot.get_child_count() > 0:
			facts["friend_yard"]["rendered_owned_plots"].append(str(slot.name))
	world.router.switch_to("visit_house")
	await _shot("20_friend_house")
	facts["friend_house"] = _camera_fact(world)
	facts["friend_house"]["door_collision_layer"] = world.visit_house.get_node("HouseDoor").collision_layer
	facts["friend_house"]["window_collision_layer"] = world.visit_house.get_node("HouseWindow").collision_layer
	world.leave_visit()
	await _shot("21_friend_return")
	facts["friend_return"] = _camera_fact(world)
	facts["friend_return"]["visiting"] = world.hud.visiting
	world.farm_location.visible = true
	world.get_node("FarmCamera").current = true
	world.hud._open_pause()
	await _shot("22_pause")
	world.hud._show_pause_settings()
	await _shot("23_settings")
	world.hud._close_pause()
	root.size = Vector2i(1024, 640)
	world.hud.open_crafting()
	await _shot("24_crafting_1024")
	facts["crafting_1024"] = {"viewport": str(root.get_visible_rect()), "minimum_width": 1020, "minimum_height": 660}
	world.hud.crafting_panel.close()
	root.size = Vector2i(736, 700)
	directory.visible = true
	await _shot("25_directory_736")
	directory.close()
	root.size = Vector2i(1280, 800)
	var result := FileAccess.open(OUT.path_join("verification.json"), FileAccess.WRITE)
	result.store_string(JSON.stringify(facts, "\t"))
	print("VISUAL_AUDIT_DONE ", facts)
	quit(0)
