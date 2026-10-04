extends SceneTree
## d52：R7 拜访系统验收（计划：docs/plan/Godot_合并路线_R7_拜访系统_代码执行计划_v0.1.md §5）。
## 子进程服务器 + 双账户 + 完整 farm_world。覆盖：
##   协议：visit.list（含对方/不含自己/在线态）；visit.snapshot（对方农场数据一致）；
##         --visits-closed → 全关 + snapshot 拒（读取失败原因）
##   隔离红线：A 拜访 B 后 farm 命令只作用于 A；visit.snapshot 无收据（重放非 duplicate）
##   客户端：地址簿渲染；进院子（结构 + 只读地块 pickable=false）；进小屋（主人昵称留言板）；
##           院门回农场后门控解除 + game 实例不变
## 用法：Godot --headless --path . --script res://tests/d52_visit_smoke.gd

const PORT := 31984
const REQ_TIMEOUT_MS := 8000
const SAVE_FILES := ["farm_save_v1.json", "farm_save_v1.json.bak"]

var godot_exe := ""
var project_dir := ""
var db_path := ""
var cert_path := ""
var key_path := ""
var server_pid := 0
var failed := false
var fail_count := 0
var checks := 0
var req_seq := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	godot_exe = OS.get_executable_path()
	project_dir = ProjectSettings.globalize_path("res://")
	db_path = project_dir.path_join(".zcode/m1/run/d52_farm.db")
	cert_path = project_dir.path_join("server/secrets/farm_server.crt")
	key_path = project_dir.path_join("server/secrets/farm_server.key")
	DirAccess.make_dir_recursive_absolute(project_dir.path_join(".zcode/m1/run"))
	for suffix in ["", "-wal", "-shm"]:
		var path: String = db_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

	var store := ServerDB.new()
	if not store.open(db_path):
		_check(false, "测试库打开失败")
		_finish()
		return
	var auth := AuthService.new()
	auth.store = store
	var codes: Array = auth.generate_invites(2, "d52")
	var tokens := {}
	var b_coins := -1
	for pair in [["a", codes[0], "玩家甲"], ["b", codes[1], "玩家乙"]]:
		var seed_farm := FarmGame.new()
		seed_farm.new_game(int(Time.get_unix_time_from_system()))
		if str(pair[0]) == "b":
			seed_farm.state["coins"] = 123
		var created: Dictionary = auth.activate(str(pair[1]), str(pair[2]), JSON.stringify(seed_farm.state))
		tokens[pair[0]] = str(created.get("token", ""))
		if str(pair[0]) == "b":
			b_coins = int(seed_farm.state["coins"])
	store.close()
	if not _spawn_server(false):
		return

	# —— 段1：协议 ——
	var a := _client()
	if not a.connect_to(PORT) or str(a.hello(str(tokens["a"])).get("t", "")) != "welcome":
		_check(false, "甲登录")
		_finish()
		return
	var listed: Dictionary = a.request("visit.list", {}, _rid())
	if not _check(str(listed.get("t", "")) == "req_ok", "visit.list 成功"):
		_finish()
		return
	var neighbors: Array = listed["result"].get("neighbors", [])
	_check(neighbors.size() == 1 and str(neighbors[0].get("nick", "")) == "玩家乙", "地址簿只含对方（不含自己）")
	_check(bool(neighbors[0].get("visits_open", false)), "默认开放参观")
	var b_id := int(neighbors[0].get("account_id", 0))
	var snap: Dictionary = a.request("visit.snapshot", {"account_id": b_id}, _rid())
	if not _check(str(snap.get("t", "")) == "req_ok", "visit.snapshot 成功"):
		_finish()
		return
	_check(int(snap["result"].get("farm", {}).get("coins", -2)) == b_coins, "快照金币与乙方库内一致（%d）" % b_coins)
	var snap_again: Dictionary = a.request("visit.snapshot", {"account_id": b_id}, _rid())
	_check(not bool(snap_again.get("duplicate", true)), "读命令无收据副作用（重放非 duplicate）")
	var bad: Dictionary = a.request("visit.snapshot", {"account_id": 999}, _rid())
	_check(str(bad.get("msg", "")).find("account_missing") >= 0, "不存在邻居 → account_missing 原因")

	# —— 段2：隔离红线 ——
	var plant: Dictionary = a.request("farm.plant", {"plot_id": 1}, _rid())
	_check(str(plant.get("t", "")) == "req_ok", "拜访数据在手时自己农场命令照常（作用于甲）")
	var re_snap: Dictionary = a.request("visit.snapshot", {"account_id": b_id}, _rid())
	_check(int(re_snap["result"].get("farm", {}).get("coins", -2)) == b_coins, "红线：乙方金币未被甲方操作改变")

	# —— 段3：客户端场景 ——
	var backup := _backup_saves()
	GameFlow.mode = GameFlow.Mode.ONLINE
	GameFlow.online_token = str(tokens["a"])
	var url_backup := SettingsStore.get_online_server_url()
	SettingsStore.set_online_server_url("wss://127.0.0.1:%d" % PORT)
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	for i in range(60):
		await process_frame
		if world.hud != null:
			break
	if not _check(world.hud != null and world.online != null, "线上 farm_world 就绪"):
		_restore(backup)
		_finish()
		return
	var g1: FarmGame = world.game
	world.hud.open_visit_directory()
	for i in range(40):
		await process_frame
		if world.hud.online_visit_panel.visible:
			break
	_check(world.hud.online_visit_panel.visible, "地址簿打开并渲染")
	world.enter_visit({"account_id": b_id, "nick": "玩家乙"}, re_snap["result"].get("farm", {}))
	await process_frame
	var yard: Node3D = world.get_node_or_null("VisitYard")
	if not _check(yard != null and yard.visible and str(world.router.current) == "visit_yard", "院子地点切换"):
		_restore(backup)
		_finish()
		return
	var visit_plot: Node = yard.get_node_or_null("VisitPlot_01")
	var plot_readonly := visit_plot != null
	if plot_readonly:
		for connection in visit_plot.input_event.get_connections():
			if connection["callable"].get_method() != "_on_visit_crop_input":
				plot_readonly = false
	_check(plot_readonly, "院子地块仅绑定只读查看，不绑定收获等写操作")
	_check(world.hud.visiting, "拜访门控开启（hud.visiting）")
	world.router.switch_to("visit_house")
	var house: Node3D = world.get_node_or_null("VisitHouseInterior")
	_check(house != null and house.visible and str(world.router.current) == "visit_house", "小屋地点切换")
	var board: Node = house.get_node_or_null("MessageBoard")
	_check(board != null and str(board.get_meta("owner_nick", "")) == "玩家乙", "留言板主人身份正确")
	world.leave_visit()
	await process_frame
	_check(str(world.router.current) == "farm" and not world.hud.visiting, "院门回农场：门控解除")
	_check(world.game == g1, "拜访往返 game 同实例（自家资产零触碰）")

	# —— 段4：--visits-closed 服务器 ——
	SettingsStore.set_online_server_url(url_backup)
	_restore(backup)
	if not _kill_server_and_wait():
		return
	if not _spawn_server(true):
		return
	var a2 := _client()
	if not a2.connect_to(PORT) or str(a2.hello(str(tokens["a"])).get("t", "")) != "welcome":
		_check(false, "关访服务器登录")
		_finish()
		return
	var closed_list: Dictionary = a2.request("visit.list", {}, _rid())
	_check(not bool(closed_list["result"].get("visits_open", true)), "关访开关下地址簿全关")
	var closed_snap: Dictionary = a2.request("visit.snapshot", {"account_id": b_id}, _rid())
	_check(str(closed_snap.get("msg", "")).find("visit_closed") >= 0, "关访快照 → visit_closed 原因")
	_finish()


