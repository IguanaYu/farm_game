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

const SHOP_ICON := preload("res://assets/sprites/facility_shop.png")
const WAREHOUSE_ICON := preload("res://assets/sprites/facility_warehouse.png")
const CRATE_ICON := preload("res://assets/sprites/item_harvest_crate.png")
const COIN_ICON := preload("res://assets/sprites/item_coin.png")
const SEED_ICONS := {
	"cabbage": preload("res://assets/sprites/seed_cabbage.png"),
	"carrot": preload("res://assets/sprites/seed_carrot.png"),
}
const CROP_ICONS := {
	"cabbage": preload("res://assets/sprites/crop_cabbage.png"),
	"carrot": preload("res://assets/sprites/crop_carrot.png"),
}
const FERTILIZER_ICONS := {
	"basic": preload("res://assets/sprites/fertilizer_basic.png"),
	"mutation": preload("res://assets/sprites/fertilizer_mutation.png"),
	"preserve": preload("res://assets/sprites/fertilizer_preserve.png"),
	"golden": preload("res://assets/sprites/fertilizer_golden.png"),
}
const WATERING_CAN_ICON := preload("res://assets/sprites/tool_watering_can.png")

const FOREST := Color("#294f3c")
const LEAF := Color("#477b52")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const TEXT_MUTED := Color("#788678")
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
var tutorial_label: Label
var tutorial_panel: PanelContainer
var care_remaining_label: Label
var coins_value: Label
var seeds_value: Label
var crops_value: Label
var level_value: Label
var plot_hint_label: Label
var status_label: Label
var modal_overlay: Control
var modal_panel: PanelContainer
var modal_title: Label
var modal_icon: TextureRect
var modal_content: VBoxContainer
var sell_all_button: Button
var harvest_all_entry: Button
var expedition_hub_panel: ExpeditionHubPanel
var loadout_panel: LoadoutPanel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud_theme := Theme.new()
	var chinese_font := SystemFont.new()
	chinese_font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	hud_theme.default_font = chinese_font
	hud_theme.default_font_size = 18
	theme = hud_theme
	_build_brand()
	_build_counters()
	_build_context()
	_build_actions()
	_build_modal()
	_build_tutorial_banner()
	_build_expedition_panels()


func refresh(state: Dictionary) -> void:
	current_state = state
	var crop_count := 0
	for batch in state["crop_batches"]:
		crop_count += batch["count"]
	coins_value.text = str(state["coins"])
	seeds_value.text = str(state["seeds"].size())
	crops_value.text = str(crop_count)
	var progress := PlantDefs.level_progress(int(state["farming_exp"]))
	if progress["next_need"] < 0:
		level_value.text = "种地 Lv.%d · 满级" % progress["level"]
	else:
		level_value.text = "种地 Lv.%d · 经验 %d/%d" % [progress["level"], progress["into_level"], progress["next_need"]]
	update_harvest_entry()
	_update_tutorial_banner()
	if modal_overlay.visible:
		_render_modal()


func tick_update(now: int) -> void:
	## 每秒调用：只更新照料面板的倒计时文字，不重建按钮，避免吃掉点击。
	if active_modal == "plot_care" and care_plot_id > 0 and is_instance_valid(care_remaining_label):
		var plot := game.get_plot(care_plot_id)
		if not plot.is_empty() and plot["seed_id"] != 0 and now < plot["ready_at"]:
			var remaining: int = plot["ready_at"] - now
			care_remaining_label.text = "生长中，还剩 %02d:%02d。基准 %d 分/作物，照料可提高分数。" % [int(remaining / 60), remaining % 60, PlantDefs.get_plant(plot["kind"])["base_score"]]


func update_harvest_entry() -> void:
	# 由时钟每秒调用：作物成熟不需要玩家操作也要让一键收获入口出现。
	var mature_count: int = 0
	if game != null:
		mature_count = game.mature_plot_ids(view_now).size()
	harvest_all_entry.visible = mature_count > 0
	harvest_all_entry.text = "一键收获（%d）" % mature_count


func show_plot_hint(plot_id: int, plot: Dictionary, now: int) -> void:
	if plot_id == 0:
		plot_hint_label.text = "点击空地播种 · 生长中点击可照料（浇水、施肥）"
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


func open_shop() -> void:
	active_modal = "shop"
	_apply_modal_height(305)
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
	_apply_modal_height(220)
	modal_overlay.visible = true
	_render_modal()


func open_plot_care(plot_id: int) -> void:
	care_plot_id = plot_id
	active_modal = "plot_care"
	_apply_modal_height(285)
	modal_overlay.visible = true
	_render_modal()


func _apply_modal_height(half_height: int) -> void:
	modal_panel.offset_top = -half_height
	modal_panel.offset_bottom = half_height


func _build_brand() -> void:
	var brand := _panel(Color("#294f3cf2"), Color("#6f9b71"), 16)
	brand.name = "FarmBrand"
	brand.offset_left = 20
	brand.offset_top = 18
	brand.offset_right = 332
	brand.offset_bottom = 112
	add_child(brand)
	var margin := _margin(12, 6)
	brand.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	margin.add_child(row)
	row.add_child(_image(CROP_ICONS["cabbage"], Vector2(62, 62)))
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	row.add_child(titles)
	titles.add_child(_label("小小农场", 26, Color.WHITE))
	titles.add_child(_label("慢慢生长，认真收获", 14, Color("#c9dfc3")))
	level_value = _label("种地 Lv.1 · 经验 0/120", 15, Color("#ffd98a"))
	titles.add_child(level_value)


const TUTORIAL_STEPS := [
	"第一步：点击一块空地，选一组白菜种子播种",
	"第二步：点击生长中的地块，在照料面板里浇一次水（免费加分）",
	"第三步：等作物成熟（约 20 分钟），点击地块收获——面板会讲清每一分是怎么来的",
	"第四步：点击门口的客人或右下角「今日集市」，比价后把作物卖掉",
	"第五步：到商店补几粒种子再播种，第二轮开始就全靠自己啦",
]


func _build_tutorial_banner() -> void:
	tutorial_panel = _panel(Color("#33492ef2"), Color("#7fa876"), 14)
	tutorial_panel.name = "TutorialBanner"
	tutorial_panel.anchor_left = 0.5
	tutorial_panel.anchor_right = 0.5
	tutorial_panel.offset_left = -370
	tutorial_panel.offset_right = 370
	tutorial_panel.offset_top = 22
	tutorial_panel.offset_bottom = 74
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
	var skip_button := _plain_button("跳过引导", Color("#ffd98a"))
	skip_button.custom_minimum_size.x = 88
	skip_button.pressed.connect(func():
		current_state["tutorial_step"] = 99
		tutorial_panel.visible = false)
	row.add_child(skip_button)


