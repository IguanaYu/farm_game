class_name EnetTransport
extends SessionTransport
## 局域网 ENet 直连传输：原 SessionHost/SessionClient 内联 ENet 逻辑的等价搬移，
## 行为与改造前一致（含 host 侧 sender==0 修正为 1 的历史兼容）。


var peer := ENetMultiplayerPeer.new()
var _is_host := false
var _reported_down := false


func listen(port: int) -> bool:
	_is_host = true
	## 槽位放宽到 8：掉线重连会占新 peer 位，靠 player_id 去重而非连接数限制。
	return peer.create_server(port, 8) == OK


func open_guest(address: String, port: int) -> bool:
	_is_host = false
	return peer.create_client(address, port) == OK


func link_ready() -> bool:
	if _is_host:
		return peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func send(peer_id: int, message: Dictionary) -> void:
	peer.set_target_peer(peer_id)
	peer.put_packet(JSON.stringify(message).to_utf8_buffer())


func close() -> void:
	peer.close()


func _drain() -> void:
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if not _reported_down:
			_reported_down = true
			_emit("link_down")
		return
	peer.poll()
	while peer.get_available_packet_count() > 0:
		var sender := peer.get_packet_peer()
		var message: Variant = JSON.parse_string(peer.get_packet().get_string_from_utf8())
		if message is Dictionary:
			if sender == 0:
				sender = 1
			_emit("message", {"peer_id": sender, "message": message})
