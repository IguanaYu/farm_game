extends SceneTree
## M0 客户端探针：独立进程连 WSS 服务器，验证传输/事务/证书校验。
## 与 scripts/server/server_main.gd 配套；编排见 tools/m0_local_verify.py。
## 用法：
##   Godot --headless --path . --script res://tests/m0_wss_probe.gd -- \
##     --url wss://127.0.0.1:31971 --cert <crt|-> --step <ping|tx|balance|receipts|malformed|handshake_fail>
##     [--count 5] [--delta 10] [--req-prefix r] [--timeout-ms 8000]
## 输出：M0-RESULT {json} 逐条；M0-FAIL <原因>；退出码 0=通过 1=失败。

const RESULT_PREFIX := "M0-RESULT "

var url := "wss://127.0.0.1:31971"
var cert_path := ""
var step := "ping"
var count := 1
var delta := 10
var req_prefix := "r"
var timeout_ms := 8000
var peer := WebSocketMultiplayerPeer.new()
var failed := false
var latencies: Array = []


func _initialize() -> void:
	_read_args()
	var deadline := Time.get_ticks_msec() + timeout_ms
	if not _connect(deadline):
		_finish()
		return
	match step:
		"handshake_fail":
			_check(false, "握手竟然成功了：未信任自签证书也连上了")
		"ping":
			_step_ping()
		"tx":
			_step_tx(deadline, false)
		"tx_replay":
			_step_tx(deadline, true)
		"balance":
			_step_balance()
		"receipts":
			_step_receipts()
		"malformed":
			_step_malformed(deadline)
		_:
			_check(false, "未知 step: %s" % step)
	_finish()


func _read_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match args[i]:
			"--url":
				url = args[i + 1]
			"--cert":
				if args[i + 1] != "-":
					cert_path = args[i + 1]
			"--step":
				step = args[i + 1]
			"--count":
				count = int(args[i + 1])
			"--delta":
				delta = int(args[i + 1])
			"--req-prefix":
				req_prefix = args[i + 1]
			"--timeout-ms":
				timeout_ms = int(args[i + 1])


func _connect(deadline: int) -> bool:
	var tls_opts: TLSOptions
	if cert_path != "":
		var cert := X509Certificate.new()
		if cert.load(cert_path) != OK:
			_check(false, "证书加载失败: %s" % cert_path)
			return false
		tls_opts = TLSOptions.client(cert)
	else:
		tls_opts = TLSOptions.client()
	if peer.create_client(url, tls_opts) != OK:
		_check(false, "create_client 失败")
		return false
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var state := peer.get_connection_status()
		if state == MultiplayerPeer.CONNECTION_CONNECTED:
			if step == "handshake_fail":
				return true
			_result({"step": "connected", "peer": peer.get_unique_id()})
			return true
		if state == MultiplayerPeer.CONNECTION_DISCONNECTED:
			if step == "handshake_fail":
				_result({"step": "handshake_fail", "outcome": "rejected_as_expected"})
				_check(true, "不信任自签证书时握手被拒（预期行为）")
				return false
			_check(false, "连接失败/被拒（握手或协议不匹配，未到 CONNECTED 即断开）")
			return false
		OS.delay_msec(5)
	_check(false, "连接超时")
	return false


func _step_ping() -> void:
	var msg: Variant = _request({"t": "ping"}, "pong", Time.get_ticks_msec() + 3000)
	if msg == null:
		return
	_check(str(msg.get("t", "")) == "pong", "pong 应答")
	_result({"step": "ping", "proto": int(msg.get("proto", 0)), "ms": latencies.back()})


func _step_tx(deadline: int, expect_duplicate: bool) -> void:
	var final_balance := 0
	var balances: Array = []
	var dup_hits := 0
	for i in range(count):
		var req_id := "%s-%d" % [req_prefix, i]
		var msg: Variant = _request({"t": "tx", "req_id": req_id, "delta": delta}, "tx_ok", deadline)
		if msg == null:
			return
		var dup := bool(msg.get("duplicate", false))
		if dup != expect_duplicate:
			_check(false, "req_id=%s duplicate=%s（期望 %s）" % [req_id, dup, expect_duplicate])
			return
		if dup:
			dup_hits += 1
		var bal := int(msg.get("balance", -1))
		balances.append(bal)
		final_balance = bal
	_result({
		"step": "tx" if not expect_duplicate else "tx_replay",
		"count": count, "delta": delta, "dup_hits": dup_hits,
		"final_balance": final_balance, "balances": balances, "latencies_ms": latencies,
	})


func _step_balance() -> void:
	var msg: Variant = _request({"t": "balance"}, "balance", Time.get_ticks_msec() + 3000)
	if msg == null:
		return
	_result({"step": "balance", "value": int(msg.get("value", -1))})


func _step_receipts() -> void:
	var msg: Variant = _request({"t": "receipts", "limit": 1000}, "receipts", Time.get_ticks_msec() + 3000)
	if msg == null:
		return
	_result({"step": "receipts", "count": int(msg.get("count", -1))})


func _step_malformed(deadline: int) -> void:
	_send_raw("这不是JSON{{{".to_utf8_buffer())
	var msg: Variant = _request({"t": "ping"}, "pong", deadline, "bad_json")
	if msg == null:
		return
	_result({"step": "malformed", "alive_after": true})


func _request(payload: Dictionary, expect_t: String, deadline: int, accept_error := "") -> Variant:
	var t0 := Time.get_ticks_msec()
	if not _send_json(payload):
		return null
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var parsed := JSON.new()
			var raw := peer.get_packet().get_string_from_utf8()
			if parsed.parse(raw) != OK or not (parsed.data is Dictionary):
				_check(false, "服务器回了非 JSON: %s" % raw.substr(0, 80))
				return null
			var msg: Dictionary = parsed.data
			var t := str(msg.get("t", ""))
			if t == "error":
				if accept_error != "" and str(msg.get("reason", "")) == accept_error:
					continue
				_check(false, "服务器 error 应答: %s" % str(msg.get("reason", "")))
				return null
			if t == expect_t:
				latencies.append(Time.get_ticks_msec() - t0)
				return msg
			_check(false, "应答类型不符：期望 %s 得到 %s" % [expect_t, t])
			return null
		OS.delay_msec(2)
	_check(false, "等待 %s 超时" % expect_t)
	return null


func _send_json(payload: Dictionary) -> bool:
	return _send_raw(JSON.stringify(payload).to_utf8_buffer())


func _send_raw(data: PackedByteArray) -> bool:
	var target := peer.get_peer(1)
	if target != null:
		target.put_packet(data)
		return true
	peer.set_target_peer(1)
	return peer.put_packet(data) == OK


func _result(payload: Dictionary) -> void:
	print(RESULT_PREFIX + JSON.stringify(payload))


func _check(ok: bool, label: String) -> void:
	if ok:
		print("M0-PASS %s" % label)
	else:
		failed = true
		print("M0-FAIL %s" % label)


func _finish() -> void:
	if peer != null:
		peer.close()
	quit(1 if failed else 0)
