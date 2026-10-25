class_name HandFan
extends Control
## 扇形手牌只负责姿态和命中；牌序、费用及裁定由 BattleScreen / CombatGame 管理。

var cards: Array[Control] = []
var selected_uid := -1
var hovered_uid := -1
var drag_uid := -1
var small := false
var hover_top_limit := 0.0
var _slots: Dictionary = {}
var _poses: Dictionary = {}
var _tweens: Dictionary = {}
var _last_layout_size := Vector2.ZERO
var _last_small := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	resized.connect(func() -> void: arrange(false))

func set_cards(ordered: Array[Control]) -> void:
	for old in cards:
		if is_instance_valid(old) and old not in ordered:
			_stop_tween(old)
	cards = ordered
	for i in range(cards.size()):
		move_child(cards[i], i)
	var resizing := size != _last_layout_size or small != _last_small
	arrange(not resizing)
	_last_layout_size = size
	_last_small = small

func set_interaction(selected: int, hovered: int, dragged := -1) -> void:
	if selected_uid == selected and hovered_uid == hovered and drag_uid == dragged:
		return
	selected_uid = selected
	hovered_uid = hovered
	drag_uid = dragged
	arrange()

func active_uid() -> int:
	return selected_uid if selected_uid >= 0 else hovered_uid

func _stop_tween(card: Control) -> void:
	var key := card.get_instance_id()
	if _tweens.has(key):
		var tween: Tween = _tweens[key]
		if tween.is_valid():
			tween.kill()
		_tweens.erase(key)

func arrange(animate := true) -> void:
	if not is_inside_tree() or size.x <= 0:
		return
	_slots.clear()
	_poses.clear()
	var density := clampf((cards.size() - 5) / 5.0, 0.0, 1.0)
	var step := lerpf(104.0, 49.0, density) if small else lerpf(120.0, 74.0, density)
	# Keep the approved spread at 1280 / 1024, and gently open on wider windows.
	step *= clampf(size.x / (1024.0 if small else 1280.0), 0.8, 1.25)
	var angle := lerpf(9.0, 13.0, density) if small else lerpf(10.0, 16.0, density)
	if cards.size() <= 2:
		angle = 3.0 if cards.size() == 2 else 0.0
	var active := active_uid()
	var active_index := -1
	for i in range(cards.size()):
		if int(cards[i].get_meta("hand_uid")) == active:
			active_index = i
	for i in range(cards.size()):
		var card := cards[i]
		var uid := int(card.get_meta("hand_uid"))
		var t := (i - (cards.size() - 1) / 2.0) / maxf(1.0, (cards.size() - 1) / 2.0)
		var pivot := Vector2(card.size.x / 2.0, card.size.y)
		var center := Vector2(size.x / 2.0 + (i - (cards.size() - 1) / 2.0) * step, size.y - 40.0 + 18.0 * t * t)
		var rotation_value := deg_to_rad(t * angle)
		_slots[uid] = _transform(center - pivot, pivot, rotation_value, Vector2.ONE)
		if active_index >= 0 and i != active_index:
			center.x += -14.0 if i < active_index else 14.0
		var scale_value := Vector2.ONE
		if i == active_index:
			center.y -= 66.0 if small else 76.0
			rotation_value = 0.0
			scale_value *= 1.18
			var min_top := minf(hover_top_limit, size.y - 8.0 - card.size.y * scale_value.y)
			center.y = maxf(center.y, min_top + card.size.y * scale_value.y)
		_poses[uid] = _transform(center - pivot, pivot, rotation_value, scale_value)
		card.pivot_offset = pivot
		card.z_index = 30 if i == active_index else 10 + i
		card.modulate.a = 0.22 if uid == drag_uid else 1.0
		_stop_tween(card)
		var position_value := center - pivot
		if animate and card.has_meta("fan_placed") and not SettingsStore.get_reduce_motion():
			var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(card, "position", position_value, 0.16)
			tween.tween_property(card, "rotation", rotation_value, 0.16)
			tween.tween_property(card, "scale", scale_value, 0.16)
			_tweens[card.get_instance_id()] = tween
		else:
			card.position = position_value
			card.rotation = rotation_value
			card.scale = scale_value
		card.set_meta("fan_placed", true)

func _transform(at: Vector2, pivot: Vector2, radians: float, factor: Vector2) -> Transform2D:
	var result := Transform2D(radians, factor, 0.0, Vector2.ZERO)
	result.origin = at + pivot - result.basis_xform(pivot)
	return result

func _contains(card: Control, pose: Transform2D, point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, card.size).has_point(pose.affine_inverse() * point)

## 命中原槽位与抬起后的牌面，移动动画不会让悬停反复丢失。
## 所有按钮共用一次确定性的取牌规则，绘制层级不依赖 Godot 的子节点输入顺序。
func card_at(global_point: Vector2) -> Control:
	var point := get_global_transform().affine_inverse() * global_point
	var active := active_uid()
	# A narrow stable band on each cost seal lets the pointer skim all ten
	# cards without the lifted face swallowing its neighbour's hover lane.
	for i in range(cards.size() - 1, -1, -1):
		var card := cards[i]
		var uid := int(card.get_meta("hand_uid"))
		if _slots.has(uid):
			var local := (_slots[uid] as Transform2D).affine_inverse() * point
			if Rect2(8, 8, 34, 36).has_point(local):
				return card
	for card in cards:
		var uid := int(card.get_meta("hand_uid"))
		if uid == active and _poses.has(uid) and _contains(card, _poses[uid], point):
			return card
	for i in range(cards.size() - 1, -1, -1):
		var card := cards[i]
		var uid := int(card.get_meta("hand_uid"))
		if _slots.has(uid) and _contains(card, _slots[uid], point):
			return card
	return null

func slot_point(uid: int, local_point: Vector2) -> Vector2:
	return get_global_transform() * (_slots.get(uid, Transform2D.IDENTITY) * local_point)

func clear_cards() -> void:
	for card in cards:
		if is_instance_valid(card):
			_stop_tween(card)
	cards.clear()
	_slots.clear()
	_poses.clear()
	selected_uid = -1
	hovered_uid = -1
	drag_uid = -1
