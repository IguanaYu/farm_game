class_name MainMenu
extends Control
## 主菜单（启动首页）：继续 / 新游戏（覆盖需确认）/ 设置 / 退出。
## 纯代码构建，沿用 room_panel 的主题与配色约定；1440×900 设计坐标。
## 按钮显式命名（ContinueButton 等），测试按控件名查找。

const FOREST := Color("#294f3c")
const LEAF := Color("#396d50")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const TEXT_MUTED := Color("#3f4a42")
const BAD_RED := Color("#a4543f")
const GOLD_FILL := Color("#fff5df")
const GOLD_LINE := Color("#d5b87d")

const SETTINGS_PATH := "user://settings.cfg"
const RELAY_PREFS_PATH := "user://relay_prefs.cfg"
const RELAY_DEFAULT_ADDRESS := "127.0.0.1:31970"
const WORLD_SCENE := "res://scenes/main.tscn"

var main_view: VBoxContainer
var confirm_view: VBoxContainer
var settings_view: VBoxContainer
var continue_button: Button
var confirm_summary: Label
var fullscreen_option: OptionButton
var tutorial_replay_check: CheckButton
var relay_address_edit: LineEdit
var settings_hint: Label
## 装饰 emoji 的基准位置，_process 里做轻微浮动。
var _float_labels: Array = []
var _float_bases: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var theme_root := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	theme_root.default_font = font
	theme_root.default_font_size = 17
	theme = theme_root
	_apply_window_mode_setting()
	_build()
	set_process(true)


func _unhandled_key_input(event: InputEvent) -> void:
	## 设置/确认页按 ESC 返回主按钮页（不退出菜单场景）。
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if settings_view.visible or confirm_view.visible:
			_show_main_view()
			get_viewport().set_input_as_handled()


