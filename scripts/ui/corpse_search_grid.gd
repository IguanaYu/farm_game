class_name CorpseSearchGrid
extends Control
## 未揭晓物品只接收占格轮廓；按整件占格搜索，完成由权威端裁定。

var loot_owner: Control
var region: Dictionary = {}
var active: Dictionary = {}
var bounds := Vector2i(2, 3)
var cell_size := 58.0
var origin := Vector2.ZERO
var deadline := 0
var active_step := ""
var occupied: Dictionary = {}
var compact := false

func _ready() -> void:
	custom_minimum_size = Vector2(0, 270) if not compact else Vector2(0, 72)
	resized.connect(_layout)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	set_process(true)

func display(value: Dictionary, session: Dictionary) -> void:
	region = value
	active = session
	bounds = Vector2i(value.get("size", [2, 3])[0], value.get("size", [2, 3])[1])
	if compact:
		custom_minimum_size.y = bounds.y * 36
	if str(active.get("step", "")) != active_step:
		active_step = str(active.get("step", ""))
		deadline = Time.get_ticks_msec() + int(active.get("remaining", 0))
	else:
		deadline = mini(deadline, Time.get_ticks_msec() + int(active.get("remaining", 0)))
	_layout()

func _layout() -> void:
	if not is_node_ready():
		return
	cell_size = minf(36 if compact else 70, minf(size.x / bounds.x, size.y / bounds.y))
	origin = (size - Vector2(bounds) * cell_size) / 2
	ExpeditionUI.clear(self)
	occupied.clear()
	for item in region.get("items", []):
		if bool(item.get("taken", false)):
			continue
		var def := ItemDefs.get_item(str(item["def_id"]))
		var rect := _rect(item).grow(-4)
		for cell in ExpeditionBaseline.cells_of(def["size"], Vector2i(item["cell"][0], item["cell"][1]), bool(item["rotated"])):
			occupied[ExpeditionBaseline.cell_key(cell)] = int(item["instance_id"])
		var art := ExpeditionArt.new()
		art.subject = loot_owner.item_art(str(item["def_id"]))
		art.tint = ItemDefs.quality_color(ItemDefs.quality_of(item))
		art.position = rect.position
		art.size = Vector2(rect.size.x, maxf(16, rect.size.y - 20))
		add_child(art)
		var label := ExpeditionUI.label(str(def["name"]), 10 if compact else 12, art.tint)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.position = rect.position + Vector2(0, rect.size.y - 20)
		label.size = Vector2(rect.size.x, 20)
		add_child(label)
	queue_redraw()

func _rect(item: Dictionary) -> Rect2:
	var dimensions: Vector2i = ItemDefs.get_item(str(item["def_id"]))["size"]
	if bool(item["rotated"]):
		dimensions = Vector2i(dimensions.y, dimensions.x)
	return Rect2(origin + Vector2(item["cell"][0], item["cell"][1]) * cell_size, Vector2(dimensions) * cell_size)

func _footprint_rect(footprint: Dictionary) -> Rect2:
	return Rect2(origin + Vector2(footprint["cell"][0], footprint["cell"][1]) * cell_size, Vector2(footprint["size"][0], footprint["size"][1]) * cell_size)

func _active_rect() -> Rect2:
	var index := int(active.get("cell", 0))
	return _footprint_rect(active.get("footprint", {"cell": [index % bounds.x, index / bounds.x], "size": [1, 1]}))

func _id(point: Vector2) -> int:
	var cell := Vector2i(floori((point.x - origin.x) / cell_size), floori((point.y - origin.y) / cell_size))
	return int(occupied.get(ExpeditionBaseline.cell_key(cell), -1))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		tooltip_text = ""
		var item: Dictionary = loot_owner._entry("corpse:%d" % _id(event.position))
		if not item.is_empty():
			tooltip_text = str(ItemDefs.get_item(str(item["def_id"]))["name"]) + " · " + ItemDefs.quality_name(ItemDefs.quality_of(item["instance"])) + "\n拖入自己的背包"
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _id(event.position) >= 0:
			loot_owner.select_item("corpse:%d" % _id(event.position))
		accept_event()

func _get_drag_data(point: Vector2) -> Variant:
	var id := _id(point)
	if id < 0:
		return null
	loot_owner.select_item("corpse:%d" % id)
	var payload: Dictionary = loot_owner.drag_payload("corpse:%d" % id)
	if payload.is_empty():
		return null
	set_drag_preview(loot_owner.drag_preview(payload))
	return payload

func _process(_delta: float) -> void:
	if is_visible_in_tree() and not active.is_empty():
		queue_redraw()

func _draw() -> void:
	var searched: Array = region.get("searched", [])
	for y in range(bounds.y):
		for x in range(bounds.x):
			var index := y * bounds.x + x
			var known := searched.any(func(value): return int(value) == index)
			var rect := Rect2(origin + Vector2(x, y) * cell_size, Vector2.ONE * cell_size).grow(-2)
			draw_style_box(ExpeditionUI.style(Color("#10232b") if known else Color("#273b43"), Color("#344c53"), 5, 0), rect)
	var font := get_theme_default_font()
	for footprint in region.get("unknown", []):
		var rect := _footprint_rect(footprint).grow(-3)
		draw_style_box(ExpeditionUI.style(Color("#30454d"), Color("#71878b"), 6, 0), rect)
		if active.is_empty() or not _active_rect().get_center().is_equal_approx(rect.get_center()):
			draw_string(font, rect.get_center() + Vector2(-8, 8), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ExpeditionUI.MUTED)
		if int(footprint["size"][0]) * int(footprint["size"][1]) > 1:
			draw_string(font, rect.position + Vector2(8, 17), "%d×%d" % [footprint["size"][0], footprint["size"][1]], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ExpeditionUI.MUTED)
	for item in region.get("items", []):
		if not bool(item.get("taken", false)):
			var tint := ItemDefs.quality_color(ItemDefs.quality_of(item))
			var selected: bool = str(loot_owner.selected_token) == "corpse:%d" % int(item["instance_id"])
			draw_style_box(ExpeditionUI.style(tint.darkened(0.73), ExpeditionUI.GOLD if selected else tint, 6, 0), _rect(item).grow(-3))
	if not active.is_empty():
		var rect := _active_rect().grow(-3)
		var fill := ExpeditionUI.style(Color("#35464a"), ExpeditionUI.GOLD, 6, 0)
		fill.set_border_width_all(2)
		draw_style_box(fill, rect)
		var center := rect.get_center()
		var progress := clampf(1.0 - float(maxi(0, deadline - Time.get_ticks_msec())) / maxf(1, float(active["duration"])), 0, 1)
		var radius := minf(rect.size.x, rect.size.y) * 0.21
		draw_circle(center, radius * 1.25, Color("#12232d"))
		draw_arc(center, radius, -PI / 2, -PI / 2 + TAU, 40, Color("#54686b"), 3, true)
		draw_arc(center, radius, -PI / 2, -PI / 2 + maxf(0.03, progress * TAU), 40, ExpeditionUI.GOLD, 4, true)
		var dimensions: Array = active.get("footprint", {}).get("size", [1, 1])
		if int(dimensions[0]) * int(dimensions[1]) > 1:
			draw_string(font, rect.position + Vector2(8, 17), "%d×%d" % [dimensions[0], dimensions[1]], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, ExpeditionUI.GOLD)
		if not compact and rect.size.y > cell_size * 1.5:
			draw_string(font, Vector2(rect.position.x, center.y + radius + 23), "搜索中", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 14, ExpeditionUI.GOLD)
