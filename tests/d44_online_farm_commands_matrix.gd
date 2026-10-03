extends SceneTree
## d44：M2 个人玩法全命令矩阵（计划 §7 表第三行，规划 F03～F07、T02/T04 农场全量）。
## 自编排：独立子进程跑 server_main；账号经"激活→种植→强杀→注入金币→重启跨成熟"
## 拿到可测全部命令的资产状态；对 §4.4 命令表逐条一正一负断言，并核销完整教程生命周期。
## 输出：D44-PASS/D44-FAIL 逐条 + D44-METRICS（快照体积/耗时）；退出码 0=通过。
## 用法：Godot --headless --path . --script res://tests/d44_online_farm_commands_matrix.gd

const PORT := 31995
## 白菜 grow_seconds=1200：重启加 1300 秒跨成熟（--dev 仅限本机 bind）。
const GROW_SHIFT := 1300
const CONNECT_TIMEOUT_MS := 15000
const REQ_TIMEOUT_MS := 6000
const RICH_COINS := 100000

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
var token := ""


func _initialize() -> void:
	WsClient.metrics_ref["req_ms"] = metrics["req_ms"]
	_setup()
	_run()
	_cleanup()
	quit(1 if failed else 0)


func _setup() -> void:
	godot_exe = OS.get_executable_path()
	project_dir = ProjectSettings.globalize_path("res://")
	db_path = project_dir.path_join(".zcode/m1/run/d44_farm.db")
	cert_path = project_dir.path_join("server/secrets/farm_server.crt")
	key_path = project_dir.path_join("server/secrets/farm_server.key")
	DirAccess.make_dir_recursive_absolute(project_dir.path_join(".zcode/m1/run"))
	for suffix in ["", "-wal", "-shm"]:
		var path: String = db_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _run() -> void:
	# —— 阶段 0：建库发码 → 起服 → 激活 → 三块地种植浇水 ——
	var store := ServerDB.new()
	if not store.open(db_path):
		_check(false, "测试库打开失败")
		return
	var auth := AuthService.new()
	auth.store = store
	var codes: Array = auth.generate_invites(1, "d44")
	store.close()
	if codes.is_empty():
		_check(false, "邀请码生成失败")
		return
	if not _spawn_server(0):
		return
	var c := _client()
	if not c.connect_to(PORT):
		_check(false, "连接失败")
		return
	var welcome: Dictionary = c.activate(codes[0], "矩阵测试")
	if not _check(str(welcome.get("t", "")) == "welcome", "激活 → welcome"):
		return
	token = str(welcome.get("token", ""))
	for plot_id in [1, 2, 3]:
		var planted: Dictionary = c.request("farm.plant", {"plot_id": plot_id}, "p%d" % plot_id)
		if not _check(planted.get("t", "") == "req_ok", "第 %d 块地播种" % plot_id):
			return
	var watered: Dictionary = c.request("farm.water", {"plot_id": 1}, "w1")
	_check(watered.get("t", "") == "req_ok", "浇水（教程 1→2）")
	c.close()

	# —— 阶段 1：强杀 → 注入金币（服务器死库直改）→ 重启跨成熟 ——
	if not _kill_server_and_wait():
		return
	if not _inject_rich_coins():
		return
	if not _spawn_server(GROW_SHIFT):
		return
	c = _client()
	if not c.connect_to(PORT):
		_check(false, "重启后重连失败")
		return
	var relogin: Dictionary = c.hello(token)
	if not _check(str(relogin.get("t", "")) == "welcome", "重启后 token 登录"):
		return
	var features: Array = relogin.get("features", [])
	_check(features.has(OnlineProtocol.FEATURE_FARM_SHOP) and features.has(OnlineProtocol.FEATURE_FARM_INVENTORY), "特性含 M2 全组")

	var harvested: Dictionary = c.request("farm.harvest_all", {}, "ha1")
	if not _check(harvested.get("t", "") == "req_ok", "跨成熟一键收获（教程 2→3）"):
		return
	var farm: Dictionary = harvested["snapshot"]["farm"]
	_check(farm["crop_batches"].size() >= 3, "≥3 批作物入库")
	_check(int(farm["tutorial_step"]) == 3, "教程 = 3")
	var coins_before := int(farm["coins"])

	# —— 市场：出售推进教程 3→4；指定客人出售；再播种完成引导 4→99 ——
	var batch_ids: Array = []
	for batch in farm["crop_batches"]:
		batch_ids.append(int(batch["id"]))
	var sold: Dictionary = c.request("farm.sell_batch", {"batch_id": batch_ids[0]}, "sb1")
	_check(sold.get("t", "") == "req_ok" and int(sold["snapshot"]["farm"]["coins"]) > coins_before, "sell_batch 出售入账（教程 3→4）")
	_check(int(sold["snapshot"]["farm"]["tutorial_step"]) == 4, "出售推进教程 = 4")
	var replant: Dictionary = c.request("farm.plant", {"plot_id": 1}, "replant1")
	_check(replant.get("t", "") == "req_ok" and int(replant["snapshot"]["farm"]["tutorial_step"]) == 99, "再播种完成引导 = 99（全生命周期核销）")
	var to_guest: Dictionary = c.request("farm.sell_batch_to", {"batch_id": batch_ids[1], "count": 1, "guest_id": 1}, "sbg1")
	_check(to_guest.get("t", "") == "req_ok", "sell_batch_to 指定客人出售")
	# 白菜汤要 2 棵白菜：留第 3 批（crop_count=5）先制作，再清仓
	var soup: Dictionary = c.request("craft.craft", {"recipe_id": "cabbage_soup"}, "soup1")
	var soup_ok: bool = soup.get("t", "") == "req_ok"
	_check(soup_ok, "craft 白菜汤（材料=保留批次）")
	if soup_ok:
		_cmd_ok(c, "craft.claim_pending", {}, "craft.claim_pending 领取/空领取")
	var sold_all: Dictionary = c.request("farm.sell_all_batches", {}, "sab1")
	_check(sold_all.get("t", "") == "req_ok" and int(sold_all["result"]) >= 0, "sell_all_batches（含收益整数）")

	# —— 商店/扩地/升级（注入金币后全部可负担） ——
	farm = sold_all["snapshot"]["farm"]
	_cmd_ok(c, "farm.buy_seeds", {"kind": "cabbage", "quantity": 3}, "buy_seeds 正向")
	var neg_qty: Dictionary = c.request("farm.buy_seeds", {"kind": "cabbage", "quantity": 0}, "bs-neg")
	_check(str(neg_qty.get("code", "")) == OnlineProtocol.ERR_OP_FAILED, "buy_seeds 数量 0 → op_failed")
	_cmd_ok(c, "farm.buy_fertilizer", {"kind": "basic", "quantity": 2}, "buy_fertilizer 正向")
	var neg_kind: Dictionary = c.request("farm.buy_fertilizer", {"kind": "nope", "quantity": 1}, "bf-neg")
	_check(str(neg_kind.get("code", "")) == OnlineProtocol.ERR_OP_FAILED, "buy_fertilizer 未知肥料 → op_failed")
	_cmd_ok(c, "farm.upgrade_shop", {}, "upgrade_shop 3→4（注入档）")
	var neg_shop: Dictionary = c.request("farm.upgrade_shop", {}, "us-neg")
	_check(str(neg_shop.get("code", "")) == OnlineProtocol.ERR_OP_FAILED, "upgrade_shop 到顶 4 → op_failed")
	_cmd_ok(c, "farm.buy_can2", {}, "buy_can2 正向")
	_cmd_ok(c, "farm.buy_plot", {}, "buy_plot 正向")
	_cmd_ok(c, "farm.upgrade_warehouse", {}, "upgrade_warehouse 正向")

	# —— 育种机/回收/待领取 ——
	_cmd_ok(c, "farm.buy_breeder", {}, "buy_breeder 正向")
	var seed_id := 0
	for seed in sold_all["snapshot"]["farm"]["seeds"]:
		seed_id = int(seed["id"])
		break
	_check(seed_id > 0, "快照里有种子可设模板")
	_cmd_ok(c, "farm.set_breeder_template", {"seed_id": seed_id}, "set_breeder_template 正向")
	var no_pending: Dictionary = c.request("farm.collect_breeder", {}, "cb-neg")
	_check(str(no_pending.get("code", "")) == OnlineProtocol.ERR_OP_FAILED, "collect_breeder 无副本 → op_failed")
	_cmd_ok(c, "farm.clear_breeder_template", {}, "clear_breeder_template 正向")
	_cmd_ok(c, "farm.buy_breeder", {}, "buy_breeder 已购 → op_failed", true, OnlineProtocol.ERR_OP_FAILED)
	_cmd_ok(c, "farm.recycle_seed", {"seed_id": seed_id}, "recycle_seed 正向")
	var no_pending_seed: Dictionary = c.request("farm.recycle_pending_seed", {"seed_id": 1}, "rps-neg")
	_check(str(no_pending_seed.get("code", "")) == OnlineProtocol.ERR_OP_FAILED, "recycle_pending_seed 无待领 → op_failed")
	_cmd_ok(c, "farm.claim_pending", {}, "claim_pending 空领取（0/0 也是成功）")

	# —— 市场锁定组 ——
	_cmd_ok(c, "farm.lock_guest", {"guest_id": 1}, "lock_guest 当日客人（注入日 1/2/3）")
	_cmd_ok(c, "farm.lock_guest", {"guest_id": 0}, "lock_guest=0 解锁客人位")
	_cmd_ok(c, "farm.lock_formula", {"kind": "cabbage"}, "lock_formula 偏好植物（注入锁定客人 2）")
	_cmd_ok(c, "farm.unlock_formula", {}, "unlock_formula 正向")
	var neg_pending: Dictionary = c.request("farm.sell_pending_crop", {"batch_id": 999}, "spc-neg")
	_check(str(neg_pending.get("code", "")) == OnlineProtocol.ERR_OP_FAILED, "sell_pending_crop 无批次 → op_failed")

	# —— 制作：正向已在市场段（白菜汤）；此处补未知配方/未达成目标负向 ——
	var neg_recipe: Dictionary = c.request("craft.craft", {"recipe_id": "nope"}, "cr-neg")
	if not _check(str(neg_recipe.get("code", "")) == OnlineProtocol.ERR_OP_FAILED, "craft 未知配方 → op_failed"):
		print("  D44-DBG craft-neg reply=", JSON.stringify(neg_recipe).substr(0, 200))
	var neg_goal: Dictionary = c.request("craft.claim_goal", {"goal_id": "nope"}, "cg-neg")
	_check(str(neg_goal.get("code", "")) == OnlineProtocol.ERR_OP_FAILED, "claim_goal 未达成 → op_failed")

	# —— 装备仓库与战备 ——
	var kit: Dictionary = c.request("inv.grant_basic_kit", {}, "kit1")
	_check(kit.get("t", "") == "req_ok", "grant_basic_kit 正向")
	var inventory_block: Dictionary = kit["snapshot"]["farm"]["expedition"]["inventory"]
	var instance_id := 0
	var instance_def := ""
	for instance in inventory_block["warehouse"]:
		instance_id = int(instance["instance_id"])
		instance_def = str(instance["def_id"])
		break
	_check(instance_id > 0, "基础装备已入仓库（instance=%d）" % instance_id)
	_cmd_ok(c, "inv.move_to_loadout", {"instance_id": instance_id, "container": "chest"}, "move_to_loadout 正向")
	_cmd_ok(c, "inv.rotate", {"instance_id": instance_id}, "rotate 正向")
	var placed: Dictionary = c.request("inv.place_at", {"instance_id": instance_id, "container": "chest", "cell": {"x": 0, "y": 0}, "rotated": false}, "pa1")
	_check(placed.get("t", "") == "req_ok", "place_at 指定格位")
	_cmd_ok(c, "inv.auto_tidy", {"container": "chest"}, "auto_tidy 正向")
	_cmd_ok(c, "inv.move_to_warehouse", {"instance_id": instance_id}, "move_to_warehouse 正向")
	var bad_move: Dictionary = c.request("inv.move_to_loadout", {"instance_id": 999999, "container": "chest"}, "mv-neg")
	_check(str(bad_move.get("code", "")) == OnlineProtocol.ERR_OP_FAILED, "move_to_loadout 无实例 → op_failed")
	var preset := {"fmt": 1, "items": [{"instance_id": instance_id, "def_id": instance_def, "container": "chest", "cell": [0, 0], "rotated": false}]}
	var applied: Dictionary = c.request("inv.apply_preset", {"preset": preset}, "ap1")
	_check(applied.get("t", "") == "req_ok" and int(applied["result"].get("applied", 0)) >= 1, "apply_preset 复合应用（原子）")
	_cmd_ok(c, "inv.clear_loadout", {}, "clear_loadout 正向")
	c.close()



