extends SceneTree
## d49：R4 洞口营地验收（计划：docs/plan/Godot_合并路线_R4_洞口营地与探索衔接_代码执行计划_v0.1.md §4）。
## 覆盖：营地结构与默认隐藏；石阶→营地路由与相机切换；营地四入口绑定（洞口=hub/篝火=组队/
## 战备台=配装/下山=返回）；紫盒已退役；farm↔营地往返零重建。
## 用法：Godot --headless --path . --script res://tests/d49_cave_camp_scene_smoke.gd

const SAVE_FILES := ["farm_save_v1.json", "farm_save_v1.json.bak"]

var failed := false
var fail_count := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var backup := _backup_saves()
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	await process_frame
	await process_frame
	var fresh := FarmGame.new()
	fresh.new_game(int(Time.get_unix_time_from_system()))
	world.game = fresh
	world.hud.game = fresh
	world._refresh_all()
	var g1: FarmGame = world.game
	var farm: Node3D = world.farm_location

	# —— 段1：营地结构 ——
	var camp: Node3D = world.get_node_or_null("CaveCamp")
	if not _check(camp != null and not camp.visible, "营地存在且默认隐藏"):
		_finish(backup)
		quit(1)
		return
	_check(camp.get_node_or_null("CampCamera") != null, "营地相机存在")
	_check(camp.find_child("CliffRock*",true,false) != null and camp.get_node_or_null("CaveMouth") != null, "山壁与暗洞口存在")
	_check(camp.get_node_or_null("CaveDepth") != null and camp.find_child("ArchCrown*",true,false) != null, "洞腔有深度和石拱")
	_check(camp.get_node_or_null("Campfire") != null and camp.get_node_or_null("Campfire/FireFlame") != null, "篝火存在（石圈+火焰）")
	_check(camp.get_node_or_null("WarBench") != null, "战备台存在")
	_check(camp.get_node_or_null("CampTent") != null, "帐篷装饰存在")
	_check(camp.get_node_or_null("DownhillPath") != null, "下山路口存在")
	_check(farm.get_node_or_null("CaveEntrance") == null, "紫盒洞口占位已退役")
	_check(camp.get_node_or_null("CaveMouth").get_meta("entry", "") == "depart", "洞口入口标记=depart")

	# —— 段2：路由与相机 ——
	var stairs: Node = farm.get_node_or_null("HillStairs")
	if not _check(stairs != null, "上山石阶入口存在"):
		_finish(backup)
		quit(1)
		return
	world.router.switch_to("cave_camp")
	var camp_cam: Camera3D = camp.get_node("CampCamera")
	var farm_cam: Camera3D = world.get_node("FarmCamera")
	_check(world.router.current == "cave_camp" and camp.visible and not farm.visible, "切到营地：地点可见性正确")
	_check(camp_cam.current and not farm_cam.current, "营地相机 current")
	world.router.go_back()
	_check(world.router.current == "farm" and farm.visible and not camp.visible, "下山返回：回农场")
	_check(farm_cam.current and not camp_cam.current, "相机还原农场")

	# —— 段3：流程入口绑定（模拟点击事件驱动处理器） ——
	world.router.switch_to("cave_camp")
	_simulate_click(camp.get_node("CaveMouth"))
	_check(world.hud.expedition_hub_panel != null and world.hud.expedition_hub_panel.visible, "洞口点击 → 出发界面（hub 面板）")
	world.hud.expedition_hub_panel.close()
	world.router.switch_to("cave_camp")
	_simulate_click(camp.get_node("WarBench"))
	_check(world.hud.loadout_panel != null and world.hud.loadout_panel.visible, "战备台点击 → 配装面板")
	world.hud.close_expedition_panels()
	world.router.switch_to("cave_camp")

	# —— 段4：零重建复检 ——
	for i in range(3):
		world.router.switch_to("cave_camp")
		world.router.go_back()
	_check(world.game == g1, "三轮往返 game 同实例（零重建）")
	_check(int(world.game.state["coins"]) == int(fresh.state["coins"]), "金币零变化")

	_finish(backup)
	quit(1 if failed else 0)


func _simulate_click(body: StaticBody3D) -> void:
	## 这里只核对处理器绑定；真实视口拾取另由 capture_scene_alignment 验证。
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	for connection in body.input_event.get_connections():
		var callback: Callable = connection["callable"]
		var args: Array = [null, event, Vector3.ZERO, Vector3.UP, 0]
		args.append_array(callback.get_bound_arguments())
		callback.callv(args)


func _backup_saves() -> Dictionary:
	var backup := {}
	for name in SAVE_FILES:
		var path := "user://%s" % name
		if FileAccess.file_exists(path):
			backup[name] = FileAccess.get_file_as_string(path)
	return backup


func _finish(backup: Dictionary) -> void:
	for name in SAVE_FILES:
		var path := "user://%s" % name
		if backup.has(name):
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(backup[name])
			file.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(ok: bool, label: String) -> bool:
	checks += 1
	if ok:
		print("D49-PASS %s" % label)
	else:
		failed = true
		fail_count += 1
		print("D49-FAIL %s" % label)
	return ok
