extends SceneTree
## M1 线上登录面板截图验证（需带窗口运行，不入回归）：打开主菜单 → 切线上农场视图 → 截图。
## 用于修复"控件溢出卡片错位"后的可视复核；附布局断言（面板必须包住全部子控件、兄弟不重叠）。
## 用法：Godot --path . --script res://tests/capture_m1_online_login.gd

var shot_path := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var project_dir := ProjectSettings.globalize_path("res://")
	DirAccess.make_dir_recursive_absolute(project_dir.path_join(".zcode/m1/run"))
	shot_path = project_dir.path_join(".zcode/m1/run/capture_m1_online_login.png")
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	var online_button: Button = menu.find_children("OnlineButton", "Button", true, false)[0]
	online_button.pressed.emit()
	await process_frame
	await process_frame
	# 布局断言：登录面板（VBox）必须完整包住每个可见子控件；兄弟控件矩形不得互相重叠
	var panel: Control = menu.find_children("OnlinePanel", "VBoxContainer", true, false)[0]
	var widgets: Array = []
	var out_panel := 0
	for child in panel.find_children("*", "Control", true, false):
		if not child.is_visible_in_tree() or not (child is Label or child is LineEdit or child is Button):
			continue
		widgets.append(child)
		if not panel.get_global_rect().encloses(child.get_global_rect()):
			out_panel += 1
			print("LAYOUT-OUT-OF-PANEL ", child.name, " ", child.get_global_rect())
	var overlaps := 0
	for i in range(widgets.size()):
		for j in range(i + 1, widgets.size()):
			if (widgets[i] as Control).get_global_rect().intersects((widgets[j] as Control).get_global_rect()):
				overlaps += 1
				print("LAYOUT-OVERLAP ", (widgets[i] as Control).name, " × ", (widgets[j] as Control).name)
	var viewport_out := 0
	for widget in widgets:
		var rect: Rect2 = (widget as Control).get_global_rect()
		if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > root.get_viewport().size.x or rect.end.y > root.get_viewport().size.y:
			viewport_out += 1
			print("LAYOUT-OUT-OF-VIEWPORT ", (widget as Control).name, " ", rect)
	print("LAYOUT widgets=%d out_of_panel=%d overlaps=%d out_of_viewport=%d panel_size=%s" % [widgets.size(), out_panel, overlaps, viewport_out, panel.size])
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(shot_path)
	print("SHOT ", shot_path)
	var ok := out_panel == 0 and overlaps == 0 and viewport_out == 0 and widgets.size() >= 5
	quit(0 if ok else 1)
