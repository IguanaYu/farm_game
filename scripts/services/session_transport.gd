class_name SessionTransport
extends RefCounted
## 会话传输层基类：统一「ENet 局域网直连」与「TCP 中继」两种链路。
## SessionHost/SessionClient 只与本类交互；事件经 poll() 返回（不用信号，
## 保持与原泵式时序一致），每帧取走并清空：
##   {kind:"message", peer_id, message}  收到对端一条游戏层消息
##   {kind:"peer_down", peer_id}         对端断开（中继即时推送；ENet 靠游戏层超时）
##   {kind:"link_up"}                    本端链路就绪（主机=监听/房号确认；客机=握手完成）
##   {kind:"link_down"}                  链路断开/连接失败（每条链路只发一次）
##   {kind:"room_code", code}            （中继·主机）房号到达
##   {kind:"error", reason}              （中继）连接/加入失败的可读原因

var _events: Array = []


func poll() -> Array:
	_drain()
	var pending := _events
	_events = []
	return pending


func link_ready() -> bool:
	return false


func room_code() -> String:
	return ""


func send(_peer_id: int, _message: Dictionary) -> void:
	push_error("SessionTransport 子类必须实现 send()")


func close() -> void:
	pass


func _drain() -> void:
	pass


func _emit(kind: String, data: Dictionary = {}) -> void:
	var event := {"kind": kind}
	event.merge(data)
	_events.append(event)
