extends SceneTree
## d43：M1 客户端桥接/登录/farm_world 线上分支集成（计划 §7 表第二行）。
## 编排：独立子进程跑 server_main；进程内用真实 OnlineClient/OnlineFarmBridge/登录面板/
## farm_world（main.tscn 全场景）走线上路径。
## 覆盖：激活→welcome→快照灌入、farm_basic 命令路由、now() 服务器锚点、
##       farm_world 线上分支（命令路由 + 未迁移入口拦截 + 本地档零写入 F09）、
##       N03 客户端侧体验（同账户新桥接顶替旧桥接）、断线 can_submit=false、
##       服务端重启自动重连续玩、登录面板凭据管理与错误文案、会话文件备份恢复。
## 输出：D43-PASS/D43-FAIL 逐条；退出码 0=通过。

const PORT := 31994
const URL := "wss://127.0.0.1:31994"

var godot_exe := ""
var project_dir := ""
var db_path := ""
var server_pid := 0
var failed := false
var fail_count := 0
var checks := 0
var _session_backup: Variant = null
var _settings_backup: String = ""


func _initialize() -> void:
	godot_exe = OS.get_executable_path()
	project_dir = ProjectSettings.globalize_path("res://")
	db_path = project_dir.path_join(".zcode/m1/run/d43_farm.db")
	DirAccess.make_dir_recursive_absolute(project_dir.path_join(".zcode/m1/run"))
	for suffix in ["", "-wal", "-shm"]:
		var path: String = db_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	# 备份本机线上凭据（客户端会在 welcome 时写 session.json）
	if FileAccess.file_exists(OnlineClient.session_path()):
		_session_backup = FileAccess.get_file_as_string(OnlineClient.session_path())
	# 备份设置里的线上服务器地址（farm_world 从 SettingsStore 取地址，测试要指向本地子进程）
	if FileAccess.file_exists("user://settings.cfg"):
		_settings_backup = FileAccess.get_file_as_string("user://settings.cfg")
	SettingsStore.set_online_server_url(URL)
	_run()


func _run() -> void:
	await _body()
	_cleanup()
	quit(1 if failed else 0)


