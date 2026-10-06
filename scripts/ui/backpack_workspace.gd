class_name BackpackWorkspace
extends Control
## 三栏背包工作台的左两栏共享组件（三栏改版 2026-10）：
## 左＝装备纸娃娃（暗黑 T 形：头盔居中在上，主武器｜护甲｜副武器一行）；
## 中＝容器栈（胸挂／背包／保险箱 纵向滚动，每块左侧容器贴图＋右侧格子）。
## 战备面板（农场侧）与搜刮台（局内）共用；全部改动经宿主 Callable 意图，组件不碰存档。
## 拖放协议：payload = {instance_id, def_id, rotated, workspace_owner}，归属按 owner_id 校验。


signal item_selected(instance_id: int)

## 宿主注入的命令口（setup 必填前四个；select 可空＝只发 item_selected 信号）。
var place_action: Callable
var equip_action: Callable
var tidy_action: Callable
var select_action: Callable
var owner_id := 0
## 宿主异步命令进行中＝true：拖放校验一律拒绝，防止旧意图覆盖新状态。
var busy := false

var slot_controls: Dictionary = {}
var container_blocks: Dictionary = {}
var container_grids: Dictionary = {}
var container_captions: Dictionary = {}
var doll_column: VBoxContainer
var stack_scroll: ScrollContainer
var doll_hint: Label

## 尺寸配置（宿主在 add_child 前按场景覆写；战备=默认，搜刮台=紧凑）。
var doll_width := 296
var stack_width := 432
var slot_min_sizes := {
	"helmet": Vector2(116, 116),
	"main_weapon": Vector2(92, 186),
	"armor": Vector2(116, 116),
	"off_weapon": Vector2(92, 186),
}
var grid_min_height := 280
var show_hint := true

const SLOT_FRAME := Color("#f2e9d2")
const SLOT_LINE := Color("#cfc19b")
const SLOT_ART_SUBJECT := {"main_weapon": "attack", "off_weapon": "attack", "helmet": "helmet", "armor": "shield"}
const CONTAINER_ART := {"chest": "rig_chest", "pack": "rig_pack", "safe": "rig_safe"}


class WorkspaceGrid extends ExpeditionLootGrid:
	## 容器格子：沿用基类的占格绘制／ghost／safe 白名单校验，拖放意图改走工作台宿主。
	var workspace: BackpackWorkspace

	func _get_drag_data(at_position: Vector2) -> Variant:
		var id := int(occupied.get(ExpeditionBaseline.cell_key(_cell(at_position)), -1))
		if id < 0:
			return null
		item_selected.emit(id)
		var instance: Dictionary = workspace._inventory().find_instance(id)
		if instance.is_empty():
			return null
		var preview := ExpeditionUI.label(ItemDefs.get_item(str(instance["def_id"]))["name"], 20)
		set_drag_preview(preview)
		return {"instance_id": id, "def_id": instance["def_id"], "rotated": instance.get("rotated", false), "workspace_owner": workspace.owner_id}

	func _valid_payload(data: Variant) -> bool:
		return data is Dictionary and int(data.get("workspace_owner", -1)) == workspace.owner_id and not workspace.busy

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		workspace.place_action.call(data, container, _cell(at_position))


