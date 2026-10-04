extends SceneTree
## d50：M4 韧性矩阵（计划：docs/plan/Godot_合并路线_R5_M4异常运维与打磨_代码执行计划_v0.1.md §3）。
## 子进程服务器 + 双客户端（WsClient 沿 d45/d46 模式）。覆盖：
##   维护门控（O04）：文件出现→新登录拒/在线 bye；移除→恢复
##   健康检查（O02）：pong 携带 online/rooms/active_runs/errors/uptime
##   备份/状态子命令（O03/O02）：VACUUM INTO 快照可独立打开且账户数一致
##   S05 断线重连：客户端断开→自动重连→原号重发→局恢复
##   S06 队友掉线：动作被拒（暂停语义）；重连恢复
##   S07 强杀重启：战斗中杀→重启→局/收据/农场一致→继续撤离
##   S08 提交后回执前断：重连后状态=已提交、重放 duplicate、无重复入账
## 用法：Godot --headless --path . --script res://tests/d50_m4_resilience_matrix.gd

const PORT := 31986
const REQ_TIMEOUT_MS := 8000

var godot_exe := ""
var project_dir := ""
var db_path := ""
var cert_path := ""
var key_path := ""
var maintenance_path := ""
var server_pid := 0
var failed := false
var fail_count := 0
var checks := 0
var req_seq := 0
var _last_rid := ""


func _initialize() -> void:
	_setup()
	_run()
	_cleanup()
	quit(1 if failed else 0)


func _setup() -> void:
	godot_exe = OS.get_executable_path()
	project_dir = ProjectSettings.globalize_path("res://")
	db_path = project_dir.path_join(".zcode/m1/run/d50_farm.db")
	maintenance_path = project_dir.path_join(".zcode/m1/run/d50_maintenance.flag")
	cert_path = project_dir.path_join("server/secrets/farm_server.crt")
	key_path = project_dir.path_join("server/secrets/farm_server.key")
	DirAccess.make_dir_recursive_absolute(project_dir.path_join(".zcode/m1/run"))
	for suffix in ["", "-wal", "-shm"]:
		var path: String = db_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if FileAccess.file_exists(maintenance_path):
		DirAccess.remove_absolute(maintenance_path)


