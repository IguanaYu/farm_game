extends SceneTree
## d59：R8 好友互助验收（计划：docs/plan/Godot_好友互助浇水施肥_代码执行计划_v0.1.md §5）。
## 子进程服务器 + 双账户 + 完整 farm_world。覆盖：
##   协议：visit.water（时段生效/水壶取最高档原位升级/2级扩散/帮助者经验）；
##         visit.fertilize（扣帮助者库存/主人库存红线/未到期不可覆盖）；
##         幂等（同 req_id 重放 duplicate 且不二次生效）；门槛（自己/999/坏地块/成熟作物）
##   缓存红线：主人先焐热写穿缓存 → 好友帮助 → 主人下一条命令快照必须看到帮助结果（evict 链路）
##   结算：--dev-time-shift 跨成熟后主人收获 → breakdown 含好友加成、经历含好友昵称、helpers 清空
##   开关：--visits-closed → visit_closed；--features 缺 visit_help → feature_disabled
##   客户端：进院子 → 生长中地块开 visit_care 弹窗（肥料按钮=访客自己库存）→ 点浇水走通真实链路
## 用法：Godot --headless --path . --script res://tests/d59_visit_help_smoke.gd

const PORT := 31985
const SAVE_FILES := ["farm_save_v1.json", "farm_save_v1.json.bak"]
const FEATURES_NO_HELP := "farm_basic,farm_shop,farm_breeding,farm_market,farm_craft,farm_inventory,expedition,visit"

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
	db_path = project_dir.path_join(".zcode/m1/run/d59_farm.db")
	cert_path = project_dir.path_join("server/secrets/farm_server.crt")
	key_path = project_dir.path_join("server/secrets/farm_server.key")
	DirAccess.make_dir_recursive_absolute(project_dir.path_join(".zcode/m1/run"))
	for suffix in ["", "-wal", "-shm"]:
		var path: String = db_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

	# —— 种子档：甲（帮助者，2 级水壶+基础肥料×2）；乙（主人，地块 1/2/4 生长中、3 已成熟、2 预浇 can1） ——
	var now0 := int(Time.get_unix_time_from_system())
	var store := ServerDB.new()
	if not store.open(db_path):
		_check(false, "测试库打开失败")
		_finish()
		return
	var auth := AuthService.new()
	auth.store = store
	var codes: Array = auth.generate_invites(2, "d59")
	var tokens := {}
	var a_id := 0
	var b_id := 0
	for pair in [["a", codes[0], "玩家甲"], ["b", codes[1], "玩家乙"]]:
		var seed_farm := FarmGame.new()
		seed_farm.new_game(now0)
		if str(pair[0]) == "a":
			seed_farm.state["can_level"] = 2
			seed_farm.state["fertilizers"]["basic"] = 2
			seed_farm.state["fertilizers"]["mutation"] = 1
			seed_farm.state["farming_exp"] = 0
		else:
			# 每次播种取当时仓库第一粒（播种会移除种子，不能复用同一 id）。
			for entry in [[1, -300], [2, -300], [3, -1300], [4, -300]]:
				var sid := int(seed_farm.state["seeds"][0]["id"])
				seed_farm.plant_seed(int(entry[0]), sid, now0 + int(entry[1]))
			seed_farm.water(2, now0 - 200)
			seed_farm.state["coins"] = 555
		var created: Dictionary = auth.activate(str(pair[1]), str(pair[2]), JSON.stringify(seed_farm.state))
		tokens[pair[0]] = str(created.get("token", ""))
	store.close()
	if not _spawn_server([]):
		return

	# —— 段1：协议 ——
	var a := _client()
	if not a.connect_to(PORT) or str(a.hello(str(tokens["a"])).get("t", "")) != "welcome":
		_check(false, "甲登录")
		_finish()
		return
	var b := _client()
	if not b.connect_to(PORT) or str(b.hello(str(tokens["b"])).get("t", "")) != "welcome":
		_check(false, "乙登录")
		_finish()
		return
	var listed: Dictionary = a.request("visit.list", {}, _rid())
	b_id = int(listed["result"]["neighbors"][0].get("account_id", 0))
	a_id = 3 - b_id
	_check(b_id > 0, "地址簿含对方")

	# 主人先发一条命令焐热写穿缓存（失败命令也走 load_runtime）。
	var warm: Dictionary = b.request("farm.harvest", {"plot_id": 1}, _rid())
	_check(str(warm.get("t", "")) == "req_err" and str(warm.get("msg", "")).find("还没成熟") >= 0, "主人缓存焐热（未成熟收获失败如预期）")

	var water_req_id := _rid()
	var water: Dictionary = a.request("visit.water", {"owner_id": b_id, "plot_id": 1}, water_req_id)
	if not _check(str(water.get("t", "")) == "req_ok", "visit.water 成功"):
		_finish()
		return
	var wres: Dictionary = water["result"]
	_check((wres.get("watered", []) as Array).size() == 1 and int(wres["watered"][0]) == 1, "目标地块时段生效")
	_check(int(wres["watered"][0]) == 1 and (wres.get("upgraded", []) as Array).size() == 1 and int(wres["upgraded"][0]) == 2, "2 级水壶扩散：预浇 can1 的地块 2 被原位升级")
	_check(int(wres.get("exp", 0)) == PlantDefs.HELPER_EXP_PER_ACTION, "帮助者通用经验 +%d" % PlantDefs.HELPER_EXP_PER_ACTION)
	_check(int(water.get("snapshot", {}).get("farm", {}).get("farming_exp", -1)) == PlantDefs.HELPER_EXP_PER_ACTION, "应答快照=帮助者自己的农场（经验已入档）")

	var replay: Dictionary = a.request("visit.water", {"owner_id": b_id, "plot_id": 1}, water_req_id)
	_check(bool(replay.get("duplicate", false)), "同 req_id 重放 → duplicate")

	var again: Dictionary = a.request("visit.water", {"owner_id": b_id, "plot_id": 1}, _rid())
	_check(str(again.get("msg", "")).find("没有产生任何效果") >= 0, "已浇时段同级再浇 → 无效果")

	var fert: Dictionary = a.request("visit.fertilize", {"owner_id": b_id, "plot_id": 1, "kind": "basic"}, _rid())
	if not _check(str(fert.get("t", "")) == "req_ok", "visit.fertilize 成功"):
		_finish()
		return
	_check(int(fert.get("snapshot", {}).get("farm", {}).get("fertilizers", {}).get("basic", -1)) == 1, "肥料扣帮助者库存（2→1）")
	var fert_blocked: Dictionary = a.request("visit.fertilize", {"owner_id": b_id, "plot_id": 1, "kind": "mutation"}, _rid())
	_check(str(fert_blocked.get("msg", "")).find("到期") >= 0, "未到期不可覆盖肥料")

	# 主人视角核验：快照里帮助痕迹齐备 + 主人肥料库存零触碰（红线）。
	# 失败命令不带快照，用一条成功的 farm.plant 取回应答快照（plot 5 空地，不干扰其他断言）。
	var recheck: Dictionary = b.request("farm.plant", {"plot_id": 5}, _rid())
	if not _check(str(recheck.get("t", "")) == "req_ok", "主人侧核验命令成功"):
		_finish()
		return
	var b_plots: Array = recheck.get("snapshot", {}).get("farm", {}).get("plots", [])
	var p1: Dictionary = b_plots[0] if b_plots.size() > 0 else {}
	var p2: Dictionary = b_plots[1] if b_plots.size() > 1 else {}
	var seg1: Array = p1.get("watered_segments", [])
	var seg2: Array = p2.get("watered_segments", [])
	_check(seg1.size() == 1 and int(seg1[0].get("can_level", 0)) == 2 and int(seg1[0].get("helper", 0)) == a_id, "缓存红线：主人下一条命令看到好友浇水（evict 生效，helper 身份正确）")
	_check(seg2.size() == 1 and int(seg2[0].get("can_level", 0)) == 2, "升级不追加重复条目（每时段仍只 1 条，计分不重复）")
	_check((p1.get("helpers", []) as Array).size() == 1 and (p2.get("helpers", []) as Array).size() == 1, "helpers 每好友每轮一次（两块地各 1 条）")
	var b_fert: Dictionary = (p1.get("fertilizer", {}) as Dictionary)
	_check(str(b_fert.get("kind", "")) == "basic" and int(b_fert.get("helper", 0)) == a_id, "主人地块肥料带帮助者身份")
	_check(int(recheck.get("snapshot", {}).get("farm", {}).get("fertilizers", {}).get("basic", -2)) == 0, "红线：主人自己的肥料库存未被消耗")

	var self_hit: Dictionary = a.request("visit.water", {"owner_id": a_id, "plot_id": 1}, _rid())
	_check(str(self_hit.get("msg", "")).find("account_missing") >= 0, "owner=自己 → account_missing")
	var ghost: Dictionary = a.request("visit.water", {"owner_id": 999, "plot_id": 1}, _rid())
	_check(str(ghost.get("msg", "")).find("account_missing") >= 0, "owner 不存在 → account_missing")
	var bad_plot: Dictionary = a.request("visit.water", {"owner_id": b_id, "plot_id": 0}, _rid())
	_check(str(bad_plot.get("msg", "")).find("plot_missing") >= 0, "坏地块号 → plot_missing")
	var mature: Dictionary = a.request("visit.water", {"owner_id": b_id, "plot_id": 3}, _rid())
	_check(str(mature.get("msg", "")).find("成熟") >= 0, "成熟作物浇水 → 无效")

	# —— 段2：客户端场景（真实链路：点地块开弹窗 → 点浇水按钮 → bridge → 服务器） ——
	var re_snap: Dictionary = a.request("visit.snapshot", {"account_id": b_id}, _rid())
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
	world.online.visiting = {"owner": {"account_id": b_id, "nick": "玩家乙"}, "farm": re_snap["result"].get("farm", {})}
	world.enter_visit(world.online.visiting["owner"], re_snap["result"].get("farm", {}))
	await process_frame
	if not _check(world.get_node_or_null("VisitYard") != null and str(world.router.current) == "visit_yard", "院子地点切换"):
		_restore(backup)
		_finish()
		return
	var plot4: Dictionary = (re_snap["result"]["farm"]["plots"] as Array)[3]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	world._on_visit_crop_input(null, click, Vector3.ZERO, Vector3.ZERO, 0, plot4)
	_check(world.hud.active_modal == "visit_care", "生长中地块 → 拜访照料弹窗")
	var water_button := _find_button_by_text(world.hud.modal_content, "帮 玩家乙 浇水")
	_check(water_button != null, "弹窗含帮浇水按钮")
	var fert_button := _find_button_by_text(world.hud.modal_content, "基础肥料 · 1 次")
	_check(fert_button != null, "施肥按钮显示访客自己的库存（基础肥料 · 1 次）")
	if water_button != null:
		water_button.pressed.emit()
		var helped := false
		for i in range(150):
			await process_frame
			var plots_now: Array = (world.online.visiting.get("farm", {}).get("plots", []) as Array)
			if plots_now.size() > 3 and (plots_now[3].get("watered_segments", []) as Array).size() > 0:
				helped = true
				break
		_check(helped, "点浇水走通真实链路（拜访快照地块 4 已浇水）")
	world.leave_visit()
	await process_frame
	_check(str(world.router.current) == "farm" and not world.hud.visiting, "院门回农场：门控解除")
	SettingsStore.set_online_server_url(url_backup)
	_restore(backup)
	world.queue_free()
	await process_frame
	await process_frame

	# —— 段3：time-shift 跨成熟 → 主人收获看好友加成 ——
	if not _kill_server_and_wait():
		return
	if not _spawn_server(["--dev", "--dev-time-shift", "1300"]):
		return
	var b2 := _client()
	if not b2.connect_to(PORT) or str(b2.hello(str(tokens["b"])).get("t", "")) != "welcome":
		_check(false, "time-shift 服务器乙登录")
		_finish()
		return
	var harvest: Dictionary = b2.request("farm.harvest", {"plot_id": 1}, _rid())
	if not _check(str(harvest.get("t", "")) == "req_ok", "跨成熟收获成功"):
		_finish()
		return
	var batch: Dictionary = harvest["result"]["batch"]
	var breakdown: Dictionary = batch["score_breakdown"]
	var helper_expect := int(float(PlantDefs.HELPER_BONUS_PCT_PER_FRIEND) / 100.0 * 200)
	_check(int(breakdown.get("helper_count", 0)) == 1 and int(breakdown.get("helper_bonus", 0)) == helper_expect, "breakdown 含好友加成（×1，+%d 分）" % helper_expect)
	_check(int(breakdown.get("water_bonus", 0)) == 40, "浇水加成取最高档（can2 = 基准 20%）")
	var story_text := ""
	for event in harvest["result"].get("events", []):
		story_text += str(event.get("text", ""))
	_check(story_text.find("玩家甲") >= 0, "经历含好友昵称")
	var reset_plot: Dictionary = (harvest.get("snapshot", {}).get("farm", {}).get("plots", []) as Array)[0]
	_check((reset_plot.get("helpers", []) as Array).is_empty() and (reset_plot.get("watered_segments", []) as Array).is_empty(), "收获重置：helpers 与浇水记录清空")

	# —— 段4：--visits-closed ——
	if not _kill_server_and_wait():
		return
	if not _spawn_server(["--visits-closed"]):
		return
	var a3 := _client()
	if not a3.connect_to(PORT) or str(a3.hello(str(tokens["a"])).get("t", "")) != "welcome":
		_check(false, "关访服务器登录")
		_finish()
		return
	var closed_help: Dictionary = a3.request("visit.water", {"owner_id": b_id, "plot_id": 1}, _rid())
	_check(str(closed_help.get("msg", "")).find("visit_closed") >= 0, "关访 → 帮助命令拒绝 visit_closed")

	# —— 段5：--features 缺 visit_help ——
	if not _kill_server_and_wait():
		return
	if not _spawn_server(["--features", FEATURES_NO_HELP]):
		return
	var a4 := _client()
	if not a4.connect_to(PORT) or str(a4.hello(str(tokens["a"])).get("t", "")) != "welcome":
		_check(false, "特性灰度服务器登录")
		_finish()
		return
	var gated_list: Dictionary = a4.request("visit.list", {}, _rid())
	_check(str(gated_list.get("t", "")) == "req_ok", "visit 特性在 → 地址簿正常")
	var gated_help: Dictionary = a4.request("visit.water", {"owner_id": b_id, "plot_id": 1}, _rid())
	_check(str(gated_help.get("code", "")) == OnlineProtocol.ERR_FEATURE_DISABLED, "缺 visit_help → feature_disabled")
	_finish()


func _rid() -> String:
	req_seq += 1
	return "d59-%04d" % req_seq


func _find_button_by_text(node: Node, prefix: String) -> Button:
	if node is Button and str((node as Button).text).begins_with(prefix):
		return node
	for child in node.get_children():
		var found := _find_button_by_text(child, prefix)
		if found != null:
			return found
	return null


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


func _spawn_server(extra_args: Array) -> bool:
	var args := [
		"--headless", "--path", project_dir, "res://scenes/server_main.tscn", "--",
		"--port", str(PORT), "--db", db_path,
		"--cert", cert_path, "--key", key_path, "--tag", "d59",
	]
	args.append_array(extra_args)
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
	print("D59-SUMMARY checks=%d failed=%d" % [checks, fail_count])
	quit(1 if failed else 0)


func _check(ok: bool, label: String) -> bool:
	checks += 1
	if ok:
		print("D59-PASS %s" % label)
	else:
		failed = true
		fail_count += 1
		print("D59-FAIL %s" % label)
	return ok


func _client() -> WsClient:
	var client := WsClient.new()
	client.cert_path = cert_path
	return client


# —— WSS 测试客户端（沿 d52） ——————————————————————————————————————

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
