class_name FarmHud
extends Control

signal buy_seed_requested(kind: String, quantity: int)
signal buy_fertilizer_requested(kind: String, quantity: int)
signal upgrade_shop_requested
signal plant_seed_requested(plot_id: int, seed_id: int)
signal water_requested(plot_id: int)
signal fertilize_requested(plot_id: int, kind: String)
signal harvest_all_requested
signal sell_batch_requested(batch_id: int)
signal sell_all_requested
signal recycle_seed_requested(seed_id: int)
signal recycle_pending_seed_requested(seed_id: int)
signal sell_pending_crop_requested(batch_id: int)
signal claim_pending_requested
signal upgrade_warehouse_requested
signal buy_breeder_requested
signal upgrade_breeder_requested
signal set_template_requested(seed_id: int)
signal clear_template_requested
signal collect_breeder_requested
signal buy_plot_requested
signal buy_can2_requested
signal lock_guest_requested(guest_id: int)
signal unlock_guest_requested
signal lock_formula_requested(kind: String)
signal unlock_formula_requested
signal sell_batch_to_requested(batch_id: int, count: int, guest_id: int)
signal debug_mature_requested
signal expedition_save_requested(dirty: bool)
## HUD 本地改动需要立即落盘时发出（如跳过引导），世界层执行普通保存＋刷新。
signal save_requested

const SHOP_ICON := preload("res://assets/sprites/facility_shop.png")
const WAREHOUSE_ICON := preload("res://assets/sprites/facility_warehouse.png")
const CRATE_ICON := preload("res://assets/sprites/item_harvest_crate.png")
const COIN_ICON := preload("res://assets/sprites/item_coin.png")
const SEED_ICONS := {
	"cabbage": preload("res://assets/sprites/seed_cabbage.png"),
	"carrot": preload("res://assets/sprites/seed_carrot.png"),
	"glow_berry": preload("res://assets/sprites/seed_glow_berry.svg"),
	"rock_sprout": preload("res://assets/sprites/seed_rock_sprout.svg"),
}
const CROP_ICONS := {
	"cabbage": preload("res://assets/sprites/crop_cabbage.png"),
	"carrot": preload("res://assets/sprites/crop_carrot.png"),
	"glow_berry": preload("res://assets/sprites/crop_glow_berry.svg"),
	"rock_sprout": preload("res://assets/sprites/crop_rock_sprout.svg"),
	"star_bloom": preload("res://assets/sprites/crop_carrot.png"),
}
const FERTILIZER_ICONS := {
	"basic": preload("res://assets/sprites/fertilizer_basic.png"),
	"mutation": preload("res://assets/sprites/fertilizer_mutation.png"),
	"preserve": preload("res://assets/sprites/fertilizer_preserve.png"),
	"golden": preload("res://assets/sprites/fertilizer_golden.png"),
}
const WATERING_CAN_ICON := preload("res://assets/sprites/tool_watering_can.png")

const FOREST := Color("#294f3c")
const LEAF := Color("#396d50")
const CREAM := Color("#f7f8f2")
const TEXT_DARK := Color("#283f33")
const TEXT_MUTED := Color("#657468")
const ACCENT_GOLD := Color("#9b713a")
const LOCK_RED := Color("#a4543f")

# 世界层注入的只读上下文：规则查询走 FarmGame，UI 不另写规则。
var game: FarmGame
var view_now: int = 0
var current_state: Dictionary = {}
var active_modal: String = ""
var picker_plot_id: int = 0
var care_plot_id: int = 0
var last_harvest_result: Dictionary = {}
var last_harvest_all_result: Dictionary = {}
var market_sell_counts: Dictionary = {}
var seed_filter: String = "all"
var shop_tab: String = "seeds"
var expanded_details: Dictionary = {}
var growth_bar: ProgressBar
var care_water_button: Button
var care_segments: HFlowContainer
var care_watering_signature: String = ""
var level_bar: ProgressBar
var modal_scroll: ScrollContainer
var toast_timer: Timer
var tutorial_label: Label
var tutorial_panel: PanelContainer
var care_remaining_label: Label
var coins_value: Label
var seeds_value: Label
var crops_value: Label
var level_value: Label
var plot_hint_label: Label
var status_label: Label
## M1 线上模式（计划 §5.6）：状态角标 + 未联网化入口的门控。
var online_mode := false
var online_badge: Label = null
## M2：线上命令发送口，farm_world 在线模式注入 Callable(online, "request")；
## 空 Callable = 单机。制作/装备仓库/战备三个面板经它发命令而不直改本地档。
var online_request: Callable = Callable()
var modal_overlay: Control
var modal_panel: PanelContainer
var modal_title: Label
var modal_icon: TextureRect
var modal_content: VBoxContainer
var sell_all_button: Button
var harvest_all_entry: Button
var expedition_hub_panel: ExpeditionHubPanel
var loadout_panel: LoadoutPanel
var battle_screen: BattleScreen
var map_panel: ExpeditionMapPanel
var crafting_panel: CraftingPanel
var equipment_warehouse_panel: WarehousePanel
var room_panel: RoomPanel
var coop_client_panel: CoopClientPanel
var active_expedition: ExpeditionGame
var last_expedition_receipt: Dictionary = {}
## 合作局主机侧会话（F-04）：地图/战斗面板的裁定入口与快照刷新从这里注入。
var coop_host: SessionHost = null
var online_bridge: OnlineFarmBridge = null
## R4：地点路由回调（farm_world 注入；结算回营地用）。
var location_router: Callable = Callable()
var online_room_panel: OnlineRoomPanel = null
var online_run_panel: OnlineRunPanel = null
var online_visit_panel: OnlineVisitPanel = null
## R7：拜访模式——只读参观，拦截一切自身操作（资产隔离红线）。
var visiting := false
var location_id := "farm"
var location_owner: Dictionary = {}
var brand_title: Label
var object_anchor := Vector2.ZERO
var basket_batch_id := 0
var selected_guest_id := 0
var readonly_title := ""
var readonly_body := ""
var readonly_owner := ""
var guest_quotes: Array[PanelContainer] = []
var quote_labels: Array[Label] = []
var quote_projection: Callable = Callable()
var owner_projection: Callable = Callable()
var owner_quote: PanelContainer
var owner_quote_label: Label

## ESC 暂停菜单：所有面板收起时才允许弹出；卡片内分主视图与设置子视图两页。
var pause_overlay: Control
var pause_back_button: Button
var pause_quit_button: Button
var pause_main_view: VBoxContainer
var pause_settings_view: VBoxContainer
var pause_settings_panel: SettingsView


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = LifeUI.make_theme()
	_build_brand()
	_build_counters()
	_build_context()
	_build_actions()
	_build_tutorial_banner()
	_build_modal()
	_build_expedition_panels()
	_build_pause_overlay()
	_build_world_quotes()


func refresh(state: Dictionary) -> void:
	current_state = state
	var crop_count := 0
	for batch in state["crop_batches"]:
		crop_count += batch["count"]
	coins_value.text = str(state["coins"])
	seeds_value.text = str(state["seeds"].size())
	crops_value.text = str(crop_count)
	var progress := PlantDefs.level_progress(int(state["farming_exp"]))
	level_value.text = "Lv.%d" % progress["level"]
	level_value.tooltip_text = "种地经验 %d / %d" % [progress["into_level"], progress["next_need"]] if progress["next_need"] > 0 else "种地已满级"
	level_bar.value = 100.0 if progress["next_need"] < 0 else 100.0 * progress["into_level"] / maxf(1, progress["next_need"])
	update_harvest_entry()
	_update_tutorial_banner()
	_refresh_world_quotes()
	if modal_overlay.visible:
		_render_modal()


func tick_update(now: int) -> void:
	## 每秒更新倒计时、进度与时段状态，不重建操作按钮，避免吃掉点击。
	if active_modal == "plot_care" and care_plot_id > 0 and is_instance_valid(care_remaining_label):
		var plot := game.get_plot(care_plot_id)
		if not plot.is_empty() and plot["seed_id"] != 0:
			var remaining: int = maxi(0, plot["ready_at"] - now)
			care_remaining_label.text = "已成熟 · 点击地块收获" if remaining == 0 else "%02d:%02d 后成熟" % [int(remaining / 60), remaining % 60]
			if is_instance_valid(growth_bar):
				growth_bar.value = 100.0 * (now - plot["planted_at"]) / maxf(1, plot["ready_at"] - plot["planted_at"])
			_update_care_watering(now)


func update_harvest_entry() -> void:
	# 由时钟每秒调用：作物成熟不需要玩家操作也要让一键收获入口出现。
	var mature_count: int = 0
	if game != null:
		mature_count = game.mature_plot_ids(view_now).size()
	harvest_all_entry.visible = mature_count > 0 and location_id == "farm" and not visiting
	harvest_all_entry.get_node("ActionStack/ActionCaption").text = "收获 · %d" % mature_count


func show_plot_hint(plot_id: int, plot: Dictionary, now: int) -> void:
	if plot_id == 0:
		plot_hint_label.text = {"farm":"点击田地种植 · 建筑与路口可以进入", "shop":"篮子选数量，再找客人成交", "cave_camp":"洞口出发 · 战备台配装 · 篝火组队", "visit_yard":"只读参观 · 房子进屋 · 院门回家", "visit_house":"坐坐喝茶 · 门窗回到院子"}.get(location_id, "")
		return
	if plot.is_empty() or not bool(plot.get("owned",false)):
		plot_hint_label.text = "待开垦地 · 点击查看开垦条件"
		return
	if plot["seed_id"] == 0:
		plot_hint_label.text = "第 %d 块地  ·  空地，点击播种" % plot_id
		return
	var defn := PlantDefs.get_plant(plot["kind"])
	var name: String = defn["display_name"]
	if now >= plot["ready_at"]:
		plot_hint_label.text = "第 %d 块地  ·  %s成熟，点击收获" % [plot_id, name]
		return
	var remaining: int = plot["ready_at"] - now
	var hint := "第 %d 块地  ·  %s生长中 %02d:%02d  ·  浇水 %d/%d" % [plot_id, name, int(remaining / 60), remaining % 60, plot["watered_segments"].size(), defn["water_segments"]]
	if not plot.get("fertilizer", {}).is_empty() and plot["fertilizer"]["expires_at"] > now:
		var fertilizer_name: String = PlantDefs.FERTILIZERS[plot["fertilizer"]["kind"]]["display_name"]
		var minutes := int(ceil(float(plot["fertilizer"]["expires_at"] - now) / 60.0))
		hint += "  ·  %s剩 %d 分钟" % [fertilizer_name, minutes]
	plot_hint_label.text = hint


func show_status(message: String) -> void:
	status_label.text = message
	status_label.visible = not message.is_empty()
	status_label.tooltip_text = message
	toast_timer.start()


func show_harvest(result: Dictionary) -> void:
	last_harvest_result = result
	active_modal = "harvest"
	_apply_modal_height(300)
	modal_overlay.visible = true
	_render_modal()


func show_harvest_all(result: Dictionary) -> void:
	last_harvest_all_result = result
	active_modal = "harvest_all"
	_apply_modal_height(300)
	modal_overlay.visible = true
	_render_modal()


func set_online_mode(enabled: bool) -> void:
	## 线上模式开关：显示状态角标；单机路径不调用，界面零变化（计划 §5.6）。
	online_mode = enabled
	if enabled and online_badge == null:
		online_badge = Label.new()
		online_badge.name = "OnlineBadge"
		online_badge.add_theme_font_size_override("font_size", 14)
		online_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		online_badge.offset_left = -260
		online_badge.offset_right = -12
		online_badge.offset_top = 8
		online_badge.offset_bottom = 34
		online_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(online_badge)
	if online_badge != null:
		online_badge.visible = enabled


func set_online_status(text: String, is_online: bool) -> void:
	if online_badge == null:
		return
	online_badge.text = "联机 · %s" % text
	online_badge.add_theme_color_override("font_color", Color("#2e7d4f") if is_online else Color("#b0623a"))


## R7：拜访入口选中（地址簿回调）。
signal visit_enter_requested(owner: Dictionary, farm: Dictionary)


func _online_blocked(hint: String) -> bool:
	## M1：依赖本地权威档/本地局的入口在线上模式一律拦截（F09）；
	## R7：拜访模式同样拦截（只读参观，资产隔离红线）。
	if visiting:
		if status_label != null:
			show_status("拜访中不能操作，先回自己的农场。")
		return true
	if not online_mode:
		return false
	if status_label != null:
		show_status(hint)
	return true


## R7：拜访门控开关。
func set_visiting(on: bool) -> void:
	visiting = on


## R7：地址簿入口（信箱/小桥/邻里房屋）。
func open_visit_directory() -> void:
	if online_bridge == null:
		show_status("线上功能不可用，请重新登录。")
		return
	_close_modal()
	online_visit_panel.open(online_bridge)


func _on_visit_requested(owner: Dictionary, farm: Dictionary) -> void:
	online_visit_panel.close()
	visit_enter_requested.emit(owner, farm)


func open_shop() -> void:
	active_modal = "shop"
	_apply_modal_height(335)
	modal_overlay.visible = true
	_render_modal()


