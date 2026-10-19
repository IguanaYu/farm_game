extends SceneTree
## 森林第一章 P0 截图：五区占位预览与主菜单入口（需真实窗口运行，回归收集器跳过 capture_）。
## 运行：Godot（非 headless）--path . --script res://tests/capture_forest_preview.gd

const OUT_DIR := "res://screenshots/forest_ch1_p0_2026-10-19"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1024, 640)
	root.content_scale_size = Vector2i(1024, 640)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1024, 640))
	# 主菜单（测试功能关）：森林预览按钮隐藏。
	var menu: Control = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu
	await _frames(4)
	await _shot("01_menu_test_off")
	# 打开测试功能：森林预览按钮出现。
	var toggle := menu.find_child("TestModeButton", true, false) as Button
	toggle.button_pressed = true
	await _frames(2)
	await _shot("02_menu_test_on")
	# 进入五区占位预览。
	menu.find_child("ForestPreviewButton", true, false).pressed.emit()
	await _frames(6)
	await _shot("03_chapter_preview_top")
	# 滚到预览底部，确认湿地卡片完整。
	var scroll := root.find_child("PreviewScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await _frames(3)
	await _shot("04_chapter_preview_bottom")
	# 返回主菜单（验证回程链路）。
	root.find_child("BackButton", true, false).pressed.emit()
	await _frames(4)
	var back_ok := root.find_child("MainMenuView", true, false) != null
	print("CAPTURE_FOREST_PREVIEW_%s" % ("PASS" if back_ok else "FAIL"))
	_cleanup()
	quit(0 if back_ok else 1)


func _shot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _frames(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	root.get_texture().get_image().save_png(OUT_DIR.path_join(filename + ".png"))
	print("  shot: " + filename)


func _cleanup() -> void:
	GameFlow.reset()


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame
