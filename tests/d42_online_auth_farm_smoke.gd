extends SceneTree
## d42：M1 服务端"账号+最小线上农场"全链路（计划 §7 表首行，规划 T01/T02/T03/T04/T13 子集）。
## 自编排：进程内先用 ServerDB/AuthService 直接生成邀请码（不依赖子进程 stdout），
## 再以独立 Godot 子进程跑 server_main（沿 M0"禁止同进程替代"口径），双客户端走真实 WSS+证书钉扎。
## 覆盖：激活开户/自动登录/版本拒绝/未认证拒绝/特性门控/未知命令/种植浇水施肥收获/
##       批量教程推进/账户隔离/收据重放与冲突/强杀重启恢复/服务器时间跨成熟/单会话顶替/限速。
## 输出：D42-PASS/D42-FAIL 逐条 + D42-METRICS；退出码 0=通过。
## 用法：Godot --headless --path . --script res://tests/d42_online_auth_farm_smoke.gd

const PORT := 31990
## 白菜 grow_seconds=1200：重启服务端加 1300 秒偏移跨成熟（--dev 仅限本机 bind）。
const GROW_SHIFT := 1300
const CONNECT_TIMEOUT_MS := 15000
const REQ_TIMEOUT_MS := 6000

var godot_exe := ""
var project_dir := ""
var db_path := ""
var cert_path := ""
var key_path := ""
var server_pid := 0
var failed := false
var fail_count := 0
var checks := 0
var metrics := {"snapshot_bytes": 0, "req_ms": []}


func _initialize() -> void:
	WsClient.metrics_ref["req_ms"] = metrics["req_ms"]
	_setup()
	_run()
	_cleanup()
	quit(1 if failed else 0)