func open_warehouse(tab := "crops") -> void:
	active_modal = "warehouse_seeds" if tab == "seeds" else "warehouse_crops"
	_apply_modal_height(285)
	modal_overlay.visible = true
	_render_modal()


func open_breeder() -> void:
	active_modal = "breeder"
	_apply_modal_height(285)
	modal_overlay.visible = true
	_render_modal()


func open_market() -> void:
	active_modal = "market"
	_apply_modal_height(300)
	modal_overlay.visible = true
	_render_modal()


func open_seed_picker(plot_id: int) -> void:
	picker_plot_id = plot_id
	active_modal = "seed_picker"
	_apply_modal_height(305)
	modal_overlay.visible = true
	_render_modal()


func open_plot_care(plot_id: int) -> void:
	care_plot_id = plot_id
	active_modal = "plot_care"
	_apply_modal_height(285)
	modal_overlay.visible = true
	_render_modal()


func _apply_modal_height(_half_height: int) -> void:
	# Light workspaces leave the world visible; only complex expedition work uses a full-screen mode.
	var compact := active_modal in ["seed_picker","plot_care","harvest","harvest_all","expansion","readonly","guest"]
	var width := 430.0 if compact else 530.0
	var height := minf(490.0 if compact else 640.0,size.y-140.0)
	var at := Vector2(size.x-width-24,112)
	if compact and location_id == "farm" and object_anchor != Vector2.ZERO:
		at = object_anchor + Vector2(48,-height*0.45)
		if at.x+width > size.x-24:
			at.x = object_anchor.x-width-48
		at.x = clampf(at.x,24,size.x-width-24)
		at.y = clampf(at.y,108,size.y-height-24)
	modal_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	modal_panel.position = at
	modal_panel.size = Vector2(width,height)
	modal_scroll.scroll_vertical = 0


func _build_brand() -> void:
	var brand := _panel(Color("#f7f8f2f5"), Color("#ffffff70"), 18)
	brand.name = "FarmBrand"
	brand.offset_left = 24
	brand.offset_top = 22
	brand.offset_right = 345
	brand.offset_bottom = 88
	add_child(brand)
	var margin := _margin(14, 10)
	brand.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	row.add_child(_image(CROP_ICONS["cabbage"], Vector2(42, 42)))
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(titles)
	brand_title = _label("我的农场",22,TEXT_DARK)
	titles.add_child(brand_title)
	level_bar = _progress(LEAF)
	level_bar.custom_minimum_size = Vector2(100, 4)
	titles.add_child(level_bar)
	level_value = _label("Lv.1", 16, LEAF)
	row.add_child(level_value)


const TUTORIAL_STEPS := [
	"选一块空地，种下白菜",
	"点开正在生长的白菜，浇一次水",
	"等待成熟，点击地块收获",
	"去集市，比价卖出第一批菜",
	"去商店补种，开始下一轮",
]


func _build_tutorial_banner() -> void:
	tutorial_panel = _panel(Color("#33492ef2"), Color("#7fa876"), 14)
	tutorial_panel.name = "TutorialBanner"
	tutorial_panel.anchor_left = 0.5
	tutorial_panel.anchor_right = 0.5
	tutorial_panel.offset_left = -255
	tutorial_panel.offset_right = 255
	tutorial_panel.offset_top = 106
	tutorial_panel.offset_bottom = 152
	tutorial_panel.visible = false
	add_child(tutorial_panel)
	var margin := _margin(14, 6)
	tutorial_panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	tutorial_label = _label("", 16, Color("#e8f5df"))
	tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(tutorial_label)
	var skip_button := _plain_button("跳过", Color("#ffd98a"))
	skip_button.name = "SkipTutorialButton"
	skip_button.custom_minimum_size.x = 58
	skip_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	skip_button.pressed.connect(func():
		current_state["tutorial_step"] = 99
		tutorial_panel.visible = false
		## F-08：跳过也立即保存——此前只改内存，重开后引导会再次弹出。
		save_requested.emit())
	row.add_child(skip_button)


func _update_tutorial_banner() -> void:
	if tutorial_panel == null:
		return
	if location_id != "farm" or visiting:
		tutorial_panel.hide()
		return
	var step := int(current_state.get("tutorial_step", 99))
	if step < 0 or step >= TUTORIAL_STEPS.size():
		tutorial_panel.visible = false
		return
	tutorial_panel.visible = true
	tutorial_label.text = "%d / 5   %s" % [step + 1, TUTORIAL_STEPS[step]]


func _build_counters() -> void:
	var counters := HBoxContainer.new()
	counters.name = "FarmCounters"
	counters.anchor_left = 1.0
	counters.anchor_right = 1.0
	counters.offset_left = -424
	counters.offset_right = -24
	counters.offset_top = 22
	counters.offset_bottom = 88
	counters.add_theme_constant_override("separation", 8)
	add_child(counters)
	coins_value = _counter(counters, COIN_ICON, "金币", ACCENT_GOLD)
	seeds_value = _counter(counters, SEED_ICONS["cabbage"], "种子", LEAF)
	crops_value = _counter(counters, CROP_ICONS["cabbage"], "作物", LEAF)


func _counter(parent: HBoxContainer, icon_texture: Texture2D, caption: String, accent: Color) -> Label:
	var chip := _panel(Color("#f7f8f2f5"), Color("#ffffff70"), 18)
	chip.tooltip_text = caption
	chip.custom_minimum_size.x = 120
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(chip)
	var margin := _margin(12, 10)
	chip.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	row.add_child(_image(icon_texture, Vector2(34, 34)))
	var value := _label("0", 22, accent)
	row.add_child(value)
	return value


func _build_context() -> void:
	var context := _panel(Color("#f7f8f2ed"), Color("#ffffff70"), 18)
	context.name = "PlotContext"
	context.anchor_top = 1.0
	context.anchor_bottom = 1.0
	context.offset_left = 24
	context.offset_right = 570
	context.offset_top = -74
	context.offset_bottom = -24
	context.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(context)
	var margin := _margin(18, 10)
	context.add_child(margin)
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(stack)
	plot_hint_label = _label("选一块地，开始种植", 18, TEXT_DARK)
	plot_hint_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	plot_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(plot_hint_label)
	status_label = _label("", 14, TEXT_MUTED)
	status_label.visible = false
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack.add_child(status_label)
	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.wait_time = 6.0
	toast_timer.timeout.connect(func(): status_label.text = ""; status_label.hide())
	add_child(toast_timer)


func _build_actions() -> void:
	var actions := HBoxContainer.new()
	actions.name = "FarmActions"
	actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	actions.offset_left = -156
	actions.offset_right = -24
	actions.offset_top = -90
	actions.offset_bottom = -20
	add_child(actions)
	harvest_all_entry = _icon_action("一键收获", CRATE_ICON, CREAM, Color("#a8bf8a"))
	harvest_all_entry.name = "HarvestAllButton"
	harvest_all_entry.visible = false
	harvest_all_entry.pressed.connect(func(): harvest_all_requested.emit())
	actions.add_child(harvest_all_entry)


func _icon_action(caption: String, texture: Texture2D, fill: Color, border: Color) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(112, 76)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _style(fill, border, 15))
	button.add_theme_stylebox_override("hover", _style(Color.WHITE, Color("#77a76d"), 15))
	button.add_theme_stylebox_override("pressed", _style(Color("#e8f0e3"), Color("#477b52"), 15))
	var stack := VBoxContainer.new()
	stack.name = "ActionStack"
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", -3)
	button.add_child(stack)
	var icon := _image(texture, Vector2(44, 44))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(icon)
	var label := _label(caption, 15, TEXT_DARK)
	label.name = "ActionCaption"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(label)
	return button


func _build_modal() -> void:
	modal_overlay = Control.new()
	modal_overlay.name = "ModalOverlay"
	modal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_overlay.visible = false
	add_child(modal_overlay)
	var shade := ColorRect.new()
	shade.name = "ModalShade"
	shade.color = Color.TRANSPARENT
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_overlay.add_child(shade)
	modal_panel = _panel(CREAM, Color("#e1e8df"), 20)
	modal_panel.name = "FarmModal"
	modal_panel.anchor_left = 0.5
	modal_panel.anchor_right = 0.5
	modal_panel.anchor_top = 0.5
	modal_panel.anchor_bottom = 0.5
	modal_panel.offset_left = -440
	modal_panel.offset_right = 440
	modal_panel.offset_top = -240
	modal_panel.offset_bottom = 240
	modal_overlay.add_child(modal_panel)
	var outer := _margin(16, 16)
	modal_panel.add_child(outer)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	outer.add_child(layout)
	var header := _panel(Color.TRANSPARENT, Color.TRANSPARENT, 14)
	header.custom_minimum_size.y = 58
	layout.add_child(header)
	var header_margin := _margin(13, 7)
	header.add_child(header_margin)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	header_margin.add_child(header_row)
	modal_icon = _image(SHOP_ICON, Vector2(42, 42))
	header_row.add_child(modal_icon)
	modal_title = _label("", 25, TEXT_DARK)
	modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(modal_title)
	var close_button := _plain_button("×", TEXT_DARK)
	close_button.custom_minimum_size.x = 40
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.pressed.connect(_close_modal)
	header_row.add_child(close_button)
	var scroll := ScrollContainer.new()
	modal_scroll = scroll
	scroll.name = "ModalScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 只允许纵向滚动：长行靠换行收窄，横向溢出会把卡片右侧的按钮挤出可视区。
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	modal_content = VBoxContainer.new()
	modal_content.name = "ModalContent"
	modal_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_content.add_theme_constant_override("separation", 13)
	scroll.add_child(modal_content)
	sell_all_button = _solid_button("全部按默认价出售", Color("#9b713f"))
	sell_all_button.name = "SellAllButton"
	sell_all_button.visible = false
	sell_all_button.pressed.connect(func(): sell_all_requested.emit())
	layout.add_child(sell_all_button)


func _render_modal() -> void:
	care_remaining_label = null
	growth_bar = null
	care_water_button = null
	care_segments = null
	care_watering_signature = ""
	for child in modal_content.get_children():
		modal_content.remove_child(child)
		child.queue_free()
	match active_modal:
		"shop":
			sell_all_button.visible = false
			_render_shop()
		"warehouse_crops", "warehouse":
			sell_all_button.visible = not current_state["crop_batches"].is_empty()
			sell_all_button.text = "全部出售（%d 批）" % current_state["crop_batches"].size()
			_render_warehouse_crops()
		"warehouse_seeds":
			sell_all_button.visible = false
			_render_warehouse_seeds()
		"breeder":
			sell_all_button.visible = false
			_render_breeder()
		"harvest":
			sell_all_button.visible = false
			_render_harvest()
		"harvest_all":
			sell_all_button.visible = false
			_render_harvest_all()
		"seed_picker":
			sell_all_button.visible = false
			_render_seed_picker()
		"plot_care":
			sell_all_button.visible = false
			_render_plot_care()
		"market":
			sell_all_button.visible = false
			_render_market()
		"basket":
			sell_all_button.visible = false
			_render_basket()
		"guest":
			sell_all_button.visible = false
			_render_guest()
		"expansion":
			sell_all_button.visible = false
			_render_expansion()
		"readonly":
			sell_all_button.visible = false
			modal_title.text = readonly_title
			modal_content.add_child(_wrapped(readonly_owner,LEAF))
			modal_content.add_child(_wrapped(readonly_body))
	call_deferred("_fit_workspace")


func _fit_workspace() -> void:
	if not modal_overlay.visible:
		return
	var cap := minf(490.0 if active_modal in ["seed_picker","plot_care","harvest","expansion","readonly","guest"] else 640.0,size.y-140.0)
	modal_panel.size.y = minf(cap,maxf(210,modal_content.get_combined_minimum_size().y+146))
	modal_panel.position.x = maxf(24,minf(modal_panel.position.x,size.x-modal_panel.size.x-24))



func _render_harvest() -> void:
	var result: Dictionary = last_harvest_result
	var batch: Dictionary = result["batch"]
	var defn := PlantDefs.get_plant(batch["kind"])
	modal_title.text = "收获啦！"
	modal_icon.texture = CRATE_ICON
	var rewards := HBoxContainer.new()
	rewards.add_theme_constant_override("separation", 12)
	modal_content.add_child(rewards)
	rewards.add_child(_reward_card(CROP_ICONS[batch["kind"]], defn["display_name"], "×%d" % batch["count"]))
	rewards.add_child(_reward_card(SEED_ICONS[batch["kind"]], "新种子", "×%d" % result["seeds"]))
	rewards.add_child(_reward_card(COIN_ICON, "默认售价", "%d 金" % game.batch_sale_price(batch)))
	modal_content.add_child(_attribute_chips(batch.get("attributes", {})))
	var summary := _label("%d 分 / 个    ·    经验 +%d" % [batch["score_breakdown"]["per_crop_score"], result["exp_gain"]], 20, LEAF)
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_content.add_child(summary)
	if result["farming_level_up"] or result["plant_level_up"]:
		modal_content.add_child(_wrapped("升级了！新的等级加成将在下一轮生效。", LEAF))
	var score := _disclosure(modal_content, "分数怎么算的", "harvest_score")
	score.add_child(_breakdown_card(batch["score_breakdown"], batch))
	var seeds := _disclosure(modal_content, "查看新种子词条", "harvest_seeds")
	for index in range(result.get("child_traits", []).size()):
		seeds.add_child(_label("种子 %d" % (index + 1), 14, TEXT_MUTED))
		seeds.add_child(_trait_chips(result["child_traits"][index]))
	var story := _disclosure(modal_content, "这一轮的经历", "harvest_story")
	for event in result["events"]:
		story.add_child(_wrapped(event["text"]))
	story.add_child(_wrapped("种地与%s各获得 %d 经验。" % [defn["display_name"], result["exp_gain"]]))
	if not bool(result.get("stored_crops", true)) or not bool(result.get("stored_seeds", true)):
		modal_content.add_child(_wrapped("仓库已满，部分产出待领取。", LOCK_RED))
		var pending := _solid_button("整理仓库", LEAF)
		pending.pressed.connect(func(): open_warehouse())
		modal_content.add_child(pending)
	var actions := HBoxContainer.new()
	modal_content.add_child(actions)
	var done := _solid_button("继续种田", LEAF)
	done.pressed.connect(_close_modal)
	actions.add_child(done)
	var market := _plain_button("去集市", TEXT_DARK)
	market.pressed.connect(open_market)
	actions.add_child(market)