func _update_tutorial_banner() -> void:
	if tutorial_panel == null:
		return
	var step := int(current_state.get("tutorial_step", 99))
	if step < 0 or step >= TUTORIAL_STEPS.size():
		tutorial_panel.visible = false
		return
	tutorial_panel.visible = true
	tutorial_label.text = "【新手引导】%s" % TUTORIAL_STEPS[step]


func _build_counters() -> void:
	var counters := HBoxContainer.new()
	counters.name = "FarmCounters"
	counters.anchor_left = 1.0
	counters.anchor_right = 1.0
	counters.offset_left = -482
	counters.offset_right = -20
	counters.offset_top = 24
	counters.offset_bottom = 87
	counters.add_theme_constant_override("separation", 9)
	add_child(counters)
	coins_value = _counter(counters, COIN_ICON, "金币", ACCENT_GOLD)
	seeds_value = _counter(counters, SEED_ICONS["cabbage"], "种子", Color("#4e8758"))
	crops_value = _counter(counters, CROP_ICONS["cabbage"], "作物", Color("#5b8b60"))


func _counter(parent: HBoxContainer, icon_texture: Texture2D, caption: String, accent: Color) -> Label:
	var chip := _panel(Color("#fffaf0ee"), Color("#e2e4d4"), 13)
	chip.custom_minimum_size.x = 116
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(chip)
	var margin := _margin(8, 5)
	chip.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	margin.add_child(row)
	row.add_child(_image(icon_texture, Vector2(42, 42)))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", -2)
	row.add_child(stack)
	stack.add_child(_label(caption, 12, TEXT_MUTED))
	var value := _label("0", 21, accent)
	stack.add_child(value)
	return value


func _build_context() -> void:
	var context := _panel(Color("#294f3ce9"), Color("#6d946d"), 16)
	context.name = "PlotContext"
	context.anchor_top = 1.0
	context.anchor_bottom = 1.0
	context.offset_left = 20
	context.offset_right = 600
	context.offset_top = -100
	context.offset_bottom = -18
	add_child(context)
	var margin := _margin(18, 10)
	context.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	margin.add_child(stack)
	plot_hint_label = _label("点击空地播种 · 生长中点击可照料（浇水、施肥）", 19, Color.WHITE)
	stack.add_child(plot_hint_label)
	status_label = _label("浇水、施肥能提高收获分数 · 收获明细可核对每一分", 15, Color("#c5ddc4"))
	stack.add_child(status_label)


func _build_actions() -> void:
	var actions := HBoxContainer.new()
	actions.name = "FarmActions"
	actions.anchor_left = 1.0
	actions.anchor_right = 1.0
	actions.anchor_top = 1.0
	actions.anchor_bottom = 1.0
	actions.offset_left = -554
	actions.offset_right = -20
	actions.offset_top = -114
	actions.offset_bottom = -18
	actions.add_theme_constant_override("separation", 10)
	add_child(actions)
	harvest_all_entry = _icon_action("一键收获", CRATE_ICON, Color("#eaf4df"), Color("#87b06f"))
	harvest_all_entry.name = "HarvestAllButton"
	harvest_all_entry.visible = false
	harvest_all_entry.pressed.connect(func(): harvest_all_requested.emit())
	actions.add_child(harvest_all_entry)
	var market_button := _icon_action("今日集市", COIN_ICON, Color("#fff5df"), Color("#d5b87d"))
	market_button.name = "OpenMarketButton"
	market_button.pressed.connect(func(): view_now = 0; open_market())
	actions.add_child(market_button)
	var shop_button := _icon_action("种子商店", SHOP_ICON, Color("#fff5df"), Color("#d5b87d"))
	shop_button.name = "OpenShopButton"
	shop_button.pressed.connect(open_shop)
	actions.add_child(shop_button)
	var warehouse_button := _icon_action("作物仓库", WAREHOUSE_ICON, Color("#fff5df"), Color("#d5b87d"))
	warehouse_button.name = "OpenWarehouseButton"
	warehouse_button.pressed.connect(func(): open_warehouse())
	actions.add_child(warehouse_button)


