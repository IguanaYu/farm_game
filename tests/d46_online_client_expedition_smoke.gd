extends SceneTree
## d46：M3 客户端接线（W07，计划 §7）：OnlineFarmBridge 局命令面 + push 信号 +
## OnlineRoomPanel/OnlineRunPanel 无头驱动。对子进程服务器走真实 WSS。
## 覆盖：depart_solo 后镜像与信号；run_action 往返；强杀重启后新桥恢复镜像（S05）；
##       双桥房间全流程（建/入/准备/出发/双端镜像同步）；结算推送信号；面板 open/_refresh 无错。
## 输出：D46-PASS/D46-FAIL；退出码 0=通过。
## 用法：Godot --headless --path . --script res://tests/d46_online_client_expedition_smoke.gd

const PORT := 31988

var godot_exe := ""
var project_dir := ""
var db_path := ""
var cert_path := ""
var key_path := ""
var server_pid := 0
var failed := false
var fail_count := 0
var checks := 0


func _initialize() -> void:
	_setup()
	await _run()
	_cleanup()
	quit(1 if failed else 0)


func _setup() -> void:
	godot_exe = OS.get_executable_path()
	project_dir = ProjectSettings.globalize_path("res://")
	db_path = project_dir.path_join(".zcode/m1/run/d46_farm.db")
	cert_path = project_dir.path_join("server/secrets/farm_server.crt")
	key_path = project_dir.path_join("server/secrets/farm_server.key")
	DirAccess.make_dir_recursive_absolute(project_dir.path_join(".zcode/m1/run"))
	for suffix in ["", "-wal", "-shm"]:
		var path: String = db_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _run() -> void:
	var store := ServerDB.new()
	if not store.open(db_path):
		_check(false, "测试库打开失败")
		return
	var auth := AuthService.new()
	auth.store = store
	var codes: Array = auth.generate_invites(2, "d46")
	store.close()
	if not _spawn_server():
		return

	# —— 段1：单人局 via bridge ——
	var bridge := OnlineFarmBridge.new()
	bridge.name = "BridgeA"
	root.add_child(bridge)
	bridge.client.cert_path = cert_path
	var reply0: Dictionary = await _activate(bridge, str(codes[0]), "玩家甲")
	if not _check(bool(reply0.get("ok", false)), "桥 A 邀请激活并灌入快照"):
		return
	var token := bridge.client.token
	if not _check(token.begins_with("t_"), "桥 A 取得 token"):
		return

	var kit: Dictionary = await bridge.request("inv.grant_basic_kit", {})
	if not _check(str(kit.get("t", "")) == "req_ok", "桥 A 基础套装"):
		return
	var warehouse: Array = kit["snapshot"]["farm"]["expedition"]["inventory"]["warehouse"]
	# 三栏改版：武器/草帽上装备槽（第 1 回合有牌），其余入胸挂。
	for instance in warehouse.duplicate():
		if str(instance["def_id"]) == "old_shortsword":
			await bridge.request("inv.equip", {"instance_id": int(instance["instance_id"]), "slot": "main_weapon"})
		elif str(instance["def_id"]) == "straw_hat":
			await bridge.request("inv.equip", {"instance_id": int(instance["instance_id"]), "slot": "helmet"})
		else:
			await bridge.request("inv.move_to_loadout", {"instance_id": int(instance["instance_id"]), "container": "chest"})

	var run_events: Array = []
	bridge.run_snapshot.connect(func(run, version): run_events.append([run, version]))
	var depart: Dictionary = await bridge.depart_solo()
	if not _check(str(depart.get("t", "")) == "req_ok", "桥 A 单人出发（depart_solo）"):
		return
	if not _check(not bridge.mirror_run.is_empty() and int(bridge.mirror_run_version) == 1, "出发后镜像 run v1"):
		return
	_check(run_events.size() >= 1, "run_snapshot 信号已发射")

	var moved: Dictionary = await bridge.run_action("move_to", {"row": 1, "col": 0})
	if not _check(bool(moved.get("ok", false)), "run_action 选路（move_to）"):
		print("  D46-DBG move=", JSON.stringify(moved).substr(0, 200))
		return
	_check(int(bridge.mirror_run.get("current", {}).get("row", -1)) == 1, "镜像推进到第 1 排（version=%d）" % bridge.mirror_run_version)

	var bad: Dictionary = await bridge.run_action("move_to", {"row": 9, "col": 0})
	_check(not bool(bad.get("ok", false)), "非法选路被拒并带回原因")

	# —— 段2：面板无头驱动（单人局镜像） ——
	var run_panel := OnlineRunPanel.new()
	run_panel.name = "OnlineRunPanel"
	root.add_child(run_panel)
	run_panel.open(bridge)
	await process_frame
	await process_frame
	_check(run_panel.visible, "OnlineRunPanel 打开（镜像渲染无错）")
	run_panel.close()
	_check(not run_panel.visible, "OnlineRunPanel 关闭")

	# —— 段3：强杀重启 → 新桥恢复镜像（S05 客户端半） ——
	bridge.client.shutdown()
	bridge.queue_free()
	if not _kill_server_and_wait():
		return
	if not _spawn_server():
		return
	var bridge2 := OnlineFarmBridge.new()
	bridge2.name = "BridgeA2"
	root.add_child(bridge2)
	bridge2.client.cert_path = cert_path
	var booted2 := {"done": false}
	bridge2.snapshot_applied.connect(func(): booted2["done"] = true)
	bridge2.begin("wss://127.0.0.1:%d" % PORT, token)
	if not await _wait_until(func(): return booted2["done"], 10000):
		_check(false, "重启后桥 A2 重连超时")
		return
	_check(true, "重启后桥 A2 重连（welcome）")
	if not _check(not bridge2.mirror_run.is_empty() and int(bridge2.mirror_run.get("current", {}).get("row", -1)) == 1, "welcome 恢复活动局镜像（row=1）"):
		return
	## 跨重启继续原局并收尾（S05+S03 组合：重启后的局可正常结算）。
	var resumed_abandon: Dictionary = await bridge2.run_action("abandon", {})
	_check(bool(resumed_abandon.get("ok", false)), "重启后继续原局并放弃（结算跨重启）")
	if not await _wait_until(func(): return bridge2.mirror_run.is_empty() or str(bridge2.mirror_run.get("outcome", "")) != "", 4000):
		_check(false, "局终镜像更新")
		return

	# —— 段4：房间面板 + 双桥全流程 ——
	## 放弃结算损失了携带的基础装备：按规则补领缺失部件并重新入胸挂。
	var kit2: Dictionary = await bridge2.request("inv.grant_basic_kit", {})
	if str(kit2.get("t", "")) == "req_ok":
		await _move_all_to_chest(bridge2, kit2)
	var room_panel := OnlineRoomPanel.new()
	room_panel.name = "OnlineRoomPanel"
	root.add_child(room_panel)
	room_panel.open(bridge2)
	await process_frame
	_check(room_panel.visible, "OnlineRoomPanel 打开（无房大厅渲染）")
	var created: Dictionary = await bridge2.room_create()
	if not _check(str(created.get("t", "")) == "req_ok", "桥 A2 建房"):
		return
	var code := str(created["result"].get("code", ""))
	await process_frame
	_check(str(bridge2.mirror_room.get("code", "")) == code, "房间镜像同步（push.room→room_updated）")

	var bridge_b := OnlineFarmBridge.new()
	bridge_b.name = "BridgeB"
	root.add_child(bridge_b)
	bridge_b.client.cert_path = cert_path
	var reply_b: Dictionary = await _activate(bridge_b, str(codes[1]), "玩家乙")
	if not _check(bool(reply_b.get("ok", false)), "桥 B 邀请激活"):
		return
	var kit_b: Dictionary = await bridge_b.request("inv.grant_basic_kit", {})
	await _move_all_to_chest(bridge_b, kit_b)
	var joined: Dictionary = await bridge_b.room_join(code)
	if not _check(str(joined.get("t", "")) == "req_ok", "桥 B 按房码加入"):
		return
	await bridge2.room_ready(true)
	await bridge_b.room_ready(true)
	var depart2: Dictionary = await bridge2.begin_depart()
	if not _check(str(depart2.get("t", "")) == "req_ok", "双人出发（房主发起）"):
		print("  D46-DBG depart2=", JSON.stringify(depart2).substr(0, 240))
		return
	if not await _wait_until(func(): return not bridge_b.mirror_run.is_empty(), 6000):
		_check(false, "桥 B 收到开局推送（push.run 镜像）")
		return
	_check(bridge2.mirror_run.get("run_id", "") == bridge_b.mirror_run.get("run_id", ""), "双桥同一局")

	# 面板以 p2 视角渲染
	run_panel.open(bridge_b)
	await process_frame
	await process_frame
	_check(run_panel.visible and run_panel.member_key == "p2", "OnlineRunPanel p2 视角（房主=甲）")
	run_panel.close()

	# 投票选路（双端动作）+ 撤离结算推送
	var v1: Dictionary = await bridge2.run_action("vote_move", {"row": 1, "col": 0})
	_check(bool(v1.get("waiting", false)) or bool(v1.get("ok", false)), "甲投票")
	var v2: Dictionary = await bridge_b.run_action("vote_move", {"row": 1, "col": 0})
	_check(bool(v2.get("ok", false)), "乙同票前进")
	_check(int(bridge_b.mirror_run.get("current", {}).get("row", -1)) == 1, "乙镜像推进第 1 排")

	var settlements: Array = []
	bridge_b.settlement_arrived.connect(func(s): settlements.append(s))
	var ab1: Dictionary = await bridge2.run_action("abandon_member", {})
	_check(bool(ab1.get("ok", false)), "房主放弃（服务器自动补结算给队友）")
	if not await _wait_until(func(): return settlements.size() >= 1, 6000):
		_check(false, "乙收到结算推送（settlement_arrived）")
		return
	_check(true, "乙收到结算推送（settlement_arrived）")
	var farm_b_block: Dictionary = bridge_b.game.state.get("expedition", {})
	_check(str(farm_b_block.get("inventory", {}).get("occupied_by_run", "x")) == "", "乙桥农场镜像占用解除（结算快照回灌）")


