extends SceneTree
## 互联网房号中继全链路（方案 docs/plan/Godot_联机中继_互联网房间_方案与执行计划_v0.1.md）。
## 本进程内拉起 tools/relay_server.py（真实 TCP 中继、真实 NDJSON 序列化），
## 主机/客机各建 FarmGame，经中继完成：建房房号→加入→准备/出发事务→
## 动作裁定与快照镜像→客机断线（peer_down 即时掉线）→同房号重连恢复。
## 依赖本机 python 可执行；ENet 局域网路径由 d26/d27 覆盖，此处只测中继。


const RELAY_PORT := 31989
const PLAYER_ID := "p-relay-smoke"


var failed := false
var host: SessionHost
var client: SessionClient
var host_game: FarmGame
var client_game: FarmGame
var relay_pid := -1
var client_results: Dictionary = {}


func _initialize() -> void:
	relay_pid = _start_relay()
	_check(relay_pid > 0, "中继：relay_server.py 启动（本机需有 python）")
	if relay_pid <= 0:
		_finish()
		return
	_check(_wait_relay_up(), "中继：端口 %d 就绪" % RELAY_PORT)
	if failed:
		_cleanup()
		_finish()
		return

	host_game = _fresh_game(1)
	client_game = _fresh_game(2)

	# —— 建房与加入 ——
	host = SessionHost.new()
	_check(host.listen_relay(host_game, "127.0.0.1", RELAY_PORT), "建房：主机发起中继连接")
	_pump(120)
	var code := host.relay_room_code()
	_check(code.length() == 6, "建房：收到 6 位房号（实际 %s）" % ("空" if code == "" else code))
	if failed:
		_cleanup()
		_finish()
		return

	client = SessionClient.new()
	client.action_result_received.connect(func(action_id: String, result: Dictionary) -> void:
		client_results[action_id] = result)
	_check(client.connect_relay(code, client_game, "127.0.0.1", RELAY_PORT), "加入：客机发起中继连接")
	_pump(120)
	_check(client.link_ready(), "加入：中继握手完成")
	var inventory := InventoryGame.new()
	inventory.bind(client_game.state["expedition"])
	client.hello_with(PLAYER_ID, inventory)
	_pump(80)
	_check(int((host.room["members"] as Dictionary).size()) >= 2, "握手：客机进入主机成员表")

	# —— 准备与出发事务（两段式，经中继）——
	host.host_set_ready(true)
	client.set_ready(true)
	_pump(80)
	var depart := host.begin_depart()
	_check(bool(depart.get("waiting", false)) or bool(depart["ok"]), "出发：主机发起（等客机保存确认）")
	_pump(100)
	var confirmed := client.confirm_depart()
	_check(bool(confirmed["ok"]), "出发：客机写占用并回执")
	_pump(150)
	_check(host.expedition != null, "出发：双方确认后开局")
	_check(not client.mirror_run.is_empty(), "出发：客机收到局快照")

	# —— 动作与快照（客机意图经中继裁定；主机推进经中继广播）——
	client.send_action("vote_move", {"row": 1, "col": 0})
	_pump(80)
	_check(int(host.expedition.run["current"]["row"]) == 0, "选路：客机单方投票不移动")
	host.host_action("vote_move", {"row": 1, "col": 0})
	_check(int(host.expedition.run["current"]["row"]) == 1, "选路：双票后前进到第 1 排")
	_pump(80)
	_check(int(client.mirror_run.get("current", {}).get("row", -1)) == 1, "快照：客机镜像同步到第 1 排")

	# —— 断线与重连：同房号新连接，player_id 去重接回 ——
	client.disconnect_link()
	_pump_host_only(700)
	_check(host.any_member_offline(), "掉线：主机检测到客机离线（peer_down/超时）")

	var reconnected := SessionClient.new()
	_check(reconnected.connect_relay(code, client_game, "127.0.0.1", RELAY_PORT), "重连：同房号再次发起加入")
	client = reconnected
	_pump(120)
	_check(client.link_ready(), "重连：链路重建")
	var rejoin_inventory := InventoryGame.new()
	rejoin_inventory.bind(client_game.state["expedition"])
	client.hello_with(PLAYER_ID, rejoin_inventory)
	_pump(120)
	_check(not client.mirror_run.is_empty(), "重连：欢迎重放快照（镜像非空）")
	_check(int(client.mirror_run.get("current", {}).get("row", -1)) == 1, "重连：镜像为断线前状态")
	_check(not host.any_member_offline(), "重连：成员恢复在线")

	_cleanup()
	_finish()


func _pump(frames: int) -> void:
	for attempt in range(frames):
		if host != null:
			host.poll()
		if client != null:
			client.poll()
		OS.delay_msec(5)


func _pump_host_only(frames: int) -> void:
	for attempt in range(frames):
		if host != null:
			host.poll()
		OS.delay_msec(5)


func _start_relay() -> int:
	var script := ProjectSettings.globalize_path("res://tools/relay_server.py")
	for executable in ["python", "python3"]:
		var probe: Array = []
		if OS.execute(executable, ["--version"], probe) != 0:
			continue
		var pid := OS.create_process(executable, [script, "--port", str(RELAY_PORT)])
		if pid > 0:
			return pid
	return -1


## 端口探活：最多等 5 秒，能建立 TCP 连接即认为服务已监听。
func _wait_relay_up() -> bool:
	for attempt in range(25):
		var probe := StreamPeerTCP.new()
		probe.connect_to_host("127.0.0.1", RELAY_PORT)
		for inner in range(8):
			probe.poll()
			if probe.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				probe.disconnect_from_host()
				return true
			OS.delay_msec(10)
		probe.disconnect_from_host()
	return false


func _cleanup() -> void:
	if relay_pid > 0:
		OS.kill(relay_pid)
		relay_pid = -1


func _fresh_game(marker: int) -> FarmGame:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261100 + marker)
	game.new_game(1000)
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	for instance in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	return game


func _finish() -> void:
	if failed:
		push_error("D34_RELAY_SMOKE_FAIL")
	else:
		print("D34_RELAY_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
