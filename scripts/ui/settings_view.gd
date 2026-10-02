class_name SettingsView
extends VBoxContainer
## 共用设置面板：主菜单"设置"子页与游戏内暂停菜单共用一套。
## 所有改动即时持久化（SettingsStore / relay_prefs.cfg）并即时生效（窗口 / 音频总线）。
## 宿主负责返回按钮，并在每次展示前调 refresh() 回填当前值。

const RELAY_PREFS_PATH := "user://relay_prefs.cfg"
const RELAY_DEFAULT_ADDRESS := "127.0.0.1:31970"
const TEXT_MAIN := Color("#35513d")
const TEXT_MUTED := Color("#5f6d63")
const ROW_LABEL_WIDTH := 92

var fullscreen_option: OptionButton
var resolution_option: OptionButton
var vsync_check: CheckButton
var tutorial_replay_check: CheckButton
var relay_address_edit: LineEdit
var hint_label: Label

var _volume_rows := {}


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_build()
	refresh()


func _build() -> void:
	var window_row := _row()
	window_row.add_child(_row_label("窗口模式"))
	fullscreen_option = OptionButton.new()
	fullscreen_option.name = "FullscreenOption"
	fullscreen_option.add_item("窗口化", 0)
	fullscreen_option.add_item("全屏", 1)
	fullscreen_option.item_selected.connect(_on_fullscreen_selected)
	window_row.add_child(fullscreen_option)
	add_child(window_row)

	var resolution_row := _row()
	resolution_row.add_child(_row_label("窗口尺寸"))
	resolution_option = OptionButton.new()
	resolution_option.name = "ResolutionOption"
	for size in SettingsStore.RESOLUTIONS:
		var value: Vector2i = size
		resolution_option.add_item("%d × %d" % [value.x, value.y])
	resolution_option.item_selected.connect(_on_resolution_selected)
	resolution_row.add_child(resolution_option)
	add_child(resolution_row)

	var vsync_row := _row()
	var vsync_label := _row_label("垂直同步")
	vsync_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vsync_row.add_child(vsync_label)
	vsync_check = CheckButton.new()
	vsync_check.name = "VsyncCheck"
	vsync_check.toggled.connect(_on_vsync_toggled)
	vsync_row.add_child(vsync_check)
	add_child(vsync_row)

	_build_volume_row("主音量", "MasterVolumeSlider", "Master")
	_build_volume_row("音乐", "MusicVolumeSlider", "Music")
	_build_volume_row("音效", "SfxVolumeSlider", "SFX")

	var tutorial_row := _row()
	var tutorial_label := _row_label("重新显示引导")
	tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_row.add_child(tutorial_label)
	tutorial_replay_check = CheckButton.new()
	tutorial_replay_check.name = "TutorialReplayCheck"
	tutorial_replay_check.toggled.connect(_on_tutorial_replay_toggled)
	tutorial_row.add_child(tutorial_replay_check)
	add_child(tutorial_row)
	var tutorial_hint := _label("开启后，下次进入农场时从头播放新手引导", 12, TEXT_MUTED)
	tutorial_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(tutorial_hint)

	var relay_title := _label("联机服务器地址（互联网房号模式用）", 14, TEXT_MAIN)
	add_child(relay_title)
	relay_address_edit = LineEdit.new()
	relay_address_edit.name = "RelayAddressEdit"
	relay_address_edit.placeholder_text = "IP:端口（如 1.2.3.4:31970）"
	add_child(relay_address_edit)
	var relay_save_button := Button.new()
	relay_save_button.name = "RelaySaveButton"
	relay_save_button.text = "保存联机服务器地址"
	relay_save_button.pressed.connect(save_relay_address)
	add_child(relay_save_button)
	hint_label = _label("", 12, Color("#396d50"))
	hint_label.name = "SettingsHint"
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint_label)


func _build_volume_row(title: String, slider_name: String, bus_name: String) -> void:
	var row := _row()
	row.add_child(_row_label(title))
	var slider := HSlider.new()
	slider.name = slider_name
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.custom_minimum_size.x = 170
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void: _on_volume_changed(bus_name, value))
	row.add_child(slider)
	var value_label := _label("100", 13, TEXT_MUTED)
	value_label.custom_minimum_size.x = 36
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	add_child(row)
	_volume_rows[bus_name] = {"slider": slider, "value": value_label}