class EquipSlot extends Control:
	## 装备槽：拖入＝装备（类别不符画红框）、拖出＝卸下（放容器/仓库）、点击＝选中。
	var slot := "main_weapon"
	var workspace: BackpackWorkspace
	var instance: Dictionary = {}
	var hovered := false
	var selected_flag := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func refresh(new_instance: Dictionary, selected_id: int) -> void:
		instance = new_instance
		selected_flag = not instance.is_empty() and int(instance["instance_id"]) == selected_id
		ExpeditionUI.clear(self)
		if instance.is_empty():
			tooltip_text = "%s槽：把%s拖到这里装备（第 1 回合入牌堆）" % [ExpeditionBaseline.SLOT_DISPLAY[slot], _category_name()]
			var caption := ExpeditionUI.label(ExpeditionBaseline.SLOT_DISPLAY[slot], 12, Color("#8a7f5c"))
			caption.position = Vector2(2, size.y / 2.0 - 20)
			caption.size = Vector2(size.x - 4, 20)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			add_child(caption)
			queue_redraw()
			return
		var def := ItemDefs.get_item(str(instance["def_id"]))
		var art := ExpeditionArt.new()
		art.subject = ExpeditionLootPanel.item_art(str(instance["def_id"]))
		art.tint = ItemDefs.quality_color(ItemDefs.quality_of(instance))
		art.position = Vector2(6, 6)
		art.size = Vector2(size.x - 12, size.y - 30)
		add_child(art)
		var label := ExpeditionUI.label(str(def.get("name", "?")), 12, ExpeditionUI.INK)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.position = Vector2(2, size.y - 24)
		label.size = Vector2(size.x - 4, 22)
		add_child(label)
		tooltip_text = "%s · %s · %s槽 · 第 1 回合入牌堆\n点选查看详情，拖动到容器即卸下。" % [
			def["name"], ItemDefs.quality_name(ItemDefs.quality_of(instance)), ExpeditionBaseline.SLOT_DISPLAY[slot]]
		queue_redraw()

	func _category_name() -> String:
		return {"weapon": "武器", "helmet": "帽子／头盔", "armor": "防具"}[ExpeditionBaseline.SLOT_CATEGORY[slot]]

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not instance.is_empty():
			workspace._select(int(instance["instance_id"]))
			accept_event()

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if instance.is_empty():
			return null
		workspace._select(int(instance["instance_id"]))
		var preview := ExpeditionUI.label(ItemDefs.get_item(str(instance["def_id"]))["name"], 20)
		set_drag_preview(preview)
		return {"instance_id": int(instance["instance_id"]), "def_id": instance["def_id"], "rotated": false, "workspace_owner": workspace.owner_id}

	func _valid_payload(data: Variant) -> bool:
		if not (data is Dictionary) or int(data.get("workspace_owner", -1)) != workspace.owner_id or workspace.busy:
			return false
		if not instance.is_empty() and int(instance["instance_id"]) == int(data.get("instance_id", -1)):
			return false
		return ExpeditionBaseline.slot_accepts(slot, str(data.get("def_id", "")))

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		hovered = true
		queue_redraw()
		return _valid_payload(data)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		workspace.equip_action.call(data, slot)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
			hovered = false
			queue_redraw()

	func _draw() -> void:
		var fill := SLOT_FRAME
		var line := SLOT_LINE
		if not instance.is_empty():
			var tint: Color = ItemDefs.quality_color(ItemDefs.quality_of(instance))
			fill = tint.darkened(0.82)
			line = tint.darkened(0.2)
			if selected_flag:
				line = ExpeditionUI.GOLD
		var style := ExpeditionUI.style(fill, line, 10, 0)
		style.set_border_width_all(2)
		draw_style_box(style, Rect2(Vector2.ZERO, size).grow(-2))
		if hovered and get_viewport() != null and get_viewport().gui_is_dragging():
			var data: Variant = get_viewport().gui_get_drag_data()
			var color := ExpeditionUI.TEAL if _valid_payload(data) else ExpeditionUI.RED
			draw_rect(Rect2(Vector2.ZERO, size).grow(-3), Color(color, 0.28))
			draw_rect(Rect2(Vector2.ZERO, size).grow(-3), color, false, 2)


