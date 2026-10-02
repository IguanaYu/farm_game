class_name RoomPanel
extends Control
## 好友组队房间页（2.6 设计 D2.6-01/02/03）。主机/客机两种角色；
## 轮询驱动 SessionHost／SessionClient（本面板 _process 负责泵网络）。
## 局域网／本机直连为当前实测方式；互联网直连需端口可达（交付报告如实标注）。

signal close_requested
signal coop_run_started_host(expedition: ExpeditionGame)
signal coop_run_started_client(client: SessionClient)

const FOREST := Color("#294f3c")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const TEXT_MUTED := Color("#3f4a42")
const BAD_RED := Color("#a4543f")
## 加入超时提示（毫秒）：链路一直不 ready 时给出可读原因。
const JOIN_TIMEOUT_MS := 5000

var game: FarmGame
var host: SessionHost = null
var client: SessionClient = null
var is_host := false
## 连接端口可覆盖（默认 31967；面板级测试用独立端口避免撞上正在运行的游戏）。
var listen_port := SessionHost.DEFAULT_PORT
var status_label: Label
var members_label: Label
var address_edit: LineEdit
var ready_button: Button
var depart_button: Button
## 客机准备状态以主机广播为准（F-11：据此切换而不是固定 true）。
var client_ready_state := false
var _hello_sent := false
var _join_started_ms := 0
## 已处理过的出发局 ID：同一局只确认一次；拒绝后主机再次发起（新 ID）仍会确认。
var _handled_run_id := ""


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
	client_ready_state = false
	_hello_sent = false
	_handled_run_id = ""
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
		if not _hello_sent:
			if client.link_ready():
				## 握手不再挂一次性定时器：链路就绪即发，慢连接不丢 hello（F-03 附带）。
				_hello_sent = true
				var inventory := InventoryGame.new()
				inventory.bind(game.state["expedition"])
				client.hello_with(str(game.state["expedition"].get("player_id", "")), inventory)
				status_label.text = "已连接，正在握手……"
			elif Time.get_ticks_msec() - _join_started_ms > JOIN_TIMEOUT_MS:
				status_label.text = "连不上主机：检查地址与端口（31967）。"
		## 出发指令到达：本机保存→写占用→回执（F-03；保存失败阻止开局）。
		if client.pending_run_id != "" and client.pending_run_id != _handled_run_id:
			_handled_run_id = client.pending_run_id
			_on_depart_begin()


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
	if not host.listen(game, listen_port):
		status_label.text = "监听失败：端口被占用？"
		host = null
		return
	is_host = true
	client = null
	ready_button.disabled = false
	host.packet_received.connect(_on_host_packet)
	_refresh_room()
	status_label.text = "房间已创建。把你的局域网地址告诉好友来加入。"


func _on_host_packet(_peer_id: int, message: Dictionary) -> void:
	match str(message.get("t", "")):
		"hello", "ready":
			_refresh_room()
		"depart_declined":
			## 客机保存失败等：本次出发作废，提示后可再次发起。
			status_label.text = "出发被客机拒绝：%s（问题解决后可再次点出发）" % str(message.get("reason", "未知原因"))
			_refresh_room()


func _refresh_room() -> void:
	if host == null:
		return
	var names: Array = []
	var member_count := 0
	var all_ready := true
	for member_id in host.room["members"]:
		var member: Dictionary = host.room["members"][member_id]
		member_count += 1
		if not bool(member.get("ready", false)):
			all_ready = false
		names.append("%s%s%s" % [member.get("name", "?"), "（主机）" if bool(member.get("is_host", false)) else "", " ✓已准备" if bool(member.get("ready", false)) else ""])
	members_label.text = "成员：%s" % "、".join(names)
	## 出发按钮只在两人齐且全员准备时可用（F-11 验收：客机取消准备后主机不能出发）。
	depart_button.disabled = host.expedition != null or member_count < 2 or not all_ready


func _on_join() -> void:
	var address := address_edit.text.strip_edges()
	if address == "":
		address = "127.0.0.1"
	client = SessionClient.new()
	if not client.connect_to_host(address, game, listen_port):
		status_label.text = "连接发起失败。"
		client = null
		return
	is_host = false
	host = null
	_hello_sent = false
	_handled_run_id = ""
	_join_started_ms = Time.get_ticks_msec()
	ready_button.disabled = false
	depart_button.disabled = true
	client.room_updated.connect(_on_room_updated)
	client.run_received.connect(_on_client_depart)
	client.welcome_received.connect(_on_client_welcome)
	status_label.text = "连接中……（主机确认后这里会更新）"


func _on_client_welcome(ok: bool, reason: String) -> void:
	if not ok and reason != "":
		status_label.text = "主机拒绝：%s" % reason


## 主机广播的房间视图：刷新成员列表，并记住本机（客机）的准备状态（F-11）。
func _on_room_updated(room: Dictionary) -> void:
	var names: Array = []
	for member_id in room.get("members", {}):
		var member: Dictionary = room["members"][member_id]
		var mark := ""
		if not bool(member.get("online", true)):
			mark = "（离线）"
		elif bool(member.get("ready", false)):
			mark = " ✓已准备"
		names.append("%s%s%s" % [member.get("name", "?"), "（主机）" if bool(member.get("is_host", false)) else "", mark])
		if not bool(member.get("is_host", false)):
			client_ready_state = bool(member.get("ready", false))
	members_label.text = "成员：%s" % "、".join(names)
	if _hello_sent:
		ready_button.disabled = false
		status_label.text = "已加入房间（成员状态随主机广播更新）。"


func _on_ready() -> void:
	if is_host and host != null:
		host.host_set_ready(not bool(host.room["members"][1]["ready"]))
		_refresh_room()
	elif client != null:
		## 按主机广播的本机状态切换（F-11：第二次点击是取消，不是再准备一次）。
		client.set_ready(not client_ready_state)
		status_label.text = "已取消准备，可继续调整战备。" if client_ready_state else "已准备，等待主机出发。"


func _on_depart() -> void:
	if host == null:
		return
	var result := host.begin_depart()
	status_label.text = str(result.get("reason", ""))
	if bool(result.get("waiting", false)):
		status_label.text = "已发起出发：等待客机保存确认……"
	if host.expedition != null:
		visible = false
		coop_run_started_host.emit(host.expedition)


## 收到主机出发指令（F-03）：先落盘本机存档 → 写占用并回执 → 再落盘一次占用状态；
## 任一步失败都不回执/明确拒绝，主机收不到确认就不会开局。
func _on_depart_begin() -> void:
	if not _save_farm():
		status_label.text = "出发暂停：本机存档写入失败（检查磁盘空间与权限）。"
		client.decline_depart("存档写入失败")
		return
	var confirmed := client.confirm_depart()
	if not confirmed["ok"]:
		status_label.text = "出发暂停：%s" % str(confirmed["reason"])
		client.decline_depart(str(confirmed["reason"]))
		return
	if not _save_farm():
		status_label.text = "警告：占用已写入但落盘失败；重启后可能需要重新占用，请联系主机。"
		return
	status_label.text = "已确认出发，等待主机开局……"


## 客机侧落盘（与 farm_world._save 同一规则：育种结算→整档写入）。
func _save_farm() -> bool:
	game.breeder_settle(int(Time.get_unix_time_from_system()))
	return SaveStore.save_state(game.state)


func _on_client_depart(_run: Dictionary) -> void:
	## 正式局快照到达：切到客机局界面（F-03 的界面切换半边，此前从未接线）。
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