func _rid() -> String:
	req_seq += 1
	return "d52-%04d" % req_seq


func _backup_saves() -> Dictionary:
	var backup := {}
	for name in SAVE_FILES:
		var path := "user://%s" % name
		if FileAccess.file_exists(path):
			backup[name] = FileAccess.get_file_as_string(path)
	return backup


func _restore(backup: Dictionary) -> void:
	for name in SAVE_FILES:
		var path := "user://%s" % name
		if backup.has(name):
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(backup[name])
			file.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _spawn_server(closed: bool) -> bool:
	var args := [
		"--headless", "--path", project_dir, "res://scenes/server_main.tscn", "--",
		"--port", str(PORT), "--db", db_path,
		"--cert", cert_path, "--key", key_path, "--tag", "d52",
	]
	if closed:
		args.append("--visits-closed")
	server_pid = OS.create_process(godot_exe, args)
	if server_pid < 0:
		_check(false, "服务端子进程启动失败")
		return false
	var probe := WebSocketMultiplayerPeer.new()
	var cert := X509Certificate.new()
	cert.load(cert_path)
	probe.create_client("wss://127.0.0.1:%d" % PORT, TLSOptions.client(cert))
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		probe.poll()
		if probe.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			probe.close()
			return true
		if probe.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			break
		OS.delay_msec(20)
	_check(false, "服务端 15 秒内未就绪")
	return false