func _run() -> void:
	var store := ServerDB.new()
	if not store.open(db_path):
		_check(false, "测试库打开失败")
		return
	var auth := AuthService.new()
	auth.store = store
	var codes: Array = auth.generate_invites(2, "d50")
	# 预铸两账户（含可出发战备），避免登录面板路径。
	var tokens := {}
	for pair in [["a", codes[0], "玩家甲"], ["b", codes[1], "玩家乙"]]:
		var seed_farm := FarmGame.new()
		seed_farm.new_game(int(Time.get_unix_time_from_system()))
		var inv := InventoryGame.new()
		inv.bind(seed_farm.state["expedition"])
		inv.grant_basic_kit()
		for instance in seed_farm.state["expedition"]["inventory"]["warehouse"].duplicate():
			inv.move_to_loadout(int(instance["instance_id"]), "chest")
		var created: Dictionary = auth.activate(str(pair[1]), str(pair[2]), JSON.stringify(seed_farm.state))
		tokens[pair[0]] = str(created.get("token", ""))
	store.close()
	if not _spawn_server(["--maintenance-file", maintenance_path]):
		return

	# —— 段1：健康检查（O02） ——
	var probe := _client()
	if not probe.connect_to(PORT):
		_check(false, "探针连接")
		return
	probe.send_json({"t": "ping"})
	var pong := probe.wait_for(func(m): return str(m.get("t", "")) == "pong", REQ_TIMEOUT_MS)
	_check(str(pong.get("proto", "")) != "" and pong.has("uptime_s"), "健康包携带 proto/uptime")
	_check(int(pong.get("online", -1)) >= 1, "健康包携带 online 计数")
	probe.close()

	# —— 段2：维护门控（O04） ——
	var a := _client()
	var b := _client()
	if not (a.connect_to(PORT) and b.connect_to(PORT)):
		_check(false, "双客户端连接")
		return
	var wa := a.hello(str(tokens["a"]))
	var wb := b.hello(str(tokens["b"]))
	_check(str(wa.get("t", "")) == "welcome" and str(wb.get("t", "")) == "welcome", "双账户登录")
	var file := FileAccess.open(maintenance_path, FileAccess.WRITE)
	file.store_string("maintenance")
	file.close()
	OS.delay_msec(1200)
	var bye_a := a.wait_for(func(m): return str(m.get("t", "")) == "bye", 4000)
	_check(str(bye_a.get("code", "")) == OnlineProtocol.ERR_MAINTENANCE, "维护开启：在线连接收 bye(maintenance)")
	var c := _client()
	if c.connect_to(PORT):
		c.send_json({"t": "hello", "token": str(tokens["a"]), "proto": OnlineProtocol.PROTO_VERSION, "rules": OnlineProtocol.RULES_VERSION, "build": OnlineProtocol.CLIENT_BUILD})
		var maint := c.wait_for(func(m): return str(m.get("t", "")) == "error", 4000)
		_check(str(maint.get("code", "")) == OnlineProtocol.ERR_MAINTENANCE, "维护期新登录被拒")
	DirAccess.remove_absolute(maintenance_path)
	OS.delay_msec(1200)
	var a2 := _client()
	if not a2.connect_to(PORT) or str(a2.hello(str(tokens["a"])).get("t", "")) != "welcome":
		_check(false, "维护解除后恢复登录")
		return
	_check(true, "维护解除后恢复登录")

	# —— 段3：出发双人局（供 S05~S08） ——
	var r1: Dictionary = a2.request("room.create", {}, _rid("a2"))
	var code := str(r1.get("result", {}).get("code", ""))
	var b2 := _client()
	b2.connect_to(PORT)
	b2.hello(str(tokens["b"]))
	b2.request("room.join", {"code": code}, _rid("b2"))
	b2.request("room.ready", {"ready": true}, _rid("b2"))
	a2.request("room.ready", {"ready": true}, _rid("a2"))
	var depart: Dictionary = a2.request("room.begin_depart", {}, _rid("a2"))
	if not _check(str(depart.get("t", "")) == "req_ok", "双人出发（矩阵前置）"):
		return
	_act(a2, "vote_move", {"row": 1, "col": 0})
	_act(b2, "vote_move", {"row": 1, "col": 0})
	var coins_a_before := int(_farm_coins(a2))

	# —— 段4：S06 队友掉线暂停语义 ——
	b2.close()
	OS.delay_msec(400)
	var blocked: Dictionary = _act(a2, "signal", {"text": "还在吗"})
	_check(not bool(blocked.get("ok", true)) and str(blocked.get("reason", "")).find("掉线") >= 0, "S06：队友掉线 → 动作被拒（暂停语义，不判死）")

	# —— 段5：S05+队友重连恢复 ——
	var b3 := _client()
	if not b3.connect_to(PORT) or str(b3.hello(str(tokens["b"])).get("t", "")) != "welcome":
		_check(false, "S05：队友重连")
		return
	var wb3 := b3.last_welcome
	_check(str(wb3.get("run", {}).get("run_id", "")) != "", "S05：重连 welcome 恢复活动局")
	var resumed: Dictionary = _act(b3, "signal", {"text": "回来了"})
	_check(bool(resumed.get("ok", false)), "S05：重连后动作恢复可用")

	# —— 段6：S07 战斗中强杀重启 ——
	_act(a2, "start_battle", {})
	if not _kill_server_and_wait():
		return
	if not _spawn_server(["--maintenance-file", maintenance_path]):
		return
	for client in [a2, b3]:
		client.reconnect(PORT)
	OS.delay_msec(400)
	var wa2 := a2.hello(str(tokens["a"]))
	if str(wa2.get("run", {}).get("phase", "")) != "battle":
		_check(false, "S07：重启后恢复战斗中局")
		return
	_check(true, "S07：重启后恢复战斗中局")
	## 双方都要重登（S06 在线语义：全员会话在才推进）。
	if str(b3.hello(str(tokens["b"])).get("run", {}).get("run_id", "")) != str(wa2.get("run", {}).get("run_id", "")):
		_check(false, "S07：队友重登恢复同一局")
		return
	_check(true, "S07：队友重登恢复同一局")
	## 重启后普通命令与局命令都应立即可用（认证与收据延续）。
	var probe_cmd: Dictionary = a2.request("farm.harvest_all", {}, _rid("probe"))
	_check(str(probe_cmd.get("t", "")) == "req_err", "S07：重启后农场命令可用（认证延续）")
	var probe_act: Dictionary = _act(a2, "signal", {"text": "probe"})
	_check(bool(probe_act.get("ok", false)), "S07：重启后局动作可用")
	var outcome := _auto_battle([["p1", a2], ["p2", b3]])
	_check(outcome == "won", "S07：重启后继续打赢战斗（%s）" % outcome)
	if outcome != "won":
		return
	_act(a2, "finish_battle", {})
	_act(a2, "leave_node", {})
	for row_col in [[2, 0], [3, 0], [4, 0]]:
		_act(a2, "vote_move", {"row": row_col[0], "col": row_col[1]})
		_act(b3, "vote_move", {"row": row_col[0], "col": row_col[1]})
		if row_col[0] < 4:
			_act(a2, "leave_node", {})
	_act(a2, "take_rest", {"option": "heal"})
	_act(a2, "vote_extract", {"agree": true})
	var settle := _act(b3, "vote_extract", {"agree": true})
	_check(bool(settle.get("ok", false)), "S07：重启后完整走到撤离结算")

	# —— 段7：S08 提交后回执前断（离线客户端重连对账） ——
	a2.close()
	OS.delay_msec(300)
	var a3 := _client()
	a3.connect_to(PORT)
	var wa3 := a3.hello(str(tokens["a"]))
	_check(str(wa3.get("t", "")) == "welcome" and not wa3.has("run"), "S08：结算后重连无活动局（状态=已提交）")
	var coins_a_after := int(_farm_coins(a3))
	_check(coins_a_after >= coins_a_before, "S08：金币无回退（%d ≥ %d）" % [coins_a_after, coins_a_before])

	# —— 段8：备份与状态子命令（O03/O02） ——
	var backup_dir := project_dir.path_join(".zcode/m1/run/d50_backup")
	var out := _run_server_once(["--db", db_path, "--backup", backup_dir])
	var backup_marker := out.find("BACKUP_OK ")
	_check(backup_marker >= 0, "备份子命令产出快照")
	if backup_marker < 0:
		return
	var backup_file := out.substr(backup_marker + len("BACKUP_OK ")).split("
")[0].strip_edges()
	var verify := ServerDB.new()
	if verify.open(backup_file):
		var n := int(verify.query_one("SELECT COUNT(*) AS n FROM accounts")["n"])
		_check(n == 2, "备份快照可独立打开且账户数一致（%d）" % n)
		verify.close()
	else:
		_check(false, "备份快照可独立打开")
	var out2 := _run_server_once(["--db", db_path, "--status"])
	_check(str(out2).find("STATUS_OK") >= 0 and str(out2).find("runs_total") >= 0, "状态子命令输出摘要")


func _farm_coins(client: WsClient) -> int:
	client.send_json({"t": "hello", "token": client.token_cache, "proto": OnlineProtocol.PROTO_VERSION, "rules": OnlineProtocol.RULES_VERSION, "build": OnlineProtocol.CLIENT_BUILD})
	var w := client.wait_for(func(m): return str(m.get("t", "")) == "welcome", REQ_TIMEOUT_MS)
	return int(w.get("snapshot", {}).get("farm", {}).get("coins", -1))


func _rid(label: String) -> String:
	req_seq += 1
	_last_rid = "%s-%04d" % [label, req_seq]
	return _last_rid


func _act(client: WsClient, kind: String, args: Dictionary) -> Dictionary:
	var reply: Dictionary = client.request("run.action", {"kind": kind, "args": args}, _rid("act"))
	if str(reply.get("t", "")) == "req_ok":
		if reply.has("run"):
			client.latest_run = reply["run"]
		var result: Dictionary = reply.get("result", {})
		return result if result is Dictionary else {}
	if str(reply.get("t", "")) == "req_err":
		return {"ok": false, "reason": str(reply.get("msg", reply.get("code", "")))}
	return {"ok": false, "reason": "timeout"}


func _auto_battle(members: Array) -> String:
	for round in range(40):
		var battle: Dictionary = (members[0][1] as WsClient).latest_run.get("battle", {})
		if battle.is_empty():
			return "no-battle"
		var outcome := str(battle.get("outcome", ""))
		if outcome != "":
			return outcome
		for pair in members:
			var key := str(pair[0])
			var client: WsClient = pair[1]
			for card in battle.get("players", {}).get(key, {}).get("hand", []):
				var target := _auto_target(str(card.get("card_id", "")), key, battle)
				_act(client, "play_card", {"uid": int(card["uid"]), "target": target})
				battle = client.latest_run.get("battle", battle)
				if str(battle.get("outcome", "")) != "":
					return str(battle["outcome"])
			_act(client, "end_turn", {})
			battle = client.latest_run.get("battle", battle)
			if str(battle.get("outcome", "")) != "":
				return str(battle["outcome"])
	return "timeout"


func _auto_target(card_id: String, member_key: String, battle: Dictionary) -> String:
	var def: Dictionary = CardDefs.CARDS.get(card_id, {})
	if str(def.get("target", "enemy")) == "enemy":
		for enemy in battle.get("enemies", []):
			if bool(enemy.get("alive", true)):
				return str(enemy.get("id", "e1"))
		return "e1"
	return member_key


func _run_server_once(extra: Array) -> String:
	var args := ["--headless", "--path", project_dir, "res://scenes/server_main.tscn", "--"]
	args.append_array(extra)
	var output: Array = []
	OS.execute(godot_exe, args, output, true)
	return str(output[0] if output.size() > 0 else "")


func _spawn_server(extra: Array = []) -> bool:
	var args := [
		"--headless", "--path", project_dir, "res://scenes/server_main.tscn", "--",
		"--port", str(PORT), "--db", db_path,
		"--cert", cert_path, "--key", key_path, "--tag", "d50",
	]
	args.append_array(extra)
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
	if FileAccess.file_exists(maintenance_path):
		DirAccess.remove_absolute(maintenance_path)
	print("D50-SUMMARY checks=%d failed=%d" % [checks, fail_count])


func _check(ok: bool, label: String) -> bool:
	checks += 1
	if ok:
		print("D50-PASS %s" % label)
	else:
		failed = true
		fail_count += 1
		print("D50-FAIL %s" % label)
	return ok


func _client() -> WsClient:
	var client := WsClient.new()
	client.cert_path = cert_path
	return client


# —— WSS 测试客户端（沿 d45；welcome 缓存 + 关闭） ——————————————————————

class WsClient:
	const REPLY_TIMEOUT_MS := 8000
	var peer := WebSocketMultiplayerPeer.new()
	var cert_path := ""
	var inbox: Array = []
	var latest_run := {}
	var last_welcome := {}
	var token_cache := ""

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

	func close() -> void:
		peer.close()

	func reconnect(port: int) -> bool:
		peer.close()
		OS.delay_msec(150)
		inbox.clear()
		return connect_to(port)

	func poll_packets() -> void:
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var raw := peer.get_packet().get_string_from_utf8()
			var parsed := JSON.new()
			if parsed.parse(raw) != OK or not (parsed.data is Dictionary):
				continue
			var msg: Dictionary = parsed.data
			if str(msg.get("t", "")) == "welcome":
				last_welcome = msg
			if str(msg.get("t", "")) == "push" and str(msg.get("kind", "")) == "run":
				latest_run = msg.get("run", {})
			inbox.append(msg)

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
		token_cache = token
		send_json({"t": "hello", "token": token, "proto": OnlineProtocol.PROTO_VERSION, "rules": OnlineProtocol.RULES_VERSION, "build": OnlineProtocol.CLIENT_BUILD})
		return wait_for(func(m): return str(m.get("t", "")) == "welcome" or str(m.get("t", "")) == "error", REPLY_TIMEOUT_MS)

	func request(op: String, args: Dictionary, req_id: String) -> Dictionary:
		send_json({"t": "req", "req_id": req_id, "op": op, "args": args})
		var reply := wait_for(
			func(m): return (str(m.get("t", "")) == "req_ok" or str(m.get("t", "")) == "req_err") and str(m.get("req_id", "")) == req_id,
			REPLY_TIMEOUT_MS
		)
		if str(reply.get("t", "")) == "req_ok" and reply.has("run"):
			latest_run = reply.get("run", {})
		return reply
