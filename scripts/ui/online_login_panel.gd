class_name OnlineLoginPanel
extends Control
## M1 线上农场登录面板（计划 §5.4，W02 UI）：邀请码激活（首次）/一键登录（本机有凭据）/
## 撤销本机凭据（N02）。成功后发 entered_online(token)，由主菜单切 farm_world（Mode.ONLINE）。
## 服务器地址可改（SettingsStore [online] server_url），默认内置腾讯云直连。

signal entered_online(token: String)

const FOREST := Color("#294f3c")
const CREAM := Color("#fff9ed")
const TEXT_MUTED := Color("#3f4a42")
const BAD_RED := Color("#a4543f")

var status_label: Label
var nick_edit: LineEdit
var invite_edit: LineEdit
var address_edit: LineEdit
var activate_button: Button
var login_button: Button
var revoke_button: Button
var client: OnlineClient = null
var _busy := false


func _ready() -> void:
	custom_minimum_size = Vector2(520, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title := Label.new()
	title.text = "线上农场"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", FOREST)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "线上进度由服务器实时保存；操作需要联网。与本地存档完全独立。"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)

	nick_edit = _line_edit("昵称（首次激活时填写，1～16 字符）")
	box.add_child(nick_edit)
	invite_edit = _line_edit("邀请码（FARM-XXXX-XXXX，找开发者领取）")
	box.add_child(invite_edit)

	activate_button = _button("激活并创建线上农场")
	activate_button.pressed.connect(_on_activate)
	box.add_child(activate_button)

	login_button = _button("进入我的线上农场")
	login_button.pressed.connect(_on_login)
	box.add_child(login_button)

	revoke_button = _button("清除本机登录凭据")
	revoke_button.pressed.connect(_on_revoke)
	box.add_child(revoke_button)

	address_edit = _line_edit("服务器地址")
	address_edit.text = SettingsStore.get_online_server_url()
	address_edit.text_changed.connect(_on_address_changed)
	box.add_child(address_edit)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", TEXT_MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)

	_refresh_session()


func _refresh_session() -> void:
	var session := OnlineClient.load_session()
	var has_session := not session.is_empty()
	login_button.visible = has_session
	revoke_button.visible = has_session
	if has_session:
		status_label.text = "本机已保存「%s」的登录凭据。" % str(session.get("nick", ""))


func _on_address_changed(text: String) -> void:
	if text.begins_with("wss://"):
		SettingsStore.set_online_server_url(text)


func _on_activate() -> void:
	if _busy:
		return
	var invite := invite_edit.text.strip_edges(true, true)
	var nick := nick_edit.text.strip_edges(true, true)
	if nick.is_empty() or nick.length() > OnlineProtocol.NICK_MAX_CHARS:
		_show_status("请先填写昵称（1～16 字符）。", true)
		return
	if invite.is_empty():
		_show_status("请填写邀请码。", true)
		return
	_run_handshake(func(c: OnlineClient) -> void:
		c.activate(_server_url(), invite, nick)
	, "正在激活…")


func _on_login() -> void:
	if _busy:
		return
	var session := OnlineClient.load_session()
	if session.is_empty():
		_refresh_session()
		_show_status("本机没有凭据，请用邀请码激活。", true)
		return
	_run_handshake(func(c: OnlineClient) -> void:
		c.begin_with_token(_server_url(), str(session.get("token", "")))
	, "正在登录…")


func _on_revoke() -> void:
	OnlineClient.clear_session()
	_refresh_session()
	_show_status("本机凭据已清除（不影响账户，可在任意电脑重新登录）。", false)


func _server_url() -> String:
	var url := address_edit.text.strip_edges(true, true)
	return url if url.begins_with("wss://") else SettingsStore.get_online_server_url()


func _run_handshake(starter: Callable, busy_text: String) -> void:
	_busy = true
	_show_status(busy_text, false)
	for button in [activate_button, login_button, revoke_button]:
		button.disabled = true
	if client != null:
		client.queue_free()
	client = OnlineClient.new()
	client.name = "OnlineHandshakeClient"
	add_child(client)
	var outcome := {"msg": null}
	client.welcome_received.connect(func(welcome): outcome["msg"] = welcome, CONNECT_ONE_SHOT)
	client.handshake_failed.connect(func(code, need): outcome["msg"] = {"code": code, "need": need}, CONNECT_ONE_SHOT)
	starter.call(client)
	var deadline := Time.get_ticks_msec() + 12000
	while outcome["msg"] == null and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	for button in [activate_button, login_button, revoke_button]:
		button.disabled = false
	_busy = false
	var msg: Variant = outcome["msg"]
	if msg == null:
		_show_status("连接超时：检查网络或服务器地址。", true)
		return
	if msg is Dictionary and str(msg.get("code", "")) != "":
		_show_status(_fail_text(str(msg["code"]), msg.get("need", {})), true)
		return
	var welcome: Dictionary = msg
	# 面板的握手连接到此为止；farm_world 会用凭据重新登录（短暂双连由服务器单会话顶替）
	client.shutdown()
	client.queue_free()
	client = null
	GameFlow.online_token = str(welcome.get("token", OnlineClient.load_session().get("token", "")))
	_refresh_session()
	entered_online.emit(GameFlow.online_token)


func _fail_text(code: String, need: Dictionary) -> String:
	match code:
		OnlineProtocol.ERR_INVITE_INVALID:
			return "邀请码无效：请核对输入（区分大小写可忽略，连字符要有）。"
		OnlineProtocol.ERR_INVITE_USED:
			return "邀请码已被使用：一个码只能激活一个账户。"
		OnlineProtocol.ERR_NICK_INVALID:
			return "昵称不合法：1～16 个字符。"
		OnlineProtocol.ERR_VERSION_MISMATCH:
			return "客户端版本过旧，请向开发者索取新包（需要协议 %s）。" % str(need.get("proto", "?"))
		OnlineProtocol.ERR_TOKEN_INVALID:
			return "登录凭据已失效：请重新激活或联系开发者重发。"
		OnlineProtocol.ERR_ACCOUNT_DISABLED:
			return "该账户已被停用：请联系开发者。"
		OnlineProtocol.ERR_SESSION_REPLACED:
			return "该账户已在别处登录。"
		OnlineProtocol.ERR_INTERNAL:
			return "服务器内部错误：请联系开发者（保留截图）。"
	return "连接失败（%s）。" % code


func _show_status(text: String, bad := false) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", BAD_RED if bad else TEXT_MUTED)


func _line_edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.add_theme_font_size_override("font_size", 15)
	return edit


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	return button