func _icon_action(caption: String, texture: Texture2D, fill: Color, border: Color) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(126, 96)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _style(fill, border, 15))
	button.add_theme_stylebox_override("hover", _style(Color("#fffbea"), Color("#77a76d"), 15))
	button.add_theme_stylebox_override("pressed", _style(Color("#e8f0d8"), Color("#477b52"), 15))
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", -3)
	button.add_child(stack)
	var icon := _image(texture, Vector2(54, 54))
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(icon)
	var label := _label(caption, 16, TEXT_DARK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(label)
	return button


func _build_modal() -> void:
	modal_overlay = Control.new()
	modal_overlay.name = "ModalOverlay"
	modal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_overlay.visible = false
	add_child(modal_overlay)
	var shade := ColorRect.new()
	shade.name = "ModalShade"
	shade.color = Color(0.11, 0.20, 0.14, 0.51)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_overlay.add_child(shade)
	modal_panel = _panel(CREAM, Color("#d5c9aa"), 20)
	modal_panel.name = "FarmModal"
	modal_panel.anchor_left = 0.5
	modal_panel.anchor_right = 0.5
	modal_panel.anchor_top = 0.5
	modal_panel.anchor_bottom = 0.5
	modal_panel.offset_left = -345
	modal_panel.offset_right = 345
	modal_panel.offset_top = -240
	modal_panel.offset_bottom = 240
	modal_overlay.add_child(modal_panel)
	var outer := _margin(16, 16)
	modal_panel.add_child(outer)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	outer.add_child(layout)
	var header := _panel(FOREST, Color("#6e986c"), 14)
	header.custom_minimum_size.y = 78
	layout.add_child(header)
	var header_margin := _margin(13, 7)
	header.add_child(header_margin)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	header_margin.add_child(header_row)
	modal_icon = _image(SHOP_ICON, Vector2(60, 60))
	header_row.add_child(modal_icon)
	modal_title = _label("", 27, Color.WHITE)
	modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(modal_title)
	var close_button := _plain_button("关闭 ×", Color("#d6e5cf"))
	close_button.custom_minimum_size.x = 94
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.pressed.connect(_close_modal)
	header_row.add_child(close_button)
	var scroll := ScrollContainer.new()
	scroll.name = "ModalScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
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


func _render_harvest() -> void:
	var result: Dictionary = last_harvest_result
	var batch: Dictionary = result["batch"]
	var breakdown: Dictionary = batch["score_breakdown"]
	var defn := PlantDefs.get_plant(batch["kind"])
	modal_title.text = "收获完成"
	modal_icon.texture = CRATE_ICON
	var heading := _label("第 %d 块地的%s成熟了！" % [batch["plot_id"], defn["display_name"]], 24, TEXT_DARK)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_content.add_child(heading)
	var rewards := HBoxContainer.new()
	rewards.add_theme_constant_override("separation", 14)
	modal_content.add_child(rewards)
	rewards.add_child(_reward_card(CROP_ICONS[batch["kind"]], defn["display_name"], "×%d" % batch["count"]))
	rewards.add_child(_reward_card(SEED_ICONS[batch["kind"]], "新种子", "×%d" % result["seeds"]))
	rewards.add_child(_reward_card(COIN_ICON, "默认售价", "%d 金币" % game.batch_sale_price(batch)))
	if result.get("child_traits", []) is Array and not result["child_traits"].is_empty():
		var trait_lines := ""
		for index in range(result["child_traits"].size()):
			if index > 0:
				trait_lines += "  ·  "
			trait_lines += "种子%d[%s]" % [index + 1, BreedingDefs.traits_text(result["child_traits"][index])]
		var child_label := _label("新种子词条（每粒独立判定）：%s" % trait_lines, 14, TEXT_MUTED)
		child_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		modal_content.add_child(child_label)
	modal_content.add_child(_breakdown_card(breakdown, batch))
	var story_card := _panel(Color("#f2ecd9"), Color("#ddd0ae"), 12)
	modal_content.add_child(story_card)
	var story_margin := _margin(12, 8)
	story_card.add_child(story_margin)
	var story_stack := VBoxContainer.new()
	story_stack.add_theme_constant_override("separation", 3)
	story_margin.add_child(story_stack)
	story_stack.add_child(_label("这一轮的经历", 17, TEXT_DARK))
	for event in result["events"]:
		story_stack.add_child(_label("· %s" % event["text"], 14, TEXT_MUTED))
	if not bool(result.get("stored_crops", true)) or not bool(result.get("stored_seeds", true)):
		var pending_row := HBoxContainer.new()
		pending_row.add_theme_constant_override("separation", 10)
		modal_content.add_child(pending_row)
		pending_row.add_child(_label("仓库已满：这部分产出进入待领取，不会丢失。", 15, LOCK_RED))
		var pending_button := _solid_button("去整理/出售/回收", Color("#9b713f"))
		pending_button.custom_minimum_size.x = 150
		pending_button.pressed.connect(func(): open_warehouse())
		pending_row.add_child(pending_button)
	var exp_line := _label("经验 +%d（种地与%s各一份）" % [result["exp_gain"], defn["display_name"]], 16, Color("#3f6d8e"))
	if result["farming_level_up"]:
		exp_line.text += "  ·  种地升级了！"
	if result["plant_level_up"]:
		exp_line.text += "  ·  %s升级了！" % defn["display_name"]
	exp_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_content.add_child(exp_line)


func _render_harvest_all() -> void:
	var result: Dictionary = last_harvest_all_result
	modal_title.text = "一键收获完成"
	modal_icon.texture = CRATE_ICON
	var heading := _label("共收获 %d 块成熟地：作物 ×%d，新种子 ×%d，经验 +%d。" % [result["results"].size(), result["total_crops"], result["total_seeds"], result["total_exp"]], 21, TEXT_DARK)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_content.add_child(heading)
	for entry in result["results"]:
		modal_content.add_child(_breakdown_card(entry["batch"]["score_breakdown"], entry["batch"], true))
	if result["level_up_count"] > 0:
		var note := _label("其中有收获触发了升级，升级只影响下一轮的等级加分。", 15, Color("#3f6d8e"))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		modal_content.add_child(note)


func _breakdown_card(breakdown: Dictionary, batch: Dictionary, compact := false) -> PanelContainer:
	var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
	card.name = "BreakdownCard_%d" % batch["id"]
	var margin := _margin(12, 8)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	margin.add_child(stack)
	var title_line := "第 %d 块地 · %s ×%d" % [batch["plot_id"], PlantDefs.get_plant(batch["kind"])["display_name"], batch["count"]]
	if compact:
		title_line += "  ·  默认售价 %d 金币" % game.batch_sale_price(batch)
	stack.add_child(_label(title_line, 18, TEXT_DARK))
	var lines := [
		"基准分 %d/作物" % breakdown["base"],
		"等级加分 +%d/作物（播种快照：种地 Lv.%d + 植物 Lv.%d，各 +5%%/级）" % [breakdown["level_bonus"], breakdown["farming_level_snapshot"], breakdown["plant_level_snapshot"]],
		"正向波动 +%d/作物（%d%%）" % [breakdown["fluctuation_bonus"], breakdown["fluctuation_pct"]],
		"浇水 +%d/作物（%d/%d 个时段）" % [breakdown["water_bonus"], breakdown["water_segments_done"], breakdown["water_segments_total"]],
	]
	if breakdown["fertilizer_kind"] != "":
		lines.append("肥料 +%d/作物（%s）" % [breakdown["fertilizer_bonus"], PlantDefs.FERTILIZERS[breakdown["fertilizer_kind"]]["display_name"]])
	else:
		lines.append("肥料 +0/作物（本轮未生效）")
	lines.append("遭遇 +%d/作物（%s）" % [breakdown["encounter_bonus"], "+".join(breakdown["encounter_tiers"].map(func(tier): return str(tier)))])
	for line in lines:
		stack.add_child(_label("· " + line, 14, TEXT_MUTED))
	var total := _label("每个作物 = %d 分，整批 %d×%d = %d 分；默认售价 = ⌊%d×1.2÷100⌋ = %d 金币。" % [
		breakdown["per_crop_score"],
		breakdown["per_crop_score"], breakdown["crop_count"], breakdown["batch_total"],
		breakdown["batch_total"], game.batch_sale_price(batch),
	], 16, ACCENT_GOLD)
	stack.add_child(total)
	return card


func _render_seed_picker() -> void:
	modal_title.text = "选择要播种的种子"
	modal_icon.texture = SEED_ICONS["cabbage"]
	modal_content.add_child(_label("第 %d 块地是空地。选定一组种子播种（消耗其中 1 粒）：" % picker_plot_id, 18, TEXT_DARK))
	var groups := game.seed_groups()
	if groups.is_empty():
		var empty_stack: Array = current_state.get("pending", {}).get("seeds", [])
		if not empty_stack.is_empty():
			modal_content.add_child(_label("种子区已满，还有 %d 粒新种子待领取。请先整理仓库。" % empty_stack.size(), 17, LOCK_RED))
		else:
			modal_content.add_child(_label("没有种子了，请先到商店购买。", 17, LOCK_RED))
		var shop_button := _solid_button("打开种子商店", LEAF)
		shop_button.pressed.connect(func(): open_shop())
		modal_content.add_child(shop_button)
		return
	for group in groups:
		var defn := PlantDefs.get_plant(group["kind"])
		var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
		card.name = "SeedGroup_%d" % int(group["seed_ids"][0])
		modal_content.add_child(card)
		var margin := _margin(12, 8)
		card.add_child(margin)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 11)
		margin.add_child(row)
		row.add_child(_image(SEED_ICONS[group["kind"]], Vector2(52, 52)))
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 1)
		row.add_child(details)
		var quality: int = BreedingDefs.quality_score(group["traits"])
		details.add_child(_label("%s种子 ×%d  ·  品质 %d 分" % [defn["display_name"], group["count"], quality], 17, TEXT_DARK))
		details.add_child(_label("词条：%s" % BreedingDefs.traits_text(group["traits"]), 13, TEXT_MUTED))
		details.add_child(_label("%d 分钟成熟 · 每作物基准 %d 分" % [int(defn["grow_seconds"] / 60), defn["base_score"]], 13, TEXT_MUTED))
		var plant_button := _solid_button("播种", LEAF)
		plant_button.custom_minimum_size.x = 88
		plant_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		plant_button.pressed.connect(_emit_plant_seed.bind(picker_plot_id, int(group["seed_ids"][0])))
		row.add_child(plant_button)


