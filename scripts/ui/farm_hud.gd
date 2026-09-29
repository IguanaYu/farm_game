class_name FarmHud
extends Control

signal buy_requested(quantity: int)
signal sell_batch_requested(batch_id: int)
signal sell_all_requested
signal debug_mature_requested

const SHOP_ICON := preload("res://assets/sprites/facility_shop.png")
const WAREHOUSE_ICON := preload("res://assets/sprites/facility_warehouse.png")
const CRATE_ICON := preload("res://assets/sprites/item_harvest_crate.png")
const COIN_ICON := preload("res://assets/sprites/item_coin.png")
const SEED_ICON := preload("res://assets/sprites/seed_cabbage.png")
const CABBAGE_ICON := preload("res://assets/sprites/crop_cabbage.png")

const FOREST := Color("#294f3c")
const LEAF := Color("#477b52")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const TEXT_MUTED := Color("#788678")

var current_state: Dictionary = {}
var active_modal: String = ""
var harvest_plot_id: int = 0
var harvest_seed_count: int = 0
var coins_value: Label
var seeds_value: Label
var crops_value: Label
var plot_hint_label: Label
var status_label: Label
var modal_overlay: Control
var modal_panel: PanelContainer
var modal_title: Label
var modal_icon: TextureRect
var modal_content: VBoxContainer
var sell_all_button: Button


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


func refresh(state: Dictionary) -> void:
	current_state = state
	var crop_count := 0
	for batch in state["crop_batches"]:
		crop_count += batch["count"]
	coins_value.text = str(state["coins"])
	seeds_value.text = str(state["seeds"].size())
	crops_value.text = str(crop_count)
	if modal_overlay.visible:
		_render_modal()


func show_plot_hint(plot_id: int, plot: Dictionary, now: int) -> void:
	if plot_id == 0:
		plot_hint_label.text = "点击田地播种，成熟后再次点击收获"
		return
	if plot["seed_id"] == 0:
		plot_hint_label.text = "第 %d 块地  ·  空地，点击播种" % plot_id
	elif now >= plot["ready_at"]:
		plot_hint_label.text = "第 %d 块地  ·  白菜成熟，点击收获" % plot_id
	else:
		var remaining: int = plot["ready_at"] - now
		plot_hint_label.text = "第 %d 块地  ·  生长中 %02d:%02d" % [plot_id, int(remaining / 60), remaining % 60]


func show_status(message: String) -> void:
	status_label.text = message


func show_harvest(plot_id: int, seed_count: int) -> void:
	harvest_plot_id = plot_id
	harvest_seed_count = seed_count
	active_modal = "harvest"
	modal_panel.offset_top = -205
	modal_panel.offset_bottom = 205
	modal_overlay.visible = true
	_render_modal()


func open_shop() -> void:
	active_modal = "shop"
	modal_panel.offset_top = -192
	modal_panel.offset_bottom = 192
	modal_overlay.visible = true
	_render_modal()


func open_warehouse() -> void:
	active_modal = "warehouse"
	modal_panel.offset_top = -240
	modal_panel.offset_bottom = 240
	modal_overlay.visible = true
	_render_modal()


func _build_brand() -> void:
	var brand := _panel(Color("#294f3cf2"), Color("#6f9b71"), 16)
	brand.name = "FarmBrand"
	brand.offset_left = 20
	brand.offset_top = 18
	brand.offset_right = 332
	brand.offset_bottom = 95
	add_child(brand)
	var margin := _margin(12, 6)
	brand.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	margin.add_child(row)
	row.add_child(_image(CABBAGE_ICON, Vector2(62, 62)))
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	row.add_child(titles)
	titles.add_child(_label("小小农场", 26, Color.WHITE))
	titles.add_child(_label("慢慢生长，认真收获", 14, Color("#c9dfc3")))


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
	coins_value = _counter(counters, COIN_ICON, "金币", Color("#a87535"))
	seeds_value = _counter(counters, SEED_ICON, "种子", Color("#4e8758"))
	crops_value = _counter(counters, CABBAGE_ICON, "作物", Color("#5b8b60"))


