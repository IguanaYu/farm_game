extends SceneTree
## 手动育种测试入口：真实点击开关/继续/立即成熟，验证统一时钟、独立存档与恢复。

const FILES := ["farm_save_v1.json", "farm_save_v1.json.bak", "farm_save_v1.json.tmp", "farm_test_save_v1.json", "farm_test_save_v1.json.bak", "farm_test_save_v1.json.tmp", "settings.cfg"]
var failed := false
var backup := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for filename in FILES:
		var path: String = "user://" + filename
		if FileAccess.file_exists(path):
			backup[filename] = FileAccess.get_file_as_bytes(path)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	GameFlow.reset()
	FarmTestMode.enabled = false
	root.size = Vector2i(1024, 640)
	root.content_scale_size = Vector2i(1024, 640)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1024, 640))
	var normal := FarmGame.new()
	normal.new_game(int(Time.get_unix_time_from_system()))
	normal.state["coins"] = 321
	normal.state["tutorial_step"] = 99
	normal.state["seeds"][0]["traits"] = [{"effect": "water_guarantee", "tier": 1}]
	_check(SaveStore.save_state(normal.state), "准备正式档")
	var normal_bytes := FileAccess.get_file_as_bytes(SaveStore.SAVE_PATH)
	var menu := load("res://scenes/main_menu.tscn").instantiate() as MainMenu
	root.add_child(menu)
	current_scene = menu
	await _frames(4)
	var toggle := menu.find_child("TestModeButton", true, false) as Button
	_check(toggle != null and not toggle.button_pressed, "主菜单默认关闭测试功能")
	_check(toggle.get_global_rect().end.x <= root.size.x and toggle.get_global_rect().end.y <= root.size.y, "1024×640 下右下角开关在窗口内")
	_check(not toggle.get_global_rect().intersects(menu.find_child("MenuCenter", true, false).get_child(0).get_global_rect()), "右下角开关不遮挡主菜单")
	await _shot("01_menu_off")
	await _click(toggle)
	_check(FarmTestMode.enabled and toggle.button_pressed, "真实点击开启测试模式")
	_check((menu.find_child("OnlineButton", true, false) as Button).disabled and (menu.find_child("CoopButton", true, false) as Button).disabled, "测试模式关闭联机入口")
	await _shot("02_menu_on")
	await _click(menu.continue_button)
	await _frames(4)
	var world := current_scene
	_check(world != null and world.get("context") != null, "真实点击继续测试进入农场")
	if world == null or world.get("context") == null:
		_cleanup()
		return
	var context: GameContext = world.context
	var game: FarmGame = world.game
	var hud: FarmHud = world.hud
	_check(context.test_clock != null and context.test_clock.speed == 60, "默认 60 倍农场时钟")
	_check(context.save_path == FarmTestMode.SAVE_PATH and game.state["coins"] == 321, "首次测试复制正式进度，写入独立档")
	_check(game.state["seeds"][0]["traits"] == normal.state["seeds"][0]["traits"], "复制进度保留育种词条")
	_check(hud.find_child("FarmTestControls", true, false) != null, "测试农场显示倍率与成熟按钮")
	_check(Engine.time_scale == 1.0, "动画与战斗速度保持正常")
	await _shot("03_farm_controls")

	var clock_start := context.now()
	await _wait_real(0.15)
	_check(context.now() - clock_start >= 8, "真实时间 0.15 秒推进约 9 秒农场时间")
	var before_change := context.now()
	var speed := hud.find_child("TestSpeedSelect", true, false) as OptionButton
	speed.select(3)
	speed.item_selected.emit(3)
	_check(context.test_clock.speed == 1200 and context.now() >= before_change, "切换 1200 倍不中断、不倒退时间")
	_check(SaveStore.load_state(FarmTestMode.SAVE_PATH).get("test_clock", {}).get("speed", 0) == 1200, "倍率保存到测试档")

	var seed_id := int(game.state["seeds"][0]["id"])
	world._on_plant_seed_requested(1, seed_id)
	_check(not game.is_ready(1, context.now()), "播种后正常经历生长阶段")
	await _wait_real(1.2)
	_check(game.is_ready(1, context.now()), "1200 倍下白菜约 1 秒自然成熟")
	world._do_harvest(1)
	_check(game.get_plot(1)["seed_id"] == 0 and not game.state["crop_batches"].is_empty(), "加速成熟后正常收获作物与新种子")
	hud.close_modal_after_action()
	world._on_plant_seed_requested(2, int(game.state["seeds"][0]["id"]))
	await _click(hud.find_child("TestMatureButton", true, false) as Button)
	_check(game.is_ready(2, context.now()), "真实点击让正在生长的作物立即成熟")
	world._on_clock_tick()
	_check(hud.harvest_all_entry.visible, "成熟后显示一键收获入口")
	await _shot("04_mature")

	# 真实加速时钟完成复制，同时验证育种面板原位刷新。
	game.state["breeder"]["owned"] = true
	var template_id := int(game.state["seeds"][0]["id"])
	_check(game.set_breeder_template(template_id, context.now())["ok"], "设置育种模板")
	hud.open_breeder()
	var collect_button := hud.breeder_collect_button
	_check(collect_button.disabled, "产种前领取按钮禁用")
	await _wait_real(3.2)
	world._on_clock_tick()
	_check(int(game.state["breeder"]["pending"]) >= 1, "育种机共享 1200 倍时钟，约 3 秒复制一粒")
	_check(hud.breeder_collect_button == collect_button and not collect_button.disabled, "育种产出原位刷新领取按钮")
	await _shot("05_breeder_ready")
	await _click(collect_button)
	_check(int(game.state["breeder"]["pending"]) == 0, "真实点击领取加速育种结果")
	hud.close_modal_after_action()
	hud.open_room()
	_check(not hud.room_panel.visible, "测试进度不会进入好友房间")
	game.state["coins"] = 654
	context.test_clock.set_speed(1)
	_check(world._save(), "测试档保存成功")
	var saved_time := context.now()
	hud._on_pause_back_to_menu()
	await _frames(5)
	menu = current_scene as MainMenu
	_check(menu != null and menu.test_mode_button.button_pressed, "返回主菜单保留测试开关")
	await _click(menu.continue_button)
	await _frames(5)
	world = current_scene
	context = world.context
	_check(world.game.state["coins"] == 654 and context.test_clock.speed == 1, "重进测试保留进度与倍率")
	_check(context.now() >= saved_time and context.now() <= saved_time + 3, "重进测试恢复虚拟时间，不跳回系统时钟")
	world.hud._on_pause_back_to_menu()
	await _frames(5)
	menu = current_scene as MainMenu
	await _click(menu.test_mode_button)
	_check(not FarmTestMode.enabled and not (menu.find_child("OnlineButton", true, false) as Button).disabled, "关闭测试恢复普通入口")
	await _click(menu.continue_button)
	await _frames(5)
	world = current_scene
	_check(world.context.test_clock == null and world.game.state["coins"] == 321, "关闭测试后读回正式进度与现实时间")
	_check(world.hud.find_child("FarmTestControls", true, false) == null, "普通农场隐藏测试控件")
	_check(FileAccess.get_file_as_bytes(SaveStore.SAVE_PATH) == normal_bytes, "测试全流程未改动正式存档")
	world.queue_free()
	current_scene = null
	await _frames(3)
	FarmTestMode.enabled = true
	GameFlow.mode = GameFlow.Mode.NEW_GAME
	var fresh_context := GameContext.create()
	fresh_context.boot()
	_check(fresh_context.game.state["coins"] == 0 and fresh_context.test_clock.speed == 60, "新测试从初始进度与默认倍率开始")
	_check(SaveStore.load_backup_state(FarmTestMode.SAVE_PATH).get("coins", -1) == 654, "开始新测试时旧测试进度备份")
	_check(FileAccess.get_file_as_bytes(SaveStore.SAVE_PATH) == normal_bytes, "开始新测试也不会覆盖正式档")
	GameFlow.mode = GameFlow.Mode.ONLINE
	FarmTestMode.enabled = true
	var online_context := GameContext.create()
	_check(online_context.test_clock == null, "线上模式始终使用服务器时钟")
	_cleanup()


func _click(button: Button) -> void:
	_check(button != null and button.is_visible_in_tree() and not button.disabled, "真实输入目标可点击")
	if button == null:
		return
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await _frames(2)
	if DisplayServer.get_name() != "headless":
		_check(root.gui_get_hovered_control() == button, "鼠标命中按钮，无遮挡")
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await _frames(2)


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _wait_real(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		await create_timer(0.025).timeout


func _shot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _frames(3)
	await RenderingServer.frame_post_draw
	var directory := "res://screenshots/farm_test_2026-10-13"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.get_texture().get_image().save_png(directory.path_join(filename + ".png"))


func _cleanup() -> void:
	GameFlow.reset()
	FarmTestMode.enabled = false
	for filename in FILES:
		var path: String = "user://" + filename
		if backup.has(filename):
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(backup[filename])
			file.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("D60_FARM_TEST_MODE_FAIL" if failed else "D60_FARM_TEST_MODE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
