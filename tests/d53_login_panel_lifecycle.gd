extends SceneTree
## d53：登录面板握手生命周期（D-01 回归）。
## 背景：实机测试发现"一键登录 6 试 1 成"——面板 _run_handshake 超时/被踢路径
## 遗留握手客户端，其 begin_with_token 自动重连生命周期在后台无限重连、反复抢注
## 账号会话，把后续登录拖进"顶替-被踢"循环。
## 覆盖：
##   1) 超时路径必须关停并释放握手客户端（无僵尸）；
##   2) 握手期被踢必须立即以错误终结（不再挂到超时）；
##   3) 换客户端重入时旧握手客户端先 shutdown 再释放；
##   4) 真实主菜单→面板→登录→farm_world 线上 boot 全链路（真实场景冒烟）。
## 输出 D53-PASS/D53-FAIL 逐条；退出码 0=通过。
## 用法：Godot --headless --path . --script res://tests/d53_login_panel_lifecycle.gd

const PORT := 31987
const URL := "wss://127.0.0.1:31987"
const DEAD_URL := "wss://127.0.0.1:31989"
const PANEL_DEADLINE_MS := 12000

var server_pid := 0
var db_path := ""
var failed := false
var checks := 0


func _initialize() -> void:
	_setup_server()
	await _check_timeout_releases_client()
	await _check_kicked_ends_immediately()
	await _check_reentry_retires_old_client()
	await _check_full_ui_flow()
	_cleanup()
	print("D53 %s %d 项检查，失败 %d 项" % ["PASS" if not failed else "FAIL", checks, 1 if failed else 0])
	quit(1 if failed else 0)


func _check(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failed = true
	print("D53 %s %s" % ["ok" if cond else "FAIL", label])


func _setup_server() -> void:
	var project_dir := ProjectSettings.globalize_path("res://")
	db_path = project_dir.path_join(".zcode/d53/run/lifecycle.db")
	DirAccess.make_dir_recursive_absolute(project_dir.path_join(".zcode/d53/run"))
	for suffix in ["", "-wal", "-shm"]:
		var p: String = db_path + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	server_pid = OS.create_process(OS.get_executable_path(),
		["--headless", "--path", ".", "res://scenes/server_main.tscn", "--",
		 "--port", str(PORT), "--db", db_path,
		 "--cert", "server/secrets/farm_server.crt", "--key", "server/secrets/farm_server.key",
		 "--tag", "d53"])
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.25).timeout
		if FileAccess.file_exists(db_path):
			break
	await create_timer(0.8).timeout


func _invite() -> String:
	for attempt in range(8):
		var store := ServerDB.new()
		if store.open(db_path):
			var auth := AuthService.new()
			auth.store = store
			var codes: Array = auth.generate_invites(1, "d53")
			store.close()
			if not codes.is_empty():
				return str(codes[0])
		await create_timer(0.4).timeout
	return ""


func _make_menu() -> Node:
	var menu := preload("res://scripts/ui/main_menu.gd").new()
	root.add_child(menu)
	await process_frame
	menu._on_online()
	await process_frame
	return menu


## 1) 超时释放：对死端口登录，面板走完 12s 超时后，握手客户端必须已关停并出树。
func _check_timeout_releases_client() -> void:
	OnlineClient.save_session("t_deadbeef", 99, "超时测试")
	SettingsStore.set_online_server_url(DEAD_URL)
	var menu := await _make_menu()
	var panel: OnlineLoginPanel = menu.online_panel
	panel._on_login()
	var t0 := Time.get_ticks_msec()
	while panel._busy and Time.get_ticks_msec() - t0 < PANEL_DEADLINE_MS + 4000:
		await process_frame
	var c = panel.client
	_check(c == null or not c.is_inside_tree() or c.state == 0,
		"超时路径释放握手客户端（僵尸根治）")
	menu.queue_free()
	await process_frame


