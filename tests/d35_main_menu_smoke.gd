extends SceneTree
## 主菜单轮 d35：启动首页（继续/新游戏/设置/退出）与 farm_world 的模式分流。
## 覆盖：无档禁用继续、存档摘要、新游戏覆盖确认与 .bak 备份、
## 设置页（窗口模式/重播引导/中继地址持久化）、ESC 返回主按钮页、
## tutorial_step 重播消费（GameFlow 与 settings.cfg 两个来源）。
## 运行前后备份/恢复真实存档与设置文件（与 d33 的隔离约定一致）。


var failed := false
const SAVE_FILES := ["farm_save_v1.json", "farm_save_v1.json.bak"]
const PREF_FILES := ["settings.cfg", "relay_prefs.cfg"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var backup := _backup_files(SAVE_FILES)
	var prefs_backup := _backup_files(PREF_FILES)
	_remove_files(SAVE_FILES)
	_remove_files(PREF_FILES)
	GameFlow.reset()

	# —— 无档：继续按钮禁用，其余按钮存在 ——
	var menu: MainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var continue_button := menu.find_child("ContinueButton", true, false) as Button
	_check(continue_button != null, "继续按钮存在")
	_check(continue_button.disabled, "无档时继续按钮禁用")
	_check("暂无存档" in continue_button.text, "无档文案提示暂无存档")
	_check(menu.find_child("NewGameButton", true, false) != null, "新游戏按钮存在")
	_check(menu.find_child("QuitButton", true, false) != null, "退出按钮存在")

	# —— 设置页：中继地址持久化（合法/非法）、重播引导写 cfg 与 GameFlow ——
	(menu.find_child("SettingsButton", true, false) as Button).pressed.emit()
	await process_frame
	var settings_view := menu.find_child("SettingsView", true, false) as Control
	_check(settings_view.visible, "设置页打开")
	var relay_edit := menu.find_child("RelayAddressEdit", true, false) as LineEdit
	relay_edit.text = "abc"
	menu._on_relay_address_save()
	_check("格式不对" in menu.settings_hint.text, "非法中继地址被拒绝")
	relay_edit.text = "10.1.2.3:31970"
	menu._on_relay_address_save()
	var relay_config := ConfigFile.new()
	relay_config.load("user://relay_prefs.cfg")
	_check(str(relay_config.get_value("relay", "address", "")) == "10.1.2.3:31970", "合法中继地址写入 relay_prefs.cfg（与房间页共用）")
	var replay_check := menu.find_child("TutorialReplayCheck", true, false) as CheckButton
	replay_check.button_pressed = true
	var settings_config := ConfigFile.new()
	settings_config.load("user://settings.cfg")
	_check(bool(settings_config.get_value("tutorial", "replay", false)), "重播引导写入 settings.cfg")
	_check(GameFlow.reset_tutorial, "重播引导同步 GameFlow 标志")
	replay_check.button_pressed = false
	var cleared_config := ConfigFile.new()
	cleared_config.load("user://settings.cfg")
	_check(not bool(cleared_config.get_value("tutorial", "replay", true)), "关掉重播引导写回 false")
	GameFlow.reset()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	menu._unhandled_key_input(esc)
	_check(menu.find_child("MainMenuView", true, false).visible and not settings_view.visible, "设置页 ESC 返回主按钮页")
	GameFlow.reset()

	# —— 有档：继续按钮启用且摘要正确；新游戏先弹覆盖确认 ——
	var now := int(Time.get_unix_time_from_system())
	var seeded := FarmGame.new()
	seeded.new_game(now)
	seeded.state["coins"] = 999
	seeded.state["created_at"] = now - 3 * 86400
	seeded.state["tutorial_step"] = 99
	SaveStore.save_state(seeded.state)
	menu._refresh_continue_summary()
	_check(not continue_button.disabled, "有档时继续按钮启用")
	_check("第 4 天" in continue_button.text and "金币 999" in continue_button.text, "继续按钮显示存档摘要（第 4 天 · 金币 999）")
	(menu.find_child("NewGameButton", true, false) as Button).pressed.emit()
	await process_frame
	var confirm_view := menu.find_child("ConfirmView", true, false) as Control
	_check(confirm_view.visible and not menu.find_child("MainMenuView", true, false).visible, "已有档时新游戏先弹覆盖确认")

	# —— 确认覆盖：真实走 change_scene_to_file 进农场，旧档进 .bak ——
	(menu.find_child("ConfirmNewGameButton", true, false) as Button).pressed.emit()
	await process_frame
	await process_frame
	var world := current_scene as Node3D
	_check(world != null and world.get("game") != null, "确认后切换进农场世界")
	if world != null and world.get("game") != null:
		_check(int(world.game.state["coins"]) == 0, "新游戏模式不读旧档（金币回到 0）")
		_check(int(world.game.state["tutorial_step"]) == 0, "新档引导从头开始")
		_check(GameFlow.mode == GameFlow.Mode.AUTO, "farm_world 消费后 GameFlow 复位")
		var backup_state: Dictionary = SaveStore.load_backup_state()
		_check(int(backup_state.get("coins", -1)) == 999, "旧档 999 自动进 .bak 备份")
	world.queue_free()
	current_scene = null
	await process_frame

	# —— 继续模式 + cfg 重播引导：tutorial_step 归零且标志消费即清 ——
	var continued := FarmGame.new()
	continued.new_game(now)
	continued.state["tutorial_step"] = 99
	SaveStore.save_state(continued.state)
	var clear_config := ConfigFile.new()
	clear_config.set_value("tutorial", "replay", true)
	clear_config.save("user://settings.cfg")
	GameFlow.mode = GameFlow.Mode.CONTINUE
	GameFlow.reset_tutorial = false
	var world2: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world2)
	await process_frame
	await process_frame
	_check(int(world2.game.state["tutorial_step"]) == 0, "cfg 重播标志：读档后引导归零")
	var after_config := ConfigFile.new()
	after_config.load("user://settings.cfg")
	_check(not bool(after_config.get_value("tutorial", "replay", true)), "cfg 重播标志消费即清（下次不再重播）")
	_check(GameFlow.mode == GameFlow.Mode.AUTO and not GameFlow.reset_tutorial, "消费后 GameFlow 全复位")
	world2.queue_free()
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
	for save_name in ["farm_save_v1.json", "farm_save_v1.json.bak", "settings.cfg", "relay_prefs.cfg"]:
		if not backup.has(str(save_name)) and dir != null and FileAccess.file_exists("user://" + str(save_name)):
			dir.remove(str(save_name))


func _finish() -> void:
	if failed:
		push_error("D35_MAIN_MENU_FAIL")
	else:
		print("D35_MAIN_MENU_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