class FlowItemGrid extends Control:
	## 自动装箱的流式大格子（仓库／物资“巨大背包”视图）：只读布局、可拖出、点选。
	var workspace: BackpackWorkspace
	var entries: Array = []
	var rects: Array = []
	var cell := 40.0
	signal entry_selected(instance_id: int)
	signal token_selected(token: String)

	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		resized.connect(_relayout)

	func set_items(new_entries: Array) -> void:
		entries = new_entries
		_pack()
		_rebuild_children()

	func _pack() -> void:
		rects = []
		var cursor := Vector2(2, 2)
		var row_height := 0.0
		var total_height := 0.0
		for entry in entries:
			var dims: Vector2i = entry.get("dims", Vector2i(1, 1))
			var w := float(dims.x) * cell
			var h := float(dims.y) * cell
			if cursor.x + w > size.x and cursor.x > 2:
				cursor.x = 2
				cursor.y += row_height + 6
				row_height = 0
			rects.append(Rect2(cursor, Vector2(w, h)))
			cursor.x += w + 6
			row_height = maxf(row_height, h)
			total_height = cursor.y + row_height
		custom_minimum_size = Vector2(0, total_height + 4)

	func _relayout() -> void:
		_pack()
		_rebuild_children()

	func _rebuild_children() -> void:
		ExpeditionUI.clear(self)
		for i in range(entries.size()):
			var entry: Dictionary = entries[i]
			var rect: Rect2 = rects[i]
			var art := ExpeditionArt.new()
			art.subject = str(entry.get("art", "crystal"))
			art.tint = entry.get("tint", ExpeditionUI.TEAL)
			art.position = rect.position + Vector2(2, 2)
			art.size = Vector2(maxf(8, rect.size.x - 4), maxf(8, rect.size.y - 4))
			add_child(art)
		queue_redraw()

	func _hit(at_position: Vector2) -> int:
		for i in range(rects.size()):
			if rects[i].has_point(at_position):
				return i
		return -1

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var hit := _hit(event.position)
			tooltip_text = str(entries[hit].get("tooltip", "")) if hit >= 0 else ""
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var hit := _hit(event.position)
			if hit >= 0:
				entry_selected.emit(int(entries[hit].get("instance_id", -1)))
				token_selected.emit(str(entries[hit].get("payload_extra", {}).get("token", "")))
				accept_event()

	func _get_drag_data(at_position: Vector2) -> Variant:
		var hit := _hit(at_position)
		if hit < 0:
			return null
		var entry: Dictionary = entries[hit]
		entry_selected.emit(int(entry.get("instance_id", -1)))
		var preview := ExpeditionUI.label(str(entry.get("name", "?")), 20)
		set_drag_preview(preview)
		var payload := {"instance_id": int(entry.get("instance_id", -1)), "def_id": str(entry.get("def_id", "")), "rotated": false, "workspace_owner": workspace.owner_id}
		var extra: Dictionary = entry.get("payload_extra", {})
		for key in extra:
			payload[key] = extra[key]
		return payload

	func _draw() -> void:
		for i in range(entries.size()):
			var entry: Dictionary = entries[i]
			var tint: Color = entry.get("tint", ExpeditionUI.TEAL)
			var style := ExpeditionUI.style(tint.darkened(0.78), tint.darkened(0.25), 7, 0)
			style.set_border_width_all(1)
			draw_style_box(style, rects[i].grow(-2))
			if str(entry.get("name", "")) != "" and rects[i].size.x >= cell * 0.5:
				# 名字贴在物品矩形中间，放不下时按宽度收缩字号（CJK 字宽≈字号）。
				var label := str(entry.get("name", ""))
				var font := get_theme_default_font()
				var font_size := 11
				var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
				var max_width: float = rects[i].size.x - 6
				if text_size.x > max_width:
					font_size = clampi(int(max_width / maxf(1.0, float(label.length()))), 7, 11)
					text_size = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
				var pos: Vector2 = rects[i].position + (rects[i].size - text_size) / 2.0
				draw_string(font, pos + Vector2(0, text_size.y * 0.5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#efe6cf"))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func setup(owner_control: Control, actions: Dictionary) -> void:
	owner_id = owner_control.get_instance_id()
	place_action = actions.get("place", Callable())
	equip_action = actions.get("equip", Callable())
	tidy_action = actions.get("tidy", Callable())
	select_action = actions.get("select", Callable())


func _build() -> void:
	# 外层最小宽度＝实际内容（纸娃娃行宽不小于三槽+间距）+容器栈+间距；
	# 只按 doll_width 声明会小于内容，SHRINK_BEGIN 场景下溢出遮挡邻栏（d44 排查结论）。
	var row_min: float = slot_min_sizes["main_weapon"].x + slot_min_sizes["armor"].x + slot_min_sizes["off_weapon"].x + 16.0
	doll_width = maxi(doll_width, int(row_min))
	custom_minimum_size = Vector2(doll_width + stack_width + 12, 0)
	var columns := HBoxContainer.new()
	columns.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	columns.add_theme_constant_override("separation", 12)
	add_child(columns)
	doll_column = VBoxContainer.new()
	doll_column.custom_minimum_size = Vector2(doll_width, 0)
	doll_column.add_theme_constant_override("separation", 8)
	columns.add_child(doll_column)
	doll_column.add_child(_title_label("装备"))
	doll_column.add_child(_make_slot("helmet"))
	doll_column.add_child(_make_slot_row(["main_weapon", "armor", "off_weapon"]))
	doll_hint = _title_label("装备槽的牌第 1 回合入堆")
	doll_hint.add_theme_font_size_override("font_size", 12)
	doll_column.add_child(doll_hint)
	doll_hint.visible = show_hint
	doll_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	stack_scroll = ScrollContainer.new()
	stack_scroll.custom_minimum_size = Vector2(stack_width, 0)
	stack_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(stack_scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 12)
	stack_scroll.add_child(stack)
	for container in ExpeditionBaseline.CONTAINERS:
		var block := _build_container_block(container)
		stack.add_child(block)
		container_blocks[container] = block


func _make_slot(slot: String) -> EquipSlot:
	var control := EquipSlot.new()
	control.slot = slot
	control.workspace = self
	var min_size: Vector2 = slot_min_sizes.get(slot, Vector2(110, 110))
	control.custom_minimum_size = min_size
	control.size = min_size
	slot_controls[slot] = control
	return control


func _make_slot_row(slots: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for slot in slots:
		row.add_child(_make_slot(str(slot)))
	return row


func _build_container_block(container: String) -> PanelContainer:
	var block := PanelContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_stylebox_override("panel", ExpeditionUI.style(Color("#f7f1de"), Color("#e2e4d4"), 10, 6))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	block.add_child(column)
	var caption_row := HBoxContainer.new()
	column.add_child(caption_row)
	var name_label := _title_label(ExpeditionBaseline.CONTAINER_DISPLAY[container])
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	caption_row.add_child(name_label)
	var caption := _title_label("")
	caption.add_theme_font_size_override("font_size", 12)
	caption.clip_text = true
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption_row.add_child(caption)
	container_captions[container] = caption
	var tidy := Button.new()
	tidy.text = "整理"
	tidy.custom_minimum_size = Vector2(48, 26)
	tidy.add_theme_font_size_override("font_size", 12)
	tidy.size_flags_horizontal = Control.SIZE_SHRINK_END
	tidy.pressed.connect(func():
		if tidy_action.is_valid():
			tidy_action.call(container))
	caption_row.add_child(tidy)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	column.add_child(body)
	var art_column := VBoxContainer.new()
	art_column.custom_minimum_size = Vector2(92, 0)
	body.add_child(art_column)
	var art := ExpeditionArt.new()
	art.subject = CONTAINER_ART[container]
	art.tint = Color("#8a9b7a") if container == "chest" else (Color("#7a8ca0") if container == "pack" else Color("#a09072"))
	art.custom_minimum_size = Vector2(88, 112)
	art_column.add_child(art)
	var grid := WorkspaceGrid.new()
	grid.workspace = self
	grid.container = container
	grid.custom_minimum_size = Vector2(0, grid_min_height)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.item_selected.connect(func(id): _select(id))
	body.add_child(grid)
	container_grids[container] = grid
	return block


func _inventory() -> InventoryGame:
	return _inventory_of.call() if _inventory_of.is_valid() else null


## 宿主注入的库存读取口（每次刷新取最新绑定，避免快照悬空）。
var _inventory_of: Callable


func bind_inventory(provider: Callable) -> void:
	_inventory_of = provider


func refresh(inventory: InventoryGame, selected_id: int) -> void:
	for slot in slot_controls:
		slot_controls[slot].refresh(inventory.equipped_in(slot), selected_id)
	for container in ExpeditionBaseline.CONTAINERS:
		var instances: Array = inventory.loadout_list(container).duplicate(true)
		for instance in instances:
			instance["loot_art"] = ExpeditionLootPanel.item_art(str(instance["def_id"]))
			instance["loot_tint"] = ItemDefs.quality_color(ItemDefs.quality_of(instance))
		var dims := ExpeditionBaseline.size_for(inventory.expedition, container)
		var caption: Label = container_captions[container]
		if container == "safe":
			caption.text = "%d×%d 格 · 不入牌堆 · 死亡保留" % [dims.x, dims.y]
		else:
			caption.text = "%d×%d 格 · 第 %d 回合入牌库" % [dims.x, dims.y, ExpeditionBaseline.JOIN_ROUND[container]]
		var grid: WorkspaceGrid = container_grids[container]
		grid.display(instances, dims, selected_id)


func _select(instance_id: int) -> void:
	item_selected.emit(instance_id)
	if select_action.is_valid():
		select_action.call(instance_id)


func _title_label(content: String) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("#35513d"))
	return label
