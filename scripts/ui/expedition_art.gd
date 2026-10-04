class_name ExpeditionArt
extends Control
## 可缩放的原生矢量插画；不需要外部贴图，所有敌人都有对应形象。

var subject := "crystal"
var tint := Color("#7ac7b3")
var layer_id := "moss_stone_shallow"
var stage_scene := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _poly(points: Array, color: Color) -> void:
	var packed := PackedVector2Array()
	for point in points:
		packed.append(Vector2(point[0], point[1]))
	draw_colored_polygon(packed, color)

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	if subject == "cave":
		_draw_cave()
		return
	if stage_scene:
		_draw_cave()
	var unit := minf(size.x, size.y) / 200.0
	draw_set_transform(Vector2(size.x / 2.0 - 100.0 * unit, size.y / 2.0 - 100.0 * unit), 0, Vector2.ONE * unit)
	var shadow := Color("#101d25")
	var light := tint.lightened(0.3)
	draw_circle(Vector2(100, 100), 82, Color(tint, 0.055))
	match subject:
		"farmer":
			_poly([[66,113],[132,113],[145,168],[116,171],[103,148],[85,171],[56,166]],Color("#899b75"))
			_poly([[76,157],[95,157],[95,189],[79,189]],Color("#927453"))
			_poly([[108,157],[127,157],[124,189],[108,189]],Color("#927453"))
			draw_circle(Vector2(101,91),34,Color("#e5c8a2"))
			draw_circle(Vector2(91,96),3,Color("#485a50"))
			draw_circle(Vector2(113,96),3,Color("#485a50"))
			draw_style_box(ExpeditionUI.style(Color("#ead7a4"),Color.TRANSPARENT,14,0),Rect2(52,60,97,21))
			draw_style_box(ExpeditionUI.style(Color("#dfc795"),Color.TRANSPARENT,13,0),Rect2(72,34,58,40))
			draw_line(Vector2(74,65),Vector2(128,65),Color("#ad8163"),6)
		"ore":
			_poly([[33, 144], [51, 82], [87, 63], [110, 81], [142, 69], [171, 119], [151, 158], [69, 169]], tint)
			_poly([[51, 82], [87, 63], [110, 81], [101, 122], [64, 131]], light)
			_poly([[111, 94], [142, 69], [171, 119], [139, 137]], tint.lightened(0.15))
		"fiber":
			for i in range(7):
				draw_arc(Vector2(71 + i * 9, 104), 42 - i * 2, -1.5, 1.9, 24, tint.lightened(i * 0.025), 8, true)
			draw_line(Vector2(80, 64), Vector2(116, 151), Color("#80634c"), 9, true)
		"bandage":
			draw_style_box(ExpeditionUI.style(Color("#e0d6be"), tint, 14, 0), Rect2(44, 59, 111, 92))
			for x in [67, 85, 103, 121]:
				draw_line(Vector2(x, 64), Vector2(x + 12, 147), Color("#b3af9b"), 2, true)
			draw_circle(Vector2(100, 104), 25, tint)
			draw_line(Vector2(100, 89), Vector2(100, 119), Color("#f6e9c8"), 8)
			draw_line(Vector2(85, 104), Vector2(115, 104), Color("#f6e9c8"), 8)
		"seed":
			draw_style_box(ExpeditionUI.style(Color("#977957"), Color("#cbb082"), 8, 0), Rect2(51, 65, 99, 102))
			draw_line(Vector2(53, 78), Vector2(149, 78), Color("#dfc393"), 5)
			draw_line(Vector2(100, 143), Vector2(100, 102), tint, 6, true)
			_poly([[100, 122], [72, 115], [70, 96], [89, 100], [100, 113]], light)
			_poly([[100, 111], [113, 87], [132, 85], [126, 109], [100, 124]], tint)
		"relic":
			_poly([[57, 151], [69, 124], [70, 67], [100, 36], [134, 70], [131, 125], [148, 151], [142, 167], [58, 167]], Color("#ad8c57"))
			_poly([[100, 36], [134, 70], [131, 125], [100, 140]], light)
			draw_circle(Vector2(101, 89), 13, tint.darkened(0.3))
			draw_line(Vector2(70, 148), Vector2(134, 148), light, 5)
		"tools":
			draw_line(Vector2(60, 159), Vector2(128, 52), Color("#a08261"), 16, true)
			draw_polyline(PackedVector2Array([Vector2(65, 59), Vector2(109, 36), Vector2(143, 58), Vector2(163, 91)]), tint, 17, true)
		"attack":
			_poly([[70, 125], [134, 35], [156, 28], [154, 54], [89, 140]], light)
			_poly([[78, 129], [148, 37], [89, 140]], tint)
			draw_line(Vector2(54, 114), Vector2(102, 154), Color("#b48553"), 12, true)
			draw_line(Vector2(77, 137), Vector2(51, 166), Color("#765747"), 15, true)
			draw_circle(Vector2(48, 167), 9, Color("#dcb777"))
		"shield":
			_poly([[100, 30], [156, 54], [150, 119], [130, 152], [100, 173], [70, 152], [50, 119], [44, 54]], tint)
			_poly([[100, 42], [144, 63], [139, 115], [123, 142], [100, 157]], light)
			draw_line(Vector2(100, 65), Vector2(100, 138), shadow, 6, true)
			draw_line(Vector2(70, 95), Vector2(130, 95), shadow, 6, true)
		"heal":
			_poly([[80, 29], [120, 29], [120, 70], [149, 103], [149, 151], [136, 167], [64, 167], [51, 151], [51, 103], [80, 70]], light)
			_poly([[60, 113], [140, 113], [140, 150], [132, 157], [68, 157], [60, 150]], tint)
			draw_rect(Rect2(76, 25, 48, 15), Color("#aa835b"))
			draw_line(Vector2(100, 120), Vector2(100, 150), Color("#f6e9c8"), 9)
			draw_line(Vector2(85, 135), Vector2(115, 135), Color("#f6e9c8"), 9)
		"draw", "cargo":
			for i in range(3):
				draw_style_box(ExpeditionUI.style(tint.darkened(0.15 * i), light, 8, 0), Rect2(44 + i * 18, 39 + i * 13, 78, 105))
			_poly([[121, 82], [138, 108], [121, 133], [104, 108]], light)
		"chest":
			draw_style_box(ExpeditionUI.style(Color("#95704b"), Color("#dfb67a"), 9, 0), Rect2(36, 67, 128, 96))
			draw_line(Vector2(38, 106), Vector2(162, 106), shadow, 6)
			draw_rect(Rect2(91, 96, 18, 28), light)
			for x in [56, 138]:
				draw_line(Vector2(x, 70), Vector2(x, 160), Color("#dfb67a"), 6)
		"exit", "rest", "start":
			_poly([[100, 24], [128, 49], [157, 163], [43, 163], [72, 49]], Color("#32474c"))
			_poly([[93, 70], [122, 90], [131, 156], [68, 156]], tint)
			if subject == "exit":
				_poly([[93, 70], [122, 90], [131, 156], [68, 156]], Color("#e1e4bc"))
				_poly([[68,156],[131,156],[172,198],[24,198]],Color("#d9e1b6",0.22))
			draw_line(Vector2(100, 89), Vector2(100, 144), light, 5)
			draw_line(Vector2(100, 89), Vector2(83, 111), light, 5)
			draw_line(Vector2(100, 89), Vector2(117, 111), light, 5)
		"slime":
			draw_ellipse_shadow()
			_poly([[33, 149], [37, 110], [59, 82], [87, 78], [109, 59], [137, 70], [154, 98], [171, 148], [155, 163], [57, 165]], Color("#72a791"))
			_poly([[37, 110], [59, 82], [87, 78], [109, 59], [137, 70], [105, 90], [76, 94], [57, 115]], Color("#a3ccb2"))
			_eyes(85, 117, 121, 113)
			draw_arc(Vector2(105, 133), 9, 0.2, 2.8, 12, shadow, 3, true)
		"cave_bat", "deep_bat", "void_moth":
			draw_ellipse_shadow()
			_poly([[89, 98], [64, 63], [12, 40], [24, 100], [43, 92], [53, 121], [75, 111], [92, 136]], Color("#8b87b3"))
			_poly([[111, 98], [136, 63], [188, 40], [176, 100], [157, 92], [147, 121], [125, 111], [108, 136]], Color("#8b87b3"))
			_poly([[89, 76], [79, 54], [98, 67], [114, 53], [117, 80], [128, 112], [119, 147], [100, 158], [81, 145], [73, 115]], Color("#bbb0d0"))
			_eyes(91, 103, 112, 103)
			_poly([[92, 122], [98, 132], [102, 122], [107, 132], [112, 122]], Color("#fff1cf"))
		"rock_crab", "crystal_spider", "vein_crawler":
			draw_ellipse_shadow()
			for side in [-1, 1]:
				for i in range(3):
					draw_polyline(PackedVector2Array([Vector2(100 + side * 40, 103 + i * 14), Vector2(100 + side * 69, 110 + i * 15), Vector2(100 + side * 80, 131 + i * 13)]), Color("#a58e76"), 7, true)
			_poly([[53, 124], [63, 85], [88, 60], [122, 63], [151, 93], [149, 135], [110, 151], [72, 145]], Color("#8d9c9e"))
			_poly([[63, 85], [88, 60], [122, 63], [116, 101], [81, 109]], Color("#c2cbbe"))
			_eyes(86, 123, 119, 122)
			if subject != "rock_crab":
				_poly([[89, 84], [99, 36], [118, 61], [114, 93]], Color("#9fddd3"))
		"ore_golem", "prism_golem", "root_guardian", "crystal_tyrant":
			draw_ellipse_shadow()
			_poly([[47, 75], [78, 59], [131, 60], [156, 77], [175, 133], [150, 149], [138, 112], [129, 167], [106, 170], [100, 137], [89, 169], [65, 165], [63, 112], [46, 143], [26, 129]], Color("#839a91"))
			_poly([[75, 31], [111, 21], [134, 41], [130, 73], [82, 76], [66, 56]], Color("#b6c5b1"))
			_eyes(88, 52, 116, 50)
			_poly([[98, 89], [115, 109], [100, 128], [85, 110]], Color("#e0bd7b") if subject == "root_guardian" else Color("#9cddd7"))
			if subject in ["crystal_tyrant", "prism_golem"]:
				_poly([[55, 78], [47, 25], [72, 63]], Color("#9cddd7"))
				_poly([[137, 68], [159, 18], [164, 82]], Color("#9cddd7"))
		_:
			_poly([[100, 22], [149, 81], [139, 140], [100, 178], [62, 140], [51, 81]], tint)
			_poly([[100, 22], [100, 178], [62, 140], [51, 81]], light)
			draw_polyline(PackedVector2Array([Vector2(51, 81), Vector2(100, 104), Vector2(149, 81)]), Color("#ecf2cf"), 2, true)