func _render_harvest_all() -> void:
	var result: Dictionary = last_harvest_all_result
	modal_title.text = "收获了 %d 块地" % result["results"].size()
	modal_icon.texture = CRATE_ICON
	var rewards := HBoxContainer.new()
	modal_content.add_child(rewards)
	rewards.add_child(_reward_card(CRATE_ICON, "作物", "×%d" % result["total_crops"]))
	rewards.add_child(_reward_card(SEED_ICONS["cabbage"], "新种子", "×%d" % result["total_seeds"]))
	rewards.add_child(_reward_card(CROP_ICONS["cabbage"], "经验", "+%d" % result["total_exp"]))
	for entry in result["results"]:
		var batch: Dictionary = entry["batch"]
		var body := _disclosure(modal_content, "%s ×%d · %d 分/个 · 地块 %02d" % [PlantDefs.get_plant(batch["kind"])["display_name"], batch["count"], batch["score_breakdown"]["per_crop_score"], batch["plot_id"]], "harvest_all_%d" % batch["id"])
		body.add_child(_breakdown_card(batch["score_breakdown"], batch))
		if not bool(entry.get("stored_crops", true)) or not bool(entry.get("stored_seeds", true)):
			modal_content.add_child(_wrapped("地块 %02d 部分产出待领取：仓库已满。" % batch["plot_id"], LOCK_RED))
	if result["level_up_count"] > 0:
		modal_content.add_child(_wrapped("升级了！等级加成将在下一轮生效。", LEAF))
	var done := _solid_button("继续种田", LEAF)
	done.pressed.connect(_close_modal)
	modal_content.add_child(done)


func _breakdown_card(breakdown: Dictionary, batch: Dictionary, _compact := false) -> PanelContainer:
	var card := _panel(Color("#f0f3eb"), Color.TRANSPARENT, 12)
	card.name = "BreakdownCard_%d" % batch["id"]
	var stack := _card_stack(card)
	stack.add_child(_label("每个作物的分数", 16, TEXT_DARK))
	var values := [["基准", breakdown["base"]], ["等级", breakdown["level_bonus"]], ["波动", breakdown["fluctuation_bonus"]], ["浇水", breakdown["water_bonus"]], ["肥料", breakdown["fertilizer_bonus"]], ["遭遇", breakdown["encounter_bonus"]]]
	for entry in values:
		var row := HBoxContainer.new()
		stack.add_child(row)
		var caption := _label(entry[0], 14, TEXT_MUTED)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		row.add_child(_label(str(entry[1]) if entry[0] == "基准" else "%+d" % entry[1], 14, TEXT_DARK))
	stack.add_child(_wrapped("合计 %d 分 / 个 · 整批 %d 分 · 默认 %d 金币" % [breakdown["per_crop_score"], breakdown["batch_total"], game.batch_sale_price(batch)], LEAF))
	stack.add_child(_wrapped("播种等级：种地 Lv.%d / 植物 Lv.%d（各 +5%%/级）。波动 %d%%；浇水 %d/%d 时段。" % [breakdown["farming_level_snapshot"], breakdown["plant_level_snapshot"], breakdown["fluctuation_pct"], breakdown["water_segments_done"], breakdown["water_segments_total"]]))
	var fertilizer_kind: String = breakdown["fertilizer_kind"]
	stack.add_child(_wrapped("肥料：%s；遭遇档位：%s。" % ["本轮未生效" if fertilizer_kind == "" else PlantDefs.FERTILIZERS[fertilizer_kind]["display_name"], str(breakdown["encounter_tiers"])]))
	stack.add_child(_wrapped("整批分数 = %d × %d。售价由规则层按批次倍率计算并向下取整，包含生效的出售加成。" % [breakdown["per_crop_score"], breakdown["crop_count"]]))
	return card


func _render_seed_picker() -> void:
	modal_title.text = "播种 · 地块 %02d" % picker_plot_id
	modal_icon.texture = SEED_ICONS["cabbage"]
	var groups := game.seed_groups()
	if groups.is_empty():
		modal_content.add_child(_wrapped("没有可用种子。仓库有待领取种子时，先整理并领取。"))
		var shop_button := _solid_button("去买种子", LEAF)
		shop_button.pressed.connect(open_shop)
		modal_content.add_child(shop_button)
		return
	var grid := _grid(modal_content)
	for group in groups:
		grid.add_child(_seed_inventory_card(group, true))


func _emit_plant_seed(plot_id: int, seed_id: int) -> void:
	plant_seed_requested.emit(plot_id, seed_id)


func _render_plot_care() -> void:
	var plot := game.get_plot(care_plot_id)
	if plot.is_empty() or plot["seed_id"] == 0:
		_close_modal()
		return
	var defn := PlantDefs.get_plant(plot["kind"])
	modal_title.text = "%s · 地块 %02d" % [defn["display_name"], care_plot_id]
	modal_icon.texture = CROP_ICONS[plot["kind"]]
	var status := _panel(Color.WHITE, Color("#e1e8df"), 16)
	modal_content.add_child(status)
	var stack := _card_stack(status)
	var remaining: int = maxi(0, plot["ready_at"] - view_now)
	care_remaining_label = _label("已成熟" if remaining == 0 else "%02d:%02d 后成熟" % [int(remaining / 60), remaining % 60], 26, LEAF)
	stack.add_child(care_remaining_label)
	growth_bar = _progress(LEAF)
	growth_bar.value = 100.0 * (view_now - plot["planted_at"]) / maxf(1, plot["ready_at"] - plot["planted_at"])
	stack.add_child(growth_bar)
	care_segments = HFlowContainer.new()
	stack.add_child(care_segments)
	if remaining > 0:
		var water := _solid_button("浇水 · 免费", Color("#416c87"))
		care_water_button = water
		water.pressed.connect(func(): water_requested.emit(care_plot_id))
		modal_content.add_child(water)
	else:
		modal_content.add_child(_wrapped("关闭面板，点击地块收获。", LEAF))
	_update_care_watering(view_now)
	modal_content.add_child(_section_label("施肥"))
	var fertilizer: Dictionary = plot.get("fertilizer", {})
	var blocked: bool = not fertilizer.is_empty() and fertilizer["expires_at"] > view_now
	if blocked:
		modal_content.add_child(_wrapped("%s · 剩余 %d 分钟" % [PlantDefs.FERTILIZERS[fertilizer["kind"]]["display_name"], int(ceil(float(fertilizer["expires_at"] - view_now) / 60.0))], LEAF))
	var owned_any := false
	var choices := HFlowContainer.new()
	modal_content.add_child(choices)
	for kind in PlantDefs.FERTILIZERS:
		var uses := int(current_state["fertilizers"].get(kind, 0))
		if uses <= 0:
			continue
		owned_any = true
		var button := _solid_button("%s · %d 次" % [PlantDefs.FERTILIZERS[kind]["display_name"], uses], Color("#edf2e9"))
		button.disabled = blocked
		button.tooltip_text = "肥料未到期，不能替换" if blocked else "施用 1 次，有效 2 小时"
		button.pressed.connect(_emit_fertilize.bind(care_plot_id, kind))
		choices.add_child(button)
	if not owned_any:
		var shop := _plain_button("去买肥料", TEXT_DARK)
		shop.pressed.connect(func(): shop_tab = "fertilizers"; open_shop())
		modal_content.add_child(shop)
	var rules := _disclosure(modal_content, "照料规则", "care_rules")
	rules.add_child(_wrapped("基准 %d 分 / 作物。浇水免费，每个有效时段只记一次，各时段加分相加；2 级水壶一次浇三块地，每时段 +20%%。肥料每次持续 2 小时，可覆盖多轮种植，有效期间不能更换。" % defn["base_score"]))
	var story := _disclosure(modal_content, "本轮经历", "care_story")
	if plot.get("events", []).is_empty():
		story.add_child(_wrapped("还没有新的经历。"))
	for event in plot.get("events", []):
		story.add_child(_wrapped(event["text"]))


func _emit_fertilize(plot_id: int, kind: String) -> void:
	fertilize_requested.emit(plot_id, kind)


func _render_shop() -> void:
	modal_title.text = "商店"
	modal_icon.texture = SHOP_ICON
	var tabs := HBoxContainer.new()
	modal_content.add_child(tabs)
	for entry in [["seeds", "种子"], ["fertilizers", "肥料"], ["facilities", "设施"]]:
		var button := _tab_button(entry[1], shop_tab == entry[0])
		button.pressed.connect(func(): shop_tab = entry[0]; modal_scroll.scroll_vertical = 0; _render_modal())
		tabs.add_child(button)
	match shop_tab:
		"seeds":
			var grid := _grid(modal_content)
			for kind in PlantDefs.plant_kinds():
				grid.add_child(_seed_product_card(kind))
		"fertilizers":
			var grid := _grid(modal_content)
			for kind in PlantDefs.FERTILIZERS:
				grid.add_child(_fertilizer_product_card(kind))
		"facilities":
			modal_content.add_child(_shop_upgrade_card())
			modal_content.add_child(_breeder_product_card())


func _breeder_product_card() -> PanelContainer:
	var card := _panel(Color.WHITE, Color("#e1e8df"), 12)
	card.name = "BreederProductCard"
	var margin := _margin(12, 8)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	row.add_child(_image(WAREHOUSE_ICON, Vector2(44, 44)))
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 2)
	row.add_child(details)
	if bool(current_state["breeder"]["owned"]):
		details.add_child(_label("育种机 · 已拥有（%d 级）" % int(current_state["breeder"]["level"]), 18, TEXT_DARK))
		details.add_child(_label("到仓库 → 育种机页签使用；升级也在那里。", 14, TEXT_MUTED))
		return card
	var farming_level := PlantDefs.level_from_exp(int(current_state["farming_exp"]))
	details.add_child(_label("育种机（复制种子）", 18, TEXT_DARK))
	details.add_child(_label("种地 2 级解锁 · %d 金币 · 每 60 分钟复制 1 粒模板种子" % BreedingDefs.BREEDER_BUY_COST, 14, TEXT_MUTED))
	var button := _solid_button("购买 · %d 金币" % BreedingDefs.BREEDER_BUY_COST, LEAF)
	button.custom_minimum_size.x = 150
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	if farming_level < BreedingDefs.BREEDER_UNLOCK_FARMING_LEVEL:
		details.add_child(_label("🔒 需要种地 %d 级（当前 %d）" % [BreedingDefs.BREEDER_UNLOCK_FARMING_LEVEL, farming_level], 13, LOCK_RED))
		button.disabled = true
		button.text = "未解锁"
	button.pressed.connect(func(): buy_breeder_requested.emit())
	row.add_child(button)
	return card


func _section_label(text: String) -> Label:
	var label := _label(text, 20, FOREST)
	label.add_theme_constant_override("separation", 4)
	return label


func _seed_product_card(kind: String) -> PanelContainer:
	var defn := PlantDefs.get_plant(kind)
	var card := _panel(Color.WHITE, Color("#e1e8df"), 16)
	card.name = "SeedProduct_%s" % kind
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := _card_stack(card)
	_item_heading(stack, CROP_ICONS[kind], "%s种子" % defn["display_name"], "")
	var metrics := HFlowContainer.new()
	metrics.add_theme_constant_override("h_separation", 6)
	stack.add_child(metrics)
	metrics.add_child(_tag("%d 分钟" % int(defn["grow_seconds"] / 60), Color("#e9f0e4"), LEAF))
	metrics.add_child(_tag("基准 %d" % defn["base_score"], Color("#edf0f3"), Color("#4c687e")))
	var lock_reason := game.seed_lock_reason(kind)
	var info := _disclosure(stack, "生长与产出", "product_" + kind)
	info.add_child(_wrapped("%d 分钟成熟，每个作物基准 %d 分。每块地每轮产出 2～3 粒新种子；照料、等级和遭遇影响最终分数。" % [int(defn["grow_seconds"] / 60), defn["base_score"]]))
	if lock_reason != "":
		stack.add_child(_tag("未解锁", Color("#f5eae2"), LOCK_RED))
		info.add_child(_wrapped(lock_reason, LOCK_RED))
	var price := MarketDefs.discounted_total(defn["seed_price"], int(current_state["shop_level"]))
	var six_price := MarketDefs.discounted_total(6 * defn["seed_price"], int(current_state["shop_level"]))
	var actions := HBoxContainer.new()
	stack.add_child(actions)
	var one := _solid_button("1 粒 · %d 金" % price, LEAF)
	one.disabled = lock_reason != "" or int(current_state["coins"]) < price
	one.tooltip_text = lock_reason if lock_reason != "" else "购买 1 粒种子"
	one.pressed.connect(func(): buy_seed_requested.emit(kind, 1))
	actions.add_child(one)
	var six := _solid_button("6 粒 · %d 金" % six_price, Color("#edf2e9"))
	six.disabled = lock_reason != "" or int(current_state["coins"]) < six_price
	six.tooltip_text = lock_reason if lock_reason != "" else "购买 6 粒种子"
	six.pressed.connect(func(): buy_seed_requested.emit(kind, 6))
	actions.add_child(six)
	return card


