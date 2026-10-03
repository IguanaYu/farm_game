class_name OnlineRoomPanel
extends Control
## M3 线上组队房间页（W07 最小 UI，计划 §5.2）：建房/房码加入/准备/发起出发/离开。
## 数据源是 OnlineFarmBridge 的 room_updated 镜像；出发成功与局推进由 HUD 切到 OnlineRunPanel。

signal close_requested

const CREAM := Color("#fff9ed")
const GOLD := Color("#e8d9a8")
const LIGHT_TEXT := Color("#e8f2d8")
const LIGHT_MUTED := Color("#a3b59b")

var bridge: OnlineFarmBridge
var state_label: Label
var code_label: Label
var members_column: VBoxContainer
var action_row: HBoxContainer
var status_label: Label
var join_edit: LineEdit
var main_frame: CenterContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	theme = ExpeditionUI.make_theme()
	_build()


func open(target_bridge: OnlineFarmBridge) -> void:
	bridge = target_bridge
	if not bridge.room_updated.is_connected(_on_room):
		bridge.room_updated.connect(_on_room)
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _on_room(_room: Dictionary) -> void:
	if visible:
		_refresh()


func _build() -> void:
	ExpeditionUI.backdrop(self)
	var center := CenterContainer.new()
	main_frame = center
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := ExpeditionUI.panel(Color("#20332a"), Color("#6f9b71"), 16)
	panel.custom_minimum_size = Vector2(720, 460)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var overline := _label("COOP ROOM   /   好友组队", 14, ExpeditionUI.GOLD)
	overline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(overline)
	var close_button := ExpeditionUI.button("返回农场   ×")
	close_button.pressed.connect(func() -> void: close_requested.emit())
	top.add_child(close_button)
	column.add_child(_label("输入朋友的房号，或者自己开一间。", 22, CREAM))
	state_label = _label("", 15, GOLD)
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(state_label)
	code_label = _label("", 26, CREAM)
	column.add_child(code_label)
	members_column = VBoxContainer.new()
	members_column.add_theme_constant_override("separation", 6)
	members_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(members_column)
	action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	column.add_child(action_row)
	status_label = _label("", 13, ExpeditionUI.RED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)


func _refresh() -> void:
	if bridge == null:
		return
	var room: Dictionary = bridge.mirror_room
	for child in members_column.get_children():
		members_column.remove_child(child)
		child.queue_free()
	for child in action_row.get_children():
		action_row.remove_child(child)
		child.queue_free()
	if room.is_empty() or str(room.get("phase", "")) == "over":
		_refresh_lobby()
		return
	_refresh_room(room)


## 无房间：建房 + 房码加入。
func _refresh_lobby() -> void:
	state_label.text = "你还没有加入房间。"
	code_label.text = ""
	var create := ExpeditionUI.button("创建房间（我是房主）", true)
	create.pressed.connect(_on_create)
	action_row.add_child(create)
	join_edit = LineEdit.new()
	join_edit.placeholder_text = "输入 6 位房号"
	join_edit.max_length = 6
	join_edit.custom_minimum_size = Vector2(180, 40)
	join_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_row.add_child(join_edit)
	var join := ExpeditionUI.button("加入房间")
	join.pressed.connect(_on_join)
	action_row.add_child(join)


## 房间内：成员列表 + 准备/出发/离开。
func _refresh_room(room: Dictionary) -> void:
	var phase := str(room.get("phase", "waiting"))
	state_label.text = "等待出发（双方准备后，房主发起）" if phase == "waiting" else "本局已开始"
	code_label.text = "房号  %s" % str(room.get("code", "?"))
	var me_id := int(bridge.client.account_id)
	var is_creator := int(room.get("creator_account_id", 0)) == me_id
	var members: Array = room.get("members", [])
	var all_ready := members.size() >= 2
	for member in members:
		var line := "%s%s  ·  %s  ·  %s" % [
			str(member.get("nick", "?")),
			("（房主）" if int(member.get("account_id", 0)) == int(room.get("creator_account_id", 0)) else ""),
			"已准备" if bool(member.get("ready", false)) else "未准备",
			"在线" if bool(member.get("online", false)) else "离线",
		]
		members_column.add_child(_label(line, 16, LIGHT_TEXT if int(member.get("account_id", 0)) != me_id else GOLD))
		if not bool(member.get("ready", false)):
			all_ready = false
	if members.size() < 2:
		members_column.add_child(_label("等待朋友加入……把房号发给他。", 14, LIGHT_MUTED))
	var mine_ready := false
	for member in members:
		if int(member.get("account_id", 0)) == me_id:
			mine_ready = bool(member.get("ready", false))
	if phase == "waiting":
		var ready := ExpeditionUI.button("取消准备" if mine_ready else "准备出发", not mine_ready)
		ready.pressed.connect(_on_ready.bind(not mine_ready))
		action_row.add_child(ready)
		if is_creator:
			var depart := ExpeditionUI.button("发起出发   →", true)
			depart.disabled = not all_ready
			depart.tooltip_text = "双方准备就绪后可用" if depart.disabled else "服务器会一次性检查双方战备并开局"
			depart.pressed.connect(_on_depart)
			action_row.add_child(depart)
	var leave := ExpeditionUI.button("离开房间")
	leave.pressed.connect(_on_leave)
	action_row.add_child(leave)


func _flash(message: String) -> void:
	status_label.text = message


func _on_create() -> void:
	var reply: Dictionary = await bridge.room_create()
	if str(reply.get("t", "")) != "req_ok":
		_flash("创建失败：%s" % str(reply.get("msg", reply.get("code", "未知原因"))))
		return
	_flash("房间已创建，把房号发给朋友。")


func _on_join() -> void:
	if join_edit == null:
		return
	var code := join_edit.text.strip_edges().to_upper()
	if code.length() != 6:
		_flash("房号是 6 位字符。")
		return
	var reply: Dictionary = await bridge.room_join(code)
	if str(reply.get("t", "")) != "req_ok":
		_flash("加入失败：%s" % str(reply.get("msg", reply.get("code", "未知原因"))))
		return


func _on_ready(ready: bool) -> void:
	await bridge.room_ready(ready)


func _on_depart() -> void:
	var reply: Dictionary = await bridge.begin_depart()
	if str(reply.get("t", "")) != "req_ok":
		_flash("出发失败：%s" % str(reply.get("msg", reply.get("code", "未知原因"))))
		return


func _on_leave() -> void:
	var reply: Dictionary = await bridge.room_leave()
	if str(reply.get("t", "")) != "req_ok":
		_flash("离开失败：%s" % str(reply.get("msg", reply.get("code", "未知原因"))))
		return
	_flash("")


func _label(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