func _setup() -> void:
	godot_exe = OS.get_executable_path()
	project_dir = ProjectSettings.globalize_path("res://")
	db_path = project_dir.path_join(".zcode/m1/run/d42_farm.db")
	cert_path = project_dir.path_join("server/secrets/farm_server.crt")
	key_path = project_dir.path_join("server/secrets/farm_server.key")
	DirAccess.make_dir_recursive_absolute(project_dir.path_join(".zcode/m1/run"))
	for suffix in ["", "-wal", "-shm"]:
		var path: String = db_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _run() -> void:
	# —— 邀请码：进程内直接建库生成（子进程 stdout 无法读取） ——
	var store := ServerDB.new()
	if not store.open(db_path):
		_check(false, "测试库打开失败（SQLite 扩展未加载？）")
		return
	var auth := AuthService.new()
	auth.store = store
	var codes: Array = auth.generate_invites(2, "d42")
	store.close()
	if codes.size() != 2:
		_check(false, "邀请码生成失败")
		return

	if not _spawn_server(0):
		return
	var a := _client()
	var b := _client()
	if not (a.connect_to(PORT) and b.connect_to(PORT)):
		_check(false, "双客户端连接失败")
		return
	_check(true, "双客户端 WSS 连接（证书钉扎）")

	# —— N05：未认证请求被拒（N04 版本错误在另一条连接上测，避免污染） ——
	var raw := a.send_json({"t": "req", "req_id": "x1", "op": "farm.plant", "args": {"plot_id": 1}})
	_check(raw, "req 发送")
	var err_reply := a.wait_for(func(m): return str(m.get("t", "")) == "error", REQ_TIMEOUT_MS)
	_check(str(err_reply.get("code", "")) == OnlineProtocol.ERR_NOT_AUTHENTICATED, "hello 前发 req → not_authenticated")

	# —— N04：版本不匹配拒绝并断开 ——
	var vbad := _client()
	if vbad.connect_to(PORT):
		vbad.send_json({"t": "hello", "token": "t_none", "proto": 99, "rules": 1, "build": 1})
		var vreply := vbad.wait_for(func(m): return str(m.get("t", "")) == "error", REQ_TIMEOUT_MS)
		_check(str(vreply.get("code", "")) == OnlineProtocol.ERR_VERSION_MISMATCH, "版本不符 → version_mismatch")
		_check(int(vreply.get("need", {}).get("proto", 0)) == OnlineProtocol.PROTO_VERSION, "need 携带服务器协议版本")

	# —— N01 激活开户 ——
	var welcome_a: Dictionary = a.activate(codes[0], "玩家甲")
	if not _check_welcome(a, welcome_a, "甲激活"):
		return
	var welcome_b: Dictionary = b.activate(codes[1], "玩家乙")
	if not _check_welcome(b, welcome_b, "乙激活"):
		return
	_check(welcome_a["account_id"] != welcome_b["account_id"], "两账户编号不同")
	var token_a: String = welcome_a["token"]
	var token_b: String = welcome_b["token"]
	var seq := int(welcome_a["farm_seq"])
	var farm_a: Dictionary = welcome_a["snapshot"]["farm"]
	_check(int(farm_a["tutorial_step"]) == 0, "新档 tutorial_step=0")
	_check(farm_a["seeds"].size() == 6 and farm_a["plots"].size() == 10, "新档 10 地块 6 种子")
	_check(int(welcome_a["account_id"]) >= 1, "账户编号有效")

	# 重复使用邀请码 → invite_used
	var c := _client()
	if c.connect_to(PORT):
		c.send_json({"t": "activate", "invite": codes[0], "nick": "冒名", "proto": OnlineProtocol.PROTO_VERSION, "rules": OnlineProtocol.RULES_VERSION, "build": OnlineProtocol.CLIENT_BUILD})
		var used: Dictionary = c.wait_for(func(m): return str(m.get("t", "")) == "error", REQ_TIMEOUT_MS)
		_check(str(used.get("code", "")) == OnlineProtocol.ERR_INVITE_USED, "邀请码复用 → invite_used")

	# —— F02：播种/浇水/施肥/收获 ——
	var plant_args := {"plot_id": 1}
	var planted: Dictionary = a.request("farm.plant", plant_args, "a-plant-1")
	if not _check_ok(planted, "甲播种第 1 块地"):
		return
	farm_a = planted["snapshot"]["farm"]
	_check(int(farm_a["plots"][0]["seed_id"]) != 0, "快照：第 1 块地已种植")
	_check(farm_a["seeds"].size() == 5, "快照：种子 6→5（扣种）")
	_check(int(farm_a["tutorial_step"]) == 1, "服务器教程 0→1")

	var watered: Dictionary = a.request("farm.water", {"plot_id": 1}, "a-water-1")
	if not _check_ok(watered, "甲浇水（1 时段）"):
		return
	_check(bool(watered["result"].get("ok", false)), "浇水结果 ok")
	_check(int(watered["snapshot"]["farm"]["tutorial_step"]) == 2, "服务器教程 1→2")
	seq = int(watered["farm_seq"])

	# 负向：无肥料 → op_failed（规则拒绝）
	var fert: Dictionary = a.request("farm.fertilize", {"plot_id": 1, "kind": "growth"}, "a-fert-0")
	_check(str(fert.get("t", "")) == "req_err" and str(fert.get("code", "")) == OnlineProtocol.ERR_OP_FAILED, "无肥料施肥 → op_failed")

	# 负向：未成熟收获被拒
	var early: Dictionary = a.request("farm.harvest", {"plot_id": 1}, "a-harvest-early")
	_check(str(early.get("t", "")) == "req_err" and str(early["msg"]).find("成熟") >= 0, "未成熟收获被拒（含原因）")

	# 未知命令（M2 命令尚不在 M1 命令表，同样落 unknown_op；特性门控在末段用 --features "" 复测）
	var unknown: Dictionary = a.request("farm.nope", {}, "a-unknown-1")
	_check(str(unknown.get("code", "")) == OnlineProtocol.ERR_UNKNOWN_OP, "未知命令 → unknown_op")

	# —— 账户隔离：乙的操作不影响甲（farm_seq 不动） ——
	var b_planted: Dictionary = b.request("farm.plant", {"plot_id": 1}, "b-plant-1")
	_check(b_planted.get("t", "") == "req_ok", "乙播种自己的第 1 块地")
	var a_still: Dictionary = a.request("farm.water", {"plot_id": 1}, "a-water-1")  # 同号重放
	_check(bool(a_still.get("duplicate", false)), "同 req_id 重放 → duplicate=true")
	_check(int(a_still["farm_seq"]) == seq, "乙多次操作后甲的 farm_seq 不变（账户隔离）")
	_check(int(a_still["snapshot"]["farm"]["plots"][0]["watered_segments"].size()) == 1, "重放不重复记账（浇水时段仍 1）")

	# —— req_id 冲突：同号不同参 ——
	var conflict: Dictionary = a.request("farm.plant", {"plot_id": 2}, "a-plant-1")
	_check(str(conflict.get("code", "")) == OnlineProtocol.ERR_REQ_ID_CONFLICT, "同 req_id 不同 args → req_id_conflict")

	# —— 强杀重启 + 服务器时间跨成熟（F08：改时钟=偏移，不依赖客户端时间） ——
	a.close()
	b.close()
	if not _kill_server_and_wait():
		return
	if not _spawn_server(GROW_SHIFT):
		return
	var a2 := _client()
	if not a2.connect_to(PORT):
		_check(false, "重启后甲重连失败")
		return
	var relogin: Dictionary = a2.hello(token_a)
	if not _check_welcome(a2, relogin, "甲重启后自动登录", false):
		return
	var now_s := int(relogin["server_now"])
	var farm2: Dictionary = relogin["snapshot"]["farm"]
	_check(int(farm2["plots"][0]["seed_id"]) != 0, "强杀重启：第 1 块地作物仍在（已提交不丢）")
	_check(int(farm2["tutorial_step"]) == 2, "重启后教程进度保持 2")
	_check(int(farm2["plots"][0]["ready_at"]) <= now_s, "服务器时间偏移后作物已成熟")
	_check(farm2["seeds"].size() == 5, "重启后种子数不变（无重复扣发）")

	var harvested: Dictionary = a2.request("farm.harvest", {"plot_id": 1}, "a-harvest-1")
	if not _check_ok(harvested, "跨成熟收获成功"):
		return
	var farm3: Dictionary = harvested["snapshot"]["farm"]
	_check(bool(harvested["result"].get("ok", false)), "收获结果 ok")
	_check(farm3["crop_batches"].size() == 1, "作物批次 +1 入库")
	_check(int(farm3["tutorial_step"]) == 3, "服务器教程 2→3")
	_check(int(farm3["farming_exp"]) > 0, "收获经验入账")

	# 收据重放：收获不重复入账
	var replay: Dictionary = a2.request("farm.harvest", {"plot_id": 1}, "a-harvest-1")
	_check(bool(replay.get("duplicate", false)), "收获重放 → duplicate=true")
	_check(int(replay["farm_seq"]) == int(harvested["farm_seq"]), "重放不产生新状态版本")
	_check(replay["snapshot"]["farm"]["crop_batches"].size() == 1, "重放不重复发作物")

	# —— N03 单会话顶替 ——
	var a3 := _client()
	if not a3.connect_to(PORT):
		_check(false, "第三连接建立失败")
		return
	var replaced: Dictionary = a3.hello(token_a)
	_check(bool(replaced.get("account_id", 0) != 0), "新连接登录同账户成功")
	var kick: Dictionary = a2.wait_for(func(m): return str(m.get("t", "")) == "kicked", REQ_TIMEOUT_MS)
	_check(str(kick.get("reason", "")) == OnlineProtocol.ERR_SESSION_REPLACED, "旧连接收到 kicked(session_replaced)")
	a2.close()

	# —— 乙在重启后的世界继续（凭据跨重启有效） ——
	var b2 := _client()
	if b2.connect_to(PORT):
		var b_back: Dictionary = b2.hello(token_b)
		_check(bool(b_back.get("account_id", 0) != 0), "乙 token 重启后仍可登录")
		var b_own: Dictionary = b2.request("farm.harvest_all", {}, "b-harvest-all-1")
		_check(b_own.get("t", "") == "req_ok" and int(b_own["farm_seq"]) >= 1, "乙重启后一键收获成功（各自状态独立恢复）")
		_check(b_own["snapshot"]["farm"]["crop_batches"].size() == 1, "乙收获入自己的批次（账户隔离再证）")
		b2.close()

	# —— N05 限速：新鲜连接连发 100 ping（阈值 90/3s，须超窗触发且恢复后可通信） ——
	var r := _client()
	if r.connect_to(PORT):
		var saw_limited := false
		for i in range(100):
			r.send_json({"t": "ping"})
		var deadline := Time.get_ticks_msec() + 3000
		while Time.get_ticks_msec() < deadline:
			var msg: Dictionary = r.poll_one()
			if msg.is_empty():
				OS.delay_msec(5)
				continue
			if str(msg.get("code", "")) == OnlineProtocol.ERR_RATE_LIMITED:
				saw_limited = true
			if str(msg.get("t", "")) == "pong" and saw_limited:
				break
		_check(saw_limited, "窗口内超量 → rate_limited（恢复后仍可通信）")
		r.close()

	# —— 特性门控：重启为 --features ""，表内命令也应被拒（服务端灰度开关） ——
	a3.close()
	c.close()
	vbad.close()
	if not _kill_server_and_wait():
		return
	if not _spawn_server(GROW_SHIFT, "-"):
		return
	var g := _client()
	if not g.connect_to(PORT):
		_check(false, "门控复测连接失败")
		return
	var g_welcome: Dictionary = g.hello(token_a)
	_check(bool(g_welcome.get("account_id", 0) != 0), "空特性下仍可登录")
	_check(g_welcome.get("features", []).is_empty(), "welcome.features 为空（服务端开关生效）")
	var gated: Dictionary = g.request("farm.plant", {"plot_id": 2}, "a-gated-1")
	_check(str(gated.get("code", "")) == OnlineProtocol.ERR_FEATURE_DISABLED, "表内命令在特性关闭时 → feature_disabled")
	g.close()
	return


