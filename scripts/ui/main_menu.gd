class_name MainMenu
extends Control
## 主菜单（启动首页）：继续 / 新游戏（覆盖需确认）/ 线上农场（M1 服务器权威档）/
## 好友联机（本地档房间）/ 设置 / 退出。
## 纯代码构建，沿用 room_panel 的主题与配色约定；1440×900 设计坐标。
## 按钮显式命名（ContinueButton 等），测试按控件名查找。
## 设置子页复用 SettingsView（与游戏内暂停菜单共用一套）。

const FOREST := ExpeditionUI.TEXT
const TEXT_MUTED := ExpeditionUI.MUTED
const BAD_RED := ExpeditionUI.RED

const WORLD_SCENE := "res://scenes/main.tscn"
const CARD_PLAYTEST_SCENE := "res://scenes/card_playtest.tscn"

var main_view: VBoxContainer
var confirm_view: VBoxContainer
var settings_view: VBoxContainer
var online_view: VBoxContainer
var online_panel: OnlineLoginPanel
var settings_panel: SettingsView
var continue_button: Button
var confirm_summary: Label
var test_mode_button: Button
var test_mode_hint: Label
## 装饰 emoji 的基准位置，_process 里做轻微浮动。
var _float_labels: Array = []
var _float_bases: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = ExpeditionUI.make_theme()
	SettingsStore.apply_window_settings()
	SettingsStore.apply_volumes()
	_build()
	resized.connect(_fit_settings_page)
	_fit_settings_page()
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
	var card := ExpeditionUI.panel(Color(ExpeditionUI.PANEL, 0.98), ExpeditionUI.LINE, 0)
	card.custom_minimum_size = Vector2(530, 0)
	center.add_child(card)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)
	var signature := HBoxContainer.new()
	signature.alignment = BoxContainer.ALIGNMENT_CENTER
	signature.add_theme_constant_override("separation", 16)
	stack.add_child(signature)
	signature.add_child(ExpeditionUI.seal(58))
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", 0)
	signature.add_child(title)
	title.add_child(_label("小小农场", 40, FOREST))
	title.add_child(_label("耕种 · 探险 · 组队", 13, TEXT_MUTED))
	separator_space(stack, 8)

	main_view = VBoxContainer.new()
	main_view.name = "MainMenuView"
	main_view.add_theme_constant_override("separation", 12)
	stack.add_child(main_view)
	continue_button = _menu_button("继续游戏", 46, 19)
	continue_button.name = "ContinueButton"
	continue_button.pressed.connect(_on_continue)
	main_view.add_child(continue_button)
	var new_game_button := _menu_button("开始新游戏", 46, 19)
	new_game_button.name = "NewGameButton"
	new_game_button.pressed.connect(_on_new_game)
	main_view.add_child(new_game_button)
	var card_button := _menu_button("卡牌试玩", 46, 19, true)
	card_button.tooltip_text = "自动配装，直接体验战斗与战后搜刮。试玩进度独立。"
	card_button.name = "CardPlaytestButton"
	card_button.pressed.connect(_on_card_playtest)
	main_view.add_child(card_button)
	var online_button := _menu_button("线上农场", 44, 20)
	online_button.tooltip_text = "连接服务器，继续线上进度。"
	online_button.name = "OnlineButton"
	online_button.pressed.connect(_on_online)
	main_view.add_child(online_button)
	var coop_button := _menu_button("好友组队", 44, 20)
	coop_button.tooltip_text = "使用本机存档创建或加入好友房间。"
	coop_button.name = "CoopButton"
	coop_button.pressed.connect(_on_coop)
	main_view.add_child(coop_button)
	var settings_button := _menu_button("设置", 44, 20)
	settings_button.name = "SettingsButton"
	settings_button.pressed.connect(_on_settings)
	main_view.add_child(settings_button)
	var quit_button := _menu_button("退出游戏", 44, 20)
	quit_button.name = "QuitButton"
	quit_button.pressed.connect(_on_quit)
	main_view.add_child(quit_button)

	confirm_view = _build_confirm_view()
	stack.add_child(confirm_view)
	online_view = _build_online_view()
	stack.add_child(online_view)
	settings_view = _build_settings_view()
	stack.add_child(settings_view)

	var footer := _label("v%s" % SettingsStore.game_version(), 12, TEXT_MUTED)
	footer.tooltip_text = "本地档即时保存，线上档由服务器保存。"
	footer.mouse_filter = Control.MOUSE_FILTER_PASS
	footer.name = "MenuFooter"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(footer)
	_build_test_toggle()
	_refresh_continue_summary()
	_refresh_test_mode()