func _emit_plant_seed(plot_id: int, seed_id: int) -> void:
	plant_seed_requested.emit(plot_id, seed_id)


func _render_plot_care() -> void:
	var plot := game.get_plot(care_plot_id)
	if plot.is_empty() or plot["seed_id"] == 0:
		_close_modal()
		return
	var defn := PlantDefs.get_plant(plot["kind"])
	modal_title.text = "第 %d 块地 · %s" % [care_plot_id, defn["display_name"]]
	modal_icon.texture = CROP_ICONS[plot["kind"]]
	var status := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
	modal_content.add_child(status)
	var status_margin := _margin(12, 8)
	status.add_child(status_margin)
	var status_stack := VBoxContainer.new()
	status_stack.add_theme_constant_override("separation", 3)
	status_margin.add_child(status_stack)
	if view_now >= plot["ready_at"]:
		status_stack.add_child(_label("已经成熟，关闭后点击地块即可收获。", 18, TEXT_DARK))
	else:
		var remaining: int = plot["ready_at"] - view_now
		care_remaining_label = _label("生长中，还剩 %02d:%02d。基准 %d 分/作物，照料可提高分数。" % [int(remaining / 60), remaining % 60, defn["base_score"]], 17, TEXT_DARK)
		status_stack.add_child(care_remaining_label)
		var watering := game.watering_status(care_plot_id, view_now)
		for segment in watering["segments"]:
			var start_minute := int(segment["start_offset"] / 60)
			var end_minute := int(segment["end_offset"] / 60)
			var line := "第 %d 时段（第 %d~%d 分钟）：%s" % [segment["index"] + 1, start_minute, end_minute, "已浇水 ✓" if segment["watered"] else "未浇水"]
			if watering["current"] == segment["index"]:
				line += "  ← 当前时段"
			elif not segment["watered"] and segment["index"] < watering["current"]:
				line += "（已错过）"
			status_stack.add_child(_label("· " + line, 15, TEXT_MUTED if segment["watered"] else TEXT_DARK))
		var water_row := HBoxContainer.new()
		water_row.add_theme_constant_override("separation", 10)
		modal_content.add_child(water_row)
		var water_button := _solid_button("浇水（当前时段）", Color("#3f6d8e"))
		water_button.pressed.connect(func(): water_requested.emit(care_plot_id))
		water_row.add_child(water_button)
		water_row.add_child(_image(WATERING_CAN_ICON, Vector2(44, 44)))
		modal_content.add_child(_label("普通水壶免费，每个有效时段只记一次；两个时段都浇，加分相加。", 14, TEXT_MUTED))
	modal_content.add_child(_label("肥料（每次 2 小时，覆盖多轮短种植；未到期不能更换）", 17, TEXT_DARK))
	var fertilizer: Dictionary = plot.get("fertilizer", {})
	var fertilizer_blocked: bool = not fertilizer.is_empty() and fertilizer["expires_at"] > view_now
	if fertilizer_blocked:
		var minutes := int(ceil(float(fertilizer["expires_at"] - view_now) / 60.0))
		modal_content.add_child(_label("当前生效：%s，剩约 %d 分钟。到期前不能施新肥料。" % [PlantDefs.FERTILIZERS[fertilizer["kind"]]["display_name"], minutes], 15, Color("#3f6d8e")))
	var fertilizer_row := HBoxContainer.new()
	fertilizer_row.add_theme_constant_override("separation", 8)
	modal_content.add_child(fertilizer_row)
	var owned_any := false
	for kind in PlantDefs.FERTILIZERS:
		var uses: int = int(current_state["fertilizers"].get(kind, 0))
		if uses <= 0:
			continue
		owned_any = true
		var button := _solid_button("%s ×%d" % [PlantDefs.FERTILIZERS[kind]["display_name"], uses], Color("#7c6a3f"))
		button.custom_minimum_size.x = 118
		button.disabled = fertilizer_blocked
		button.pressed.connect(_emit_fertilize.bind(care_plot_id, kind))
		fertilizer_row.add_child(button)
	if not owned_any:
		var shop_link := _plain_button("到商店购买肥料", Color("#d6e5cf"))
		shop_link.pressed.connect(func(): open_shop())
		modal_content.add_child(shop_link)
	var story := _panel(Color("#f2ecd9"), Color("#ddd0ae"), 12)
	modal_content.add_child(story)
	var story_margin := _margin(12, 8)
	story.add_child(story_margin)
	var story_stack := VBoxContainer.new()
	story_stack.add_theme_constant_override("separation", 3)
	story_margin.add_child(story_stack)
	story_stack.add_child(_label("本轮经历", 16, TEXT_DARK))
	if plot.get("events", []).is_empty():
		story_stack.add_child(_label("· 暂时没有记录。", 14, TEXT_MUTED))
	for event in plot.get("events", []):
		story_stack.add_child(_label("· %s" % event["text"], 14, TEXT_MUTED))


func _emit_fertilize(plot_id: int, kind: String) -> void:
	fertilize_requested.emit(plot_id, kind)