func _cmd_ok(c: WsClient, op: String, args: Dictionary, label: String, expect_fail := false, expect_code := "") -> void:
	var reply: Dictionary = c.request(op, args, "auto-%s-%d" % [op, checks])
	if expect_fail:
		if not _check(reply.get("t", "") == "req_err" and str(reply.get("code", "")) == expect_code, label):
			print("  D44-DBG op=%s reply=%s" % [op, JSON.stringify(reply).substr(0, 160)])
	else:
		if not _check(reply.get("t", "") == "req_ok", label):
			print("  D44-DBG op=%s reply=%s" % [op, JSON.stringify(reply).substr(0, 160)])


## 服务器停机期间直改账户金币，保证商店/制作正向断言可负担（测试专用，不在线上路径）。
func _inject_rich_coins() -> bool:
	var store := ServerDB.new()
	if not store.open(db_path):
		_check(false, "注入：库打开失败")
		return false
	var rows: Array = store.query_all("SELECT id, farm_state FROM accounts")
	var ok := true
	for row in rows:
		var parsed: Variant = JSON.parse_string(str(row["farm_state"]))
		if not (parsed is Dictionary):
			ok = false
			break
		var farm: Dictionary = parsed
		farm["coins"] = RICH_COINS
		## 种地/商店等级与市场日一并注入：育种机（等级 2）、锁定客人/公式（商店 2/3 级、
		## 当日客人与公式随机）在纯自然流程下不可测，注入后为确定性前置。
		farm["farming_exp"] = 10000
		farm["shop_level"] = 3
		var market: Dictionary = farm.get("market", {})
		market["guest_ids"] = [1, 2, 3]
		market["locked_guest_id"] = 2
		market["lock_guest_pending"] = 0
		market["lock_formula_pending"] = {}
		market["formulas"] = {"cabbage": {"type": "attribute", "attribute": "sweetness", "sub_attribute": ""}, "carrot": {}}
		farm["market"] = market
		if not store.exec("UPDATE accounts SET farm_state = ? WHERE id = ?", [JSON.stringify(farm), int(row["id"])]):
			ok = false
			break
	store.close()
	_check(ok, "金币注入（%d）" % RICH_COINS)
	return ok


