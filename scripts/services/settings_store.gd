class_name SettingsStore
extends RefCounted
## user://settings.cfg 的统一读写与生效（项目无 autoload，静态类模式与 SaveStore 一致）。
## 键结构：[window] fullscreen / width / height / vsync；[audio] master / music / sfx（0~1 线性）；
## [tutorial] replay（沿用主菜单轮既有键，旧 cfg 直接兼容）。
## 联机服务器地址仍走 relay_prefs.cfg（RoomPanel 共用，不搬家）。

const SETTINGS_PATH := "user://settings.cfg"
const VOLUME_BUSES := ["Master", "Music", "SFX"]
## 设置页分辨率下拉的固定档位（16:10 为主，贴合 1440×900 设计分辨率）。
const RESOLUTIONS := [Vector2i(1280, 800), Vector2i(1440, 900), Vector2i(1680, 1050), Vector2i(1920, 1200)]


static func _load() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	return config


static func _save(config: ConfigFile) -> void:
	config.save(SETTINGS_PATH)


# —— 窗口 ——————————————————————————————————————————————————————

static func get_fullscreen() -> bool:
	return bool(_load().get_value("window", "fullscreen", false))


static func set_fullscreen(value: bool) -> void:
	var config := _load()
	config.set_value("window", "fullscreen", value)
	_save(config)


static func get_window_size() -> Vector2i:
	var config := _load()
	var width := int(config.get_value("window", "width", 1280))
	var height := int(config.get_value("window", "height", 800))
	if width <= 0 or height <= 0:
		return Vector2i(1280, 800)
	return Vector2i(width, height)


static func set_window_size(size: Vector2i) -> void:
	var config := _load()
	config.set_value("window", "width", size.x)
	config.set_value("window", "height", size.y)
	_save(config)


static func get_vsync() -> bool:
	return bool(_load().get_value("window", "vsync", true))


static func set_vsync(value: bool) -> void:
	var config := _load()
	config.set_value("window", "vsync", value)
	_save(config)


static func apply_window_settings() -> void:
	## 启动时由主菜单调用一次；headless 下 DisplayServer 各调用为安全空操作。
	if get_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(get_window_size())
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if get_vsync() else DisplayServer.VSYNC_DISABLED)


# —— 音量（存 0~1 线性；生效时转 dB，0 直接走总线静音） ———————————————————

static func get_volume(bus_name: String) -> float:
	return clampf(float(_load().get_value("audio", bus_name.to_lower(), 1.0)), 0.0, 1.0)


static func set_volume(bus_name: String, linear: float) -> void:
	var config := _load()
	config.set_value("audio", bus_name.to_lower(), clampf(linear, 0.0, 1.0))
	_save(config)


static func apply_volumes() -> void:
	for bus_name in VOLUME_BUSES:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			continue
		var linear := get_volume(bus_name)
		AudioServer.set_bus_mute(index, linear <= 0.001)
		if linear > 0.001:
			AudioServer.set_bus_volume_db(index, linear_to_db(linear))


# —— 新手引导重播（跨启动来源；本次会话来源在 GameFlow.reset_tutorial） ——————————

static func get_tutorial_replay() -> bool:
	return bool(_load().get_value("tutorial", "replay", false))


static func set_tutorial_replay(value: bool) -> void:
	var config := _load()
	config.set_value("tutorial", "replay", value)
	_save(config)


# —— 版本号 ————————————————————————————————————————————————————

static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
