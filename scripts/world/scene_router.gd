class_name SceneRouter
extends Node
## 地点路由（合并路线 R2，设计稿 §3/§10）：常驻根下的地点注册表与切换。
## R2 语义：切换=地点节点可见性 + 进入/离开钩子（不 instantiate/销毁、不触碰 GameContext）；
## 返回栈记录来路；过渡为纯表现（CanvasLayer 淡入淡出，约 0.25s，不阻塞切换本体，
## headless 下同样安全——切换同步完成）。

signal location_changed(location_id: String)

var current := ""
var _locations := {}  # id -> {root: Node, on_enter: Callable, on_leave: Callable}
var _stack: Array = []
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null
var _fade_tween: Tween = null


func register(id: String, root: Node, on_enter := Callable(), on_leave := Callable()) -> void:
	_locations[id] = {"root": root, "on_enter": on_enter, "on_leave": on_leave}
	if current == "":
		current = id
		root.visible = true


func unregister(id: String) -> void:
	# Active locations must leave through switch_to so visibility, picking and cameras agree.
	assert(id != current, "Leave a location before unregistering it")
	_locations.erase(id)
	_stack = _stack.filter(func(entry): return str(entry) != id)


## 切换地点：push=true 记录返回栈（普通入口）；同地点直通不动作。
func switch_to(id: String, push := true) -> void:
	if not _locations.has(id):
		push_warning("SceneRouter：未注册的地点 %s" % id)
		return
	if id == current:
		return
	_transition()
	var from := str(current)
	if _locations.has(from):
		var leaving: Dictionary = _locations[from]
		(leaving["root"] as Node).visible = false
		if leaving["on_leave"].is_valid():
			leaving["on_leave"].call()
	if push and from != "":
		_stack.push_back(from)
	current = id
	var entering: Dictionary = _locations[id]
	(entering["root"] as Node).visible = true
	if entering["on_enter"].is_valid():
		entering["on_enter"].call()
	location_changed.emit(id)


## 返回上一地点（商店门/院门等自然出口）；栈空时不动。
func go_back() -> void:
	if _stack.is_empty():
		return
	var target := str(_stack.pop_back())
	if target == current:
		return
	switch_to(target, false)


func can_go_back() -> bool:
	return not _stack.is_empty()


func _ensure_fade() -> void:
	if _fade_layer != null:
		return
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "SceneFadeLayer"
	_fade_layer.layer = 90
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.05, 0.09, 0.07, 0.0)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)


func _transition() -> void:
	_ensure_fade()
	if _fade_rect == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if SettingsStore.get_reduce_motion():
		_fade_rect.color.a = 0.0
		return
	# Location changes remain synchronous; one short veil fades away without competing tweens.
	_fade_rect.color.a = 0.28
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_rect, "color:a", 0.0, 0.24)
