class_name BattleGlyph
extends Control
## Small vector symbols, independent of the system font's emoji coverage.

var kind := "energy"
var color := ExpeditionUI.GOLD

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var unit := minf(size.x, size.y) / 24.0
	draw_set_transform((size - Vector2.ONE * 24 * unit) / 2, 0, Vector2.ONE * unit)
	match kind:
		"settings":
			for i in range(8):
				var direction := Vector2.from_angle(TAU * i / 8.0)
				draw_line(Vector2(12, 12) + direction * 7, Vector2(12, 12) + direction * 10, color, 4, true)
			draw_arc(Vector2(12, 12), 6.5, 0, TAU, 32, color, 3, true)
			draw_circle(Vector2(12, 12), 2, color)
		"attack", "damage":
			draw_colored_polygon(PackedVector2Array([Vector2(8, 14), Vector2(17, 3), Vector2(21, 3), Vector2(21, 7), Vector2(11, 17)]), color)
			draw_line(Vector2(5, 12), Vector2(14, 21), color, 2.5, true)
			draw_line(Vector2(8, 17), Vector2(3, 22), color, 3, true)
		"shield", "block":
			draw_colored_polygon(PackedVector2Array([Vector2(12, 2), Vector2(21, 6), Vector2(20, 15), Vector2(16, 20), Vector2(12, 23), Vector2(8, 20), Vector2(4, 15), Vector2(3, 6)]), color)
			draw_line(Vector2(12, 6), Vector2(12, 17), color.darkened(0.35), 2, true)
		"heart", "heal":
			draw_circle(Vector2(7, 8), 5, color)
			draw_circle(Vector2(17, 8), 5, color)
			draw_colored_polygon(PackedVector2Array([Vector2(2, 10), Vector2(22, 10), Vector2(12, 22)]), color)
		"draw", "cards", "discard":
			draw_style_box(ExpeditionUI.style(Color.TRANSPARENT, color, 2, 0), Rect2(3, 2, 13, 17))
			draw_style_box(ExpeditionUI.style(ExpeditionUI.PANEL, color, 2, 0), Rect2(8, 6, 13, 17))
		"exhaust":
			draw_line(Vector2(5, 5), Vector2(19, 19), color, 2.5, true)
			draw_line(Vector2(19, 5), Vector2(5, 19), color, 2.5, true)
		"rescue":
			draw_rect(Rect2(9, 2, 6, 20), color)
			draw_rect(Rect2(2, 9, 20, 6), color)
		_:
			draw_colored_polygon(PackedVector2Array([Vector2(14, 1), Vector2(4, 14), Vector2(11, 14), Vector2(9, 23), Vector2(21, 9), Vector2(14, 9)]), color)

static func make(symbol: String, tint: Color, extent := 20) -> BattleGlyph:
	var glyph := BattleGlyph.new()
	glyph.kind = symbol
	glyph.color = tint
	glyph.custom_minimum_size = Vector2.ONE * extent
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return glyph