func _fertilizer_product_card(kind: String) -> PanelContainer:
	var defn: Dictionary = PlantDefs.FERTILIZERS[kind]
	var card := _panel(Color.WHITE, Color("#e1e8df"), 16)
	card.name = "FertilizerProduct_%s" % kind
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := _card_stack(card)
	var effects := {"basic": "收获加分", "mutation": "更多新词条", "preserve": "保留与升档", "golden": "出售加成"}
	_item_heading(stack, FERTILIZER_ICONS[kind], defn["display_name"], effects[kind])
	var metrics := HFlowContainer.new()
	stack.add_child(metrics)
	metrics.add_child(_tag("2 小时", Color("#e9f0e4"), LEAF))
	metrics.add_child(_tag("基准 +20%", Color("#edf0f3"), Color("#4c687e")))
	var effect := "每份 10 次使用，每次覆盖一块地 2 小时，可跨多轮种植；有效期间不能替换。本轮作物增加 20% 基准分。"
	if kind == "mutation":
		effect += "新种子出现全新词条的概率增加 10 个百分点。"
	elif kind == "preserve":
		effect += "亲本词条保留率 80%，升档机会翻倍。"
	elif kind == "golden":
		effect += "带金克拉效果的批次出售倍率 +0.2，默认与客人报价均生效。"
	var info := _disclosure(stack, "效果与使用规则", "fertilizer_" + kind)
	info.add_child(_wrapped(effect))
	var required_level := PlantDefs.GOLDEN_FERTILIZER_UNLOCK_LEVEL_PLACEHOLDER if kind == "golden" else PlantDefs.FERTILIZER_UNLOCK_FARMING_LEVEL
	var locked := PlantDefs.level_from_exp(int(current_state["farming_exp"])) < required_level
	if locked:
		stack.add_child(_tag("种地 Lv.%d 解锁" % required_level, Color("#f5eae2"), LOCK_RED))
	else:
		stack.add_child(_label("剩余 %d 次" % int(current_state["fertilizers"].get(kind, 0)), 14, TEXT_MUTED))
	if kind == "golden":
		info.add_child(_wrapped("解锁条件暂定为种地 %d 级。" % required_level))
	var actions := HBoxContainer.new()
	stack.add_child(actions)
	for quantity in [1, 5]:
		var price := MarketDefs.discounted_total(quantity * defn["price"], int(current_state["shop_level"]))
		var button := _solid_button("%d 份 · %d 金" % [quantity, price], LEAF if quantity == 1 else Color("#edf2e9"))
		button.disabled = locked or int(current_state["coins"]) < price
		button.pressed.connect(func(): buy_fertilizer_requested.emit(kind, quantity))
		actions.add_child(button)
	return card


func _shop_upgrade_card() -> PanelContainer:
	var card := _panel(Color.WHITE, Color("#e1e8df"), 12)
	card.name = "ShopUpgradeCard"
	var margin := _margin(12, 8)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)
	var level := int(current_state["shop_level"])
	var shop_row := HBoxContainer.new()
	shop_row.add_theme_constant_override("separation", 10)
	stack.add_child(shop_row)
	shop_row.add_child(_image(SHOP_ICON, Vector2(50, 50)))
	var shop_details := VBoxContainer.new()
	shop_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_details.add_theme_constant_override("separation", 2)
	shop_row.add_child(shop_details)
	shop_details.add_child(_label("商店等级 %d 级 · 商品价格优惠 %d%%（整笔四舍五入）" % [level, int(MarketDefs.shop_discount(level) * 100)], 16, TEXT_DARK))
	if level >= MarketDefs.MAX_SHOP_LEVEL:
		shop_details.add_child(_label("已达当前版本最高等级。", 14, TEXT_MUTED))
	else:
		var next_cost: int = MarketDefs.SHOP_UPGRADE_COSTS[level + 1]
		var perk := "解锁第二种种子" if level == 1 else ("解锁锁定客人" if level == 2 else "解锁锁定公式")
		shop_details.add_child(_label("升到 %d 级：%s · %d 金币" % [level + 1, perk, next_cost], 14, TEXT_MUTED))
		var button := _solid_button("升级到 %d 级 · %d 金币" % [level + 1, next_cost], Color("#8a6d3f"))
		button.custom_minimum_size.x = 180
		button.size_flags_horizontal = Control.SIZE_SHRINK_END
		button.pressed.connect(func(): upgrade_shop_requested.emit())
		shop_row.add_child(button)
	var plot_row := HBoxContainer.new()
	plot_row.add_theme_constant_override("separation", 10)
	stack.add_child(plot_row)
	plot_row.add_child(_image(CRATE_ICON, Vector2(44, 44)))
	var plot_details := VBoxContainer.new()
	plot_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plot_details.add_theme_constant_override("separation", 2)
	plot_row.add_child(plot_details)
	var next_plot := game.next_buyable_plot_id()
	if next_plot == 0:
		plot_details.add_child(_label("扩地：十块地都已拥有。", 15, TEXT_DARK))
	else:
		var plot_price: int = MarketDefs.PLOT_PRICES.get(next_plot, 0)
		plot_details.add_child(_label("扩地：第 %d 块地 · %d 金币（已拥有 %d/10 块）" % [next_plot, plot_price, game.owned_plot_ids().size()], 15, TEXT_DARK))
		var plot_button := _solid_button("买下第 %d 块地" % next_plot, LEAF)
		plot_button.custom_minimum_size.x = 150
		plot_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		plot_button.pressed.connect(func(): buy_plot_requested.emit())
		plot_row.add_child(plot_button)
	var can_row := HBoxContainer.new()
	can_row.add_theme_constant_override("separation", 10)
	stack.add_child(can_row)
	can_row.add_child(_image(WATERING_CAN_ICON, Vector2(44, 44)))
	var can_details := VBoxContainer.new()
	can_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	can_details.add_theme_constant_override("separation", 2)
	can_row.add_child(can_details)
	if int(current_state["can_level"]) >= 2:
		can_details.add_child(_label("水壶 2 级：一次浇三块地，每时段 +20%。", 15, TEXT_DARK))
	else:
		can_details.add_child(_label("水壶 2 级：一次浇三块地、每时段加分翻倍 · %d 金币" % MarketDefs.CAN2_COST, 15, TEXT_DARK))
		var can_button := _solid_button("升级水壶", Color("#3f6d8e"))
		can_button.custom_minimum_size.x = 130
		can_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		can_button.pressed.connect(func(): buy_can2_requested.emit())
		can_row.add_child(can_button)
	return card


func _warehouse_tabs(active: String) -> HBoxContainer:
	var tabs := HBoxContainer.new()
	tabs.name = "WarehouseTabs"
	tabs.add_theme_constant_override("separation", 8)
	var crops_tab := _solid_button("作物 %d/%d" % [game.crop_slots_used(), game.warehouse_capacity()], LEAF if active == "crops" else Color("#edf2e9"))
	crops_tab.custom_minimum_size.x = 100
	crops_tab.pressed.connect(func(): open_warehouse("crops"))
	tabs.add_child(crops_tab)
	var seeds_tab := _solid_button("种子 %d/%d" % [game.seed_slots_used(), game.warehouse_capacity()], LEAF if active == "seeds" else Color("#edf2e9"))
	seeds_tab.custom_minimum_size.x = 100
	seeds_tab.pressed.connect(func(): open_warehouse("seeds"))
	tabs.add_child(seeds_tab)
	var breeder_tab := _solid_button("育种机", LEAF if active == "breeder" else Color("#edf2e9"))
	breeder_tab.custom_minimum_size.x = 90
	breeder_tab.pressed.connect(func(): open_breeder())
	tabs.add_child(breeder_tab)
	return tabs


func _render_pending_section() -> void:
	var pending: Dictionary = current_state.get("pending", {"crops": [], "seeds": []})
	if pending["crops"].is_empty() and pending["seeds"].is_empty():
		return
	var card := _panel(Color("#faf0e5"), Color("#e7d7c1"), 12)
	card.name = "PendingCard"
	modal_content.add_child(card)
	var stack := _card_stack(card)
	stack.add_child(_wrapped("待领取 · 作物 %d 批 / 种子 %d 粒" % [pending["crops"].size(), pending["seeds"].size()], ACCENT_GOLD))
	var claim := _solid_button("领取入库", LEAF)
	claim.tooltip_text = "领取仓库空间能容纳的产出，其余继续保留"
	claim.pressed.connect(func(): claim_pending_requested.emit())
	stack.add_child(claim)
	var list := _disclosure(stack, "整理待领取产出", "pending_items")
	for batch in pending["crops"]:
		var row := HBoxContainer.new()
		list.add_child(row)
		row.add_child(_wrapped("%s ×%d · %d 金" % [PlantDefs.get_plant(batch.get("kind", "cabbage"))["display_name"], batch["count"], game.batch_sale_price(batch)], TEXT_DARK))
		var sell := _plain_button("出售", TEXT_DARK)
		sell.size_flags_horizontal = Control.SIZE_SHRINK_END
		sell.pressed.connect(func(): sell_pending_crop_requested.emit(batch["id"]))
		row.add_child(sell)
	for seed in pending["seeds"]:
		var row := HBoxContainer.new()
		list.add_child(row)
		row.add_child(_wrapped("%s种子 · %s" % [PlantDefs.get_plant(seed["kind"])["display_name"], BreedingDefs.traits_text(seed.get("traits", []))], TEXT_DARK))
		var recycle := _plain_button("回收 · 5 金", TEXT_DARK)
		recycle.size_flags_horizontal = Control.SIZE_SHRINK_END
		recycle.pressed.connect(func(): recycle_pending_seed_requested.emit(seed["id"]))
		row.add_child(recycle)


func _render_warehouse_crops() -> void:
	modal_title.text = "仓库"
	modal_icon.texture = WAREHOUSE_ICON
	modal_content.add_child(_warehouse_tabs("crops"))
	_render_pending_section()
	if current_state["crop_batches"].is_empty():
		modal_content.add_child(_wrapped("还没有收获。成熟的作物会存放在这里。"))
	else:
		var grid := _grid(modal_content)
		for batch in current_state["crop_batches"]:
			var card := _panel(Color.WHITE, Color("#e1e8df"), 16)
			card.name = "BatchCard_%d" % batch["id"]
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(card)
			var stack := _card_stack(card)
			_item_heading(stack, CROP_ICONS[batch["kind"]], "%s ×%d" % [PlantDefs.get_plant(batch["kind"])["display_name"], batch["count"]], "%d 分 / 个 · 地块 %02d" % [int(batch.get("per_crop_score", batch["base_score"])), batch["plot_id"]])
			stack.add_child(_attribute_chips(batch.get("attributes", {})))
			var info := _disclosure(stack, "得分明细", "crop_%d" % batch["id"])
			if batch.has("score_breakdown"):
				info.add_child(_breakdown_card(batch["score_breakdown"], batch))
			var actions := HBoxContainer.new()
			stack.add_child(actions)
			var sell := _solid_button("出售 · %d 金" % game.batch_sale_price(batch), LEAF)
			sell.pressed.connect(_emit_batch_sale.bind(batch["id"]))
			actions.add_child(sell)
			var market := _plain_button("去比价", TEXT_DARK)
			market.pressed.connect(open_market)
			actions.add_child(market)
	_render_warehouse_upgrade()