func _build() -> void:
	_build_backdrop()
	var center := CenterContainer.new()
	center.name = "MenuCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := _panel(CREAM, Color("#d5c9aa"), 20)
	card.custom_minimum_size = Vector2(470, 0)
	center.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 26)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)
	stack.add_child(_label("🌻 小小农场", 40, FOREST))
	stack.add_child(_label("点击种植、离线成长，还有洞穴探险与好友组队", 14, TEXT_MUTED))
	separator_space(stack, 8)

	main_view = VBoxContainer.new()
	main_view.name = "MainMenuView"
	main_view.add_theme_constant_override("separation", 12)
	stack.add_child(main_view)
	continue_button = _menu_button("继续游戏", Color("#eaf4df"), Color("#87b06f"), 46, 19)
	continue_button.name = "ContinueButton"
	continue_button.pressed.connect(_on_continue)
	main_view.add_child(continue_button)
	var new_game_button := _menu_button("开始新游戏", GOLD_FILL, GOLD_LINE, 46, 19)
	new_game_button.name = "NewGameButton"
	new_game_button.pressed.connect(_on_new_game)
	main_view.add_child(new_game_button)
	var settings_button := _menu_button("设置", Color("#f2eede"), Color("#cfc4a6"), 40, 16)
	settings_button.name = "SettingsButton"
	settings_button.pressed.connect(_on_settings)
	main_view.add_child(settings_button)
	var quit_button := _menu_button("退出游戏", Color("#f7e9e2"), Color("#c98d77"), 40, 16)
	quit_button.name = "QuitButton"
	quit_button.pressed.connect(_on_quit)
	main_view.add_child(quit_button)

	confirm_view = _build_confirm_view()
	stack.add_child(confirm_view)
	settings_view = _build_settings_view()
	stack.add_child(settings_view)

	var footer := _label("存档即时保存 · 单机本地单存档", 12, TEXT_MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(footer)
	_refresh_continue_summary()


# —— 三个子视图 ——————————————————————————————————————————————


func _build_confirm_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "ConfirmView"
	view.visible = false
	view.add_theme_constant_override("separation", 12)
	view.add_child(_label("覆盖现有存档？", 22, FOREST))
	confirm_summary = _label("", 14, TEXT_MUTED)
	confirm_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view.add_child(confirm_summary)
	var warning := _label("开始新游戏会覆盖当前存档（旧档自动备份为 farm_save_v1.json.bak）。", 13, BAD_RED)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view.add_child(warning)
	var confirm_button := _menu_button("确认覆盖并开始", Color("#eaf4df"), Color("#87b06f"), 42, 17)
	confirm_button.name = "ConfirmNewGameButton"
	confirm_button.pressed.connect(func() -> void: _enter_world(GameFlow.Mode.NEW_GAME))
	view.add_child(confirm_button)
	var back_button := _menu_button("返回", Color("#f2eede"), Color("#cfc4a6"), 36, 15)
	back_button.pressed.connect(func() -> void: _show_main_view())
	view.add_child(back_button)
	return view


func _build_settings_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "SettingsView"
	view.visible = false
	view.add_theme_constant_override("separation", 12)
	view.add_child(_label("设置", 22, FOREST))

	var window_row := HBoxContainer.new()
	window_row.add_theme_constant_override("separation", 10)
	view.add_child(window_row)
	window_row.add_child(_label("窗口模式", 15, TEXT_DARK))
	fullscreen_option = OptionButton.new()
	fullscreen_option.name = "FullscreenOption"
	fullscreen_option.add_item("窗口化", 0)
	fullscreen_option.add_item("全屏", 1)
	fullscreen_option.item_selected.connect(_on_fullscreen_selected)
	window_row.add_child(fullscreen_option)

	var tutorial_row := HBoxContainer.new()
	tutorial_row.add_theme_constant_override("separation", 10)
	view.add_child(tutorial_row)
	var tutorial_label := _label("重新显示新手引导", 15, TEXT_DARK)
	tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_row.add_child(tutorial_label)
	tutorial_replay_check = CheckButton.new()
	tutorial_replay_check.name = "TutorialReplayCheck"
	tutorial_replay_check.toggled.connect(_on_tutorial_replay_toggled)
	tutorial_row.add_child(tutorial_replay_check)

	var relay_title := _label("联机服务器地址（互联网房号模式用）", 15, TEXT_DARK)
	view.add_child(relay_title)
	relay_address_edit = LineEdit.new()
	relay_address_edit.name = "RelayAddressEdit"
	relay_address_edit.placeholder_text = "IP:端口（如 1.2.3.4:31970）"
	view.add_child(relay_address_edit)
	var relay_save_button := _menu_button("保存联机服务器地址", Color("#eaf4df"), Color("#87b06f"), 36, 15)
	relay_save_button.pressed.connect(_on_relay_address_save)
	view.add_child(relay_save_button)
	settings_hint = _label("", 13, LEAF)
	view.add_child(settings_hint)
	var back_button := _menu_button("返回", Color("#f2eede"), Color("#cfc4a6"), 36, 15)
	back_button.pressed.connect(func() -> void: _show_main_view())
	view.add_child(back_button)
	return view


func _show_main_view() -> void:
	main_view.visible = true
	confirm_view.visible = false
	settings_view.visible = false
	settings_hint.text = ""
	_refresh_continue_summary()


func _show_view(view: VBoxContainer) -> void:
	main_view.visible = false
	confirm_view.visible = view == confirm_view
	settings_view.visible = view == settings_view


# —— 按钮回调 ——————————————————————————————————————————————


func _on_continue() -> void:
	_enter_world(GameFlow.Mode.CONTINUE)


func _on_new_game() -> void:
	if _load_save_summary() == "":
		_enter_world(GameFlow.Mode.NEW_GAME)
		return
	confirm_summary.text = "当前进度：%s" % _load_save_summary()
	_show_view(confirm_view)


func _on_settings() -> void:
	_load_settings_values()
	_show_view(settings_view)


func _on_quit() -> void:
	get_tree().quit()


func _enter_world(mode: int) -> void:
	GameFlow.mode = mode
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_fullscreen_selected(index: int) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("window", "fullscreen", index == 1)
	config.save(SETTINGS_PATH)
	if index == 1:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_tutorial_replay_toggled(pressed: bool) -> void:
	## 同时写 cfg（跨启动生效）与 GameFlow（本次立即进农场也生效，由 farm_world 消费后清除）。
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("tutorial", "replay", pressed)
	config.save(SETTINGS_PATH)
	GameFlow.reset_tutorial = pressed


func _on_relay_address_save() -> void:
	var address := relay_address_edit.text.strip_edges()
	var split := address.rsplit(":", false, 1)
	if address != "" and (split.size() != 2 or not str(split[1]).is_valid_int() or int(str(split[1])) <= 0 or int(str(split[1])) > 65535 or str(split[0]) == ""):
		settings_hint.text = "地址格式不对，应为 IP:端口（如 1.2.3.4:31970）。"
		return
	if address == "":
		address = RELAY_DEFAULT_ADDRESS
	var config := ConfigFile.new()
	config.load(RELAY_PREFS_PATH)
	config.set_value("relay", "address", address)
	config.save(RELAY_PREFS_PATH)
	relay_address_edit.text = address
	settings_hint.text = "联机服务器地址已保存（房间页会使用同一地址）。"


# —— 存档摘要与设置读取 ————————————————————————————————————


## 无档返回空串；有档返回"第 N 天 · 金币 X"。
func _load_save_summary() -> String:
	var saved: Dictionary = SaveStore.load_state()
	if saved.is_empty():
		return ""
	var now := int(Time.get_unix_time_from_system())
	var created := int(saved.get("created_at", 0))
	var day := maxi(1, int((now - maxi(created, 0)) / 86400) + 1) if created > 0 else 1
	return "第 %d 天 · 金币 %d" % [day, int(saved.get("coins", 0))]


func _refresh_continue_summary() -> void:
	var summary := _load_save_summary()
	if summary == "":
		continue_button.disabled = true
		continue_button.text = "继续游戏（暂无存档）"
	else:
		continue_button.disabled = false
		continue_button.text = "继续游戏 · %s" % summary


func _apply_window_mode_setting() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK and bool(config.get_value("window", "fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _load_settings_values() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	fullscreen_option.selected = 1 if bool(config.get_value("window", "fullscreen", false)) else 0
	tutorial_replay_check.set_pressed_no_signal(bool(config.get_value("tutorial", "replay", false)))
	relay_address_edit.text = _load_relay_address()


func _load_relay_address() -> String:
	var config := ConfigFile.new()
	if config.load(RELAY_PREFS_PATH) == OK and config.has_section_key("relay", "address"):
		var saved := str(config.get_value("relay", "address", ""))
		if saved != "":
			return saved
	return RELAY_DEFAULT_ADDRESS


# —— 背景装饰 ———————————————————————————————————————————————


func _build_backdrop() -> void:
	var sky := ColorRect.new()
	sky.name = "MenuSky"
	sky.color = Color(0.88, 0.92, 0.85)
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sky)

	var sun := PanelContainer.new()
	sun.name = "MenuSun"
	var sun_style := StyleBoxFlat.new()
	sun_style.bg_color = Color("#f6e7bd")
	sun_style.set_corner_radius_all(52)
	sun.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sun.add_theme_stylebox_override("panel", sun_style)
	sun.anchor_left = 0.78
	sun.anchor_right = 0.78
	sun.anchor_top = 0.12
	sun.anchor_bottom = 0.12
	sun.custom_minimum_size = Vector2(104, 104)
	sun.offset_left = -52
	sun.offset_right = 52
	sun.offset_top = -52
	sun.offset_bottom = 52
	add_child(sun)

	_add_hill("MenuHillFar", Color("#cfe3c2"), 230, -70, 0.92)
	_add_hill("MenuHillNear", Color("#bcd6ae"), 170, 90, 1.25)

	for entry in [["MenuDecoSunflower", "🌻", 64, Vector2(0.09, 0.68)], ["MenuDecoWheat", "🌾", 52, Vector2(0.22, 0.78)], ["MenuDecoCarrot", "🥕", 44, Vector2(0.80, 0.74)], ["MenuDecoHen", "🐔", 44, Vector2(0.66, 0.82)]]:
		var label := _label(str(entry[1]), int(entry[2]), Color.WHITE)
		label.name = str(entry[0])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var anchor: Vector2 = entry[3]
		label.anchor_left = anchor.x
		label.anchor_right = anchor.x
		label.anchor_top = anchor.y
		label.anchor_bottom = anchor.y
		add_child(label)
		_float_labels.append(label)
		_float_bases.append(anchor)


func _add_hill(hill_name: String, fill: Color, height: int, x_shift: int, width_ratio: float) -> void:
	var hill := PanelContainer.new()
	hill.name = hill_name
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.corner_radius_top_left = height
	style.corner_radius_top_right = height
	hill.add_theme_stylebox_override("panel", style)
	hill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hill.anchor_left = 0.5
	hill.anchor_right = 0.5
	hill.anchor_top = 1.0
	hill.anchor_bottom = 1.0
	hill.offset_left = int(-720 * width_ratio) + x_shift
	hill.offset_right = int(720 * width_ratio) + x_shift
	hill.offset_top = -height
	hill.offset_bottom = 0
	add_child(hill)


func _process(_delta: float) -> void:
	## 装饰 emoji 轻微上下浮动，让首页有生命感。
	var time := float(Time.get_ticks_msec()) / 1000.0
	for index in _float_labels.size():
		var label: Label = _float_labels[index]
		if not is_instance_valid(label):
			continue
		var base: Vector2 = _float_bases[index]
		var drift := sin(time * 1.6 + float(index) * 1.7) * 0.012
		label.anchor_top = base.y + drift
		label.anchor_bottom = base.y + drift


# —— 小工具 ———————————————————————————————————————————————


func separator_space(parent: Control, height: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	parent.add_child(spacer)


func _panel(fill: Color, border: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _label(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _menu_button(content: String, fill: Color, border: Color, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.text = content
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT_DARK)
	button.add_theme_color_override("font_hover_color", Color("#1f3327"))
	button.add_theme_color_override("font_pressed_color", Color("#1f3327"))
	button.add_theme_color_override("font_disabled_color", Color("#5c6b5e"))
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 12
	style.content_margin_right = 12
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button