## 2) 被踢即终结：握手客户端收到 kicked 时，面板立即以该原因结束等待（不等超时）。
func _check_kicked_ends_immediately() -> void:
	OnlineClient.save_session("t_deadbeef", 99, "被踢测试")
	SettingsStore.set_online_server_url(DEAD_URL)
	var menu := await _make_menu()
	var panel: OnlineLoginPanel = menu.online_panel
	panel._on_login()
	# 等到面板进入等待（至少 1 帧）
	await process_frame
	var c = panel.client
	_check(c != null, "被踢用例：握手客户端已建立")
	var settled_at := -1
	var t0 := Time.get_ticks_msec()
	c.kicked.emit(OnlineProtocol.ERR_SESSION_REPLACED)
	while panel._busy and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	if not panel._busy:
		settled_at = int(Time.get_ticks_msec() - t0)
	_check(settled_at >= 0 and settled_at < 2500,
		"被踢路径立即终结（%dms，非挂到 12s 超时）" % maxi(0, settled_at))
	_check(panel.status_label.text.find("已在别处登录") != -1,
		"被踢原因如实展示（%s）" % panel.status_label.text.substr(0, 24))
	menu.queue_free()
	await process_frame


## 3) 重入退役：第二次握手发起时，旧握手客户端先被 shutdown 再释放。
func _check_reentry_retires_old_client() -> void:
	var menu := await _make_menu()
	var panel: OnlineLoginPanel = menu.online_panel
	var first := OnlineClient.new()
	panel.add_child(first)
	panel.client = first
	SettingsStore.set_online_server_url(DEAD_URL)
	panel._on_login()
	# _retire_client 在 _run_handshake 开头同步执行：调用返回时旧客户端已 shutdown
	# （queue_free 在帧末生效，state 要在 await 前读取）。
	var retired_state: int = first.state
	await process_frame
	_check(retired_state == 0, "重入时旧客户端已 shutdown（OFFLINE）")
	_check(panel.client != first, "重入时旧客户端已替换")
	menu.queue_free()
	await process_frame


## 4) 真实全链路：主菜单场景 → 面板登录（真服务器）→ farm_world 线上 boot 完成。
func _check_full_ui_flow() -> void:
	var code := await _invite()
	if code == "":
		_check(false, "全链路：邀请码生成")
		return
	var seed_client := OnlineClient.new()
	root.add_child(seed_client)
	var seed_done := {}
	seed_client.welcome_received.connect(func(w): seed_done["w"] = w, CONNECT_ONE_SHOT)
	seed_client.handshake_failed.connect(func(c, n): seed_done["f"] = [c, n], CONNECT_ONE_SHOT)
	seed_client.activate(URL, code, "面板甲")
	var t0 := Time.get_ticks_msec()
	while not seed_done.has("w") and not seed_done.has("f") and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
	seed_client.shutdown()
	seed_client.queue_free()
	if not seed_done.has("w"):
		_check(false, "全链路：预激活 %s" % str(seed_done.get("f", "timeout")))
		return
	OnlineClient.save_session(str(seed_done["w"].get("token", "")),
		int(seed_done["w"].get("account_id", 0)), "面板甲")
	SettingsStore.set_online_server_url(URL)

	GameFlow.mode = GameFlow.Mode.CONTINUE
	var err := change_scene_to_file("res://scenes/main_menu.tscn")
	if err != OK:
		_check(false, "全链路：装载主菜单 err=%d" % err)
		return
	var menu: Node = null
	for i in range(60):
		await process_frame
		if root.get_child_count() > 0:
			menu = root.get_child(root.get_child_count() - 1)
		if menu != null and str(menu.get_script().resource_path) == "res://scripts/ui/main_menu.gd":
			break
	if menu == null:
		_check(false, "全链路：主菜单节点")
		return
	menu._on_online()
	await process_frame
	var panel: OnlineLoginPanel = menu.online_panel
	panel._on_login()
	t0 = Time.get_ticks_msec()
	var booted := false
	var authenticated := false
	while Time.get_ticks_msec() - t0 < 15000:
		await process_frame
		# 场景切换有空窗帧（root 无子节点），先守卫再取。
		var current: Node = null
		if root.get_child_count() > 0:
			current = root.get_child(root.get_child_count() - 1)
		if current == null:
			continue
		if str(current.get_script().resource_path) == "res://scripts/world/farm_world.gd":
			var ctx: GameContext = current.context
			if ctx != null and ctx._booted:
				booted = true
				authenticated = ctx.online != null and ctx.online.client._authenticated
				break
	_check(booted and authenticated, "全链路：farm_world 线上 boot 完成（认证在位）")
	if booted and root.get_child_count() > 0:
		root.get_child(root.get_child_count() - 1).queue_free()
		for i in range(5):
			await process_frame


func _cleanup() -> void:
	if server_pid != 0:
		OS.kill(server_pid)
	# 还原线上地址指向本地测试服（避免污染后续测试的本机设置）
	SettingsStore.set_online_server_url("wss://127.0.0.1:%d" % PORT)
