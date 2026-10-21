class_name BattleCutoutMotion
extends Control
## 纸片表演层：复制当前插图，隐藏原图；从不移动按钮或写入战斗状态。

const IMPACT_TIME := 0.36
const DURATION := 0.82
var source_art: ExpeditionArt
var target_art: ExpeditionArt
var ranged := false
var elapsed := 0.0
var attacker: ExpeditionArt
var defender: ExpeditionArt
var start := Vector2.ZERO
var finish := Vector2.ZERO
var direction := 1.0
var reach := 0.0
var source_alpha := 1.0
var target_alpha := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 40
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	start = source_art.get_global_rect().get_center() - global_position
	finish = target_art.get_global_rect().get_center() - global_position
	direction = signf(finish.x - start.x)
	reach = maxf(0, absf(finish.x - start.x) - minf(target_art.size.x, target_art.size.y) * 0.65)
	attacker = _copy(source_art)
	defender = _copy(target_art)
	if ranged:
		attacker.scale.x = direction
	source_alpha = source_art.self_modulate.a
	target_alpha = target_art.self_modulate.a
	source_art.self_modulate.a = 0
	target_art.self_modulate.a = 0
	_pose()

func _copy(original: ExpeditionArt) -> ExpeditionArt:
	var copy := ExpeditionArt.new()
	copy.subject = original.subject
	copy.layer_id = original.layer_id
	copy.tint = original.tint
	copy.show_shadow = false
	copy.size = original.size
	copy.position = original.global_position - global_position
	copy.pivot_offset = copy.size * Vector2(0.5, 0.94)
	copy.modulate = original.modulate
	# 同时保留风格样稿的纹理覆盖；不能重新从登记表换回旧外观。
	copy._art_texture = original._resolve_texture()
	copy._texture_key = copy.subject + ":" + copy.layer_id
	add_child(copy)
	return copy

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= DURATION:
		queue_free()
		return
	_pose()
	queue_redraw()

func _pose() -> void:
	var windup := sin(clampf(elapsed / 0.18, 0, 1) * PI * 0.5)
	var strike := smoothstep(0.18, IMPACT_TIME, elapsed)
	var recover := smoothstep(IMPACT_TIME + 0.10, DURATION, elapsed)
	var offset: float = (-12 * windup + (22.0 if ranged else reach + 12) * strike) * (1 - recover)
	attacker.position = start - attacker.size / 2 + Vector2(direction * offset, -sin(strike * PI) * (2 if ranged else 14))
	attacker.rotation = direction * (-0.08 * windup + 0.20 * strike) * (1 - recover)
	var recoil := sin(clampf((elapsed - IMPACT_TIME) / 0.29, 0, 1) * PI)
	defender.position = finish - defender.size / 2 + Vector2(direction * recoil * 18, -recoil * 3)
	defender.rotation = direction * recoil * 0.09
	defender.self_modulate = Color(1, 0.68, 0.55) if elapsed >= IMPACT_TIME and elapsed < IMPACT_TIME + 0.10 else Color.WHITE

func _draw() -> void:
	if ranged:
		if elapsed < 0.18 or elapsed > IMPACT_TIME + 0.06:
			return
		var p := clampf((elapsed - 0.18) / (IMPACT_TIME - 0.18), 0, 1)
		var origin := start + Vector2(direction * 44, 8)
		var point := origin.lerp(finish, p) + Vector2(0, -sin(p * PI) * 18)
		var tail := point - Vector2(direction * 36, 0)
		draw_line(tail, point, Color("#ad8163"), 4, true)
		draw_colored_polygon(PackedVector2Array([point + Vector2(direction * 8, 0), point + Vector2(-direction * 4, -5), point + Vector2(-direction * 4, 5)]), Color("#d9d1b4"))
		draw_line(tail, tail + Vector2(direction * 7, -5), Color("#ead7a4"), 3, true)
	else:
		# 铜剑与角色一起摆动；剑光只出现在挥击瞬间。
		var swing := smoothstep(0.18, IMPACT_TIME, elapsed)
		var fade := 1.0 - smoothstep(0.48, DURATION, elapsed)
		var hand := attacker.position + attacker.size * Vector2(0.5, 0.65) + Vector2(direction * 22, 0)
		var angle := lerpf(-1.8, 0.35, swing)
		var tip := hand + Vector2(direction * cos(angle), sin(angle)) * 64
		draw_line(hand, tip, Color("#cf9e6a", fade), 9, true)
		draw_line(hand.lerp(tip, 0.2), tip, Color("#ead7a4", fade), 3, true)
		draw_line(hand + Vector2(-8, -5), hand + Vector2(8, 5), Color("#927453", fade), 5, true)
		if elapsed > 0.23 and elapsed < 0.44:
			draw_arc(hand, 68, -1.7 if direction > 0 else PI - 0.35, 0.35 if direction > 0 else PI + 1.7, 24, Color("#ead7a4", 0.45), 5, true)

func _exit_tree() -> void:
	# 切场景、连续出牌或窗口重排都可立即取消，保证原角色不会留在隐身状态。
	if is_instance_valid(source_art):
		source_art.self_modulate.a = source_alpha
	if is_instance_valid(target_art):
		target_art.self_modulate.a = target_alpha