# —— 回调：改动即时落库、即时生效 ————————————————————————————————

func _on_fullscreen_selected(index: int) -> void:
	SettingsStore.set_fullscreen(index == 1)
	SettingsStore.apply_window_settings()
	_sync_resolution_enabled()


func _on_resolution_selected(index: int) -> void:
	var size: Vector2i = SettingsStore.RESOLUTIONS[index]
	SettingsStore.set_window_size(size)
	if not SettingsStore.get_fullscreen():
		DisplayServer.window_set_size(size)


func _on_vsync_toggled(pressed: bool) -> void:
	SettingsStore.set_vsync(pressed)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if pressed else DisplayServer.VSYNC_DISABLED)


func _on_volume_changed(bus_name: String, value: float) -> void:
	SettingsStore.set_volume(bus_name, value / 100.0)
	SettingsStore.apply_volumes()
	var row_info: Dictionary = _volume_rows.get(bus_name, {})
	if not row_info.is_empty():
		(row_info["value"] as Label).text = str(int(value))


func _on_tutorial_replay_toggled(pressed: bool) -> void:
	## 与主菜单轮口径一致：cfg（跨启动）+ GameFlow（本次会话立即进农场）双写。
	SettingsStore.set_tutorial_replay(pressed)
	GameFlow.reset_tutorial = pressed


func save_relay_address() -> void:
	var address := relay_address_edit.text.strip_edges()
	var split := address.rsplit(":", false, 1)
	if address != "" and (split.size() != 2 or not str(split[1]).is_valid_int() or int(str(split[1])) <= 0 or int(str(split[1])) > 65535 or str(split[0]) == ""):
		hint_label.text = "地址格式不对，应为 IP:端口（如 1.2.3.4:31970）。"
		return
	if address == "":
		address = RELAY_DEFAULT_ADDRESS
	var config := ConfigFile.new()
	config.load(RELAY_PREFS_PATH)
	config.set_value("relay", "address", address)
	config.save(RELAY_PREFS_PATH)
	relay_address_edit.text = address
	hint_label.text = "联机服务器地址已保存（房间页会使用同一地址）。"


# —— 回填 ————————————————————————————————————————————————————

func refresh() -> void:
	fullscreen_option.selected = 1 if SettingsStore.get_fullscreen() else 0
	resolution_option.selected = _nearest_resolution_index(SettingsStore.get_window_size())
	vsync_check.set_pressed_no_signal(SettingsStore.get_vsync())
	for bus_name in ["Master", "Music", "SFX"]:
		var row_info: Dictionary = _volume_rows.get(bus_name, {})
		if row_info.is_empty():
			continue
		var linear := SettingsStore.get_volume(bus_name)
		(row_info["slider"] as HSlider).set_value_no_signal(linear * 100.0)
		(row_info["value"] as Label).text = str(int(round(linear * 100.0)))
	tutorial_replay_check.set_pressed_no_signal(SettingsStore.get_tutorial_replay())
	relay_address_edit.text = _load_relay_address()
	hint_label.text = ""
	_sync_resolution_enabled()


func _sync_resolution_enabled() -> void:
	resolution_option.disabled = fullscreen_option.selected == 1


func _nearest_resolution_index(size: Vector2i) -> int:
	var best := 0
	var best_distance := absi(size.x - SettingsStore.RESOLUTIONS[0].x)
	for index in SettingsStore.RESOLUTIONS.size():
		var distance := absi(size.x - SettingsStore.RESOLUTIONS[index].x)
		if distance < best_distance:
			best = index
			best_distance = distance
	return best


func _load_relay_address() -> String:
	var config := ConfigFile.new()
	if config.load(RELAY_PREFS_PATH) == OK and config.has_section_key("relay", "address"):
		var saved := str(config.get_value("relay", "address", ""))
		if saved != "":
			return saved
	return RELAY_DEFAULT_ADDRESS


# —— 小工具 ————————————————————————————————————————————————————

func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	return row


func _row_label(content: String) -> Label:
	var label := _label(content, 14, TEXT_MAIN)
	label.custom_minimum_size.x = ROW_LABEL_WIDTH
	return label


func _label(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