func _render_shop() -> void:
	modal_title.text = "种子商店"
	modal_icon.texture = SHOP_ICON
	modal_content.add_child(_section_label("种子"))
	for kind in PlantDefs.plant_kinds():
		modal_content.add_child(_seed_product_card(kind))
	modal_content.add_child(_section_label("肥料（种地 2 级解锁 · 每份 10 次使用）"))
	for kind in PlantDefs.FERTILIZERS:
		modal_content.add_child(_fertilizer_product_card(kind))
	modal_content.add_child(_section_label("商店升级"))
	modal_content.add_child(_shop_upgrade_card())
	modal_content.add_child(_section_label("设施"))
	modal_content.add_child(_breeder_product_card())
	modal_content.add_child(_label("当前金币：%d" % current_state["coins"], 17, TEXT_DARK))


func _breeder_product_card() -> PanelContainer:
	var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
	card.name = "BreederProductCard"
	var margin := _margin(12, 8)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	row.add_child(_image(WAREHOUSE_ICON, Vector2(54, 54)))
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
	var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
	card.name = "SeedProduct_%s" % kind
	var margin := _margin(12, 8)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	row.add_child(_image(SEED_ICONS[kind], Vector2(64, 64)))
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 2)
	row.add_child(details)
	details.add_child(_label("%s种子" % defn["display_name"], 20, TEXT_DARK))
	details.add_child(_label("%d 分钟成熟 · 每作物基准 %d 分 · 每地每轮 2~3 粒新种子" % [int(defn["grow_seconds"] / 60), defn["base_score"]], 14, TEXT_MUTED))
	var lock_reason := game.seed_lock_reason(kind)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	row.add_child(buttons)
	if lock_reason != "":
		details.add_child(_label("🔒 %s" % lock_reason, 14, LOCK_RED))
		var one := _solid_button("买 1 粒 · %d 金币" % defn["seed_price"], Color("#9aa392"))
		one.disabled = true
		buttons.add_child(one)
		return card
	details.add_child(_label("%d 金币 / 粒" % defn["seed_price"], 17, ACCENT_GOLD))
	var one := _solid_button("买 1 粒 · %d 金币" % defn["seed_price"], LEAF)
	one.pressed.connect(func(): buy_seed_requested.emit(kind, 1))
	buttons.add_child(one)
	var six := _solid_button("买 6 粒 · %d 金币" % (6 * defn["seed_price"]), LEAF)
	six.pressed.connect(func(): buy_seed_requested.emit(kind, 6))
	buttons.add_child(six)
	return card


func _fertilizer_product_card(kind: String) -> PanelContainer:
	var defn: Dictionary = PlantDefs.FERTILIZERS[kind]
	var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
	card.name = "FertilizerProduct_%s" % kind
	var margin := _margin(12, 8)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	row.add_child(_image(FERTILIZER_ICONS[kind], Vector2(58, 58)))
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 2)
	row.add_child(details)
	details.add_child(_label(defn["display_name"], 18, TEXT_DARK))
	var effect := "每次覆盖一块地 2 小时，本轮作物 +20% 基准分"
	if kind == "mutation":
		effect += "；提高新种子出现全新词条的机会（+10 个百分点）"
	elif kind == "preserve":
		effect += "；提高亲本词条的保留与升档机会（保留 80%，升档翻倍）"
	elif kind == "golden":
		effect += "；带金克拉效果的批次出售倍率 +0.2（默认与客人报价都生效）"
	details.add_child(_label(effect, 13, TEXT_MUTED))
	var owned: int = int(current_state["fertilizers"].get(kind, 0))
	var required_level := PlantDefs.FERTILIZER_UNLOCK_FARMING_LEVEL
	var lock_note := ""
	if kind == "golden":
		required_level = PlantDefs.GOLDEN_FERTILIZER_UNLOCK_LEVEL_PLACEHOLDER
		lock_note = "（解锁条件未定，暂用种地 %d 级占位）" % required_level
	var farming_level := PlantDefs.level_from_exp(int(current_state["farming_exp"]))
	var shop_level := int(current_state["shop_level"])
	var one_price := MarketDefs.discounted_total(defn["price"], shop_level)
	var five_price := MarketDefs.discounted_total(5 * defn["price"], shop_level)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var one := _solid_button("买 1 份 · %d 金币" % one_price, LEAF)
	one.custom_minimum_size.x = 118
	one.pressed.connect(func(): buy_fertilizer_requested.emit(kind, 1))
	buttons.add_child(one)
	var five := _solid_button("买 5 份 · %d 金币" % five_price, LEAF)
	five.custom_minimum_size.x = 118
	five.pressed.connect(func(): buy_fertilizer_requested.emit(kind, 5))
	buttons.add_child(five)
	if farming_level < required_level:
		details.add_child(_label("🔒 需要种地 %d 级（当前 %d）%s" % [required_level, farming_level, lock_note], 13, LOCK_RED))
		one.disabled = true
		five.disabled = true
		one.text = "未解锁"
		five.text = "未解锁"
	elif owned > 0:
		details.add_child(_label("已有剩余 %d 次使用 · 标价 %d 金币/份（10 次），已按商店折扣" % [owned, defn["price"]], 14, ACCENT_GOLD))
	else:
		details.add_child(_label("标价 %d 金币/份（10 次使用），已按商店折扣" % defn["price"], 14, ACCENT_GOLD))
	row.add_child(buttons)
	return card


func _shop_upgrade_card() -> PanelContainer:
	var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
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
	var crops_tab := _solid_button("作物区（%d/%d 格）" % [game.crop_slots_used(), game.warehouse_capacity()], LEAF if active == "crops" else Color("#9aa392"))
	crops_tab.custom_minimum_size.x = 200
	crops_tab.pressed.connect(func(): open_warehouse("crops"))
	tabs.add_child(crops_tab)
	var seeds_tab := _solid_button("种子区（%d/%d 格）" % [game.seed_slots_used(), game.warehouse_capacity()], LEAF if active == "seeds" else Color("#9aa392"))
	seeds_tab.custom_minimum_size.x = 200
	seeds_tab.pressed.connect(func(): open_warehouse("seeds"))
	tabs.add_child(seeds_tab)
	var breeder_tab := _solid_button("育种机", LEAF if active == "breeder" else Color("#9aa392"))
	breeder_tab.custom_minimum_size.x = 120
	breeder_tab.pressed.connect(func(): open_breeder())
	tabs.add_child(breeder_tab)
	return tabs