func _kill_server_and_wait() -> bool:
	if server_pid <= 0:
		return true
	OS.kill(server_pid)
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and OS.is_process_running(server_pid):
		OS.delay_msec(50)
	server_pid = 0
	OS.delay_msec(250)
	return true


func _finish() -> void:
	if server_pid > 0:
		OS.kill(server_pid)
	print("D52-SUMMARY checks=%d failed=%d" % [checks, fail_count])
	quit(1 if failed else 0)


func _check(ok: bool, label: String) -> bool:
	checks += 1
	if ok:
		print("D52-PASS %s" % label)
	else:
		failed = true
		fail_count += 1
		print("D52-FAIL %s" % label)
	return ok


func _client() -> WsClient:
	var client := WsClient.new()
	client.cert_path = cert_path
	return client


# —— WSS 测试客户端（沿 d50） ——————————————————————————————————————

class WsClient:
	const REPLY_TIMEOUT_MS := 8000
	var peer := WebSocketMultiplayerPeer.new()
	var cert_path := ""
	var inbox: Array = []

	func connect_to(port: int) -> bool:
		var cert := X509Certificate.new()
		if cert.load(cert_path) != OK:
			return false
		if peer.create_client("wss://127.0.0.1:%d" % port, TLSOptions.client(cert)) != OK:
			return false
		var deadline := Time.get_ticks_msec() + 8000
		while Time.get_ticks_msec() < deadline:
			peer.poll()
			var status := peer.get_connection_status()
			if status == MultiplayerPeer.CONNECTION_CONNECTED:
				return true
			if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
				return false
			OS.delay_msec(5)
		return false

	func poll_packets() -> void:
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var raw := peer.get_packet().get_string_from_utf8()
			var parsed := JSON.new()
			if parsed.parse(raw) != OK or not (parsed.data is Dictionary):
				continue
			inbox.append(parsed.data)

	func send_json(payload: Dictionary) -> bool:
		poll_packets()
		peer.set_target_peer(1)
		return peer.put_packet(JSON.stringify(payload).to_utf8_buffer()) == OK

	func wait_for(predicate: Callable, timeout_ms: int) -> Dictionary:
		for i in range(inbox.size()):
			var msg: Dictionary = inbox[i]
			if predicate.call(msg):
				inbox.remove_at(i)
				return msg
		var deadline := Time.get_ticks_msec() + timeout_ms
		while Time.get_ticks_msec() < deadline:
			poll_packets()
			for i in range(inbox.size()):
				var msg: Dictionary = inbox[i]
				if predicate.call(msg):
					inbox.remove_at(i)
					return msg
			OS.delay_msec(3)
		return {}

	func hello(token: String) -> Dictionary:
		send_json({"t": "hello", "token": token, "proto": OnlineProtocol.PROTO_VERSION, "rules": OnlineProtocol.RULES_VERSION, "build": OnlineProtocol.CLIENT_BUILD})
		return wait_for(func(m): return str(m.get("t", "")) == "welcome" or str(m.get("t", "")) == "error", REPLY_TIMEOUT_MS)

	func request(op: String, args: Dictionary, req_id: String) -> Dictionary:
		send_json({"t": "req", "req_id": req_id, "op": op, "args": args})
		return wait_for(
			func(m): return (str(m.get("t", "")) == "req_ok" or str(m.get("t", "")) == "req_err") and str(m.get("req_id", "")) == req_id,
			REPLY_TIMEOUT_MS
		)