func _check(ok: bool, label: String) -> bool:
	checks += 1
	if ok:
		print("D44-PASS %s" % label)
	else:
		failed = true
		fail_count += 1
		print("D44-FAIL %s" % label)
	return ok


func _spawn_server(time_shift: int) -> bool:
	var args := [
		"--headless", "--path", project_dir, "res://scenes/server_main.tscn", "--",
		"--port", str(PORT), "--db", db_path,
		"--cert", cert_path, "--key", key_path, "--tag", "d44",
	]
	if time_shift != 0:
		args.append_array(["--dev", "--dev-time-shift", str(time_shift)])
	server_pid = OS.create_process(godot_exe, args)
	if server_pid < 0:
		_check(false, "服务端子进程启动失败")
		return false
	var deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		if _port_ready():
			OS.delay_msec(150)
			return true
		OS.delay_msec(200)
	_check(false, "服务端未就绪")
	return false


func _port_ready() -> bool:
	var probe := WebSocketMultiplayerPeer.new()
	var cert := X509Certificate.new()
	cert.load(cert_path)
	probe.create_client("wss://127.0.0.1:%d" % PORT, TLSOptions.client(cert))
	var deadline := Time.get_ticks_msec() + 400
	var ready := false
	while Time.get_ticks_msec() < deadline:
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
		OS.delay_msec(50)
	server_pid = 0
	OS.delay_msec(250)
	return true


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
	metrics["snapshot_bytes"] = int(WsClient.metrics_ref.get("snapshot_bytes", 0))
	print("D44-METRICS " + JSON.stringify(metrics))
	print("D44-SUMMARY checks=%d failed=%d" % [checks, fail_count])


