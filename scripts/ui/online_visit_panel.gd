class_name OnlineVisitPanel
extends Control
## R7 邻里地址簿（设计稿 §7）：信箱/小桥/邻里房屋点击打开；整条目=去拜访。
## 四态：在线开放/离线开放/暂未开放/读取失败（错误文案显示在对应条目旁）。
## 拜访成功后由 farm_world 切院子地点；ESC/关闭回当前农场。

signal close_requested
signal visit_requested(owner: Dictionary, farm: Dictionary)

const CREAM := Color("#fff9ed")
const LIGHT_TEXT := Color("#e8f2d8")
const LIGHT_MUTED := Color("#a3b59b")
const WARN_GOLD := Color("#e8d9a8")

var bridge: OnlineFarmBridge
var status_label: Label
var list_column: VBoxContainer
var main_frame: CenterContainer
var _last_visit_account := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	theme = ExpeditionUI.make_theme()
	_build()


func open(target_bridge: OnlineFarmBridge) -> void:
	bridge = target_bridge
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _refresh() -> void:
	if bridge == null:
		return
	for child in list_column.get_children():
		list_column.remove_child(child)
		child.queue_free()
	status_label.text = "正在翻看邻里地址簿……"
	var reply: Dictionary = await bridge.visit_list()
	if str(reply.get("t", "")) != "req_ok":
		status_label.text = "地址簿打不开：%s" % str(reply.get("msg", reply.get("code", "请稍后再试")))
		return
	var result: Dictionary = reply.get("result", {})
	var neighbors: Array = result.get("neighbors", [])
	if neighbors.is_empty():
		status_label.text = "附近还没有别的邻居。"
		return
	status_label.text = "点一位邻居去他家院子看看（参观只读，不能动主人东西）。"
	var sorted: Array = neighbors.duplicate()
	# 上次拜访的靠前（客户端本地标记，稿 §7）。
	sorted.sort_custom(func(a, b) -> bool:
		return int(a.get("account_id", 0)) == _last_visit_account)
	for neighbor in sorted:
		list_column.add_child(_entry(neighbor))


func _entry(neighbor: Dictionary) -> Control:
	var nick := str(neighbor.get("nick", "?"))
	var online := bool(neighbor.get("online", false))
	var open_now := bool(neighbor.get("visits_open", false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var state_text := "在线 · 开放参观" if online and open_now else ("离线 · 开放参观" if open_now else "暂未开放")
	var info := _label("%s  ·  %s%s" % [nick, state_text, "  ·  上次拜访" if int(neighbor.get("account_id", 0)) == _last_visit_account else ""], 17, LIGHT_TEXT if open_now else LIGHT_MUTED)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	if open_now:
		var visit := ExpeditionUI.button("去拜访   →", true)
		visit.pressed.connect(_on_visit.bind(neighbor))
		row.add_child(visit)
	else:
		row.add_child(_label("（原因：主人暂未开放）", 13, LIGHT_MUTED))
	return row


func _on_visit(neighbor: Dictionary) -> void:
	var target := int(neighbor.get("account_id", 0))
	status_label.text = "正在前往 %s 的院子……" % str(neighbor.get("nick", "?"))
	var reply: Dictionary = await bridge.visit_snapshot(target)
	if str(reply.get("t", "")) != "req_ok":
		## 读取失败：条目旁说明原因，保留选择画面（稿 §7 四态）。
		status_label.text = "没能到 %s 家：%s（可重试或换一位）" % [
			str(neighbor.get("nick", "?")), str(reply.get("msg", reply.get("code", "读取失败")))]
		return
	_last_visit_account = target
	var result: Dictionary = reply.get("result", {})
	visit_requested.emit(result.get("owner", {}), result.get("farm", {}))


func _build() -> void:
	ExpeditionUI.backdrop(self)
	var center := CenterContainer.new()
	main_frame = center
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := ExpeditionUI.panel(Color("#20332a"), Color("#6f9b71"), 16)
	panel.custom_minimum_size = Vector2(680, 460)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var overline := _label("NEIGHBORS   /   邻里地址簿", 14, ExpeditionUI.GOLD)
	overline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(overline)
	var close_button := ExpeditionUI.button("合上地址簿   ×")
	close_button.pressed.connect(func() -> void: close_requested.emit())
	top.add_child(close_button)
	column.add_child(_label("串门啦：去朋友家院子和小屋坐坐。", 22, CREAM))
	status_label = _label("", 15, WARN_GOLD)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	list_column = VBoxContainer.new()
	list_column.add_theme_constant_override("separation", 8)
	list_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_column)


func _label(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