func _render_warehouse_seeds() -> void:
	modal_title.text = "仓库"
	modal_icon.texture = WAREHOUSE_ICON
	modal_content.add_child(_warehouse_tabs("seeds"))
	_render_pending_section()
	var filter_row := HFlowContainer.new()
	filter_row.name = "SeedFilterRow"
	modal_content.add_child(filter_row)
	var filters: Array = [["all", "全部"]]
	for kind in PlantDefs.plant_kinds():
		filters.append([kind, PlantDefs.get_plant(kind)["display_name"]])
	filters.append_array([["traits", "有词条"], ["quality", "品质 ≥3"]])
	for entry in filters:
		var button := _tab_button(entry[1], seed_filter == entry[0])
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.pressed.connect(_change_seed_filter.bind(entry[0]))
		filter_row.add_child(button)
	var groups := game.seed_groups()
	if seed_filter in PlantDefs.plant_kinds():
		groups = groups.filter(func(group): return group["kind"] == seed_filter)
	elif seed_filter == "traits":
		groups = groups.filter(func(group): return not group["traits"].is_empty())
	elif seed_filter == "quality":
		groups = groups.filter(func(group): return BreedingDefs.quality_score(group["traits"]) >= 3)
	if groups.is_empty():
		modal_content.add_child(_wrapped("没有符合筛选条件的种子。"))
	else:
		var grid := _grid(modal_content)
		for group in groups:
			grid.add_child(_seed_inventory_card(group))
	var info := _disclosure(modal_content, "叠放与品质规则", "seed_rules")
	info.add_child(_wrapped("属性与词条完全相同的种子叠放，每格最多 %d 粒；品质取最高单条词条分，不把多个词条相加。回收每次消耗 1 粒，返还 5 金币。" % BreedingDefs.SEED_STACK_MAX))
	_render_warehouse_upgrade()


func _change_seed_filter(value: String) -> void:
	seed_filter = value
	_render_modal()


func _emit_template_toggle(seed_id: int, is_template: bool) -> void:
	if is_template:
		clear_template_requested.emit()
	else:
		set_template_requested.emit(seed_id)


func _emit_recycle(seed_id: int) -> void:
	recycle_seed_requested.emit(seed_id)


func _render_warehouse_upgrade() -> void:
	var level := int(current_state["warehouse_level"])
	var card := _panel(Color.WHITE, Color("#e1e8df"), 12)
	card.name = "WarehouseUpgradeCard"
	modal_content.add_child(card)
	var margin := _margin(12, 8)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	row.add_child(_image(WAREHOUSE_ICON, Vector2(50, 50)))
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 2)
	row.add_child(details)
	details.add_child(_label("仓库等级 %d 级 · 每区 %d 格" % [level, BreedingDefs.WAREHOUSE_CAPACITY_BY_LEVEL[level - 1]], 17, TEXT_DARK))
	if level >= BreedingDefs.WAREHOUSE_CAPACITY_BY_LEVEL.size():
		details.add_child(_label("已达当前版本最高等级。", 14, TEXT_MUTED))
		return
	var cost: int = BreedingDefs.WAREHOUSE_UPGRADE_COSTS[level + 1]
	details.add_child(_label("升级到 %d 级：每区 %d 格 · %d 金币" % [level + 1, BreedingDefs.WAREHOUSE_CAPACITY_BY_LEVEL[level], cost], 14, TEXT_MUTED))
	var button := _solid_button("升级仓库", Color("#8a6d3f"))
	button.custom_minimum_size.x = 120
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.pressed.connect(func(): upgrade_warehouse_requested.emit())
	row.add_child(button)


func _render_breeder() -> void:
	modal_title.text = "育种机"
	modal_icon.texture = WAREHOUSE_ICON
	modal_content.add_child(_warehouse_tabs("breeder"))
	var status := game.breeder_status(view_now)
	var card := _panel(Color.WHITE, Color("#e1e8df"), 16)
	card.name = "BreederStatusCard"
	modal_content.add_child(card)
	var stack := _card_stack(card)
	if not status["owned"]:
		_item_heading(stack, SEED_ICONS["cabbage"], "复制你的好种子", "60 分钟 / 粒 · 容量 8 粒")
		var buy := _solid_button("购买 · %d 金" % BreedingDefs.BREEDER_BUY_COST, LEAF)
		var farming_level := PlantDefs.level_from_exp(int(current_state["farming_exp"]))
		buy.disabled = farming_level < BreedingDefs.BREEDER_UNLOCK_FARMING_LEVEL or int(current_state["coins"]) < BreedingDefs.BREEDER_BUY_COST
		buy.tooltip_text = "需要种地 Lv.%d 与 %d 金币" % [BreedingDefs.BREEDER_UNLOCK_FARMING_LEVEL, BreedingDefs.BREEDER_BUY_COST]
		buy.pressed.connect(func(): buy_breeder_requested.emit())
		stack.add_child(buy)
		stack.add_child(_wrapped("种地 Lv.%d 解锁" % BreedingDefs.BREEDER_UNLOCK_FARMING_LEVEL))
	else:
		var level: int = status["level"]
		stack.add_child(_label("Lv.%d · 副本 %d/%d" % [level, status["pending"], status["capacity"]], 22, LEAF))
		stack.add_child(_wrapped("%d 分钟 / 粒" % int(status["cycle_seconds"] / 60)))
		if status["template"].is_empty():
			var choose := _plain_button("去种子仓库选择模板", TEXT_DARK)
			choose.pressed.connect(func(): open_warehouse("seeds"))
			stack.add_child(choose)
		else:
			var template: Dictionary = status["template"]
			_item_heading(stack, CROP_ICONS[template["kind"]], PlantDefs.get_plant(template["kind"])["display_name"], "品质 %d · 当前模板" % BreedingDefs.quality_score(template.get("traits", [])))
			stack.add_child(_trait_chips(template.get("traits", [])))
			var progress := _progress(LEAF)
			progress.value = 100.0 * status["progress_seconds"] / maxf(1, status["cycle_seconds"])
			stack.add_child(progress)
			stack.add_child(_wrapped("复制中 · %d%%" % int(progress.value) if status["running"] else "机内已满 · 复制暂停"))
		var actions := HBoxContainer.new()
		stack.add_child(actions)
		var collect := _solid_button("领取 %d 粒" % status["pending"], LEAF)
		collect.disabled = int(status["pending"]) == 0
		collect.pressed.connect(func(): collect_breeder_requested.emit())
		actions.add_child(collect)
		var next_cost: int = BreedingDefs.BREEDER_LEVELS[level]["upgrade_cost"]
		if level < 3:
			var upgrade := _plain_button("升级 · %d 金" % next_cost if next_cost >= 0 else "升级价格待定", TEXT_DARK)
			upgrade.disabled = next_cost < 0 or int(current_state["coins"]) < next_cost
			upgrade.pressed.connect(func(): upgrade_breeder_requested.emit())
			actions.add_child(upgrade)
	var rules := _disclosure(modal_content, "复制规则", "breeder_rules")
	rules.add_child(_wrapped("先在种子仓库设置模板，原种留在仓库。育种机定期复制出词条完全相同的种子，离线也继续计时；机内满了会暂停，领取后继续。切换模板时，各模板的进度分别保留，切回可以继续。"))


func _attribute_name(key: String) -> String:
	match key:
		"water":
			return "含水量"
		"fiber":
			return "纤维"
		"color":
			return "色泽"
	return key


func _formula_text(formula: Dictionary) -> String:
	if formula.is_empty():
		return "今日无公式"
	if formula.get("type", "") == "dual":
		return "主辅属性：%s ×%.2f + %s ×%.2f" % [
			_attribute_name(formula["attribute"]), float(formula["coefficient"]),
			_attribute_name(formula.get("sub_attribute", "")), float(formula.get("sub_coefficient", 0)),
		]
	return "单属性：%s ×%.2f" % [_attribute_name(formula["attribute"]), float(formula["coefficient"])]


func _render_market() -> void:
	modal_title.text = "今日集市"
	modal_icon.texture = COIN_ICON
	var market: Dictionary = current_state["market"]
	modal_content.add_child(_label("每天 00:00 刷新 · 北京时间", 14, TEXT_MUTED))
	if current_state["crop_batches"].is_empty():
		modal_content.add_child(_wrapped("还没有可出售的作物。收获后再来看看。"))
	for batch in current_state["crop_batches"]:
		modal_content.add_child(_market_batch_card(batch, market))
	var config := _disclosure(modal_content, "今日客人 · 收购公式 · 锁定", "market_config")
	var guest_row := VBoxContainer.new()
	guest_row.name = "MarketGuestRow"
	guest_row.add_theme_constant_override("separation", 8)
	config.add_child(guest_row)
	var locked_guest := int(market.get("locked_guest_id", 0))
	var pending_guest := int(market.get("lock_guest_pending", 0))
	var shop_level := int(current_state["shop_level"])
	for guest_id in market.get("guest_ids", []):
		var guest: Dictionary = MarketDefs.GUESTS[int(guest_id)]
		var card := _panel(Color.WHITE, Color("#e1e8df"), 12)
		card.name = "GuestCard_%d" % int(guest_id)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		guest_row.add_child(card)
		var stack := _card_stack(card)
		var is_locked: bool = locked_guest == int(guest_id)
		stack.add_child(_wrapped(guest["display_name"] + (" · 已锁定" if is_locked else ""), TEXT_DARK))
		stack.add_child(_wrapped("偏好 " + PlantDefs.get_plant(guest["preferred_kind"])["display_name"]))
		if shop_level >= 2:
			var lock_button := _solid_button("解锁客人" if is_locked and pending_guest == int(guest_id) else "锁定客人", Color("#edf2e9"))
			if is_locked and pending_guest == int(guest_id):
				lock_button.pressed.connect(func(): unlock_guest_requested.emit())
			else:
				lock_button.pressed.connect(_emit_lock_guest.bind(int(guest_id)))
			stack.add_child(lock_button)
		else:
			stack.add_child(_wrapped("商店 Lv.2 解锁锁定"))
	if pending_guest != locked_guest:
		config.add_child(_wrapped("锁定变更已记录，明天零点生效。", LEAF))
	config.add_child(_wrapped("客人收购偏好植物时，公式倍率额外 ×1.2。锁客人与锁公式的变更均于明天生效；锁公式保留类型，系数仍每日重抽。"))
	var locked_formula: Dictionary = market.get("locked_formula", {})
	for kind in PlantDefs.plant_kinds():
		var formula: Dictionary = market["formulas"].get(kind, {})
		var card := _panel(Color("#f0f3eb"), Color("#e1e8df"), 12)
		card.name = "FormulaCard_%s" % kind
		config.add_child(card)
		var stack := _card_stack(card)
		stack.add_child(_wrapped("%s · %s" % [PlantDefs.get_plant(kind)["display_name"], _formula_text(formula)], TEXT_DARK))
		var formula_locked_here: bool = locked_formula.get("kind", "") == kind
		if formula_locked_here:
			stack.add_child(_wrapped("已锁定公式类型"))
		if shop_level >= 3 and locked_guest != 0 and MarketDefs.GUESTS[locked_guest]["preferred_kind"] == kind:
			var button := _solid_button("解除公式锁" if formula_locked_here else "锁定公式类型", Color("#edf2e9"))
			if formula_locked_here:
				button.pressed.connect(func(): unlock_formula_requested.emit())
			else:
				button.pressed.connect(_emit_lock_formula.bind(kind))
			stack.add_child(button)
		else:
			stack.add_child(_wrapped("锁公式需要商店 Lv.3，并锁定偏好该作物的客人。"))


func _emit_lock_guest(guest_id: int) -> void:
	lock_guest_requested.emit(guest_id)


func _emit_lock_formula(kind: String) -> void:
	lock_formula_requested.emit(kind)


func _market_batch_card(batch: Dictionary, market: Dictionary) -> PanelContainer:
	var card := _panel(Color.WHITE, Color("#e1e8df"), 16)
	card.name = "MarketBatch_%d" % batch["id"]
	var stack := _card_stack(card)
	_item_heading(stack, CROP_ICONS[batch["kind"]], "%s ×%d" % [PlantDefs.get_plant(batch["kind"])["display_name"], batch["count"]], "%d 分 / 个 · 地块 %02d" % [int(batch.get("per_crop_score", batch["base_score"])), batch["plot_id"]])
	stack.add_child(_attribute_chips(batch.get("attributes", {})))
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	stack.add_child(controls)
	controls.add_child(_label("卖出", 15, TEXT_MUTED))
	var count_option := OptionButton.new()
	count_option.name = "SellCountOption"
	var selected_count: int = clampi(int(market_sell_counts.get(int(batch["id"]), batch["count"])), 1, batch["count"])
	for count_value in range(1, batch["count"] + 1):
		count_option.add_item("%d 个" % count_value)
	count_option.selected = selected_count - 1
	count_option.item_selected.connect(func(_index: int):
		market_sell_counts[int(batch["id"])] = count_option.selected + 1
		_render_modal())
	controls.add_child(count_option)
	var default_button := _solid_button("整批默认出售 · %d 金" % game.batch_sale_price(batch), Color("#edf2e9"))
	default_button.tooltip_text = "始终出售整批；左侧数量仅用于向客人拆批出售"
	default_button.pressed.connect(_emit_batch_sale.bind(batch["id"]))
	controls.add_child(default_button)
	var best_price := -1
	for guest_id in market.get("guest_ids", []):
		best_price = maxi(best_price, int(game.quote(batch, selected_count, int(guest_id))["coins"]))
	var quotes := VBoxContainer.new()
	quotes.add_theme_constant_override("separation", 10)
	stack.add_child(quotes)
	var info := _disclosure(stack, "报价计算", "quote_%d" % batch["id"])
	info.add_child(_wrapped("默认按整批出售，客人按所选数量出售。高亮表示这三位客人的最高报价；最终价格由批次分数、属性公式、客人偏好与肥料效果共同决定。"))
	for guest_id in market.get("guest_ids", []):
		var priced := game.quote(batch, selected_count, int(guest_id))
		var guest: Dictionary = MarketDefs.GUESTS[int(guest_id)]
		var best: bool = int(priced["coins"]) == best_price
		var quote_card := _panel(Color("#f0f5eb") if best else CREAM, Color("#9cbb8f") if best else Color("#e1e8df"), 12)
		quote_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quotes.add_child(quote_card)
		var column := _card_stack(quote_card)
		column.add_child(_wrapped(guest["display_name"] + (" · 最高" if best else ""), LEAF if best else TEXT_DARK))
		column.add_child(_label("%d 金" % priced["coins"], 25, LEAF if best else TEXT_DARK))
		var sell := _solid_button("卖给他", LEAF if best else Color("#e7ece2"))
		sell.pressed.connect(_emit_sell_to.bind(int(batch["id"]), int(guest_id), count_option))
		column.add_child(sell)
		info.add_child(_wrapped("%s · 倍率 ×%.2f%s · %d 个 = %d 金币" % [guest["display_name"], priced["multiplier"], "（包含偏好 ×1.2）" if priced["preferred"] else "", selected_count, priced["coins"]]))
	return card