func _client() -> WsClient:
	var client := WsClient.new()
	client.cert_path = cert_path
	return client


func _check_welcome(_client: WsClient, welcome: Dictionary, label: String, expect_token := true) -> bool:
	if not _check(welcome.get("t", "") == "welcome", "%s → welcome" % label):
		return false
	_check(int(welcome.get("account_id", 0)) >= 1, "%s：账户编号有效" % label)
	_check(str(welcome.get("nick", "")) != "", "%s：昵称返回" % label)
	_check(welcome.get("features", []).has(OnlineProtocol.FEATURE_FARM_BASIC), "%s：特性含 farm_basic" % label)
	_check(welcome.get("snapshot", {}).get("farm", {}).size() > 5, "%s：快照含农场档" % label)
	if expect_token:
		_check(str(welcome.get("token", "")).begins_with("t_"), "%s：token 下发" % label)
	var snapshot_text := JSON.stringify(welcome.get("snapshot", {}))
	metrics["snapshot_bytes"] = maxi(int(metrics["snapshot_bytes"]), snapshot_text.length())
	return true


func _check_ok(reply: Dictionary, label: String) -> bool:
	return _check(reply.get("t", "") == "req_ok" and not bool(reply.get("duplicate", false)), label)


func _spawn_server(time_shift: int, extra_features := "keep") -> bool:
	var args := [
		"--headless", "--path", project_dir, "res://scenes/server_main.tscn", "--",
		"--port", str(PORT), "--db", db_path,
		"--cert", cert_path, "--key", key_path, "--tag", "d42",
	]
	if time_shift != 0:
		args.append_array(["--dev", "--dev-time-shift", str(time_shift)])
	if extra_features != "keep":
		args.append_array(["--features", extra_features])
	server_pid = OS.create_process(godot_exe, args)
	if server_pid < 0:
		_check(false, "服务端子进程启动失败")
		return false
	# 等待端口就绪：轮询连接（服务端启动含引擎冷启动，留足余量）
	var deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		var probe := WebSocketMultiplayerPeer.new()
		var cert := X509Certificate.new()
		cert.load(cert_path)
		probe.create_client("wss://127.0.0.1:%d" % PORT, TLSOptions.client(cert))
		var probe_deadline := Time.get_ticks_msec() + 500
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
		if ready:
			OS.delay_msec(150)  # 握手完成后等服务端完成 peer 记账
			return true
		OS.delay_msec(200)
	_check(false, "服务端 %.1f 秒内未就绪" % (CONNECT_TIMEOUT_MS / 1000.0))
	return false