func _client() -> WsClient:
	var client := WsClient.new()
	client.cert_path = cert_path
	return client


# —— WSS 测试客户端（同 d42 模式） ——————————————————————————————————

class WsClient:
	const REPLY_TIMEOUT_MS := 6000
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
			if predicate.call(inbox[i]):
				return inbox.pop_at(i)
		var deadline := Time.get_ticks_msec() + timeout_ms
		while Time.get_ticks_msec() < deadline:
			poll_packets()
			for i in range(inbox.size()):
				if predicate.call(inbox[i]):
					return inbox.pop_at(i)
			OS.delay_msec(3)
		return {}


	func hello(login_token: String) -> Dictionary:
		send_json({
			"t": "hello", "token": login_token,
			"proto": OnlineProtocol.PROTO_VERSION, "rules": OnlineProtocol.RULES_VERSION,
			"build": OnlineProtocol.CLIENT_BUILD,
		})
		return wait_for(func(m): return str(m.get("t", "")) == "welcome" or str(m.get("t", "")) == "error", REPLY_TIMEOUT_MS)


	func activate(invite: String, nick: String) -> Dictionary:
		send_json({
			"t": "activate", "invite": invite, "nick": nick,
			"proto": OnlineProtocol.PROTO_VERSION, "rules": OnlineProtocol.RULES_VERSION,
			"build": OnlineProtocol.CLIENT_BUILD,
		})
		return wait_for(func(m): return str(m.get("t", "")) == "welcome" or str(m.get("t", "")) == "error", REPLY_TIMEOUT_MS)


	func request(op: String, args: Dictionary, req_id: String) -> Dictionary:
		var t0 := Time.get_ticks_msec()
		# 测试节流：连发突发会顶到限速窗口（服务器按条数丢弃，不排队），拉开间隔保证确定性
		OS.delay_msec(60)
		send_json({"t": "req", "req_id": req_id, "op": op, "args": args})
		var reply := wait_for(
			func(m): return (str(m.get("t", "")) == "req_ok" or str(m.get("t", "")) == "req_err") and str(m.get("req_id", "")) == req_id,
			REPLY_TIMEOUT_MS
		)
		if not reply.is_empty():
			var latencies: Array = metrics_ref["req_ms"]
			latencies.append(Time.get_ticks_msec() - t0)
			if reply.has("snapshot"):
				var snapshot_text := JSON.stringify(reply.get("snapshot", {}))
				metrics_ref["snapshot_bytes"] = maxi(int(metrics_ref.get("snapshot_bytes", 0)), snapshot_text.length())
		return reply


	func close() -> void:
		peer.close()


	static var metrics_ref := {"req_ms": [], "snapshot_bytes": 0}
