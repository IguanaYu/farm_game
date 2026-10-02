class_name RelayTransport
extends SessionTransport
## TCP+NDJSON 中继传输（协议见 tools/relay_server.py 头注释与方案文档 §3）。
## 主机模式：create_room → 房号；客机模式：join_room(房号)。
## 成员编号由中继分配：主机=1、客机=2，客机重连仍为 2（与 SessionHost 按
## player_id 重连去重兼容）。心跳每 2 秒一条 _transport_ping，不入游戏层。
##
## 连接失败/被拒统一走：error（原因）→ link_down（一次），此后本传输不再恢复，
## 重连由上层新建传输完成（与现有 SessionClient 重连流程一致）。

const CONNECT_TIMEOUT_MS := 5000
const PING_INTERVAL_MS := 2000
const MAX_LINE_BYTES := 1000000

var tcp := StreamPeerTCP.new()
var _is_host := false
var _code := ""
var _joined := false
var _buffer := PackedByteArray()
var _last_ping_ms := 0
var _connect_started_ms := 0
var _connect_pending := false
var _reported_down := false


func open_host(address: String, port: int) -> bool:
	_is_host = true
	return _connect(address, port)


func open_guest(address: String, port: int, code: String) -> bool:
	_is_host = false
	_code = code
	return _connect(address, port)


func link_ready() -> bool:
	return _joined and tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED


func room_code() -> String:
	return _code


func send(peer_id: int, message: Dictionary) -> void:
	if _is_host and peer_id == 1:
		return
	_send_line({"t": "relay", "body": message})


func close() -> void:
	tcp.disconnect_from_host()


func _connect(address: String, port: int) -> bool:
	_connect_started_ms = Time.get_ticks_msec()
	_connect_pending = true
	return tcp.connect_to_host(address, port) == OK


func _send_line(message: Dictionary) -> void:
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	tcp.put_data((JSON.stringify(message) + "\n").to_utf8_buffer())


func _fail(reason: String) -> void:
	if _reported_down:
		return
	_reported_down = true
	_emit("error", {"reason": reason})
	_emit("link_down")
	tcp.disconnect_from_host()


func _drain() -> void:
	if _reported_down:
		return
	tcp.poll()
	var status := tcp.get_status()
	if status == StreamPeerTCP.STATUS_NONE:
		if not _reported_down:
			_reported_down = true
			_emit("link_down")
		return
	if status == StreamPeerTCP.STATUS_ERROR:
		_fail("无法连接中继服务器（地址/端口不可达）")
		return
	if status == StreamPeerTCP.STATUS_CONNECTING:
		if Time.get_ticks_msec() - _connect_started_ms > CONNECT_TIMEOUT_MS:
			_fail("连接中继服务器超时")
		return
	## STATUS_CONNECTED：首帧发出建房/加入，此后按周期心跳。
	if _connect_pending:
		_connect_pending = false
		if _is_host:
			_send_line({"t": "create_room"})
		else:
			_send_line({"t": "join_room", "code": _code})
		_last_ping_ms = Time.get_ticks_msec()
	if Time.get_ticks_msec() - _last_ping_ms > PING_INTERVAL_MS:
		_send_line({"t": "_transport_ping"})
		_last_ping_ms = Time.get_ticks_msec()
	var available := tcp.get_available_bytes()
	while available > 0:
		var chunk: Array = tcp.get_data(available)
		_buffer.append_array(chunk[1])
		if _buffer.size() > MAX_LINE_BYTES:
			_fail("中继消息超长")
			return
		available = tcp.get_available_bytes()
	_process_lines()


func _process_lines() -> void:
	while true:
		var newline := _buffer.find(10)
		if newline < 0:
			break
		var line := _buffer.slice(0, newline)
		_buffer = _buffer.slice(newline + 1)
		var text := line.get_string_from_utf8().strip_edges()
		if text == "":
			continue
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_on_server_message(parsed)


func _on_server_message(message: Dictionary) -> void:
	match str(message.get("t", "")):
		"room":
			_code = str(message.get("code", ""))
			_joined = true
			_emit("room_code", {"code": _code})
			_emit("link_up")
		"joined":
			_joined = true
			_emit("link_up")
		"error":
			## 中继明确拒绝（房号不存在/客机已在线等）：上报原因并关闭，不重试。
			_reported_down = true
			_emit("error", {"reason": str(message.get("reason", ""))})
			_emit("link_down")
			tcp.disconnect_from_host()
		"peer_down":
			_emit("peer_down", {"peer_id": int(message.get("from", 0))})
		"_transport_pong":
			pass
		"relay":
			var body: Variant = message.get("body", {})
			if body is Dictionary:
				_emit("message", {"peer_id": int(message.get("from", 1)), "message": body})
		_:
			pass
