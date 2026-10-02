extends SceneTree
## 主菜单轮 d36：游戏内 ESC 暂停菜单。
## 覆盖：默认 AUTO 直启不回归、ESC 开/关暂停、设置子视图与退出游戏按钮、
## 设置子视图 ESC 先返回主视图、模态与面板打开时 ESC 让位、
## 联机占用时"回到主菜单"置灰、正常路径点按钮切回主菜单场景。
## 运行前后备份/恢复真实存档（与 d33 的隔离约定一致）。


var failed := false
const SAVE_FILES := ["farm_save_v1.json", "farm_save_v1.json.bak"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var backup := _backup_saves()
	_remove_saves()
	GameFlow.reset()

	# —— 默认 AUTO 直启农场（既有直启路径不回归）——
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	await process_frame
	await process_frame
	var hud: FarmHud = world.hud
	_check(hud != null and world.game != null, "AUTO 直启农场正常（旧路径不回归）")

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true

	# —— ESC 开暂停 / 再按 ESC 关闭 ——
	hud._unhandled_key_input(esc)
	_check(hud.pause_overlay.visible, "ESC 弹出暂停菜单")
	var resume_button := hud.find_child("PauseResumeButton", true, false) as Button
	var back_button := hud.find_child("PauseBackToMenuButton", true, false) as Button
	_check(resume_button != null and back_button != null, "暂停菜单按钮存在")
	_check(not back_button.disabled, "非联机时回到主菜单可用")
	hud._unhandled_key_input(esc)
	_check(not hud.pause_overlay.visible, "再按 ESC 关闭暂停菜单")
	resume_button.pressed.emit()
	_check(not hud.pause_overlay.visible, "继续按钮同样关闭暂停")

	# —— 设置与退出游戏按钮；设置子视图的 ESC 层级 ——
	var settings_button := hud.find_child("PauseSettingsButton", true, false) as Button
	var quit_button := hud.find_child("PauseQuitButton", true, false) as Button
	_check(settings_button != null and quit_button != null, "暂停菜单含设置与退出游戏按钮")
	hud._unhandled_key_input(esc)
	_check(hud.pause_overlay.visible, "再次 ESC 打开暂停")
	settings_button.pressed.emit()
	var pause_settings := hud.find_child("PauseSettingsView", true, false) as Control
	_check(pause_settings.visible, "设置子视图打开（含共用 SettingsView）")
	hud._unhandled_key_input(esc)
	_check(not pause_settings.visible and hud.pause_overlay.visible, "设置子视图 ESC 返回暂停主视图（不关暂停）")
	hud._unhandled_key_input(esc)
	_check(not hud.pause_overlay.visible, "暂停主视图 ESC 关闭暂停")

	# —— 模态打开时 ESC 让位（不弹暂停）——
	hud.open_shop()
	hud._unhandled_key_input(esc)
	_check(not hud.pause_overlay.visible, "商店模态打开时 ESC 不弹暂停")
	hud._close_modal()

	# —— 探险面板打开时 ESC 让位 ——
	hud.open_expedition_hub()
	await process_frame
	hud._unhandled_key_input(esc)
	_check(not hud.pause_overlay.visible, "探险面板打开时 ESC 不弹暂停")
	hud.close_expedition_panels()

	# —— 联机占用：回到主菜单置灰并提示 ——
	hud.room_panel.host = SessionHost.new()
	hud._unhandled_key_input(esc)
	_check(hud.pause_overlay.visible, "联机占用时 ESC 仍可暂停查看")
	_check(back_button.disabled and "联机" in back_button.tooltip_text, "联机占用时回到主菜单置灰并说明原因")
	hud._close_pause()
	hud.room_panel.host = null

	# —— 正常路径：回到主菜单切换场景 ——
	hud._unhandled_key_input(esc)
	back_button.pressed.emit()
	await process_frame
	await process_frame
	var menu := current_scene as MainMenu
	_check(menu != null and menu.name == "MainMenu", "回到主菜单按钮切换回主菜单场景")
	if menu != null:
		var continue_button := menu.find_child("ContinueButton", true, false) as Button
		_check(continue_button != null and not continue_button.disabled, "主菜单继续按钮可用（新档已落盘）")

	await process_frame
	_restore_saves(backup)
	_finish()


func _backup_saves() -> Dictionary:
	var backup := {}
	for save_name in SAVE_FILES:
		var path: String = "user://" + str(save_name)
		if FileAccess.file_exists(path):
			backup[str(save_name)] = FileAccess.get_file_as_bytes(path)
	return backup


func _remove_saves() -> void:
	var dir := DirAccess.open("user://")
	for save_name in SAVE_FILES:
		if dir != null and FileAccess.file_exists("user://" + str(save_name)):
			dir.remove(str(save_name))


func _restore_saves(backup: Dictionary) -> void:
	var dir := DirAccess.open("user://")
	for save_name in SAVE_FILES:
		var path: String = "user://" + str(save_name)
		if backup.has(str(save_name)):
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(backup[str(save_name)])
			file.close()
		elif FileAccess.file_exists(path) and dir != null:
			dir.remove(str(save_name))


func _finish() -> void:
	if failed:
		push_error("D36_PAUSE_MENU_FAIL")
	else:
		print("D36_PAUSE_MENU_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