func _activate(bridge: OnlineFarmBridge, invite: String, nick: String) -> Dictionary:
	## 经 bridge 激活：完整装配后走一次性激活路径，等 welcome/握手失败终态。
	var done := {"ok": false, "fail": false}
	bridge.client.welcome_received.connect(func(_payload): done["ok"] = true)
	bridge.client.handshake_failed.connect(func(_code, _need): done["fail"] = true)
	bridge.begin_with_invite("wss://127.0.0.1:%d" % PORT, invite, nick)
	if await _wait_until(func(): return bool(done["ok"]) or bool(done["fail"]), 10000):
		return {"ok": bool(done["ok"])}
	return {"ok": false, "code": "timeout"}


func _move_all_to_chest(bridge: OnlineFarmBridge, kit: Dictionary) -> void:
	## 三栏改版：武器/草帽先上装备槽（第 1 回合有牌），其余入胸挂。
	var warehouse: Array = kit.get("snapshot", {}).get("farm", {}).get("expedition", {}).get("inventory", {}).get("warehouse", [])
	for instance in warehouse.duplicate():
		if str(instance["def_id"]) == "old_shortsword":
			await bridge.request("inv.equip", {"instance_id": int(instance["instance_id"]), "slot": "main_weapon"})
		elif str(instance["def_id"]) == "straw_hat":
			await bridge.request("inv.equip", {"instance_id": int(instance["instance_id"]), "slot": "helmet"})
		else:
			await bridge.request("inv.move_to_loadout", {"instance_id": int(instance["instance_id"]), "container": "chest"})


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false


func _check(ok: bool, label: String) -> bool:
	checks += 1
	if ok:
		print("D46-PASS %s" % label)
	else:
		failed = true
		fail_count += 1
		print("D46-FAIL %s" % label)
	return ok


func _spawn_server() -> bool:
	var args := [
		"--headless", "--path", project_dir, "res://scenes/server_main.tscn", "--",
		"--port", str(PORT), "--db", db_path,
		"--cert", cert_path, "--key", key_path, "--tag", "d46",
	]
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


func _cleanup() -> void:
	if server_pid > 0:
		OS.kill(server_pid)
		OS.delay_msec(300)
	print("D46-SUMMARY checks=%d failed=%d" % [checks, fail_count])
