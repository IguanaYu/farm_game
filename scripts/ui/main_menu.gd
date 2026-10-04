class_name MainMenu
extends Control
## 主菜单（启动首页）：继续 / 新游戏（覆盖需确认）/ 线上农场（M1 服务器权威档）/
## 好友联机（本地档房间）/ 设置 / 退出。
## 纯代码构建，沿用 room_panel 的主题与配色约定；1440×900 设计坐标。
## 按钮显式命名（ContinueButton 等），测试按控件名查找。
## 设置子页复用 SettingsView（与游戏内暂停菜单共用一套）。

const FOREST := Color("#294f3c")
const LEAF := Color("#396d50")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const TEXT_MUTED := Color("#3f4a42")
const BAD_RED := Color("#a4543f")
const GOLD_FILL := Color("#fff5df")
const GOLD_LINE := Color("#d5b87d")

const WORLD_SCENE := "res://scenes/main.tscn"

var main_view: VBoxContainer
var confirm_view: VBoxContainer
var settings_view: VBoxContainer
var online_view: VBoxContainer
var online_panel: OnlineLoginPanel
var settings_panel: SettingsView
var continue_button: Button
var confirm_summary: Label
## 装饰 emoji 的基准位置，_process 里做轻微浮动。
var _float_labels: Array = []
var _float_bases: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = LifeUI.make_theme()
	SettingsStore.apply_window_settings()
	SettingsStore.apply_volumes()
	_build()
	set_process(true)


func _unhandled_key_input(event: InputEvent) -> void:
	## 设置/确认页按 pause（默认 ESC）返回主按钮页（不退出菜单场景）。
	if event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed("pause"):
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
	card.custom_minimum_size = Vector2(530, 0)
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
	stack.add_child(_label("小小农场", 40, FOREST))
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
	var online_button := _menu_button("线上农场 · 服务器进度", Color("#eef4e7"), Color("#9fbf8a"), 44, 20)
	online_button.name = "OnlineButton"
	online_button.pressed.connect(_on_online)
	main_view.add_child(online_button)
	var coop_button := _menu_button("本地组队 · 本机存档", Color("#e7eef6"), Color("#8fa8c8"), 44, 20)
	coop_button.name = "CoopButton"
	coop_button.pressed.connect(_on_coop)
	main_view.add_child(coop_button)
	var settings_button := _menu_button("设置", Color("#f2eede"), Color("#cfc4a6"), 44, 20)
	settings_button.name = "SettingsButton"
	settings_button.pressed.connect(_on_settings)
	main_view.add_child(settings_button)
	var quit_button := _menu_button("退出游戏", Color("#f7e9e2"), Color("#c98d77"), 44, 20)
	quit_button.name = "QuitButton"
	quit_button.pressed.connect(_on_quit)
	main_view.add_child(quit_button)

	confirm_view = _build_confirm_view()
	stack.add_child(confirm_view)
	online_view = _build_online_view()
	stack.add_child(online_view)
	settings_view = _build_settings_view()
	stack.add_child(settings_view)

	var footer := _label("v%s · 本地档即时保存 · 线上档服务器保存" % SettingsStore.game_version(), 12, TEXT_MUTED)
	footer.name = "MenuFooter"
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


func _build_online_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "OnlineView"
	view.visible = false
	view.add_theme_constant_override("separation", 12)
	online_panel = OnlineLoginPanel.new()
	online_panel.name = "OnlinePanel"
	online_panel.entered_online.connect(_on_entered_online)
	view.add_child(online_panel)
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
	settings_panel = SettingsView.new()
	settings_panel.name = "SettingsPanel"
	var settings_scroll := ScrollContainer.new()
	settings_scroll.custom_minimum_size = Vector2(0,480)
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.add_child(settings_scroll)
	settings_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(settings_panel)
	var back_button := _menu_button("返回", Color("#f2eede"), Color("#cfc4a6"), 36, 15)
	back_button.pressed.connect(func() -> void: _show_main_view())
	view.add_child(back_button)
	return view


func _show_main_view() -> void:
	main_view.visible = true
	confirm_view.visible = false
	online_view.visible = false
	settings_view.visible = false
	_refresh_continue_summary()


func _show_view(view: VBoxContainer) -> void:
	main_view.visible = false
	confirm_view.visible = view == confirm_view
	online_view.visible = view == online_view
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
	settings_panel.refresh()
	_show_view(settings_view)


func _on_online() -> void:
	online_panel._refresh_session()
	_show_view(online_view)


func _on_entered_online(_token: String) -> void:
	## 登录面板已保存凭据并设置 GameFlow.online_token；这里只负责切世界。
	GameFlow.mode = GameFlow.Mode.ONLINE
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_coop() -> void:
	## 好友联机入口：读档进农场并自动打开房间页（房间页里再选局域网/互联网）。
	GameFlow.mode = GameFlow.Mode.CONTINUE
	GameFlow.open_room_on_entry = true
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_quit() -> void:
	get_tree().quit()


func _enter_world(mode: int) -> void:
	GameFlow.mode = mode
	get_tree().change_scene_to_file(WORLD_SCENE)


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


# —— 背景装饰 ———————————————————————————————————————————————


func _build_backdrop() -> void:
	var container := SubViewportContainer.new()
	container.name = "MenuFarmScenery"
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,800)
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	SceneArt.landscape(world)
	for entry in [[Vector3(-5.4,0,-5.9),Color("#779574"),"杂货铺",true],[Vector3(5,0,-5.9),Color("#b78e64"),"仓库",false]]:
		var building := Node3D.new()
		building.position = entry[0]
		world.add_child(building)
		SceneArt.cottage(building,entry[2],entry[1],entry[3])
	for row in range(2):
		for col in range(5):
			var plot: Node3D = load("res://assets/models/plot_cabbage_mature.glb").instantiate()
			plot.position = Vector3((col-2)*2.7,0,0.5+row*2.7)
			world.add_child(plot)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#c6dcd0")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#ecf3ea")
	env.environment.ambient_light_energy = 0.65
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58,-25,0)
	sun.light_color = Color("#fffaf0")
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 19
	camera.position = Vector3(6.8,15.8,22.6)
	world.add_child(camera)
	camera.look_at(Vector3(0,0.4,-1.1))
	camera.make_current()
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.88,0.91,0.81,0.22)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

func _process(_delta: float) -> void:
	pass


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
	label.add_theme_font_size_override("font_size", maxi(18,size))
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