func _kill_server_and_wait() -> bool:
	if server_pid <= 0:
		return true
	OS.kill(server_pid)
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and OS.is_process_running(server_pid):
		OS.delay_msec(50)
	var gone := not OS.is_process_running(server_pid)
	_check(gone, "强杀服务端进程退出")
	server_pid = 0
	OS.delay_msec(250)  # 等 WAL 落盘句柄释放
	return gone


func _cleanup() -> void:
	if server_pid > 0 and OS.is_process_running(server_pid):
		OS.kill(server_pid)
	for suffix in ["", "-wal", "-shm"]:
		var path: String = db_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var latencies: Array = metrics["req_ms"]
	var avg := 0.0
	if not latencies.is_empty():
		var total := 0
		for ms in latencies:
			total += ms
		avg = float(total) / latencies.size()
	metrics["avg_req_ms"] = int(avg)
	print("D42-METRICS " + JSON.stringify(metrics))
	print("D42-SUMMARY checks=%d failed=%d" % [checks, fail_count])


func _check(ok: bool, label: String) -> bool:
	checks += 1
	if ok:
		print("D42-PASS %s" % label)
	else:
		failed = true
		fail_count += 1
		print("D42-FAIL %s" % label)
	return ok


# —— WSS 测试客户端（证书钉扎；按 req_id 匹配应答；kicked/欢迎等入收件箱） ——————————

