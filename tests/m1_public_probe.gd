extends SceneTree
## M1 公网探针（不入常规回归，run_regression.sh 已排除 m1_*）。
## 对腾讯云真实服务器做端到端验证：TLS 钉扎（内置公钥证书）/未信任拒绝、
## 真实邀请码激活、播种浇水、服务器重启后 token 续玩与状态恢复、公网延迟。
## 用法：
##   Godot --headless --path . --script res://tests/m1_public_probe.gd -- \
##     --step cert_reject|play|resume [--invite FARM-XXXX-XXXX] [--nick 名字] [--token t_...] [--timeout-ms 15000]
## 输出：M1P-RESULT {json} / M1P-PASS|M1P-FAIL <label>；退出码 0=通过。
## play 步会打印 M1P-TOKEN <token>（仅终端显示，勿入仓库/日志归档）。

const URL := "wss://111.229.19.23:31971"
const RESULT_PREFIX := "M1P-"

var step := "ping"
var invite := ""
var nick := "公网自测"
var token := ""
var timeout_ms := 15000
var failed := false
var latencies: Array = []


func _initialize() -> void:
	_read_args()
	match step:
		"cert_reject":
			_step_cert_reject()
		"play":
			_step_play()
		"resume":
			_step_resume()
		_:
			_check(false, "未知 step: %s" % step)
	_finish()


func _read_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match args[i]:
			"--step":
				step = args[i + 1]
			"--invite":
				invite = args[i + 1]
			"--nick":
				nick = args[i + 1]
			"--token":
				token = args[i + 1]
			"--timeout-ms":
				timeout_ms = int(args[i + 1])


func _connect(trust_cert := true) -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	var tls_opts: TLSOptions
	if trust_cert:
		var cert := X509Certificate.new()
		if cert.load("res://client/certs/farm_server.crt") != OK:
			_check(false, "内置公钥证书加载失败")
			return null
		tls_opts = TLSOptions.client(cert)
	else:
		tls_opts = TLSOptions.client()
	if peer.create_client(URL, tls_opts) != OK:
		_check(false, "create_client 失败")
		return null
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			return peer
		if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			return null
		OS.delay_msec(5)
	return null


func _step_cert_reject() -> void:
	var peer := _connect(false)
	_check(peer == null, "未信任证书时公网握手必须被拒（TLS 钉扎生效）")
	if peer != null:
		peer.close()
	var trusted := _connect(true)
	_check(trusted != null, "内置证书可建立公网 WSS 连接")
	if trusted != null:
		var t0 := Time.get_ticks_msec()
		var pong := _request(trusted, {"t": "ping"}, "pong")
		var proto_shown := str(pong.get("proto", "-")) if pong != null else "-"
		_check(pong != null, "公网 ping/pong（proto=%s）" % proto_shown)
		latencies.append(Time.get_ticks_msec() - t0)
		_result({"step": "cert_reject", "ping_ms": latencies.back()})
		trusted.close()


