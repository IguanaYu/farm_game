class_name RoomPanel
extends Control
## 好友组队房间页（2.6 设计 D2.6-01/02/03）。主机/客机两种角色；
## 轮询驱动 SessionHost／SessionClient（本面板 _process 负责泵网络）。
## 局域网／本机直连为当前实测方式；互联网直连需端口可达（交付报告如实标注）。

signal close_requested
signal coop_run_started_host(expedition: ExpeditionGame)
signal coop_run_started_client(client: SessionClient)
signal save_requested

const FOREST := Color("#294f3c")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const TEXT_MUTED := Color("#3f4a42")
const BAD_RED := Color("#a4543f")

var game: FarmGame
var host: SessionHost = null
var client: SessionClient = null
var is_host := false
var status_label: Label
var members_label: Label
var address_edit: LineEdit
var ready_button: Button
var depart_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var theme_root := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	theme_root.default_font = font
	theme_root.default_font_size = 17
	theme = theme_root
	_build()
	set_process(true)


func open(target_game: FarmGame) -> void:
	game = target_game
	visible = true
	status_label.text = "选择「创建房间」（主机）或输入主机地址后「加入房间」（客机）。"


func close() -> void:
	visible = false


func _process(_delta: float) -> void:
	if host != null:
		host.poll()
		if host.expedition != null and visible:
			var expedition: ExpeditionGame = host.expedition
			visible = false
			coop_run_started_host.emit(expedition)
	if client != null:
		client.poll()


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.11, 0.20, 0.14, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := _panel(CREAM, Color("#d5c9aa"), 16)
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(_label("好友组队（双人合作）", 22, FOREST))
	var connect_note := _label("当前连接方式：局域网／本机直连（主机 IP＋端口 31967）。互联网好友直连需主机端口可达，实测记录见交付报告。", 13, TEXT_MUTED)
	connect_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(connect_note)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var create_button := _button("创建房间（主机）", Color("#eaf4df"), Color("#87b06f"))
	create_button.pressed.connect(_on_create)
	row.add_child(create_button)
	address_edit = LineEdit.new()
	address_edit.placeholder_text = "主机地址（如 192.168.1.5）"
	address_edit.custom_minimum_size = Vector2(180, 0)
	row.add_child(address_edit)
	var join_button := _button("加入房间", Color("#fff5df"), Color("#d5b87d"))
	join_button.pressed.connect(_on_join)
	row.add_child(join_button)

	members_label = _label("成员：—", 14, TEXT_DARK)
	column.add_child(members_label)
	ready_button = _button("准备／取消准备", Color("#ffd98a"), Color("#9b713a"))
	ready_button.disabled = true
	ready_button.pressed.connect(_on_ready)
	column.add_child(ready_button)
	depart_button = _button("出发（主机，需全员准备）", Color("#eaf4df"), Color("#87b06f"))
	depart_button.disabled = true
	depart_button.pressed.connect(_on_depart)
	column.add_child(depart_button)
	status_label = _label("", 13, BAD_RED)
	column.add_child(status_label)
	var close_button := _button("返回农场", Color("#fff5df"), Color("#d5b87d"))
	close_button.pressed.connect(_on_close)
	column.add_child(close_button)


func _on_create() -> void:
	host = SessionHost.new()
	if not host.listen(game):
		status_label.text = "监听失败：端口被占用？"
		host = null
		return
	is_host = true
	client = null
	ready_button.disabled = false
	depart_button.disabled = false
	host.packet_received.connect(_on_host_packet)
	_refresh_room()
	status_label.text = "房间已创建。把你的局域网地址告诉好友来加入。"


func _on_host_packet(_peer_id: int, message: Dictionary) -> void:
	if str(message.get("t", "")) in ["hello", "ready"]:
		_refresh_room()


func _refresh_room() -> void:
	if host == null:
		return
	var names: Array = []
	for member_id in host.room["members"]:
		var member: Dictionary = host.room["members"][member_id]
		names.append("%s%s%s" % [member.get("name", "?"), "（主机）" if bool(member.get("is_host", false)) else "", " ✓已准备" if bool(member.get("ready", false)) else ""])
	members_label.text = "成员：%s" % "、".join(names)


func _on_join() -> void:
	var address := address_edit.text.strip_edges()
	if address == "":
		address = "127.0.0.1"
	client = SessionClient.new()
	if not client.connect_to_host(address, game):
		status_label.text = "连接发起失败。"
		client = null
		return
	is_host = false
	host = null
	ready_button.disabled = false
	depart_button.disabled = true
	status_label.text = "连接中……（主机确认后这里会更新）"
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(func() -> void:
		if client != null and client.link_ready():
			var inventory := InventoryGame.new()
			inventory.bind(game.state["expedition"])
			client.hello_with(str(game.state["expedition"].get("player_id", "")), inventory)
			client.room_updated.connect(func(_room: Dictionary) -> void: status_label.text = "已加入房间（成员状态随主机广播更新）。")
			status_label.text = "已连接，正在握手……"
		elif client != null:
			status_label.text = "连不上主机：检查地址与端口（31967）。"
	)


func _on_ready() -> void:
	if is_host and host != null:
		host.host_set_ready(not bool(host.room["members"][1]["ready"]))
		_refresh_room()
	elif client != null:
		client.set_ready(true)
		status_label.text = "已准备，等待主机出发。"


func _on_depart() -> void:
	if host == null:
		return
	var result := host.begin_depart()
	status_label.text = str(result.get("reason", ""))
	if host.expedition != null:
		visible = false
		coop_run_started_host.emit(host.expedition)


func _on_client_depart(_run: Dictionary) -> void:
	visible = false
	coop_run_started_client.emit(client)


func _on_close() -> void:
	visible = false
	if host != null:
		host = null
	if client != null:
		client = null
	close_requested.emit()


func _panel(fill: Color, border: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _label(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	# 默认不换行：autowrap 标签在 HBox 里会被压到一字宽竖排；长文本处显式开启。
	return label


func _button(content: String, fill: Color, border: Color) -> Button:
	var button := Button.new()
	button.text = content
	button.add_theme_color_override("font_color", Color("#35513d"))
	button.add_theme_color_override("font_hover_color", Color("#1f3327"))
	button.add_theme_color_override("font_pressed_color", Color("#1f3327"))
	button.add_theme_color_override("font_disabled_color", Color("#5c6b5e"))
	button.add_theme_font_size_override("font_size", 15)
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10
	style.content_margin_right = 10
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	return button