func _eyes(x1: float, y1: float, x2: float, y2: float) -> void:
	for point in [Vector2(x1, y1), Vector2(x2, y2)]:
		draw_circle(point, 6, Color("#14262a"))
		draw_circle(point + Vector2(-1, -2), 2, Color("#f5e8c9"))

func draw_ellipse_shadow() -> void:
	var unit := minf(size.x, size.y) / 200.0
	draw_set_transform(Vector2(size.x / 2.0 - 100 * unit, size.y / 2.0 - 100 * unit), 0, Vector2.ONE * unit)
	var points := PackedVector2Array()
	for i in range(32):
		var angle := TAU * i / 32.0
		points.append(Vector2(100 + cos(angle) * 65, 168 + sin(angle) * 9))
	draw_colored_polygon(points, Color("#0e1a20"))

func _draw_cave() -> void:
	var iron := layer_id == "iron_root_deeps"
	var crystal := layer_id == "crystal_vein_deeps"
	var base := Color("#201e29") if crystal else (Color("#272922") if iron else Color("#162b2a"))
	var rock := Color("#3c3850") if crystal else (Color("#454333") if iron else Color("#30443b"))
	draw_rect(Rect2(Vector2.ZERO, size), base)
	var w := size.x
	var h := size.y
	_poly([[0, 0], [w, 0], [w, h * 0.8], [w * 0.84, h * 0.59], [w * 0.75, h * 0.18], [w * 0.59, h * 0.1], [w * 0.45, h * 0.23], [w * 0.25, h * 0.18], [w * 0.12, h * 0.54], [0, h * 0.76]], rock.darkened(0.25))
	_poly([[0, 0], [w * 0.22, 0], [w * 0.16, h * 0.16], [w * 0.18, h * 0.28], [w * 0.1, h * 0.64], [0, h * 0.8]], Color("#20363c"))
	_poly([[w, 0], [w * 0.82, 0], [w * 0.87, h * 0.27], [w * 0.84, h * 0.51], [w * 0.92, h * 0.68], [w, h * 0.75]], Color("#21353a"))
	for i in range(18):
		var point := Vector2(w * (0.12 + fmod(i * 0.173, 0.79)), h * (0.2 + fmod(i * 0.137, 0.5)))
		draw_circle(point, 2 if i % 3 == 0 else 1, Color("#789783", 0.38))
	_poly([[0, h], [0, h * 0.87], [w * 0.27, h * 0.73], [w * 0.58, h * 0.79], [w, h * 0.69], [w, h]], Color("#17272d"))
	for i in range(7):
		var x := w*(0.08+i*0.14)
		if crystal:
			_poly([[x,h*0.79],[x+12,h*0.61],[x+24,h*0.72],[x+32,h*0.80]],Color("#9ba1c7",0.42))
		elif iron:
			draw_polyline(PackedVector2Array([Vector2(x,0),Vector2(x+18,h*0.18),Vector2(x+8,h*0.35)]),Color("#8b775b",0.25),maxf(3,w*0.006),true)
		else:
			_poly([[x,h*0.78],[x+20,h*0.72],[x+43,h*0.79],[x+23,h*0.82]],Color("#68895b",0.32))
	for x in [w * 0.06, w * 0.94]:
		for radius in [55, 35, 18]:
			draw_circle(Vector2(x, h * 0.49), radius, Color("#e5bd78", 0.025))
		draw_line(Vector2(x, h * 0.49), Vector2(x, h * 0.56), Color("#8b7052"), 5)
		draw_circle(Vector2(x, h * 0.48), 5, Color("#e5bd78"))