func _emit_sell_to(batch_id: int, guest_id: int, count_option: OptionButton) -> void:
	sell_batch_to_requested.emit(batch_id, count_option.selected + 1, guest_id)


func _reward_card(texture: Texture2D, caption: String, count: String) -> PanelContainer:
	var card := _panel(Color.WHITE, Color("#e1e8df"), 13)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := _margin(14, 10)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	row.add_child(_image(texture, Vector2(64, 64)))
	var labels := VBoxContainer.new()
	labels.add_theme_constant_override("separation", 1)
	row.add_child(labels)
	labels.add_child(_label(caption, 16, TEXT_MUTED))
	labels.add_child(_label(count, 24, TEXT_DARK))
	return card


func _emit_batch_sale(batch_id: int) -> void:
	sell_batch_requested.emit(batch_id)


func _close_modal() -> void:
	modal_overlay.visible = false
	active_modal = ""


func close_modal_after_action() -> void:
	_close_modal()


# —— ESC 暂停菜单（主菜单轮）———————————————————————————————————


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or not event.is_action_pressed("pause"):
		return
	if pause_settings_view != null and pause_settings_view.visible:
		_show_pause_main()
	elif pause_overlay != null and pause_overlay.visible:
		_close_pause()
	elif modal_overlay.visible:
		_close_modal()
	else:
		for panel in [online_visit_panel,online_room_panel,online_run_panel,loadout_panel,crafting_panel,equipment_warehouse_panel,room_panel,coop_client_panel,expedition_hub_panel]:
			if panel != null and panel.visible:
				panel.close_requested.emit()
				get_viewport().set_input_as_handled()
				return
		if _any_panel_open():
			return  # Battle and route panels own their selection/menu rules.
		_open_pause()
	get_viewport().set_input_as_handled()


func _any_panel_open() -> bool:
	if active_modal != "" or modal_overlay.visible:
		return true
	for ui_panel in [expedition_hub_panel, loadout_panel, battle_screen, map_panel, crafting_panel, equipment_warehouse_panel, room_panel, coop_client_panel, online_room_panel, online_run_panel, online_visit_panel]:
		if ui_panel != null and ui_panel.visible:
			return true
	return false


func _build_pause_overlay() -> void:
	pause_overlay = Control.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.visible = false
	add_child(pause_overlay)
	var shade := ColorRect.new()
	shade.name = "PauseShade"
	shade.color = Color(0.10, 0.18, 0.13, 0.5)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(center)
	var card := _panel(CREAM, Color("#d5c9aa"), 18)
	card.custom_minimum_size = Vector2(500, 0)
	center.add_child(card)
	var stack := _card_stack(card)
	stack.add_child(_build_pause_main_view())
	stack.add_child(_build_pause_settings_view())


func _build_pause_main_view() -> VBoxContainer:
	pause_main_view = VBoxContainer.new()
	pause_main_view.name = "PauseMainView"
	pause_main_view.add_theme_constant_override("separation", 10)
	var title := _label("⏸ 暂停", 26, FOREST)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_main_view.add_child(title)
	var hint := _label("农场进度每一步都会自动保存", 13, TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_main_view.add_child(hint)
	var resume_button := _solid_button("继续游戏", LEAF)
	resume_button.name = "PauseResumeButton"
	resume_button.pressed.connect(_close_pause)
	pause_main_view.add_child(resume_button)
	var settings_button := _solid_button("设置", Color("#e7eef0"))
	settings_button.name = "PauseSettingsButton"
	settings_button.pressed.connect(_show_pause_settings)
	pause_main_view.add_child(settings_button)
	pause_back_button = _solid_button("回到主菜单", ACCENT_GOLD)
	pause_back_button.name = "PauseBackToMenuButton"
	pause_back_button.pressed.connect(_on_pause_back_to_menu)
	pause_main_view.add_child(pause_back_button)
	pause_quit_button = _solid_button("退出游戏", Color("#c98d77"))
	pause_quit_button.name = "PauseQuitButton"
	pause_quit_button.pressed.connect(_on_pause_quit)
	pause_main_view.add_child(pause_quit_button)
	var version := _label("v%s" % SettingsStore.game_version(), 12, TEXT_MUTED)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_main_view.add_child(version)
	return pause_main_view


func _build_pause_settings_view() -> VBoxContainer:
	pause_settings_view = VBoxContainer.new()
	pause_settings_view.name = "PauseSettingsView"
	pause_settings_view.visible = false
	pause_settings_view.add_theme_constant_override("separation", 12)
	var title := _label("设置", 22, FOREST)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_settings_view.add_child(title)
	pause_settings_panel = SettingsView.new()
	pause_settings_panel.name = "PauseSettingsPanel"
	var settings_scroll := ScrollContainer.new()
	settings_scroll.custom_minimum_size = Vector2(0,480)
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pause_settings_view.add_child(settings_scroll)
	pause_settings_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(pause_settings_panel)
	var back_button := _solid_button("返回", ACCENT_GOLD)
	back_button.name = "PauseSettingsBackButton"
	back_button.pressed.connect(_show_pause_main)
	pause_settings_view.add_child(back_button)
	return pause_settings_view


func _show_pause_settings() -> void:
	pause_settings_panel.refresh()
	pause_main_view.visible = false
	pause_settings_view.visible = true


func _show_pause_main() -> void:
	pause_main_view.visible = true
	pause_settings_view.visible = false


func _open_pause() -> void:
	# 联机房间/对局进行中不允许回主菜单（会直接断开双方链路），按钮置灰说明原因；
	# 退出游戏保持可用（玩家显式退出，tooltip 说明后果）。
	var coop_active := coop_host != null or room_panel.host != null or room_panel.client != null or coop_client_panel.client != null
	pause_back_button.disabled = coop_active
	pause_back_button.tooltip_text = "联机房间或对局进行中，请先在房间页退出" if coop_active else ""
	pause_quit_button.tooltip_text = "联机房间或对局进行中，退出会直接断开双方连接" if coop_active else ""
	_show_pause_main()
	pause_overlay.visible = true


func _close_pause() -> void:
	pause_overlay.visible = false
	_show_pause_main()


func _on_pause_quit() -> void:
	## 进度已即时落盘，直接退出进程；联机中的后果由按钮 tooltip 提示。
	get_tree().quit()


func _on_pause_back_to_menu() -> void:
	GameFlow.reset()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## —— 探险入口面板（2.1）：独立脚本挂接，实现不写进本文件 ——

func _build_expedition_panels() -> void:
	expedition_hub_panel = ExpeditionHubPanel.new()
	expedition_hub_panel.name = "ExpeditionHubPanel"
	expedition_hub_panel.close_requested.connect(close_expedition_panels)
	expedition_hub_panel.open_loadout_requested.connect(open_loadout)
	expedition_hub_panel.depart_requested.connect(_on_depart_requested)
	expedition_hub_panel.resume_requested.connect(_on_resume_requested)
	expedition_hub_panel.open_equipment_warehouse_requested.connect(open_equipment_warehouse)
	expedition_hub_panel.open_room_requested.connect(open_room)
	add_child(expedition_hub_panel)
	loadout_panel = LoadoutPanel.new()
	loadout_panel.name = "LoadoutPanel"
	loadout_panel.close_requested.connect(_on_loadout_close)
	loadout_panel.demo_battle_requested.connect(open_battle_demo)
	loadout_panel.depart_requested.connect(_on_loadout_depart_requested)
	add_child(loadout_panel)
	battle_screen = preload("res://scenes/battle_screen.tscn").instantiate()
	battle_screen.name = "BattleScreen"
	battle_screen.inventory_mutated.connect(_on_battle_inventory_mutated)
	battle_screen.battle_closed.connect(_on_battle_screen_closed)
	add_child(battle_screen)
	map_panel = ExpeditionMapPanel.new()
	map_panel.name = "ExpeditionMapPanel"
	map_panel.battle_start_requested.connect(_on_run_battle_start)
	map_panel.farm_save_requested.connect(_on_expedition_farm_save)
	map_panel.run_finished.connect(_on_run_finished)
	map_panel.settlement_presented.connect(func(receipt: Dictionary): last_expedition_receipt = receipt)
	add_child(map_panel)
	crafting_panel = CraftingPanel.new()
	crafting_panel.name = "CraftingPanel"
	crafting_panel.close_requested.connect(func() -> void: crafting_panel.close())
	crafting_panel.save_requested.connect(func() -> void: expedition_save_requested.emit(true))
	add_child(crafting_panel)
	equipment_warehouse_panel = WarehousePanel.new()
	equipment_warehouse_panel.name = "EquipmentWarehousePanel"
	equipment_warehouse_panel.close_requested.connect(func() -> void: equipment_warehouse_panel.close())
	equipment_warehouse_panel.save_requested.connect(func() -> void: expedition_save_requested.emit(true))
	equipment_warehouse_panel.open_loadout_requested.connect(open_loadout)
	add_child(equipment_warehouse_panel)
	room_panel = RoomPanel.new()
	room_panel.name = "RoomPanel"
	room_panel.close_requested.connect(func() -> void: room_panel.close())
	room_panel.coop_run_started_host.connect(_on_coop_run_started_host)
	room_panel.coop_run_started_client.connect(_on_coop_run_started_client)
	add_child(room_panel)
	coop_client_panel = CoopClientPanel.new()
	coop_client_panel.name = "CoopClientPanel"
	coop_client_panel.close_requested.connect(func() -> void:
		coop_client_panel.close()
		last_expedition_receipt = coop_client_panel.settlement_receipt.duplicate(true)
		_return_to_camp_if_idle())
	add_child(coop_client_panel)
	online_room_panel = OnlineRoomPanel.new()
	online_room_panel.name = "OnlineRoomPanel"
	online_room_panel.close_requested.connect(func() -> void: online_room_panel.close())
	add_child(online_room_panel)
	online_run_panel = OnlineRunPanel.new()
	online_run_panel.name = "OnlineRunPanel"
	online_run_panel.close_requested.connect(_on_online_run_panel_closed)
	add_child(online_run_panel)
	online_visit_panel = OnlineVisitPanel.new()
	online_visit_panel.name = "OnlineVisitPanel"
	online_visit_panel.close_requested.connect(func() -> void: online_visit_panel.close())
	online_visit_panel.visit_requested.connect(_on_visit_requested)
	add_child(online_visit_panel)


func open_crafting() -> void:
	## 2.5：制作台（2.1 占位转正）。
	_close_modal()
	crafting_panel.online_request = online_request
	crafting_panel.open(game)


func open_equipment_warehouse() -> void:
	## 2.5：装备／材料仓库（与作物/种子仓库分开）。
	_close_modal()
	equipment_warehouse_panel.online_request = online_request
	equipment_warehouse_panel.open(game)


func set_online_expedition(bridge: OnlineFarmBridge) -> void:
	## M3：线上模式由 farm_world 注入桥接层，房间/局命令都从这里走。
	online_bridge = bridge


func open_room() -> void:
	## 2.6：好友组队房间页（局域网／本机直连）；M3 线上模式走服务器房间。
	if location_router.is_valid() and location_id != "cave_camp":
		location_router.call("cave_camp",false)
	if online_mode:
		if online_bridge == null:
			show_status("线上房间不可用，请重新登录。")
			return
		if not online_run_panel.visible:
			_close_modal()
			online_room_panel.open(online_bridge)
			return
	_close_modal()
	room_panel.open(game)


func _on_coop_run_started_host(expedition: ExpeditionGame) -> void:
	active_expedition = expedition
	coop_host = room_panel.host
	if coop_host != null:
		map_panel.watch_host(coop_host)
		## F-04：合作局所有推进/出牌动作走同一会话裁定入口（host_action），
		## 战斗对象在每次裁定后从权威局重新恢复。
		map_panel.host_action_sink = func(kind: String, args: Dictionary) -> Dictionary:
			return coop_host.host_action(kind, args)
		battle_screen.action_sink = map_panel.host_action_sink
		battle_screen.combat_refresher = func() -> CombatGame:
			if coop_host == null or coop_host.expedition == null:
				return null
			return coop_host.expedition.restore_battle()
		battle_screen.player_key = "p1"
	expedition_save_requested.emit(true)
	map_panel.open(expedition)


func _on_coop_run_started_client(client: SessionClient) -> void:
	coop_client_panel.open(client)


func open_battle_demo() -> void:
	## 演示战斗入口：从战备面板进入；牌组按当前布局生成（2.3），不动存档。
	if _online_blocked("战斗演示不在线上模式开放。"):
		return
	_close_modal()
	if expedition_hub_panel != null:
		expedition_hub_panel.close()
	if loadout_panel != null:
		loadout_panel.visible = false
	battle_screen.open_demo(game)


func _on_battle_inventory_mutated() -> void:
	## 战后搜刮领取写入了内存库存：标记战备面板有改动，关闭战备时统一保存。
	if loadout_panel != null:
		loadout_panel.dirty = true


## —— 探险局编排（2.4）：出发/继续、局内战斗路由、结算收尾 ——

func _on_depart_requested() -> void:
	_clear_coop_sinks()
	if online_mode:
		_on_depart_requested_online()
		return
	var result := ExpeditionGame.depart(game, int(Time.get_unix_time_from_system()))
	if not result["ok"]:
		if expedition_hub_panel != null:
			expedition_hub_panel.status_label.text = result["reason"]
		return
	active_expedition = result["game"]
	expedition_save_requested.emit(true)
	_close_modal()
	if expedition_hub_panel != null:
		expedition_hub_panel.close()
	map_panel.open(active_expedition)


func _on_loadout_depart_requested() -> void:
	_clear_coop_sinks()
	## 战备页直接出发：先剔除演示物品（与关闭保存同一规则），失败原因留在战备页。
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.strip_demo_instances()
	var result := ExpeditionGame.depart(game, int(Time.get_unix_time_from_system()))
	if not result["ok"]:
		loadout_panel.status_label.text = str(result["reason"])
		return
	loadout_panel.close()
	loadout_panel.mark_saved()
	if battle_screen != null:
		battle_screen.carried_hp = -1
	active_expedition = result["game"]
	expedition_save_requested.emit(true)
	_close_modal()
	expedition_hub_panel.close()
	map_panel.open(active_expedition)


func _on_resume_requested() -> void:
	_clear_coop_sinks()
	if online_mode:
		_on_resume_requested_online()
		return
	var result := ExpeditionGame.resume(game)
	if not result["ok"]:
		if expedition_hub_panel != null:
			expedition_hub_panel.status_label.text = result["reason"]
		return
	active_expedition = result["game"]
	_close_modal()
	if expedition_hub_panel != null:
		expedition_hub_panel.close()
	map_panel.open(active_expedition)
	if str(active_expedition.run.get("phase", "")) == "battle":
		var combat := active_expedition.restore_battle()
		if combat != null:
			map_panel.visible = false
			battle_screen.open_run(combat)


func _on_run_battle_start(combat: CombatGame) -> void:
	map_panel.visible = false
	if active_expedition != null:
		battle_screen.layer_id = str(active_expedition.run.get("layer_id","moss_stone_shallow"))
	battle_screen.open_run(combat)


func _on_battle_screen_closed() -> void:
	if not battle_screen.run_mode:
		return
	battle_screen.run_mode = false
	var finished := battle_screen.last_combat
	if active_expedition == null or finished == null:
		return
	map_panel.visible = true
	map_panel.report_battle_result(finished)
	map_panel.battle_finished()


func _on_expedition_farm_save() -> void:
	expedition_save_requested.emit(true)


func _on_run_finished() -> void:
	active_expedition = null
	coop_host = null
	_clear_coop_sinks()
	_return_to_camp_if_idle()


## R4（稿 §6）：结算完成 → 回洞口营地（"入口营地接住一次完整结算"）；失败静默（无路由时维持现状）。
func _return_to_camp_if_idle() -> void:
	if location_router == null or not location_router.is_valid():
		return
	location_router.call("cave_camp", false)
	if not last_expedition_receipt.is_empty():
		show_status("本次带回 %d 件 · 新收获 %d 件 · 保护 %d 件。点营地行囊整理。" % [last_expedition_receipt.get("returned",[]).size(),last_expedition_receipt.get("gained",[]).size(),last_expedition_receipt.get("protected",[]).size()])


## 线上局面板关闭：局终（outcome 非空）→ 回营地；局中关闭＝"返回农场并暂停"（保持现状）。
func _on_online_run_panel_closed() -> void:
	var run_over := online_bridge != null and str(online_bridge.mirror_run.get("outcome", "")) != ""
	if run_over:
		last_expedition_receipt = online_bridge.mirror_settlement.duplicate(true)
	online_run_panel.close()
	_return_to_camp_if_idle()


## —— M3：线上局编排（出发/继续/进局面板） ——

func _on_depart_requested_online() -> void:
	if online_bridge == null:
		return
	if expedition_hub_panel != null:
		expedition_hub_panel.status_label.text = "正在向服务器申请出发……"
	var reply: Dictionary = await online_bridge.depart_solo()
	if str(reply.get("t", "")) != "req_ok":
		if expedition_hub_panel != null:
			expedition_hub_panel.status_label.text = str(reply.get("msg", "出发失败，稍后再试"))
		return
	if expedition_hub_panel != null:
		expedition_hub_panel.status_label.text = ""
		expedition_hub_panel.close()
	_close_modal()
	enter_online_run()


func _on_resume_requested_online() -> void:
	if online_bridge == null:
		return
	if online_bridge.mirror_run.is_empty():
		if expedition_hub_panel != null:
			expedition_hub_panel.status_label.text = "服务器上没有你的活动局。"
		return
	_close_modal()
	if expedition_hub_panel != null:
		expedition_hub_panel.close()
	enter_online_run()


## 进入选中的线上局：局快照由 bridge 维护，面板拉镜像渲染（W07）。
func enter_online_run() -> void:
	if online_bridge == null or online_bridge.mirror_run.is_empty():
		return
	online_room_panel.close()
	online_run_panel.open(online_bridge)


## 回到单人路径时清掉合作裁定入口：地图/战斗面板恢复直调本地 ExpeditionGame。
func _clear_coop_sinks() -> void:
	map_panel.watch_host(null)
	map_panel.host_action_sink = Callable()
	battle_screen.action_sink = Callable()
	battle_screen.combat_refresher = Callable()
	battle_screen.player_key = "p1"


func open_expedition_hub() -> void:
	## M3：线上模式洞窟开放——单人出发/继续走服务器（_on_depart/_on_resume 在线分支）。
	_close_modal()
	expedition_hub_panel.open(game)


func open_loadout() -> void:
	_close_modal()
	expedition_hub_panel.close()
	loadout_panel.online_request = online_request
	loadout_panel.open(game)


func close_expedition_panels() -> void:
	if expedition_hub_panel != null:
		expedition_hub_panel.close()


func _on_loadout_close() -> void:
	## 关闭战备：剔除演示物品；真实改动通过信号交给组合根保存；重置演示连战的生命延续。
	loadout_panel.close()
	_return_to_camp_if_idle()
	var dirty: bool = loadout_panel.dirty
	loadout_panel.mark_saved()
	if battle_screen != null:
		battle_screen.carried_hp = -1
	expedition_save_requested.emit(dirty)


func _image(texture: Texture2D, dimensions: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	var bounds: Rect2i = texture.get_image().get_used_rect().grow(14)
	var cropped := AtlasTexture.new()
	cropped.atlas = texture
	cropped.region = Rect2(Vector2(bounds.position), Vector2(bounds.size))
	icon.texture = cropped
	icon.custom_minimum_size = dimensions
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon


func _panel(fill: Color, border: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(fill, border, radius))
	return panel


func _style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.10, 0.18, 0.11, 0.08)
	style.shadow_size = 3 if radius >= 12 and fill.a > 0.0 else 0
	return style


func _margin(horizontal: int, vertical: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", horizontal)
	margin.add_theme_constant_override("margin_right", horizontal)
	margin.add_theme_constant_override("margin_top", vertical)
	margin.add_theme_constant_override("margin_bottom", vertical)
	return margin


func _label(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", maxi(18,size))
	label.add_theme_color_override("font_color", color)
	return label


func _solid_button(content: String, fill: Color) -> Button:
	var button := Button.new()
	button.text = content
	button.custom_minimum_size.y = 40
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 18)
	var ink := TEXT_DARK if fill.get_luminance() > 0.5 else Color.WHITE
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", ink)
	button.add_theme_color_override("font_pressed_color", ink)
	button.add_theme_color_override("font_disabled_color", Color("#768176"))
	button.add_theme_stylebox_override("normal", _button_style(fill))
	button.add_theme_stylebox_override("hover", _button_style(fill.lightened(0.08)))
	button.add_theme_stylebox_override("pressed", _button_style(fill.darkened(0.06)))
	button.add_theme_stylebox_override("disabled", _button_style(Color("#e7ece4")))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("#609b74"), 10))
	return button


