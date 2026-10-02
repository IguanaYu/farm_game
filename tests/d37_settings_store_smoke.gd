extends SceneTree
## 流程轮 d37：设置服务（SettingsStore）与音频总线。
## 覆盖：总线布局三总线、无 cfg 时默认值、写读 round-trip、apply_volumes 生效
## （dB 换算与静音）、apply_window_settings 安全调用、旧 cfg（仅 fullscreen）兼容。
## 运行前后备份/恢复真实 settings.cfg（与 d36 的隔离约定一致）。


var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var had_settings := FileAccess.file_exists("user://settings.cfg")
	var backup := FileAccess.get_file_as_bytes("user://settings.cfg") if had_settings else PackedByteArray()
	_remove_settings()

	# —— 总线布局：Master/Music/SFX 三条 ——
	_check(AudioServer.get_bus_index("Master") >= 0, "Master 总线存在")
	var music_index := AudioServer.get_bus_index("Music")
	var sfx_index := AudioServer.get_bus_index("SFX")
	_check(music_index > 0 and sfx_index > 0 and music_index != sfx_index, "Music 与 SFX 子总线存在")

	# —— 默认值（无 cfg）——
	_check(not SettingsStore.get_fullscreen(), "默认窗口化")
	_check(SettingsStore.get_vsync(), "默认开垂直同步")
	_check(SettingsStore.get_window_size() == Vector2i(1280, 800), "默认窗口尺寸 1280×800")
	_check(is_equal_approx(SettingsStore.get_volume("Master"), 1.0), "默认主音量 1.0")
	_check(not SettingsStore.get_tutorial_replay(), "默认不重播引导")

	# —— 写读 round-trip ——
	SettingsStore.set_fullscreen(true)
	SettingsStore.set_window_size(Vector2i(1920, 1200))
	SettingsStore.set_vsync(false)
	SettingsStore.set_volume("Music", 0.5)
	SettingsStore.set_tutorial_replay(true)
	_check(SettingsStore.get_fullscreen(), "全屏写读一致")
	_check(SettingsStore.get_window_size() == Vector2i(1920, 1200), "窗口尺寸写读一致")
	_check(not SettingsStore.get_vsync(), "垂直同步关闭写读一致")
	_check(is_equal_approx(SettingsStore.get_volume("Music"), 0.5), "音量线性 0.5 写读一致")
	_check(SettingsStore.get_tutorial_replay(), "重播引导写读一致")

	# —— apply_volumes 生效：dB 换算 + 零音量静音 ——
	SettingsStore.set_volume("Master", 0.25)
	SettingsStore.set_volume("Music", 0.5)
	SettingsStore.set_volume("SFX", 0.0)
	SettingsStore.apply_volumes()
	_check(absf(AudioServer.get_bus_volume_db(music_index) - linear_to_db(0.5)) < 0.01, "Music 总线音量 = linear_to_db(0.5)")
	_check(not AudioServer.is_bus_mute(music_index), "音量 >0 时 Music 不静音")
	_check(AudioServer.is_bus_mute(sfx_index), "音量 0 → SFX 总线静音")

	# —— 窗口设置应用（headless 下为安全空调用）与版本号 ——
	SettingsStore.apply_window_settings()
	_check(not SettingsStore.game_version().is_empty() and SettingsStore.game_version() != "0.0.0", "版本号可读取（%s）" % SettingsStore.game_version())

	# —— 旧 cfg 兼容：只有主菜单轮的 fullscreen 键 ——
	_remove_settings()
	var legacy := ConfigFile.new()
	legacy.set_value("window", "fullscreen", true)
	legacy.save("user://settings.cfg")
	_check(SettingsStore.get_fullscreen() and SettingsStore.get_vsync() and is_equal_approx(SettingsStore.get_volume("Master"), 1.0), "旧 cfg（仅 fullscreen）读取得通，其余走默认")

	# —— 恢复 ——
	if had_settings:
		var file := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		file.store_buffer(backup)
		file.close()
	else:
		_remove_settings()
	_finish()


func _remove_settings() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and FileAccess.file_exists("user://settings.cfg"):
		dir.remove("settings.cfg")


func _finish() -> void:
	if failed:
		push_error("D37_SETTINGS_STORE_FAIL")
	else:
		print("D37_SETTINGS_STORE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