func _counter(parent: HBoxContainer, icon_texture: Texture2D, caption: String, accent: Color) -> Label:
	var chip := _panel(Color("#fffaf0ee"), Color("#e2e4d4"), 13)
	chip.custom_minimum_size.x = 147
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(chip)
	var margin := _margin(8, 5)
	chip.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	margin.add_child(row)
	row.add_child(_image(icon_texture, Vector2(45, 45)))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", -2)
	row.add_child(stack)
	stack.add_child(_label(caption, 13, TEXT_MUTED))
	var value := _label("0", 23, accent)
	stack.add_child(value)
	return value


func _build_context() -> void:
	var context := _panel(Color("#294f3ce9"), Color("#6d946d"), 16)
	context.name = "PlotContext"
	context.anchor_top = 1.0
	context.anchor_bottom = 1.0
	context.offset_left = 20
	context.offset_right = 570
	context.offset_top = -100
	context.offset_bottom = -18
	add_child(context)
	var margin := _margin(18, 10)
	context.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	margin.add_child(stack)
	plot_hint_label = _label("点击田地播种，成熟后再次点击收获", 19, Color.WHITE)
	stack.add_child(plot_hint_label)
	status_label = _label("六粒白菜种子已备好 · 点击建筑可进入商店或仓库", 15, Color("#c5ddc4"))
	stack.add_child(status_label)


func _build_actions() -> void:
	var actions := HBoxContainer.new()
	actions.name = "FarmActions"
	actions.anchor_left = 1.0
	actions.anchor_right = 1.0
	actions.anchor_top = 1.0
	actions.anchor_bottom = 1.0
	actions.offset_left = -286
	actions.offset_right = -20
	actions.offset_top = -114
	actions.offset_bottom = -18
	actions.add_theme_constant_override("separation", 10)
	add_child(actions)
	var shop_button := _icon_action("种子商店", SHOP_ICON, Color("#fff5df"), Color("#d5b87d"))
	shop_button.name = "OpenShopButton"
	shop_button.pressed.connect(open_shop)
	actions.add_child(shop_button)
	var warehouse_button := _icon_action("作物仓库", WAREHOUSE_ICON, Color("#fff5df"), Color("#d5b87d"))
	warehouse_button.name = "OpenWarehouseButton"
	warehouse_button.pressed.connect(open_warehouse)
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
	var icon := _image(texture, Vector2(58, 58))
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
	modal_panel.offset_left = -315
	modal_panel.offset_right = 315
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
	for child in modal_content.get_children():
		modal_content.remove_child(child)
		child.queue_free()
	if active_modal == "shop":
		sell_all_button.visible = false
		_render_shop()
	elif active_modal == "warehouse":
		sell_all_button.visible = not current_state["crop_batches"].is_empty()
		sell_all_button.text = "全部出售（%d 批）" % current_state["crop_batches"].size()
		_render_warehouse()
	elif active_modal == "harvest":
		sell_all_button.visible = false
		_render_harvest()


func _render_harvest() -> void:
	modal_title.text = "收获完成"
	modal_icon.texture = CRATE_ICON
	var heading := _label("第 %d 块地的白菜成熟了！" % harvest_plot_id, 24, TEXT_DARK)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_content.add_child(heading)
	var rewards := HBoxContainer.new()
	rewards.add_theme_constant_override("separation", 14)
	modal_content.add_child(rewards)
	rewards.add_child(_reward_card(CABBAGE_ICON, "白菜", "×5"))
	rewards.add_child(_reward_card(SEED_ICON, "新种子", "×%d" % harvest_seed_count))
	var explanation := _label("白菜已放进仓库；新种子可以接着种。", 17, TEXT_MUTED)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_content.add_child(explanation)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	modal_content.add_child(actions)
	var keep_farming := _solid_button("继续种植", LEAF)
	keep_farming.pressed.connect(_close_modal)
	actions.add_child(keep_farming)
	var visit_warehouse := _solid_button("查看仓库", Color("#9b713f"))
	visit_warehouse.pressed.connect(open_warehouse)
	actions.add_child(visit_warehouse)


