class_name BattleEffect
extends Control
## 规则事件驱动的短特效；覆盖层不拦截输入，也不参与数值结算。

var kind := "block"
var tint := Color("#7dcfff")
var center := Vector2.ZERO
var from := Vector2.ZERO
var progress := 0.0
var reduce_motion := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 45
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tween := create_tween()
	tween.tween_method(_advance, 0.0, 1.0, 0.72 if kind != "card_played" else 0.4)
	tween.tween_callback(queue_free)

func _advance(value: float) -> void:
	progress = value
	queue_redraw()

func _draw() -> void:
	var p := 0.35 if reduce_motion else progress
	var color := Color(tint, (1.0 - progress) * 0.9)
	var bright := Color.WHITE
	bright.a = color.a
	match kind:
		"card_played":
			var point := center if reduce_motion else from.lerp(center, ease(p, 0.5)) + Vector2(0, -sin(p * PI) * 60)
			if not reduce_motion:
				draw_line(from.lerp(center, maxf(0, p - 0.16)), point, Color(tint, color.a * 0.3), 5, true)
			draw_style_box(ExpeditionUI.style(Color("#f8efd9", color.a), color, 4, 0), Rect2(point - Vector2(12, 17), Vector2(24, 34)))
		"block":
			var radius := 58 + sin(p * PI) * 17
			draw_circle(center, radius, Color(tint, color.a * 0.12))
			draw_arc(center, radius, 0, TAU, 64, color, 4, true)
			var shield := PackedVector2Array([Vector2(-37, -39), Vector2(0, -51), Vector2(37, -39), Vector2(31, 12), Vector2(0, 41), Vector2(-31, 12)])
			for i in range(shield.size()):
				shield[i] += center
			draw_colored_polygon(shield, Color(tint, color.a * 0.25))
			shield.append(shield[0])
			draw_polyline(shield, bright, 3, true)
			draw_line(center + Vector2(0, -32), center + Vector2(0, 21), color, 5, true)
			_sparks(center, radius + 8, color, p)
		"damage", "poison":
			var spread := 48 + p * 45
			draw_circle(center, 25 + p * 50, Color(tint, color.a * 0.13))
			draw_line(center + Vector2(-spread, spread * 0.6), center + Vector2(spread, -spread * 0.6), color, 11 * (1 - p) + 2, true)
			draw_line(center + Vector2(-spread, spread * 0.6), center + Vector2(spread, -spread * 0.6), bright, 3, true)
			draw_line(center + Vector2(-spread * 0.6, -spread * 0.45), center + Vector2(spread * 0.6, spread * 0.45), color, 5, true)
			_sparks(center, spread, color, p)
		"heal", "rescue", "status":
			draw_circle(center, 45 + p * 30, Color(tint, color.a * 0.14))
			draw_arc(center, 45 + p * 30, 0, TAU, 64, color, 3, true)
			for i in range(5):
				var point := center + Vector2((i - 2) * 26, 20 - p * 90 + sin(float(i)) * 14)
				draw_line(point - Vector2(6, 0), point + Vector2(6, 0), color, 3, true)
				draw_line(point - Vector2(0, 6), point + Vector2(0, 6), color, 3, true)
		"draw":
			for i in range(3):
				var point := center + Vector2((i - 1) * 34, -p * 65)
				draw_style_box(ExpeditionUI.style(Color("#1b3140", color.a), color, 4, 0), Rect2(point - Vector2(12, 18), Vector2(24, 36)))
			_sparks(center, 50 + p * 30, color, p)

func _sparks(point: Vector2, radius: float, color: Color, p: float) -> void:
	for i in range(10):
		var direction := Vector2.from_angle(TAU * float(i) / 10 + 0.15)
		draw_line(point + direction * radius, point + direction * (radius + 10 + p * 12), color, 2, true)
