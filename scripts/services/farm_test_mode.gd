class_name FarmTestMode
extends RefCounted
## 主菜单开关在本次启动内保留；虚拟时钟与进度只写入独立测试档。

const SAVE_PATH := "user://farm_test_save_v1.json"
const SPEEDS := [1, 60, 300, 1200]
const DEFAULT_SPEED := 60
static var enabled := false

var speed: int = DEFAULT_SPEED
var _anchor_time: float = Time.get_unix_time_from_system()
var _anchor_ticks: int = Time.get_ticks_msec()


func restore(state: Dictionary) -> void:
	var clock: Dictionary = state.get("test_clock", {})
	_anchor_time = float(clock.get("now", Time.get_unix_time_from_system()))
	_anchor_ticks = Time.get_ticks_msec()
	var saved_speed := int(clock.get("speed", DEFAULT_SPEED))
	speed = saved_speed if saved_speed in SPEEDS else DEFAULT_SPEED


func now() -> int:
	return int(_time())


func _time() -> float:
	return _anchor_time + float(Time.get_ticks_msec() - _anchor_ticks) / 1000.0 * speed


func set_speed(value: int) -> void:
	if value not in SPEEDS:
		return
	_anchor_time = _time()
	_anchor_ticks = Time.get_ticks_msec()
	speed = value


func snapshot() -> Dictionary:
	return {"now": _time(), "speed": speed}
