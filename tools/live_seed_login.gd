extends SceneTree
## 实机测试辅助：为导出版的线上登录预置本机凭据（键盘注入不可用，无法在 UI 里输入邀请码）。
## 连本地测试服激活邀请码 → OnlineClient.save_session 写 user://online/session.json，
## 并把 SettingsStore 线上地址指向本地服。用法：
##   Godot --headless --path . --script res://tools/live_seed_login.gd -- 邀请码 昵称
## 输出 SEED_OK / SEED_FAIL 原因；退出码 0=成功。

const URL := "wss://127.0.0.1:31980"
const TIMEOUT_MS := 15000

var invite := ""
var nick := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		invite = str(args[0])
		nick = str(args[1])


func _initialize() -> void:
	var fail_reason := ""
	if invite.is_empty():
		fail_reason = "用法：-- 邀请码 昵称"
	var cert := X509Certificate.new()
	if fail_reason == "" and cert.load(ProjectSettings.globalize_path("res://").path_join("server/secrets/farm_server.crt")) != OK:
		fail_reason = "证书加载失败"
	var peer := WebSocketPeer.new()
	if fail_reason == "" and peer.connect_to_url(URL, TLSOptions.client(cert)) != OK:
		fail_reason = "WSS 连接发起失败"
	var started := Time.get_ticks_msec()
	var sent := false
	var got_welcome := false
	while fail_reason == "" and Time.get_ticks_msec() - started < TIMEOUT_MS:
		await process_frame
		peer.poll()
		var state := peer.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			fail_reason = "连接关闭 code=%d" % peer.get_close_code()
			break
		if state == WebSocketPeer.STATE_OPEN and not sent:
			peer.send_text(JSON.stringify({
				"t": "activate", "invite": invite, "nick": nick,
				"proto": OnlineProtocol.PROTO_VERSION, "rules": OnlineProtocol.RULES_VERSION,
				"build": OnlineProtocol.CLIENT_BUILD,
			}))
			sent = true
		while peer.get_available_packet_count() > 0:
			var parsed: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if not parsed is Dictionary:
				continue
			var reply: Dictionary = parsed
			if str(reply.get("t", "")) == "welcome" or reply.has("token"):
				var token := str(reply.get("token", ""))
				if not token.begins_with("t_"):
					fail_reason = "welcome 无 token：%s" % str(reply).substr(0, 160)
				else:
					OnlineClient.save_session(token, int(reply.get("account_id", 0)), nick)
					SettingsStore.set_online_server_url(URL)
					if OnlineClient.load_session().is_empty():
						fail_reason = "session.json 读回为空"
					else:
						print("SEED_OK nick=%s acct=%d" % [nick, int(reply.get("account_id", 0))])
						got_welcome = true
			else:
				fail_reason = "激活被拒：%s" % str(reply).substr(0, 160)
		if got_welcome:
			break
	if fail_reason == "" and not got_welcome:
		fail_reason = "握手超时未收到 welcome"
	if fail_reason == "":
		quit(0)
	else:
		print("SEED_FAIL ", fail_reason)
		quit(1)