func _render_pending_section() -> void:
	var pending: Dictionary = current_state.get("pending", {"crops": [], "seeds": []})
	if pending["crops"].is_empty() and pending["seeds"].is_empty():
		return
	var card := _panel(Color("#f7e3d2"), Color("#e0b89a"), 12)
	card.name = "PendingCard"
	modal_content.add_child(card)
	var margin := _margin(12, 8)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)
	stack.add_child(_label("待领取结果：作物 %d 批 · 种子 %d 粒（仓库满时收获的产出）" % [pending["crops"].size(), pending["seeds"].size()], 17, Color("#8a4a2a")))
	for batch in pending["crops"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		stack.add_child(row)
		row.add_child(_label("· 第 %d 块地 %s ×%d · 默认售价 %d 金币" % [batch["plot_id"], PlantDefs.get_plant(batch.get("kind", "cabbage"))["display_name"], batch["count"], game.batch_sale_price(batch)], 14, TEXT_MUTED))
		var sell_button := _plain_button("出售", Color("#ffd98a"))
		sell_button.custom_minimum_size.x = 60
		sell_button.pressed.connect(func(): sell_pending_crop_requested.emit(batch["id"]))
		row.add_child(sell_button)
	for seed in pending["seeds"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		stack.add_child(row)
		row.add_child(_label("· %s种子 · 词条：%s" % [PlantDefs.get_plant(seed["kind"])["display_name"], BreedingDefs.traits_text(seed.get("traits", []))], 14, TEXT_MUTED))
		var recycle_button := _plain_button("回收 5 金币", Color("#ffd98a"))
		recycle_button.custom_minimum_size.x = 100
		recycle_button.pressed.connect(func(): recycle_pending_seed_requested.emit(seed["id"]))
		row.add_child(recycle_button)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	stack.add_child(actions)
	var claim_button := _solid_button("领取入库（先腾出空间）", LEAF)
	claim_button.pressed.connect(func(): claim_pending_requested.emit())
	actions.add_child(claim_button)


func _render_warehouse_crops() -> void:
	modal_title.text = "作物仓库"
	modal_icon.texture = WAREHOUSE_ICON
	modal_content.add_child(_warehouse_tabs("crops"))
	_render_pending_section()
	if current_state["crop_batches"].is_empty():
		var empty := _panel(Color("#f6ead0"), Color("#e3d1ac"), 13)
		modal_content.add_child(empty)
		var margin := _margin(16, 17)
		empty.add_child(margin)
		margin.add_child(_label("作物区还是空的。\n点击成熟的地块收获第一批作物。", 19, TEXT_DARK))
	else:
		modal_content.add_child(_label("每块地的收获单独存放 · 当前可按默认价 1.2 倍出售", 17, TEXT_MUTED))
		for batch in current_state["crop_batches"]:
			var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
			card.name = "BatchCard_%d" % batch["id"]
			modal_content.add_child(card)
			var margin := _margin(12, 8)
			card.add_child(margin)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 11)
			margin.add_child(row)
			var icon: Texture2D = CROP_ICONS.get(batch.get("kind", "cabbage"), CROP_ICONS["cabbage"])
			row.add_child(_image(icon, Vector2(54, 54)))
			var details := VBoxContainer.new()
			details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			details.add_theme_constant_override("separation", 1)
			row.add_child(details)
			var kind_name: String = PlantDefs.get_plant(batch.get("kind", "cabbage"))["display_name"]
			var attributes: Dictionary = batch.get("attributes", {})
			details.add_child(_label("第 %d 块地 · %s ×%d · 每作物 %d 分" % [batch["plot_id"], kind_name, batch["count"], int(batch.get("per_crop_score", batch["base_score"]))], 18, TEXT_DARK))
			var attribute_line := "属性：水 %d · 纤维 %d · 色泽 %d" % [int(attributes.get("water", 0)), int(attributes.get("fiber", 0)), int(attributes.get("color", 0))]
			details.add_child(_label("%s · 默认售价 %d 金币" % [attribute_line, game.batch_sale_price(batch)], 15, ACCENT_GOLD))
			var sell_button := _solid_button("出售", Color("#9b713f"))
			sell_button.custom_minimum_size.x = 86
			sell_button.size_flags_horizontal = Control.SIZE_SHRINK_END
			sell_button.pressed.connect(_emit_batch_sale.bind(batch["id"]))
			row.add_child(sell_button)
	_render_warehouse_upgrade()


func _render_warehouse_seeds() -> void:
	modal_title.text = "种子仓库"
	modal_icon.texture = SEED_ICONS["cabbage"]
	modal_content.add_child(_warehouse_tabs("seeds"))
	_render_pending_section()
	var filter_row := HBoxContainer.new()
	filter_row.name = "SeedFilterRow"
	filter_row.add_theme_constant_override("separation", 6)
	modal_content.add_child(filter_row)
	for filter_value in [["all", "全部"], ["cabbage", "白菜"], ["carrot", "胡萝卜"], ["traits", "有词条"], ["quality", "品质 ≥3"]]:
		var button := _solid_button(filter_value[1], LEAF if seed_filter == filter_value[0] else Color("#9aa392"))
		button.custom_minimum_size.x = 86
		button.pressed.connect(_change_seed_filter.bind(filter_value[0]))
		filter_row.add_child(button)
	var groups := game.seed_groups()
	match seed_filter:
		"cabbage", "carrot":
			groups = groups.filter(func(group): return group["kind"] == seed_filter)
		"traits":
			groups = groups.filter(func(group): return not group["traits"].is_empty())
		"quality":
			groups = groups.filter(func(group): return BreedingDefs.quality_score(group["traits"]) >= 3)
	if groups.is_empty():
		var empty := _panel(Color("#f6ead0"), Color("#e3d1ac"), 13)
		modal_content.add_child(empty)
		var margin := _margin(16, 17)
		empty.add_child(margin)
		margin.add_child(_label("种子区还是空的。收获或购买种子后会出现在这里。", 18, TEXT_DARK))
		_render_warehouse_upgrade()
		return
	modal_content.add_child(_label("属性与词条完全相同的种子叠放，每格最多 %d 粒；品质只取最高单条词条分。" % BreedingDefs.SEED_STACK_MAX, 15, TEXT_MUTED))
	var template_id := int(current_state["breeder"]["template_seed_id"])
	for group in groups:
		var defn := PlantDefs.get_plant(group["kind"])
		var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
		card.name = "SeedCard_%d" % int(group["seed_ids"][0])
		modal_content.add_child(card)
		var margin := _margin(12, 8)
		card.add_child(margin)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 11)
		margin.add_child(row)
		row.add_child(_image(SEED_ICONS[group["kind"]], Vector2(50, 50)))
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 1)
		row.add_child(details)
		var is_template: bool = template_id != 0 and template_id in group["seed_ids"]
		var quality: int = BreedingDefs.quality_score(group["traits"])
		var title := "%s种子 ×%d · 品质 %d 分" % [defn["display_name"], group["count"], quality]
		if is_template:
			title += "  ★ 育种机模板"
		details.add_child(_label(title, 17, TEXT_DARK))
		details.add_child(_label("词条：%s" % BreedingDefs.traits_text(group["traits"]), 13, TEXT_MUTED))
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 6)
		row.add_child(buttons)
		var template_button := _solid_button("解除模板" if is_template else "设为模板", Color("#3f6d8e") if not is_template else Color("#8a6d3f"))
		template_button.custom_minimum_size.x = 104
		template_button.pressed.connect(_emit_template_toggle.bind(int(group["seed_ids"][0]), is_template))
		buttons.add_child(template_button)
		var recycle_button := _solid_button("回收 5 金币", Color("#9b713f"))
		recycle_button.custom_minimum_size.x = 96
		recycle_button.disabled = is_template
		recycle_button.pressed.connect(_emit_recycle.bind(int(group["seed_ids"][0])))
		buttons.add_child(recycle_button)
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
	var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
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
	if not status["owned"]:
		var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
		modal_content.add_child(card)
		var margin := _margin(14, 12)
		card.add_child(margin)
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 6)
		margin.add_child(stack)
		stack.add_child(_label("复制种子的机器：放入 1 粒模板，定期产出词条完全相同的副本。", 17, TEXT_DARK))
		stack.add_child(_label("购买需要种地 2 级 + %d 金币；1 级每 60 分钟复制 1 粒，机内最多存 8 粒。" % BreedingDefs.BREEDER_BUY_COST, 15, TEXT_MUTED))
		var buy_button := _solid_button("购买育种机 · %d 金币" % BreedingDefs.BREEDER_BUY_COST, LEAF)
		buy_button.pressed.connect(func(): buy_breeder_requested.emit())
		stack.add_child(buy_button)
		return
	var level: int = status["level"]
	var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
	card.name = "BreederStatusCard"
	modal_content.add_child(card)
	var margin := _margin(12, 8)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	stack.add_child(_label("育种机 %d 级 · 每 %d 分钟 1 粒 · 机内 %d/%d 粒" % [level, int(status["cycle_seconds"] / 60), status["pending"], status["capacity"]], 18, TEXT_DARK))
	if status["template"].is_empty():
		stack.add_child(_label("当前没有模板。到种子区选一粒种子点\"设为模板\"。", 15, TEXT_MUTED))
	else:
		var template: Dictionary = status["template"]
		stack.add_child(_label("模板：%s种子 · 品质 %d 分（原种保留在仓库）" % [PlantDefs.get_plant(template["kind"])["display_name"], BreedingDefs.quality_score(template.get("traits", []))], 16, TEXT_DARK))
		stack.add_child(_label("词条：%s" % BreedingDefs.traits_text(template.get("traits", [])), 13, TEXT_MUTED))
		if status["running"]:
			var progress: int = status["progress_seconds"]
			var percent := int(float(progress) / float(status["cycle_seconds"]) * 100.0)
			stack.add_child(_label("本周期进度：%d%%（%d/%d 秒）；切换模板后进度按种子保存，切回可继续。" % [percent, progress, status["cycle_seconds"]], 15, Color("#3f6d8e")))
		else:
			stack.add_child(_label("机内已满，复制暂停；采摘后继续。", 15, LOCK_RED))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	stack.add_child(actions)
	if int(status["pending"]) > 0:
		var collect_button := _solid_button("采摘 %d 粒副本" % status["pending"], LEAF)
		collect_button.pressed.connect(func(): collect_breeder_requested.emit())
		actions.add_child(collect_button)
	var next_cost: int = BreedingDefs.BREEDER_LEVELS[level]["upgrade_cost"]
	if level < 3:
		if next_cost < 0:
			actions.add_child(_label("升级到 %d 级：价格待定（占位）" % (level + 1), 15, TEXT_MUTED))
		else:
			var upgrade_button := _solid_button("升级 %d 级 · %d 金币" % [level + 1, next_cost], Color("#8a6d3f"))
			upgrade_button.pressed.connect(func(): upgrade_breeder_requested.emit())
			actions.add_child(upgrade_button)


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
	modal_content.add_child(_label("第 %d 天 · 每天北京时间零点刷新三位客人与两种植物的收购公式" % int(market.get("day_index", 0)), 15, TEXT_MUTED))
	var guest_row := HBoxContainer.new()
	guest_row.name = "MarketGuestRow"
	guest_row.add_theme_constant_override("separation", 8)
	modal_content.add_child(guest_row)
	var locked_guest := int(market.get("locked_guest_id", 0))
	var pending_guest := int(market.get("lock_guest_pending", 0))
	var shop_level := int(current_state["shop_level"])
	for guest_id in market.get("guest_ids", []):
		var guest: Dictionary = MarketDefs.GUESTS[int(guest_id)]
		var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
		card.name = "GuestCard_%d" % int(guest_id)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		guest_row.add_child(card)
		var margin := _margin(10, 7)
		card.add_child(margin)
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 3)
		margin.add_child(stack)
		var is_locked: bool = locked_guest == int(guest_id)
		stack.add_child(_label(guest["display_name"] + ("  ★已锁定" if is_locked else ""), 16, TEXT_DARK))
		stack.add_child(_label("长期收购：%s" % PlantDefs.get_plant(guest["preferred_kind"])["display_name"], 13, TEXT_MUTED))
		if shop_level >= 2:
			var lock_button: Button
			if is_locked and pending_guest == int(guest_id):
				lock_button = _solid_button("解除锁定（明日生效）", Color("#8a6d3f"))
				lock_button.pressed.connect(func(): unlock_guest_requested.emit())
			else:
				lock_button = _solid_button("锁定这位客人", Color("#3f6d8e"))
				lock_button.pressed.connect(_emit_lock_guest.bind(int(guest_id)))
			stack.add_child(lock_button)
		else:
			stack.add_child(_label("🔒 锁定客人需商店 2 级", 12, LOCK_RED))
	if pending_guest != locked_guest:
		modal_content.add_child(_label("锁定变更已记录，明天零点生效。", 13, Color("#3f6d8e")))
	modal_content.add_child(_section_label("今日收购公式（客人收偏好植物时公式倍率再 ×1.2）"))
	var locked_formula: Dictionary = market.get("locked_formula", {})
	for kind in ["cabbage", "carrot"]:
		var formula: Dictionary = market["formulas"].get(kind, {})
		var card := _panel(Color("#f2ecd9"), Color("#ddd0ae"), 12)
		card.name = "FormulaCard_%s" % kind
		modal_content.add_child(card)
		var margin := _margin(12, 8)
		card.add_child(margin)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		margin.add_child(row)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 2)
		row.add_child(details)
		details.add_child(_label("%s：%s" % [PlantDefs.get_plant(kind)["display_name"], _formula_text(formula)], 16, TEXT_DARK))
		var formula_locked_here: bool = locked_formula.get("kind", "") == kind
		details.add_child(_label("公式已锁定此类型（系数每日重抽）" if formula_locked_here else "公式类型与系数每日重抽", 13, TEXT_MUTED))
		if shop_level >= 3 and locked_guest != 0 and MarketDefs.GUESTS[locked_guest]["preferred_kind"] == kind:
			var button := _solid_button("解除公式锁" if formula_locked_here else "锁定此公式类型", Color("#8a6d3f"))
			button.custom_minimum_size.x = 150
			button.size_flags_horizontal = Control.SIZE_SHRINK_END
			if formula_locked_here:
				button.pressed.connect(func(): unlock_formula_requested.emit())
			else:
				button.pressed.connect(_emit_lock_formula.bind(kind))
			row.add_child(button)
		elif shop_level < 3:
			details.add_child(_label("🔒 锁定公式需商店 3 级 + 已锁客人", 12, LOCK_RED))
	modal_content.add_child(_section_label("卖菜（可整批卖给客人、按数量拆批，或默认 1.2 倍出售）"))
	if current_state["crop_batches"].is_empty():
		var empty := _panel(Color("#f6ead0"), Color("#e3d1ac"), 13)
		modal_content.add_child(empty)
		var margin := _margin(14, 12)
		empty.add_child(margin)
		margin.add_child(_label("仓库里没有作物。收获后到这里比价出售。", 17, TEXT_DARK))
		return
	for batch in current_state["crop_batches"]:
		modal_content.add_child(_market_batch_card(batch, market))


