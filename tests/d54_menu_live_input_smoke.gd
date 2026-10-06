extends SceneTree
## 菜单真实输入链路测试 d54：主菜单 → 设置（点击开/ESC 回）→ 新游戏覆盖确认（点击开/按钮回）
## → 继续游戏（点击）→ 农场 ESC 暂停（合成键走完整输入链）→ 继续（点击）/设置子页（点击开/按钮回）
## → 回到主菜单（点击）→ 退出游戏（真实点击，进程退出即通过）。
## 与 d35/d36 的直调式（pressed.emit / _unhandled_key_input 直呼）互补：本脚本全部走真实输入注入——
## 鼠标 = warp_mouse + InputEventMouseMotion + press/release（root.push_input），
## 且 headless 外先断言 gui_get_hovered_control 命中目标按钮（同时证明无遮挡）；
## 键盘 = 合成 ESC press/release 走 root.push_input 完整输入链（非直呼回调）。
## 证据两类分开：live_* = 真实输入驱动后的状态；fixture_* = 未经输入的初始状态（线上演示用 fixture 口径）。
## headless（回归）下无渲染：跳过截图与 hover 断言，输入注入与结果断言照常执行。
## 运行前后备份/恢复存档与偏好文件（与 d35 的隔离约定一致）。


var failed := false
var out_dir := ""
var menu2: MainMenu = null

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
	var can_render: bool = DisplayServer.get_name() != "headless"
	if can_render:
		out_dir = ProjectSettings.globalize_path("res://").path_join("screenshots/menu_live_20261004")
		DirAccess.make_dir_recursive_absolute(out_dir)

	# 种子档：3 天前建号、999 金、引导已完成 → 继续按钮可用、进世界不弹引导。
	var now := int(Time.get_unix_time_from_system())
	var seeded := FarmGame.new()
	seeded.new_game(now)
	seeded.state["coins"] = 999
	seeded.state["created_at"] = now - 3 * 86400
	seeded.state["tutorial_step"] = 99
	SaveStore.save_state(seeded.state)

	# —— 主菜单初始状态（fixture 证据，无输入驱动）——
	var menu: MainMenu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu
	await _frames(3)
	var continue_button := menu.find_child("ContinueButton", true, false) as Button
	_check(continue_button != null and not continue_button.disabled, "有档时继续按钮可用")
	await _shot("fixture_01_main_menu_home", "初始主菜单（无输入驱动）")

	# —— 设置：真实点击打开 → 真实 ESC 返回 ——
	await _click_button(menu.find_child("SettingsButton", true, false) as Button, "主菜单·设置按钮")
	var settings_view := menu.find_child("SettingsView", true, false) as Control
	_check(settings_view != null and settings_view.visible, "真实点击后设置页可见")
	await _shot("live_02_settings_opened_by_click", "主菜单·设置页（真实点击打开）")
	await _press_pause_key()
	_check(settings_view != null and not settings_view.visible and menu.find_child("MainMenuView", true, false).visible, "设置页真实 ESC 返回主按钮页")

	# —— 新游戏：真实点击弹覆盖确认 → 真实点击返回 ——
	await _click_button(menu.find_child("NewGameButton", true, false) as Button, "主菜单·开始新游戏按钮")
	var confirm_view := menu.find_child("ConfirmView", true, false) as Control
	_check(confirm_view != null and confirm_view.visible, "有档时新游戏真实点击弹出覆盖确认")
	await _shot("live_03_new_game_confirm_by_click", "主菜单·覆盖确认页（真实点击打开）")
	await _click_button(_find_back_button(menu.confirm_view), "确认页·返回按钮")
	_check(confirm_view != null and not confirm_view.visible, "确认页真实点击返回后关闭")

	# —— 继续游戏：真实点击 → 场景切进农场 → 读档正确 ——
	await _click_button(continue_button, "主菜单·继续游戏按钮")
	var world: Node3D = null
	for i in range(150):
		await process_frame
		var scene := current_scene
		if scene != null and scene != menu and scene is Node3D and scene.get("game") != null:
			world = scene
			break
	_check(world != null, "真实点击继续后切进农场世界")
	if world != null:
		_check(int(world.game.state["coins"]) == 999, "继续模式读种子档（金币 999）")
		_check(GameFlow.mode == GameFlow.Mode.AUTO, "farm_world 消费模式后 GameFlow 复位")
		await _pause_round_trip(world)

	# —— 收尾：恢复存档/偏好 → 真实点击"退出游戏" → 进程退出码 0 即通过 ——
	_restore_files(backup)
	_restore_files(prefs_backup)
	if failed or menu2 == null:
		push_error("D54_MENU_LIVE_FAIL")
		quit(1)
		return
	print("D54_MENU_LIVE_PASS")
	await _click_button(menu2.find_child("QuitButton", true, false) as Button, "主菜单·退出游戏按钮")
	for i in range(150):
		await process_frame
	push_error("  FAIL: 退出按钮真实点击后进程未退出")
	print("D54_MENU_LIVE_FAIL")
	quit(1)


