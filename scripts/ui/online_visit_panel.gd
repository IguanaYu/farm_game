class_name OnlineVisitPanel
extends Control
## Read-only trial pool directory; local search/pages do not create friend relationships.
signal close_requested
signal visit_requested(owner: Dictionary, farm: Dictionary)

class HouseThumbnail extends Control:
	func _ready() -> void:
		custom_minimum_size = Vector2(130,95)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_style_box(LifeUI.style(Color("#d5e0c2"),Color.TRANSPARENT,0),Rect2(Vector2.ZERO,size))
		draw_colored_polygon(PackedVector2Array([Vector2(0,65),Vector2(33,34),Vector2(65,62),Vector2(99,35),Vector2(130,59),Vector2(130,95),Vector2(0,95)]),Color("#a8be91"))
		draw_rect(Rect2(37,41,57,45),Color("#eee0b7"))
		draw_colored_polygon(PackedVector2Array([Vector2(31,45),Vector2(65,18),Vector2(100,45)]),Color("#b57e62"))
		draw_rect(Rect2(65,59,17,27),Color("#887251"))
		draw_rect(Rect2(44,55,13,15),Color("#8faaa3"))
		draw_line(Vector2(50,55),Vector2(50,70),Color("#eee0b7"),2)
		draw_line(Vector2(44,62),Vector2(57,62),Color("#eee0b7"),2)
		draw_line(Vector2(87,32),Vector2(87,16),Color("#a99270"),5)
		draw_line(Vector2(72,88),Vector2(78,95),Color("#d7c49b"),14)

var bridge: OnlineFarmBridge
var status_label: Label
var list_column: VBoxContainer
var main_frame: CenterContainer
var _last_visit_account := 0
var neighbors: Array = []
var search_edit: LineEdit
var page_label: Label
var previous_button: Button
var next_button: Button
var page := 0
var pending := false
var _revision := 0
var entry_status: Dictionary = {}
const PAGE_SIZE := 4

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	theme = LifeUI.make_theme()
	_build()

func open(target_bridge: OnlineFarmBridge) -> void:
	bridge = target_bridge
	visible = true
	_refresh()

func close() -> void:
	visible = false
	_revision += 1
	pending = false

func _refresh() -> void:
	if bridge == null:
		return
	_revision += 1
	var revision := _revision
	status_label.text = "正在翻看地址簿……"
	var reply: Dictionary = await bridge.visit_list()
	if revision != _revision or not visible:
		return
	if str(reply.get("t","")) != "req_ok":
		status_label.text = "地址簿打不开：%s。可以点刷新重试。" % str(reply.get("msg",reply.get("code","请稍后再试")))
		return
	neighbors = reply.get("result",{}).get("neighbors",[]).duplicate(true)
	neighbors.sort_custom(func(a,b):
		if (int(a.get("account_id",0))==_last_visit_account) != (int(b.get("account_id",0))==_last_visit_account):
			return int(a.get("account_id",0))==_last_visit_account
		return str(a.get("nick","")) < str(b.get("nick","")))
	page = 0
	status_label.text = "点一户人家去串门 · 家园只读参观"
	_render_entries()

func _render_entries() -> void:
	ExpeditionUI.clear(list_column)
	entry_status.clear()
	var matching: Array = neighbors.filter(func(n): return search_edit.text.strip_edges().to_lower() in str(n.get("nick","")).to_lower())
	var pages := maxi(1,ceili(float(matching.size())/PAGE_SIZE))
	page = clampi(page,0,pages-1)
	for neighbor in matching.slice(page*PAGE_SIZE,mini((page+1)*PAGE_SIZE,matching.size())):
		list_column.add_child(_entry(neighbor))
	if matching.is_empty():
		list_column.add_child(_label("还没有邻居。" if neighbors.is_empty() else "没找到这个昵称，试试少输几个字。",20,LifeUI.INK))
	page_label.text = "%d / %d 页 · %d 户" % [page+1,pages,matching.size()]
	previous_button.disabled = page == 0
	next_button.disabled = page >= pages-1

func _entry(neighbor: Dictionary) -> Control:
	var open_now := bool(neighbor.get("visits_open",false))
	var card := Button.new()
	card.custom_minimum_size.y = 113
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.disabled = not open_now
	card.pressed.connect(_on_visit.bind(neighbor))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.offset_top = 9
	row.offset_bottom = -9
	row.add_theme_constant_override("separation",18)
	card.add_child(row)
	row.add_child(HouseThumbnail.new())
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_label(str(neighbor.get("nick","邻居")),23,LifeUI.INK))
	var state_text := "在线 · 开放参观" if bool(neighbor.get("online",false)) and open_now else ("离线 · 开放参观" if open_now else "暂未开放参观")
	col.add_child(_label(state_text,18,LifeUI.GREEN))
	var message := _label("上次来过这里" if int(neighbor.get("account_id",0)) == _last_visit_account else "默认住宅外观 · 到院子看看",17,Color("#7e876e"))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(message)
	entry_status[int(neighbor.get("account_id",0))] = message
	row.add_child(_label("去拜访  →" if open_now else "稍后再来",19,LifeUI.INK))
	ExpeditionUI.ignore_tree(row)
	return card

func _on_visit(neighbor: Dictionary) -> void:
	if pending or bridge == null:
		return
	var target := int(neighbor.get("account_id",0))
	pending = true
	_revision += 1
	var revision := _revision
	status_label.text = "正在前往 %s 的院子……" % str(neighbor.get("nick","邻居"))
	var reply: Dictionary = await bridge.visit_snapshot(target)
	if revision != _revision or not visible:
		return
	pending = false
	if str(reply.get("t","")) != "req_ok":
		var message := "没能进门：%s · 点这户可重试" % str(reply.get("msg",reply.get("code","读取失败")))
		status_label.text = message
		if entry_status.has(target) and is_instance_valid(entry_status[target]):
			entry_status[target].text = message
		return
	_last_visit_account = target
	var result: Dictionary = reply.get("result",{})
	visit_requested.emit(result.get("owner",{}),result.get("farm",{}))

func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.13,0.20,0.13,0.18)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	main_frame = CenterContainer.new()
	main_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_frame)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",LifeUI.style(LifeUI.PAPER,LifeUI.LINE,22))
	panel.custom_minimum_size = Vector2(790,670)
	main_frame.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var title := _label("邻里地址簿",28,LifeUI.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close_button := Button.new()
	close_button.text = "合上  ×"
	close_button.pressed.connect(func(): close_requested.emit())
	top.add_child(close_button)
	var search_row := HBoxContainer.new()
	column.add_child(search_row)
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "找一位邻居 · 输入昵称"
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_edit.text_changed.connect(func(_text): page = 0; _render_entries())
	search_row.add_child(search_edit)
	var refresh := Button.new()
	refresh.text = "刷新"
	refresh.pressed.connect(_refresh)
	search_row.add_child(refresh)
	status_label = _label("",18,LifeUI.GREEN)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	list_column = VBoxContainer.new()
	list_column.add_theme_constant_override("separation",8)
	list_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_column)
	var pages := HBoxContainer.new()
	column.add_child(pages)
	previous_button = Button.new()
	previous_button.text = "← 上一页"
	previous_button.pressed.connect(func(): page -= 1; _render_entries())
	pages.add_child(previous_button)
	page_label = _label("",18,LifeUI.INK)
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pages.add_child(page_label)
	next_button = Button.new()
	next_button.text = "下一页 →"
	next_button.pressed.connect(func(): page += 1; _render_entries())
	pages.add_child(next_button)

func _label(content: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = content
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",color)
	return result