func _body() -> void:
	var store := ServerDB.new()
	if not store.open(db_path):
		_check(false, "测试库打开失败")
		return
	var auth := AuthService.new()
	auth.store = store
	var codes: Array = auth.generate_invites(1, "d43")
	store.close()
	if codes.is_empty():
		_check(false, "邀请码生成失败")
		return
	if not await _spawn_server():
		return

	# —— 激活（真实 OnlineClient） ——
	var hs := OnlineClient.new()
	hs.name = "HandshakeClient"
	hs.cert_path = project_dir.path_join("server/secrets/farm_server.crt")
	root.add_child(hs)
	var outcome := {"msg": null}
	hs.welcome_received.connect(func(w): outcome["msg"] = w, CONNECT_ONE_SHOT)
	hs.handshake_failed.connect(func(code, need): outcome["msg"] = {"code": code, "need": need}, CONNECT_ONE_SHOT)
	hs.activate(URL, codes[0], "桥接测试")
	if not await _wait_until(func(): return outcome["msg"] != null, 12000):
		_check(false, "激活超时")
		return
	var welcome: Dictionary = outcome["msg"]
	if not _check(str(welcome.get("t", "")) == "welcome", "OnlineClient 激活 → welcome"):
		return
	var token: String = str(welcome.get("token", ""))
	_check(token.begins_with("t_"), "token 已下发")
	var session := OnlineClient.load_session()
	_check(str(session.get("token", "")) == token, "凭据已写入 session.json（N02）")
	hs.shutdown()
	hs.queue_free()

	# —— 桥接：登录 → 快照 → 命令 ——
	var bridge := OnlineFarmBridge.new()
	bridge.name = "Bridge"
	bridge.client.cert_path = project_dir.path_join("server/secrets/farm_server.crt")
	root.add_child(bridge)
	var bootstrapped := {"done": false}
	bridge.snapshot_applied.connect(func(): bootstrapped["done"] = true)
	var fail_code := {"code": ""}
	bridge.login_failed.connect(func(code, _need): fail_code["code"] = code)
	bridge.begin(URL, token)
	if not await _wait_until(func(): return bootstrapped["done"] or fail_code["code"] != "", 12000):
		_check(false, "桥接登录/快照超时")
		return
	if not _check(bootstrapped["done"] and bridge.game.state.get("seeds", []).size() == 6, "welcome 快照灌入 FarmGame（6 种子）"):
		return
	_check(int(bridge.game.state.get("tutorial_step", -1)) == 0, "新档教程步 0")
	var now_anchor := bridge.now()
	_check(absi(now_anchor - int(welcome.get("server_now", 0))) < 10, "now() 锚定服务器时间（±10s）")
	var planted: Dictionary = await bridge.request("farm.plant", {"plot_id": 1})
	_check(planted.get("t", "") == "req_ok", "桥接 farm.plant → req_ok")
	_check(int(bridge.game.state["seeds"].size()) == 5, "快照回灌：种子 6→5")
	_check(int(bridge.game.state.get("tutorial_step", -1)) == 1, "快照回灌：教程 0→1")

	# —— farm_world 线上分支（全场景；world 自建第二个桥接，同 token 顶替上面的桥接） ——
	var save_hash_before := _file_hash("user://farm_save_v1.json")
	GameFlow.mode = GameFlow.Mode.ONLINE
	GameFlow.online_token = token
	var world: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	if not await _wait_until(func(): return world.get("hud") != null or world.get_node_or_null("OnlineFailLayer") != null, 15000):
		_check(false, "farm_world 线上引导超时")
		return
	if not _check(world.get("hud") != null, "farm_world 收到快照后构建场景与 HUD"):
		return
	var world_bridge: OnlineFarmBridge = world.get("online")
	var world_game: FarmGame = world.get("game")
	_check(world_game == world_bridge.game, "farm_world.game 即其桥接副本（同一实例）")
	var hud: FarmHud = world.get("hud")
	_check(hud.online_mode and hud.online_badge != null, "HUD 在线角标已启用")

	# N03 客户端侧：world 的桥接登录同账户，旧桥接被顶替下线
	if await _wait_until(func(): return bridge.client.state == OnlineClient.State.OFFLINE, 8000):
		_check(true, "旧桥接被新连接顶替（N03 客户端侧）")
	else:
		_check(false, "旧桥接未被顶替（N03 失效）")

	# 六命令路由：world 的处理器直通线上
	var seed_id := int(world_game.state["seeds"][0]["id"])
	var seeds_before: int = world_game.state["seeds"].size()
	world._on_plant_seed_requested(2, seed_id)
	if not await _wait_until(func(): return world_game.state["seeds"].size() == seeds_before - 1, 8000):
		_check(false, "farm_world 播种命令未生效")
		return
	_check(int(world_game.state["plots"][1]["seed_id"]) == seed_id, "第 2 块地经服务器播种成功")

	# 未迁移入口拦截：本地状态零变化
	world._on_buy_seed_requested("cabbage", 1)
	world._on_sell_all_requested()
	world._on_claim_pending_requested()
	await _sleep_frames(5)
	_check(world_game.state["seeds"].size() == seeds_before - 1, "未迁移入口不改动线上状态（拦截生效）")
	_check(int(world_game.state.get("coins", -1)) == 0, "金币未被本地路径触碰")

	# F09：全程不写本地档
	_check(_file_hash("user://farm_save_v1.json") == save_hash_before, "线上会话期间本地存档零写入（F09）")
	_check(hud.online_badge.text.find("联机") >= 0, "在线角标文本已更新（%s）" % hud.online_badge.text)

	# —— 断线：不可提交；服务端重启：world 桥接自动重连续玩 ——
	if not await _kill_server_and_wait():
		return
	if not await _wait_until(func(): return world_bridge.client.state == OnlineClient.State.RECONNECTING, 10000):
		_check(false, "断线后未进入 RECONNECTING")
		return
	_check(not world_bridge.client.can_submit(), "断线期间 can_submit=false（F09）")
	var refused: Dictionary = await world_bridge.request("farm.water", {"plot_id": 2})
	_check(refused.is_empty(), "断线期间命令被拒（返回空信封）")

	if not await _spawn_server():
		return
	if not await _wait_until(func(): return world_bridge.client.state == OnlineClient.State.ONLINE, 25000):
		_check(false, "服务端重启后自动重连失败")
		return
	world._on_water_requested(1)
	if not await _wait_until(func(): return int(world_game.state.get("tutorial_step", -1)) == 2, 10000):
		_check(false, "重连后浇水未推进教程")
		return
	_check(true, "重连后命令恢复（farm.water → 教程 1→2）")

	world.queue_free()
	bridge.queue_free()

	# —— 登录面板（非渲染断言） ——
	var panel := OnlineLoginPanel.new()
	panel.name = "LoginPanel"
	root.add_child(panel)
	_check(panel.login_button.visible, "有凭据时登录按钮可见")
	panel._show_status("测试", true)
	_check(panel.status_label.text == "测试", "面板状态文本可更新")
	var fail_text: String = panel._fail_text(OnlineProtocol.ERR_INVITE_USED, {})
	_check(fail_text.find("已被使用") >= 0, "邀请码复用错误文案正确")
	_check(panel._server_url().begins_with("wss://"), "服务器地址回退默认值")
	panel.queue_free()

	# 会话清理与恢复（不污染本机凭据）
	OnlineClient.clear_session()
	_check(OnlineClient.load_session().is_empty(), "clear_session 后凭据为空")