## 游戏内暂停菜单整圈：ESC 弹出 → 点继续关闭 → ESC 再弹 → 点开设置子页 → 点返回 → 点回到主菜单。
func _pause_round_trip(world: Node3D) -> void:
	var hud: FarmHud = world.get("hud")
	_check(hud != null, "农场 HUD 就绪")
	if hud == null:
		return
	await _press_pause_key()
	_check(hud.pause_overlay.visible, "真实 ESC 输入弹出暂停菜单")
	await _shot("live_04_pause_opened_by_esc", "游戏内暂停菜单（真实 ESC 输入）")
	await _click_button(hud.find_child("PauseResumeButton", true, false) as Button, "暂停·继续游戏按钮")
	_check(not hud.pause_overlay.visible, "真实点击继续后暂停关闭")
	await _press_pause_key()
	_check(hud.pause_overlay.visible, "再次真实 ESC 重新弹出暂停")
	await _click_button(hud.find_child("PauseSettingsButton", true, false) as Button, "暂停·设置按钮")
	var pause_settings := hud.find_child("PauseSettingsView", true, false) as Control
	_check(pause_settings != null and pause_settings.visible, "真实点击后暂停设置子页可见")
	await _shot("live_05_pause_settings_by_click", "暂停菜单·设置子页（真实点击打开）")
	await _click_button(hud.find_child("PauseSettingsBackButton", true, false) as Button, "暂停设置·返回按钮")
	_check(pause_settings != null and not pause_settings.visible and hud.pause_overlay.visible, "设置子页真实点击返回后回暂停主视图")
	await _click_button(hud.find_child("PauseBackToMenuButton", true, false) as Button, "暂停·回到主菜单按钮")
	for i in range(150):
		await process_frame
		var scene := current_scene
		if scene != null and scene != world and scene is MainMenu:
			menu2 = scene
			break
	_check(menu2 != null, "真实点击回到主菜单后场景切回")
	if menu2 != null:
		var back_continue := menu2.find_child("ContinueButton", true, false) as Button
		_check(back_continue != null and not back_continue.disabled, "回到主菜单后继续按钮可用")
		await _shot("live_06_back_to_main_menu", "回到主菜单（真实点击）")


# —— 真实输入注入 ——————————————————————————————————————————————


## 移动鼠标到按钮中心并断言 hover 命中目标（命中别的控件 = 被遮挡，点击不算数）。
func _hover_center(button: Button, label: String) -> void:
	var center := button.get_global_rect().get_center()
	root.warp_mouse(center)
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion, true)
	await process_frame
	var hovered: Control = root.gui_get_hovered_control()
	if hovered == null:
		_check(false, label + "：鼠标移到中心后无 hover 目标（被遮挡或不可见）")
	elif hovered != button and not button.is_ancestor_of(hovered):
		_check(false, label + "：hover 命中的不是目标按钮（被 " + str(hovered.get_path()) + " 挡住）")


## 真实点击：move → press → release 全走 root.push_input；headless 外先做 hover 命中断言。
func _click_button(button: Button, label: String) -> void:
	if button == null:
		_check(false, label + "：按钮不存在")
		return
	_check(button.is_visible_in_tree() and not button.disabled, label + "：可点击前提（可见且未禁用）")
	var center := button.get_global_rect().get_center()
	if DisplayServer.get_name() != "headless":
		# 窗口内与 hover 命中都是视觉证据类断言：headless 无窗口（root.size 为 0）、无 hover 状态，只在带窗口时检查。
		_check(Rect2(Vector2.ZERO, Vector2(root.size)).grow(-2).has_point(center), label + "：按钮中心在窗口内")
		await _hover_center(button, label)
	root.warp_mouse(center)
	var press := InputEventMouseButton.new()
	press.position = center
	press.global_position = center
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await _frames(2)


## 合成 ESC press/release 走完整输入链（不直呼 _unhandled_key_input）。
func _press_pause_key() -> void:
	var press := InputEventKey.new()
	press.keycode = KEY_ESCAPE
	press.pressed = true
	root.push_input(press, true)
	await process_frame
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame


# —— 截图与证据 ——————————————————————————————————————————————————


## 带 window 运行才截图；tag 前缀 live_/fixture_ 区分证据来源。
func _shot(tag: String, note: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(out_dir.path_join(tag + ".png"))
	print("SHOT " + tag + " | " + note)


# —— 存档隔离（d35 约定）———————————————————————————————————————


func _find_back_button(view: VBoxContainer) -> Button:
	if view == null:
		return null
	for child in view.get_children():
		if child is Button and (child as Button).text == "返回":
			return child
	return null


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


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