func _emit_lock_guest(guest_id: int) -> void:
	lock_guest_requested.emit(guest_id)


func _emit_lock_formula(kind: String) -> void:
	lock_formula_requested.emit(kind)


func _market_batch_card(batch: Dictionary, market: Dictionary) -> PanelContainer:
	var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
	card.name = "MarketBatch_%d" % batch["id"]
	var margin := _margin(12, 8)
	card.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	margin.add_child(stack)
	var attributes: Dictionary = batch.get("attributes", {})
	stack.add_child(_label("第 %d 块地 · %s ×%d · 每作物 %d 分 · 属性 含水量 %d / 纤维 %d / 色泽 %d" % [
		batch["plot_id"], PlantDefs.get_plant(batch.get("kind", "cabbage"))["display_name"], batch["count"],
		int(batch.get("per_crop_score", batch["base_score"])),
		int(attributes.get("water", 0)), int(attributes.get("fiber", 0)), int(attributes.get("color", 0)),
	], 16, TEXT_DARK))
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	stack.add_child(controls)
	controls.add_child(_label("出售数量：", 15, TEXT_DARK))
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
	var default_button := _solid_button("默认出售 %d 金币（整批）" % game.batch_sale_price(batch), Color("#9b713f"))
	default_button.custom_minimum_size.x = 190
	default_button.pressed.connect(_emit_batch_sale.bind(batch["id"]))
	controls.add_child(default_button)
	for guest_id in market.get("guest_ids", []):
		var priced := game.quote(batch, selected_count, int(guest_id))
		var guest: Dictionary = MarketDefs.GUESTS[int(guest_id)]
		var quote_row := HBoxContainer.new()
		quote_row.add_theme_constant_override("separation", 8)
		stack.add_child(quote_row)
		var quote_label := _label("%s%s：倍率 ×%.2f → %d 个 %d 金币" % [
			guest["display_name"], "（偏好 ×1.2）" if priced["preferred"] else "",
			priced["multiplier"], selected_count, priced["coins"],
		], 14, ACCENT_GOLD if priced["preferred"] else TEXT_MUTED)
		quote_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quote_row.add_child(quote_label)
		var sell_button := _solid_button("出售", LEAF if priced["preferred"] else Color("#7c6a3f"))
		sell_button.custom_minimum_size.x = 76
		sell_button.pressed.connect(_emit_sell_to.bind(int(batch["id"]), int(guest_id), count_option))
		quote_row.add_child(sell_button)
	return card


