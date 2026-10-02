extends SceneTree
## 流程轮 d38：主菜单"好友联机"直入房间页。
## 覆盖：好友联机按钮存在、点击后进农场并自动打开房间页、
## GameFlow 消费后复位、无档时兜底开新档、房间页关闭后回农场正常。
## 运行前后备份/恢复真实存档与设置文件（与 d35 的隔离约定一致）。


var failed := false
const SAVE_FILES := ["farm_save_v1.json", "farm_save_v1.json.bak"]
const PREF_FILES := ["settings.cfg"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var backup := _backup_files(SAVE_FILES)
	var prefs_backup := _backup_files(PREF_FILES)
	_remove_files(SAVE_FILES)
	_remove_files(PREF_FILES)
	GameFlow.reset()

	# —— 无档点好友联机：兜底开新档进农场，房间页自动打开 ——
	var menu: MainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var coop_button := menu.find_child("CoopButton", true, false) as Button
	_check(coop_button != null, "好友联机按钮存在")
	if coop_button == null:
		_restore_files(backup)
		_restore_files(prefs_backup)
		_finish()
		return
	coop_button.pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	var world := current_scene as Node3D
	_check(world != null and world.get("hud") != null, "点击后切换进农场世界")
	if world != null and world.get("hud") != null:
		var hud: FarmHud = world.hud
		_check(hud.room_panel.visible, "房间页已自动打开")
		_check(GameFlow.mode == GameFlow.Mode.AUTO and not GameFlow.open_room_on_entry, "GameFlow 消费后复位")
		_check(int(world.game.state["tutorial_step"]) == 0, "无档兜底开新档（引导从头开始）")
		hud.room_panel.close()
		_check(not hud.room_panel.visible, "房间页可关闭（正常回农场）")

	# —— 场景清理与恢复 ——
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	await process_frame
	_restore_files(backup)
	_restore_files(prefs_backup)
	_finish()


func _backup_files(names: Array) -> Dictionary:
	var backup := {}
	for save_name in names:
		var path: String = "user://" + str(save_name)
		if FileAccess.file_exists(path):
			backup[str(save_name)] = FileAccess.get_file_as_bytes(path)
	return backup


func _remove_files(names: Array) -> void:
	var dir := DirAccess.open("user://")
	for save_name in names:
		if dir != null and FileAccess.file_exists("user://" + str(save_name)):
			dir.remove(str(save_name))


func _restore_files(backup: Dictionary) -> void:
	var dir := DirAccess.open("user://")
	for save_name in backup.keys():
		var file := FileAccess.open("user://" + str(save_name), FileAccess.WRITE)
		file.store_buffer(backup[str(save_name)])
		file.close()
	for save_name in ["farm_save_v1.json", "farm_save_v1.json.bak", "settings.cfg"]:
		if not backup.has(str(save_name)) and dir != null and FileAccess.file_exists("user://" + str(save_name)):
			dir.remove(str(save_name))


func _finish() -> void:
	if failed:
		push_error("D38_MAIN_MENU_ROOM_FAIL")
	else:
		print("D38_MAIN_MENU_ROOM_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
