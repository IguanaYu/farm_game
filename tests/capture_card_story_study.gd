extends SceneTree
## 六张情境卡的当前运行版预览；规则和纹理与真实手牌共用，不访问玩家存档。

const ART := "res://assets/art_studies/card_story_v05/"
const OUT := "res://screenshots/card_story_v05/"
var cards: Array = []
var textures: Array[Texture2D] = []
var board: Control
var checks := 0
var failed := false
var ink := Color("#455b50")
var muted := Color("#7a8475")

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("CARD_STORY_FAIL: " + note)

func _label(parent: Control, value: String, at: Vector2, extent: Vector2, font_size: int, color := Color("#455b50")) -> Label:
	var node := Label.new()
	node.text = value
	node.position = at
	node.size = extent
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node

func _panel(parent: Control, at: Vector2, extent: Vector2, color: Color, border: Color, radius := 16) -> Panel:
	var node := Panel.new()
	node.position = at
	node.size = extent
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	node.add_theme_stylebox_override("panel", style)
	parent.add_child(node)
	return node

func _image(parent: Control, index: int, at: Vector2, extent: Vector2, gray := false) -> void:
	var node := TextureRect.new()
	node.texture = textures[index]
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.position = at
	node.size = extent
	if gray:
		var shader := Shader.new()
		shader.code = "shader_type canvas_item; void fragment(){vec4 c=texture(TEXTURE,UV); float y=dot(c.rgb,vec3(0.2126,0.7152,0.0722)); COLOR=vec4(vec3(y),c.a);}"
		var material := ShaderMaterial.new()
		material.shader = shader
		node.material = material
	parent.add_child(node)

func _new_board(extent: Vector2i, title: String, note: String) -> void:
	if is_instance_valid(board):
		root.remove_child(board)
		board.queue_free()
	root.size = extent
	root.content_scale_size = extent
	DisplayServer.window_set_size(extent)
	board = Control.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	theme.default_font = font
	board.theme = theme
	root.add_child(board)
	var bg := ColorRect.new()
	bg.color = Color("#f1eadf")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.add_child(bg)
	_label(board, title, Vector2(60, 28), Vector2(extent.x - 120, 54), 36)
	_label(board, note, Vector2(62, 88), Vector2(extent.x - 124, 35), 19, muted)

func _card(index: int, at: Vector2) -> void:
	var card: Dictionary = cards[index]
	var attack: bool = card.type == "attack"
	var accent := Color("#af7557") if attack else Color("#5c8991")
	var panel := _panel(board, at, Vector2(496, 476), Color("#fcf7ed"), accent)
	_label(panel, card.name, Vector2(20, 13), Vector2(420, 40), 26)
	_panel(panel, Vector2(438, 12), Vector2(40, 40), accent, accent, 20)
	var cost := _label(panel, str(int(card.cost)), Vector2(438, 12), Vector2(40, 40), 24, Color("#fff6df"))
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_image(panel, index, Vector2(16, 64), Vector2(464, 290))
	_label(panel, "攻击" if attack else "防御", Vector2(20, 369), Vector2(80, 30), 19, accent)
	var effect := CardPresentation.effect_text(card.definition)
	_label(panel, effect, Vector2(112, 367), Vector2(340, 34), 25)
	var hook := _label(panel, card.hook, Vector2(20, 413), Vector2(456, 48), 17, muted)
	hook.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _shot(name: String) -> void:
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.save_png(OUT + name + ".png") == OK, "save " + name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(ART + "manifest.json"))
	_check(manifest is Dictionary, "manifest parses")
	if not manifest is Dictionary:
		quit(1)
		return
	cards = manifest.cards
	_check(cards.size() == 6, "six cards")
	for card in cards:
		var definition: Dictionary = ForestCardStudyCombat.CARDS.get(card.id, {})
		_check(not definition.is_empty(), "runtime definition " + card.id)
		if definition.is_empty():
			quit(1)
			return
		card.name = definition.name
		card.cost = definition.cost
		card["definition"] = definition
		var texture := ChapterArtRegistry.texture(ChapterArtRegistry.card(card.id))
		_check(texture != null, "load " + card.id)
		if texture == null:
			quit(1)
			return
		textures.append(texture)
	_check(cards.filter(func(c): return c.type == "attack").size() == 4, "four attacks")
	_check(cards.filter(func(c): return c.type == "defense").size() == 2, "two defenses")
	_new_board(Vector2i(1680, 1180), "森林小冒险 · 六张情境卡", "4 张攻击（含 1 张攻防混合）/ 2 张防御  ·  当前运行数值  ·  敲壳、烟幕采用修订图")
	for i in range(6):
		_card(i, Vector2(60 + (i % 3) * 532, 146 + (i / 3) * 502))
	await _shot("01_six_cards")
	_new_board(Vector2i(1440, 950), "缩小之后，还认得出来吗？", "各格依次为：彩色 128×80 / 灰度 128×80 / 彩色 64×40  ·  图像均按标注尺寸呈现，识别效果需人工判断")
	for i in range(6):
		var x := 54 + (i % 3) * 456
		var y := 154 + (i / 3) * 366
		_label(board, cards[i].name, Vector2(x, y), Vector2(416, 36), 25)
		_image(board, i, Vector2(x, y + 58), Vector2(128, 80))
		_image(board, i, Vector2(x + 150, y + 58), Vector2(128, 80), true)
		_image(board, i, Vector2(x + 302, y + 78), Vector2(64, 40))
		_label(board, "128 × 80", Vector2(x + 18, y + 150), Vector2(130, 30), 16, muted)
		_label(board, "灰度", Vector2(x + 192, y + 150), Vector2(80, 30), 16, muted)
		_label(board, "64 × 40", Vector2(x + 300, y + 150), Vector2(100, 30), 16, muted)
		var hint := _label(board, cards[i].hook, Vector2(x, y + 212), Vector2(400, 70), 18)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	await _shot("02_thumbnail_and_grayscale")
	for i in range(6):
		_new_board(Vector2i(1280, 900), cards[i].name, cards[i].hook)
		_image(board, i, Vector2(48, 155), Vector2(1184, 740))
		await _shot("%02d_" % (i + 3) + cards[i].id)
	print("CARD_STORY_RESULT: %d checks; failed=%s; saved 8 previews" % [checks, failed])
	quit(1 if failed else 0)