func _plain_button(content: String, _color: Color) -> Button:
	return _solid_button(content, Color("#edf2e9"))


func _button_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

## 展示层组件：所有分数、品质、价格继续查询规则层。
func _update_care_watering(now: int) -> void:
	if not is_instance_valid(care_segments):
		return
	var watering := game.watering_status(care_plot_id, now)
	var signature := str(watering)
	if signature == care_watering_signature:
		return
	care_watering_signature = signature
	for child in care_segments.get_children():
		care_segments.remove_child(child)
		child.queue_free()
	var current_watered := false
	for segment in watering["segments"]:
		var current: bool = watering["current"] == segment["index"]
		if current:
			current_watered = bool(segment["watered"])
		var caption := "已浇水" if segment["watered"] else ("可浇水" if current and not watering["mature"] else ("已错过" if segment["index"] < watering["current"] or watering["mature"] else "未到时段"))
		var chip := _tag("%d · %s" % [segment["index"] + 1, caption], Color("#e9f0e4") if segment["watered"] else Color("#edf0f3"), LEAF if segment["watered"] else TEXT_MUTED)
		chip.tooltip_text = "播种后第 %d～%d 分钟" % [int(segment["start_offset"] / 60), int(segment["end_offset"] / 60)]
		care_segments.add_child(chip)
	if is_instance_valid(care_water_button):
		care_water_button.visible = not watering["mature"]
		# 2 级水壶还可照料其它地块，是否允许再次使用由规则层裁定。
		care_water_button.disabled = current_watered and int(current_state["can_level"]) < 2
		care_water_button.text = "本时段已浇水" if care_water_button.disabled else "浇水 · 免费"


func _wrapped(content: String, color := TEXT_MUTED) -> Label:
	var label := _label(content, 14, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _card_stack(card: PanelContainer) -> VBoxContainer:
	var margin := _margin(16, 14)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)
	return stack


func _grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	parent.add_child(grid)
	return grid


func _tag(caption: String, fill: Color, ink: Color) -> PanelContainer:
	var chip := _panel(fill, Color.TRANSPARENT, 8)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var margin := _margin(9, 4)
	chip.add_child(margin)
	var label := _label(caption, 14, ink)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(label)
	return chip


func _attribute_chips(attributes: Dictionary) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	for entry in [["water", "水分", "#e8f0f7", "#4a708c"], ["fiber", "纤维", "#eaf0e0", "#597542"], ["color", "色泽", "#f5eade", "#a07747"]]:
		row.add_child(_tag("%s %d" % [entry[1], int(attributes.get(entry[0], 0))], Color(entry[2]), Color(entry[3])))
	return row


func _trait_chips(traits: Array) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	if traits.is_empty():
		row.add_child(_tag("普通种子", Color("#f0f3eb"), TEXT_MUTED))
	for entry in traits:
		row.add_child(_tag(BreedingDefs.trait_text(entry), Color("#e9f0e4"), LEAF))
	return row