func _build_test_toggle() -> void:
	var corner := ExpeditionUI.panel(ExpeditionUI.PAPER, ExpeditionUI.LINE, 12)
	corner.name = "TestModeCorner"
	corner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	corner.offset_left = -242
	corner.offset_right = -20
	corner.offset_top = -104
	corner.offset_bottom = -20
	add_child(corner)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	corner.add_child(stack)
	test_mode_button = _menu_button("", 36, 16)
	test_mode_button.name = "TestModeButton"
	test_mode_button.toggle_mode = true
	test_mode_button.tooltip_text = "加速植物生长与育种机计时。首次继续会复制本地进度，测试结果独立保存。"
	test_mode_button.toggled.connect(func(on: bool) -> void:
		FarmTestMode.enabled = on
		_refresh_test_mode()
		_refresh_continue_summary())
	stack.add_child(test_mode_button)
	test_mode_hint = _label("", 12, TEXT_MUTED)
	test_mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(test_mode_hint)


func _refresh_test_mode() -> void:
	var on := FarmTestMode.enabled
	test_mode_button.set_pressed_no_signal(on)
	test_mode_button.text = "测试功能：开" if on else "测试功能：关"
	test_mode_hint.text = "独立存档 · 可调时间倍率" if on else "加速生长与育种"
	(find_child("NewGameButton", true, false) as Button).text = "开始新测试" if on else "开始新游戏"
	for button_name in ["OnlineButton", "CoopButton"]:
		var button := find_child(button_name, true, false) as Button
		button.disabled = on
		button.tooltip_text = "关闭测试功能后可联机。" if on else ("连接服务器，继续线上进度。" if button_name == "OnlineButton" else "使用本机存档创建或加入好友房间。")


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
	warning.name = "OverwriteWarning"
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	view.add_child(warning)
	var confirm_button := _menu_button("确认覆盖并开始", 42, 17, true)
	confirm_button.name = "ConfirmNewGameButton"
	confirm_button.pressed.connect(func() -> void: _enter_world(GameFlow.Mode.NEW_GAME))
	view.add_child(confirm_button)
	var back_button := _menu_button("返回", 36, 15)
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
	var back_button := _menu_button("返回", 36, 15)
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
	settings_scroll.name = "MenuSettingsScroll"
	settings_scroll.custom_minimum_size = Vector2(0,360)
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.add_child(settings_scroll)
	var settings_paper := ExpeditionUI.panel(ExpeditionUI.PAPER, ExpeditionUI.LINE, 12)
	settings_paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(settings_paper)
	settings_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_panel.theme = LifeUI.make_theme()
	settings_paper.add_child(settings_panel)
	var back_button := _menu_button("返回", 36, 15)
	back_button.pressed.connect(func() -> void: _show_main_view())
	view.add_child(back_button)
	return view

func _fit_settings_page() -> void:
	var scroll := find_child("MenuSettingsScroll", true, false) as ScrollContainer
	if scroll != null:
		scroll.custom_minimum_size.y = clampf(size.y - 360, 180, 360)


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
	if _load_save_summary() == "" or (FarmTestMode.enabled and SaveStore.load_state(FarmTestMode.SAVE_PATH).is_empty()):
		_enter_world(GameFlow.Mode.NEW_GAME)
		return
	confirm_summary.text = "当前进度：%s" % _load_save_summary()
	(find_child("OverwriteWarning", true, false) as Label).text = "开始新测试会覆盖测试存档，旧测试档自动备份。" if FarmTestMode.enabled else "开始新游戏会覆盖当前存档（旧档自动备份为 farm_save_v1.json.bak）。"
	_show_view(confirm_view)


func _on_settings() -> void:
	settings_panel.refresh()
	_show_view(settings_view)

func _on_card_playtest() -> void:
	get_tree().change_scene_to_file(CARD_PLAYTEST_SCENE)


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
	var saved: Dictionary = SaveStore.load_state(FarmTestMode.SAVE_PATH if FarmTestMode.enabled else SaveStore.SAVE_PATH)
	if saved.is_empty() and FarmTestMode.enabled:
		saved = SaveStore.load_state()
	if saved.is_empty():
		return ""
	var now := int(Time.get_unix_time_from_system())
	if FarmTestMode.enabled:
		now = int(saved.get("test_clock", {}).get("now", now))
	var created := int(saved.get("created_at", 0))
	var day := maxi(1, int((now - maxi(created, 0)) / 86400) + 1) if created > 0 else 1
	return "第 %d 天 · 金币 %d" % [day, int(saved.get("coins", 0))]


func _refresh_continue_summary() -> void:
	var summary := _load_save_summary()
	if summary == "":
		continue_button.disabled = true
		continue_button.text = "继续测试（暂无进度）" if FarmTestMode.enabled else "继续游戏（暂无存档）"
	else:
		continue_button.disabled = false
		continue_button.text = "%s · %s" % ["继续测试" if FarmTestMode.enabled else "继续游戏", summary]


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
	env.environment.background_color = Color("#847587")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#d7bdcd")
	env.environment.ambient_light_energy = 0.65
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58,-25,0)
	sun.light_color = Color("#ffd7b5")
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
	veil.color = Color(ExpeditionUI.INK, 0.38)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)

func _process(_delta: float) -> void:
	pass


# —— 小工具 ———————————————————————————————————————————————


func separator_space(parent: Control, height: int) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	parent.add_child(spacer)


func _label(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _menu_button(content: String, height: int, font_size: int, primary := false) -> Button:
	var button := ExpeditionUI.button(content, primary)
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", font_size)
	return button
