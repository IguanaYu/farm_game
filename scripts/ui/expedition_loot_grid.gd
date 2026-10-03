class_name ExpeditionLootGrid
extends Control
## 搜刮背包的实际占格；拖放只发意图，快照刷新后才移动物品。

signal item_selected(instance_id: int)
signal placement_requested(payload: Dictionary, cell: Vector2i)

var loot_owner: Control
var container := "pack"
var bounds := Vector2i(4, 4)
var items: Array = []
var selected_id := -1
var occupied: Dictionary = {}
var cell_size := 66.0
var origin := Vector2.ZERO

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(_layout)
	set_process(true)

func display(new_items: Array, dimensions: Vector2i, selected: int) -> void:
	items = new_items
	bounds = dimensions
	selected_id = selected
	occupied = ExpeditionBaseline.occupancy_map(items, container)
	custom_minimum_size = Vector2(0, 280)
	_layout()

func _layout() -> void:
	cell_size = minf(70, minf(size.x / maxi(bounds.x, 1), size.y / maxi(bounds.y, 1)))
	origin = (size - Vector2(bounds) * cell_size) / 2
	ExpeditionUI.clear(self)
	for instance in items:
		var def := ItemDefs.get_item(str(instance["def_id"]))
		var rect := _item_rect(instance).grow(-4)
		var art := ExpeditionArt.new()
		art.subject = str(instance.get("loot_art", "crystal"))
		art.tint = instance.get("loot_tint", ExpeditionUI.TEAL)
		art.position = rect.position + Vector2(0, 1)
		art.size = Vector2(rect.size.x, maxf(20, rect.size.y - 21))
		add_child(art)
		var label := ExpeditionUI.label(str(def.get("name", "?")), 11, ExpeditionUI.TEXT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.position = rect.position + Vector2(2, rect.size.y - 21)
		label.size = Vector2(maxf(0, rect.size.x - 4), 20)
		add_child(label)
	queue_redraw()

func _item_rect(instance: Dictionary) -> Rect2:
	var dimensions: Vector2i = ItemDefs.get_item(str(instance["def_id"]))["size"]
	if bool(instance.get("rotated", false)):
		dimensions = Vector2i(dimensions.y, dimensions.x)
	return Rect2(origin + Vector2(int(instance["cell"][0]), int(instance["cell"][1])) * cell_size, Vector2(dimensions) * cell_size)

func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori((point.x - origin.x) / cell_size), floori((point.y - origin.y) / cell_size))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hovered := int(occupied.get(ExpeditionBaseline.cell_key(_cell(event.position)), -1))
		tooltip_text = ""
		for instance in items:
			if int(instance["instance_id"]) == hovered:
				var def := ItemDefs.get_item(str(instance["def_id"]))
				tooltip_text = "%s · %d×%d 格 · %d 张牌\n点选查看，拖动移动，R 旋转。" % [def["name"], def["size"].x, def["size"].y, def["cards"].size()]
				break
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var id := int(occupied.get(ExpeditionBaseline.cell_key(_cell(event.position)), -1))
		if id >= 0:
			item_selected.emit(id)
		accept_event()

func _get_drag_data(at_position: Vector2) -> Variant:
	var id := int(occupied.get(ExpeditionBaseline.cell_key(_cell(at_position)), -1))
	if id < 0:
		return null
	item_selected.emit(id)
	var payload: Dictionary = loot_owner.drag_payload("carried:%d" % id)
	if payload.is_empty():
		return null
	set_drag_preview(loot_owner.drag_preview(payload))
	return payload

func _valid_payload(data: Variant) -> bool:
	return data is Dictionary and int(data.get("loot_owner", -1)) == loot_owner.get_instance_id() and not bool(loot_owner.pending_action)

func _fits(data: Dictionary, cell: Vector2i) -> bool:
	var def := ItemDefs.get_item(str(data.get("def_id", "")))
	if def.is_empty() or (container == "safe" and not bool(def.get("safe_allowed", false))):
		return false
	return ExpeditionBaseline.can_place_in(bounds, def["size"], cell, bool(data.get("rotated", false)), occupied, int(data.get("instance_id", -1)))

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	queue_redraw()
	return _valid_payload(data) and _fits(data, _cell(at_position))

func _drop_data(at_position: Vector2, data: Variant) -> void:
	placement_requested.emit(data, _cell(at_position))

func _process(_delta: float) -> void:
	if is_visible_in_tree() and get_viewport().gui_is_dragging():
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		queue_redraw()

func _draw() -> void:
	for y in range(bounds.y):
		for x in range(bounds.x):
			draw_style_box(ExpeditionUI.style(Color("#102029"), Color("#304750"), 6, 0), Rect2(origin + Vector2(x, y) * cell_size, Vector2.ONE * cell_size).grow(-2))
	for instance in items:
		var tint: Color = instance.get("loot_tint", ExpeditionUI.TEAL)
		var selected := int(instance["instance_id"]) == selected_id
		var style := ExpeditionUI.style(tint.darkened(0.72), ExpeditionUI.GOLD if selected else tint.darkened(0.25), 7, 0)
		style.set_border_width_all(2 if selected else 1)
		draw_style_box(style, _item_rect(instance).grow(-3))
	if get_viewport().gui_is_dragging() and get_global_rect().has_point(get_global_mouse_position()):
		var data: Variant = get_viewport().gui_get_drag_data()
		if _valid_payload(data):
			var cell := _cell(get_local_mouse_position())
			var dimensions: Vector2i = ItemDefs.get_item(str(data["def_id"]))["size"]
			if bool(data.get("rotated", false)):
				dimensions = Vector2i(dimensions.y, dimensions.x)
			var color := ExpeditionUI.TEAL if _fits(data, cell) else ExpeditionUI.RED
			var rect := Rect2(origin + Vector2(cell) * cell_size, Vector2(dimensions) * cell_size).grow(-3)
			draw_rect(rect, Color(color, 0.25))
			draw_rect(rect, color, false, 2)