class WsClient:
	const REPLY_TIMEOUT_MS := 6000
	var peer := WebSocketMultiplayerPeer.new()
	var cert_path := ""
	var inbox: Array = []
	var kicked := false


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
			var msg: Dictionary = parsed.data
			if str(msg.get("t", "")) == "kicked":
				kicked = true
			inbox.append(msg)


	func poll_one() -> Dictionary:
		poll_packets()
		if inbox.is_empty():
			return {}
		return inbox.pop_front()


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


	func _hello_payload(token: String) -> Dictionary:
		return {
			"t": "hello", "token": token,
			"proto": OnlineProtocol.PROTO_VERSION,
			"rules": OnlineProtocol.RULES_VERSION,
			"build": OnlineProtocol.CLIENT_BUILD,
		}


	func hello(token: String) -> Dictionary:
		send_json(_hello_payload(token))
		return wait_for(func(m): return str(m.get("t", "")) == "welcome" or str(m.get("t", "")) == "error", REQ_TIMEOUT_MS)


	func activate(invite: String, nick: String) -> Dictionary:
		var payload := _hello_payload("")
		payload["t"] = "activate"
		payload["invite"] = invite
		payload["nick"] = nick
		send_json(payload)
		return wait_for(func(m): return str(m.get("t", "")) == "welcome" or str(m.get("t", "")) == "error", REQ_TIMEOUT_MS)


	func request(op: String, args: Dictionary, req_id: String) -> Dictionary:
		var t0 := Time.get_ticks_msec()
		send_json({"t": "req", "req_id": req_id, "op": op, "args": args})
		var reply := wait_for(
			func(m): return (str(m.get("t", "")) == "req_ok" or str(m.get("t", "")) == "req_err") and str(m.get("req_id", "")) == req_id,
			REPLY_TIMEOUT_MS
		)
		if not reply.is_empty():
			_metrics(t0)
		return reply


	func _metrics(t0: int) -> void:
		var latencies: Array = metrics_ref["req_ms"]
		latencies.append(Time.get_ticks_msec() - t0)


	## metrics 属外层脚本实例；静态类拿不到，经类属性注入（见 _initialize 前 statics 不可用，
	## 这里用全局静态字典桥接，避免把测试客户端与外层耦合）。
	static var metrics_ref := {"req_ms": []}


	func close() -> void:
		peer.close()