func _step_play() -> void:
	if invite == "":
		_check(false, "play 需要 --invite")
		return
	var peer := _connect(true)
	if peer == null:
		_check(false, "公网连接失败")
		return
	var welcome := _request(peer, {
		"t": "activate", "invite": invite, "nick": nick,
		"proto": OnlineProtocol.PROTO_VERSION, "rules": OnlineProtocol.RULES_VERSION,
		"build": OnlineProtocol.CLIENT_BUILD,
	}, "welcome")
	if welcome == null:
		return
	_check(true, "公网邀请码激活 → welcome")
	_check(welcome.get("features", []).has(OnlineProtocol.FEATURE_FARM_BASIC), "特性含 farm_basic")
	var farm: Dictionary = welcome["snapshot"]["farm"]
	_check(farm["seeds"].size() == 6, "新档 6 种子")
	token = str(welcome.get("token", ""))
	var planted := _request(peer, {"t": "req", "req_id": "pub-plant-1", "op": "farm.plant", "args": {"plot_id": 1}}, "req_ok")
	if planted == null:
		return
	_check(bool(planted.get("duplicate", true)) == false, "公网播种成功")
	_check(planted["snapshot"]["farm"]["seeds"].size() == 5, "播种后种子 5")
	var watered := _request(peer, {"t": "req", "req_id": "pub-water-1", "op": "farm.water", "args": {"plot_id": 1}}, "req_ok")
	if watered == null:
		return
	_check(bool(watered["result"].get("ok", false)), "公网浇水成功")
	_check(int(watered["snapshot"]["farm"]["tutorial_step"]) == 2, "教程推进到 2")
	# 同号重放：公网收据去重
	var replay := _request(peer, {"t": "req", "req_id": "pub-water-1", "op": "farm.water", "args": {"plot_id": 1}}, "req_ok")
	if replay != null:
		_check(bool(replay.get("duplicate", false)), "公网同号重放 → duplicate=true")
	print("M1P-TOKEN %s" % token)
	_result({
		"step": "play", "account_id": int(welcome["account_id"]), "farm_seq": int(watered["farm_seq"]),
		"server_now": int(watered["server_now"]), "latencies_ms": latencies,
	})
	peer.close()


func _step_resume() -> void:
	if token == "":
		_check(false, "resume 需要 --token")
		return
	var peer := _connect(true)
	if peer == null:
		_check(false, "公网连接失败")
		return
	var welcome := _request(peer, {
		"t": "hello", "token": token,
		"proto": OnlineProtocol.PROTO_VERSION, "rules": OnlineProtocol.RULES_VERSION,
		"build": OnlineProtocol.CLIENT_BUILD,
	}, "welcome")
	if welcome == null:
		return
	_check(true, "服务器重启后 token 自动登录")
	var farm: Dictionary = welcome["snapshot"]["farm"]
	_check(int(farm["plots"][0]["seed_id"]) != 0, "重启后第 1 块地作物仍在")
	_check(farm["seeds"].size() == 5, "重启后种子数不变（无重复扣发）")
	_check(int(farm["tutorial_step"]) == 2, "重启后教程进度保持 2")
	var early := _request(peer, {"t": "req", "req_id": "pub-harvest-early", "op": "farm.harvest", "args": {"plot_id": 1}}, "req_err")
	if early != null:
		_check(str(early.get("code", "")) == OnlineProtocol.ERR_OP_FAILED, "未成熟收获被拒（规则一致）")
	_result({"step": "resume", "farm_seq": int(welcome["farm_seq"]), "latencies_ms": latencies})
	peer.close()


func _request(peer: WebSocketMultiplayerPeer, payload: Dictionary, expect_t: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	peer.set_target_peer(1)
	if peer.put_packet(JSON.stringify(payload).to_utf8_buffer()) != OK:
		_check(false, "发送失败")
		return {}
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var parsed := JSON.new()
			if parsed.parse(peer.get_packet().get_string_from_utf8()) != OK or not (parsed.data is Dictionary):
				continue
			var msg: Dictionary = parsed.data
			var t := str(msg.get("t", ""))
			if t == "error":
				_check(false, "服务器 error: %s" % str(msg.get("code", "")))
				return {}
			if t == expect_t:
				latencies.append(Time.get_ticks_msec() - t0)
				return msg
			if t == "req_err":
				if expect_t == "req_err":
					latencies.append(Time.get_ticks_msec() - t0)
					return msg
				_check(false, "req_err: %s %s" % [str(msg.get("code", "")), str(msg.get("msg", ""))])
				return {}
		OS.delay_msec(3)
	_check(false, "等待 %s 超时" % expect_t)
	return {}


func _result(payload: Dictionary) -> void:
	print(RESULT_PREFIX + "RESULT " + JSON.stringify(payload))


func _check(ok: bool, label: String) -> bool:
	if ok:
		print("M1P-PASS %s" % label)
	else:
		failed = true
		print("M1P-FAIL %s" % label)
	return ok


func _finish() -> void:
	quit(1 if failed else 0)
