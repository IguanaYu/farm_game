extends SceneTree
## 2.1-W8：网络技术试验（总计划 §10-2.1 交付项）。
## 单进程内 ENet host＋client 经 127.0.0.1 连接：验证连接建立、消息往返、主动断开。


var failed := false


func _initialize() -> void:
	var host := ENetMultiplayerPeer.new()
	var server_error := host.create_server(31921, 1)
	var client := ENetMultiplayerPeer.new()
	var client_error := client.create_client("127.0.0.1", 31921)
	_check(server_error == OK and client_error == OK, "ENet：本机创建 host 与 client 无错误")

	var connected := false
	for attempt in range(300):
		host.poll()
		client.poll()
		if host.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
				and client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			connected = true
			break
		OS.delay_msec(10)
	_check(connected, "ENet：连接在 3 秒内建立")

	if connected:
		client.put_packet("ping".to_utf8_buffer())
		var received := _drain_until(host, "ping")
		_check(received == "ping", "ENet：主机收到客户端消息（127.0.0.1 往返）")

		host.set_target_peer(client.get_unique_id())
		host.put_packet("pong".to_utf8_buffer())
		var echoed := _drain_until(client, "pong")
		_check(echoed == "pong", "ENet：客户端收到主机回复")

		client.close()
		## F-12 修复：关闭后的 peer 不再 poll（inactive 实例每次 poll 都刷错误）。
		## 主机侧继续泵，直到它观测到对端断开；客机只查询连接状态。
		var host_seen_disconnect := false
		for attempt in range(50):
			host.poll()
			if client.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
				host_seen_disconnect = true
				break
			OS.delay_msec(10)
		_check(client.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED, "ENet：主动断开后连接关闭")
		_check(host_seen_disconnect, "ENet：主机侧观测到对端断开")
		var leftover := 0
		while host.get_available_packet_count() > 0:
			host.get_packet()
			leftover += 1
		if leftover > 0:
			print("  note: 断开时主机剩余 %d 个未读包（已清空）" % leftover)

	if failed:
		push_error("D21_NET_PROBE_FAIL")
	else:
		print("D21_NET_PROBE_PASS")
	quit(1 if failed else 0)


func _drain_until(peer: ENetMultiplayerPeer, expected: String) -> String:
	for attempt in range(100):
		peer.poll()
		if peer.get_available_packet_count() > 0:
			return peer.get_packet().get_string_from_utf8()
		OS.delay_msec(10)
	return ""


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