func _reward_card(texture: Texture2D, caption: String, count: String) -> PanelContainer:
	var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 13)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := _margin(14, 10)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)
	row.add_child(_image(texture, Vector2(72, 72)))
	var labels := VBoxContainer.new()
	labels.add_theme_constant_override("separation", 1)
	row.add_child(labels)
	labels.add_child(_label(caption, 17, TEXT_MUTED))
	labels.add_child(_label(count, 26, TEXT_DARK))
	return card


func _render_shop() -> void:
	modal_title.text = "种子商店"
	modal_icon.texture = SHOP_ICON
	var product := _panel(Color("#f6ead0"), Color("#e3d1ac"), 13)
	modal_content.add_child(product)
	var margin := _margin(14, 13)
	product.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 15)
	margin.add_child(row)
	row.add_child(_image(SEED_ICON, Vector2(95, 95)))
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 4)
	row.add_child(details)
	details.add_child(_label("白菜种子", 24, TEXT_DARK))
	details.add_child(_label("20 分钟成熟 · 每块地消耗 1 粒", 17, TEXT_MUTED))
	details.add_child(_label("10 金币 / 粒", 22, Color("#9b713a")))
	modal_content.add_child(_label("当前金币：%d" % current_state["coins"], 17, TEXT_DARK))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	modal_content.add_child(buttons)
	var one := _solid_button("买 1 粒 · 10 金币", LEAF)
	one.pressed.connect(func(): buy_requested.emit(1))
	buttons.add_child(one)
	var six := _solid_button("买 6 粒 · 60 金币", LEAF)
	six.pressed.connect(func(): buy_requested.emit(6))
	buttons.add_child(six)
	modal_content.add_child(_label("种植后会收获新种子，也可以把作物卖掉再购入。", 16, TEXT_MUTED))


func _render_warehouse() -> void:
	modal_title.text = "作物仓库"
	modal_icon.texture = WAREHOUSE_ICON
	if current_state["crop_batches"].is_empty():
		var empty := _panel(Color("#f6ead0"), Color("#e3d1ac"), 13)
		modal_content.add_child(empty)
		var margin := _margin(16, 17)
		empty.add_child(margin)
		margin.add_child(_label("仓库还是空的。\n点击成熟的地块收获第一批白菜。", 19, TEXT_DARK))
		return
	modal_content.add_child(_label("每块地的收获单独存放 · 当前可按默认价出售", 17, TEXT_MUTED))
	for batch in current_state["crop_batches"]:
		var price := int(floor(float(batch["count"] * batch["base_score"]) * 1.2 / 100.0))
		var card := _panel(Color("#f6ead0"), Color("#e3d1ac"), 12)
		card.name = "BatchCard_%d" % batch["id"]
		modal_content.add_child(card)
		var margin := _margin(12, 8)
		card.add_child(margin)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 11)
		margin.add_child(row)
		row.add_child(_image(CRATE_ICON, Vector2(58, 58)))
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_theme_constant_override("separation", 1)
		row.add_child(details)
		details.add_child(_label("第 %d 块地 · 白菜 ×%d" % [batch["plot_id"], batch["count"]], 18, TEXT_DARK))
		details.add_child(_label("默认售价 %d 金币" % price, 16, Color("#9b713a")))
		var sell_button := _solid_button("出售", Color("#9b713f"))
		sell_button.custom_minimum_size.x = 86
		sell_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		sell_button.pressed.connect(_emit_batch_sale.bind(batch["id"]))
		row.add_child(sell_button)


func _emit_batch_sale(batch_id: int) -> void:
	sell_batch_requested.emit(batch_id)


func _close_modal() -> void:
	modal_overlay.visible = false
	active_modal = ""


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
	button.custom_minimum_size.y = 48
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(fill))
	button.add_theme_stylebox_override("hover", _button_style(fill.lightened(0.10)))
	button.add_theme_stylebox_override("pressed", _button_style(fill.darkened(0.10)))
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