func _item_heading(parent: Control, texture: Texture2D, title: String, subtitle: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	row.add_child(_image(texture, Vector2(52, 52)))
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(labels)
	var heading := _label(title, 20, TEXT_DARK)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	labels.add_child(heading)
	if subtitle != "":
		labels.add_child(_wrapped(subtitle))


func _disclosure(parent: Control, caption: String, key: String) -> VBoxContainer:
	var holder := VBoxContainer.new()
	holder.name = "Disclosure_" + key
	parent.add_child(holder)
	var toggle := _plain_button(caption, TEXT_MUTED)
	toggle.custom_minimum_size.y = 28
	toggle.add_theme_font_size_override("font_size", 14)
	toggle.add_theme_color_override("font_color", TEXT_MUTED)
	toggle.add_theme_color_override("font_hover_color", LEAF)
	toggle.add_theme_color_override("font_pressed_color", LEAF)
	toggle.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	toggle.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.toggle_mode = true
	toggle.button_pressed = bool(expanded_details.get(key, false))
	toggle.text = ("▾  " if toggle.button_pressed else "▸  ") + caption
	holder.add_child(toggle)
	var body := VBoxContainer.new()
	body.name = "DetailsBody"
	body.add_theme_constant_override("separation", 6)
	body.visible = toggle.button_pressed
	holder.add_child(body)
	toggle.toggled.connect(func(expanded: bool):
		expanded_details[key] = expanded
		body.visible = expanded
		toggle.text = ("▾  " if expanded else "▸  ") + caption)
	return body


func _tab_button(caption: String, selected: bool) -> Button:
	var button := _solid_button(caption, LEAF if selected else Color("#edf2e9"))
	button.custom_minimum_size.x = 68
	return button


func _progress(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	bar.add_theme_stylebox_override("background", _style(Color("#e6ece1"), Color.TRANSPARENT, 4))
	bar.add_theme_stylebox_override("fill", _style(color, Color.TRANSPARENT, 4))
	return bar


func _seed_inventory_card(group: Dictionary, planting := false) -> PanelContainer:
	var defn := PlantDefs.get_plant(group["kind"])
	var card := _panel(Color.WHITE, Color("#e1e8df"), 16)
	card.name = ("SeedGroup_" if planting else "SeedCard_") + str(group["seed_ids"][0])
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := _card_stack(card)
	var quality := BreedingDefs.quality_score(group["traits"])
	_item_heading(stack, CROP_ICONS[group["kind"]], "%s ×%d" % [defn["display_name"], group["count"]], "%d 分钟成熟 · 基准 %d" % [int(defn["grow_seconds"] / 60), defn["base_score"]])
	var quality_row := HFlowContainer.new()
	stack.add_child(quality_row)
	quality_row.add_child(_tag("品质 %d" % quality, Color("#f5edda") if quality > 0 else Color("#f0f3eb"), ACCENT_GOLD if quality > 0 else TEXT_MUTED))
	var template_id := int(current_state["breeder"]["template_seed_id"])
	var is_template: bool = template_id != 0 and template_id in group["seed_ids"]
	if is_template:
		quality_row.add_child(_tag("育种模板", Color("#e8f0f7"), Color("#4a708c")))
	stack.add_child(_trait_chips(group["traits"]))
	var actions := HBoxContainer.new()
	stack.add_child(actions)
	var seed_id := int(group["seed_ids"][0])
	if planting:
		var button := _solid_button("播种", LEAF)
		button.pressed.connect(_emit_plant_seed.bind(picker_plot_id, seed_id))
		actions.add_child(button)
	else:
		var template := _solid_button("解除模板" if is_template else "设为模板", LEAF)
		template.pressed.connect(_emit_template_toggle.bind(seed_id, is_template))
		actions.add_child(template)
		var recycle := _plain_button("回收 · 5 金", TEXT_DARK)
		recycle.disabled = is_template
		recycle.tooltip_text = "育种模板不能回收" if is_template else "回收 1 粒种子，获得 5 金币"
		recycle.pressed.connect(_emit_recycle.bind(seed_id))
		actions.add_child(recycle)
	return card

func set_object_anchor(at: Vector2) -> void:
	object_anchor = at


func set_location(id: String, owner: Dictionary = {}) -> void:
	location_id = id
	location_owner = owner
	_close_modal()
	brand_title.text = {"farm":"我的农场","shop":"田边杂货铺","cave_camp":"洞口营地","visit_yard":str(owner.get("nick","邻居"))+" · 院子","visit_house":str(owner.get("nick","邻居"))+" · 小屋"}.get(id,"小小农场")
	brand_title.tooltip_text = "右上角是我的资产" if id.begins_with("visit") else ""
	get_node("FarmBrand").custom_minimum_size.x = 0
	get_node("FarmBrand").offset_right = 390 if id.begins_with("visit") else 345
	level_bar.visible = id == "farm"
	level_value.visible = id == "farm"
	tutorial_panel.visible = id == "farm" and int(current_state.get("tutorial_step",5)) < 5
	show_plot_hint(0,{},view_now)
	update_harvest_entry()
	_refresh_world_quotes()
	if owner_quote_label != null:
		var welcome := str(owner.get("welcome_message",""))
		owner_quote_label.text = str(owner.get("nick","邻居"))+" · "+("在线" if bool(owner.get("online",false)) else "离线")+"\n静态形象 · 默认家居\n"+(welcome if not welcome.is_empty() else "主人尚未设置欢迎留言。")


func show_object_hint(caption: String) -> void:
	if caption == "":
		show_plot_hint(0,{},view_now)
	else:
		plot_hint_label.text = caption


func open_expansion() -> void:
	active_modal = "expansion"
	_apply_modal_height(220)
	modal_overlay.visible = true
	_render_modal()


func _render_expansion() -> void:
	modal_title.text = "开垦新田"
	modal_icon.texture = WAREHOUSE_ICON
	var owned := game.owned_plot_ids().size()
	modal_content.add_child(_wrapped("已开垦 %d / %d 块地" % [owned,FarmGame.MAX_PLOTS],LEAF))
	modal_content.add_child(_wrapped("扩地按原来的开垦顺序进行。购买后，这片草地就能播种。"))
	# The existing facilities card is the single source of cost, unlock conditions and purchase action.
	var price := int(MarketDefs.PLOT_PRICES.get(owned+1,0))
	modal_content.add_child(_wrapped("开垦下一块地：%d 金" % price,LEAF))
	var buy := _solid_button("开垦 · %d 金" % price,LEAF)
	buy.disabled = owned >= FarmGame.MAX_PLOTS or int(current_state.get("coins",0))<price
	buy.pressed.connect(func(): buy_plot_requested.emit())
	modal_content.add_child(buy)


func open_readonly(title: String, content: String, owner: String) -> void:
	readonly_title = title
	readonly_body = content
	readonly_owner = owner
	active_modal = "readonly"
	_apply_modal_height(200)
	modal_overlay.visible = true
	_render_modal()


func selected_basket() -> Dictionary:
	var batches: Array = current_state.get("crop_batches",[])
	for batch in batches:
		if int(batch["id"]) == basket_batch_id:
			return batch
	if not batches.is_empty():
		basket_batch_id = int(batches[0]["id"])
		return batches[0]
	basket_batch_id = 0
	return {}


func open_basket() -> void:
	selected_guest_id = 0
	active_modal = "basket"
	_apply_modal_height(270)
	modal_overlay.visible = true
	_render_modal()


func _render_basket() -> void:
	modal_title.text = "作物篮"
	modal_icon.texture = CRATE_ICON
	var chosen := selected_basket()
	modal_content.add_child(_wrapped("选一批作物和数量，三位客人的报价会同步更新。",LEAF))
	if chosen.is_empty():
		modal_content.add_child(_wrapped("篮子空了，回农场收获后再来。"))
	for batch in current_state.get("crop_batches",[]):
		var card := _panel(Color.WHITE,Color("#9eb887") if int(batch["id"]) == basket_batch_id else Color("#dce4d3"),12)
		modal_content.add_child(card)
		var col := _card_stack(card)
		var select := _solid_button("%s ×%d%s" % [PlantDefs.get_plant(batch["kind"])["display_name"],batch["count"]," · 已选" if int(batch["id"]) == basket_batch_id else ""],Color("#e4ecd9"))
		select.pressed.connect(func(): basket_batch_id = int(batch["id"]); _render_modal(); _refresh_world_quotes())
		col.add_child(select)
		if int(batch["id"]) == basket_batch_id:
			var quantity := OptionButton.new()
			quantity.name = "BasketQuantity"
			for n in range(1,int(batch["count"])+1):
				quantity.add_item("卖出 %d 个" % n)
			quantity.selected = clampi(int(market_sell_counts.get(basket_batch_id,batch["count"])),1,int(batch["count"]))-1
			quantity.item_selected.connect(func(n): market_sell_counts[basket_batch_id] = n+1; _refresh_world_quotes())
			col.add_child(quantity)
	var done := _solid_button("提好篮子 · 找客人",LEAF)
	done.pressed.connect(_close_modal)
	modal_content.add_child(done)


func open_guest(guest_id: int) -> void:
	selected_guest_id = guest_id
	active_modal = "guest"
	_apply_modal_height(230)
	modal_overlay.visible = true
	_render_modal()


func _render_guest() -> void:
	var guest: Dictionary = MarketDefs.GUESTS.get(selected_guest_id,{})
	modal_title.text = str(guest.get("display_name","客人"))+" · 收购"
	modal_icon.texture = COIN_ICON
	var batch := selected_basket()
	if batch.is_empty():
		modal_content.add_child(_wrapped("今天还没有带作物来。"))
		return
	var count := clampi(int(market_sell_counts.get(int(batch["id"]),batch["count"])),1,int(batch["count"]))
	var price := game.quote(batch,count,selected_guest_id)
	_item_heading(modal_content,CROP_ICONS[batch["kind"]],"%s ×%d" % [PlantDefs.get_plant(batch["kind"])["display_name"],count],"篮子里的所选数量")
	modal_content.add_child(_label("报价 %d 金" % price["coins"],32,LEAF))
	modal_content.add_child(_wrapped("倍率 ×%.2f%s；成交时会重新核对库存和今天的报价。" % [price["multiplier"]," · 偏好加成 ×1.2" if price["preferred"] else ""]))
	var sell := _solid_button("成交 · %d 金" % price["coins"],LEAF)
	sell.name = "GuestConfirmSale"
	sell.pressed.connect(func(): sell_batch_to_requested.emit(int(batch["id"]),count,selected_guest_id))
	modal_content.add_child(sell)
	var change := _plain_button("重新选批次与数量",TEXT_DARK)
	change.pressed.connect(open_basket)
	modal_content.add_child(change)
	var board := _plain_button("查看全部报价与锁定",TEXT_DARK)
	board.pressed.connect(open_market)
	modal_content.add_child(board)


func _build_world_quotes() -> void:
	owner_quote = _panel(CREAM,Color("#c9ceb4"),10)
	owner_quote.name = "OwnerWelcome"
	owner_quote.custom_minimum_size = Vector2(300,0)
	owner_quote.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner_quote.visible = false
	add_child(owner_quote)
	owner_quote_label = _wrapped("",TEXT_DARK)
	owner_quote_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	owner_quote.add_child(owner_quote_label)
	for i in range(3):
		var panel := _panel(Color("#fff9e8"),Color("#b9c79d"),12)
		panel.name = "GuestDialogue_%d" % (i+1)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.size = Vector2(220,120)
		panel.visible = false
		add_child(panel)
		var label := _label("",18,TEXT_DARK)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(label)
		guest_quotes.append(panel)
		quote_labels.append(label)
	move_child(modal_overlay,-1)
	move_child(pause_overlay,-1)


func _refresh_world_quotes() -> void:
	if quote_labels.is_empty() or game == null:
		return
	var ids: Array = game.state.get("market",{}).get("guest_ids",[])
	var batch := selected_basket()
	var count := 0 if batch.is_empty() else clampi(int(market_sell_counts.get(int(batch["id"]),batch["count"])),1,int(batch["count"]))
	var best := -1
	for id in ids:
		if count>0:
			best = maxi(best,int(game.quote(batch,count,int(id))["coins"]))
	for i in range(guest_quotes.size()):
		guest_quotes[i].visible = location_id == "shop" and i<ids.size()
		if i>=ids.size():
			continue
		var guest: Dictionary = MarketDefs.GUESTS[int(ids[i])]
		var pref: String = PlantDefs.get_plant(guest["preferred_kind"])["display_name"]
		var text: String = str(guest["display_name"])+"\n今天想买"+pref+"。"
		if count>0:
			var price := game.quote(batch,count,int(ids[i]))
			text += "\n%d 个 · %d 金%s" % [count,price["coins"]," · 最高" if int(price["coins"])==best else ""]
		else:
			text += "\n先到作物篮选一批菜吧。"
		quote_labels[i].text = text


func _process(_delta: float) -> void:
	if owner_quote != null:
		owner_quote.visible = location_id=="visit_house" and not _any_panel_open()
		if owner_quote.visible and owner_projection.is_valid():
			var head: Vector2 = owner_projection.call()
			owner_quote.size = Vector2(300,0)
			owner_quote.position = Vector2(clampf(head.x-150,16,size.x-316),clampf(head.y-owner_quote.size.y-32,104,size.y-200))
	for notice in get_children():
		if str(notice.name).begins_with("SaleAcknowledged"):
			notice.visible = location_id == "shop"
	if location_id != "shop" or not quote_projection.is_valid():
		return
	for i in range(guest_quotes.size()):
		guest_quotes[i].visible = not _any_panel_open() and i<game.state.get("market",{}).get("guest_ids",[]).size()
		var at: Vector2 = quote_projection.call(i)
		guest_quotes[i].position = Vector2(clampf(at.x-110,16,size.x-236),clampf(at.y-135,98,size.y-220))


func show_sale_feedback(guest_id: int, coins: int) -> void:
	# Called only after a successful rule result or authoritative reply.
	if location_id != "shop" or not quote_projection.is_valid():
		return
	var ids: Array = game.state["market"]["guest_ids"]
	var index := ids.find(guest_id)
	if index < 0:
		return
	var notice := _label("谢谢，菜很新鲜！\n+%d 金币" % coins,22,LEAF)
	notice.name = "SaleAcknowledged"
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.position = quote_projection.call(index)+Vector2(-80,-90)
	notice.z_index = 60
	add_child(notice)
	var tween := notice.create_tween().set_parallel(true)
	if not SettingsStore.get_reduce_motion():
		tween.tween_property(notice,"position:y",notice.position.y-32,1.4)
	tween.tween_property(notice,"modulate:a",0.0,0.6).set_delay(0.8)
	tween.chain().tween_callback(notice.queue_free)