func _emit_sell_to(batch_id: int, guest_id: int, count_option: OptionButton) -> void:
	sell_batch_to_requested.emit(batch_id, count_option.selected + 1, guest_id)


func _reward_card(texture: Texture2D, caption: String, count: String) -> PanelContainer:
	var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 13)
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


## —— 探险入口面板（2.1）：独立脚本挂接，实现不写进本文件 ——

func _build_expedition_panels() -> void:
	expedition_hub_panel = ExpeditionHubPanel.new()
	expedition_hub_panel.name = "ExpeditionHubPanel"
	expedition_hub_panel.close_requested.connect(close_expedition_panels)
	expedition_hub_panel.open_loadout_requested.connect(open_loadout)
	add_child(expedition_hub_panel)
	loadout_panel = LoadoutPanel.new()
	loadout_panel.name = "LoadoutPanel"
	loadout_panel.close_requested.connect(_on_loadout_close)
	add_child(loadout_panel)


func open_expedition_hub() -> void:
	_close_modal()
	expedition_hub_panel.open(game)


func open_loadout() -> void:
	_close_modal()
	expedition_hub_panel.close()
	loadout_panel.open(game)


func close_expedition_panels() -> void:
	if expedition_hub_panel != null:
		expedition_hub_panel.close()


func _on_loadout_close() -> void:
	## 关闭战备：剔除演示物品；真实改动通过信号交给组合根保存。
	loadout_panel.close()
	var dirty: bool = loadout_panel.dirty
	loadout_panel.mark_saved()
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
	style.shadow_color = Color(0.10, 0.18, 0.11, 0.20)
	style.shadow_size = 7
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
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _solid_button(content: String, fill: Color) -> Button:
	var button := Button.new()
	button.text = content
	button.custom_minimum_size.y = 44
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("#8f9a8f"))
	button.add_theme_stylebox_override("normal", _button_style(fill))
	button.add_theme_stylebox_override("hover", _button_style(fill.lightened(0.10)))
	button.add_theme_stylebox_override("pressed", _button_style(fill.darkened(0.10)))
	button.add_theme_stylebox_override("disabled", _button_style(Color("#b9bfae")))
	return button


func _plain_button(content: String, color: Color) -> Button:
	var button := Button.new()
	button.text = content
	button.custom_minimum_size.y = 40
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(Color("#3c6549")))
	button.add_theme_stylebox_override("hover", _button_style(Color("#548461")))
	return button


func _button_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style