func _cleanup() -> void:
	if server_pid > 0 and OS.is_process_running(server_pid):
		OS.kill(server_pid)
	for suffix in ["", "-wal", "-shm"]:
		var path: String = db_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	# 恢复设置（服务器地址）
	if _settings_backup != "":
		var settings_file := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
		settings_file.store_string(_settings_backup)
		settings_file.close()
	# 恢复本机凭据备份
	if _session_backup != null:
		var file := FileAccess.open(OnlineClient.session_path(), FileAccess.WRITE)
		file.store_string(str(_session_backup))
		file.close()
	elif FileAccess.file_exists(OnlineClient.session_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OnlineClient.session_path()))
	print("D43-SUMMARY checks=%d failed=%d" % [checks, fail_count])


func _spawn_server() -> bool:
	server_pid = OS.create_process(godot_exe, [
		"--headless", "--path", project_dir, "res://scenes/server_main.tscn", "--",
		"--port", str(PORT), "--db", db_path,
		"--cert", project_dir.path_join("server/secrets/farm_server.crt"),
		"--key", project_dir.path_join("server/secrets/farm_server.key"),
		"--tag", "d43",
	])
	if server_pid < 0:
		_check(false, "服务端子进程启动失败")
		return false
	# 启动等待用阻塞探测（此时无需要帧驱动的在树节点；第二次重启时仅短暂阻塞）
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if _port_ready():
			return true
		OS.delay_msec(150)
	_check(false, "服务端未就绪")
	return false


func _port_ready() -> bool:
	var probe := WebSocketMultiplayerPeer.new()
	var cert := X509Certificate.new()
	cert.load(project_dir.path_join("server/secrets/farm_server.crt"))
	probe.create_client(URL, TLSOptions.client(cert))
	var probe_deadline := Time.get_ticks_msec() + 400
	var ready := false
	while Time.get_ticks_msec() < probe_deadline:
		probe.poll()
		if probe.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			ready = true
			break
		if probe.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			break
		OS.delay_msec(5)
	probe.close()
	return ready


func _kill_server_and_wait() -> bool:
	if server_pid <= 0:
		return true
	OS.kill(server_pid)
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and OS.is_process_running(server_pid):
		await process_frame
	server_pid = 0
	OS.delay_msec(200)
	return true


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()


func _sleep_frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _file_hash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "<none>"
	var text := FileAccess.get_file_as_string(path)
	return str(text.length()) + ":" + AuthService.sha256_hex(text)


func _check(ok: bool, label: String) -> bool:
	checks += 1
	if ok:
		print("D43-PASS %s" % label)
	else:
		failed = true
		fail_count += 1
		print("D43-FAIL %s" % label)
	return ok
