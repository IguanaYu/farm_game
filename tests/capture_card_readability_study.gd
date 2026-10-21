extends SceneTree
## 仅视觉样稿：三张构图、实际尺寸/灰度缩图与同一战斗状态的前后画面。

const OUT := "res://screenshots/card_readability_v04"
const ART := "res://assets/art_studies/card_readability_v04/"
const IDS := ["forest_shoot", "forest_guard_bell", "forest_smoke_screen"]
const NAMES := ["射击", "守护铃", "烟幕"]
const ROLES := ["攻击 · 向外发力", "防御 · 封闭屏障", "防御 · 烟团包覆"]
var game: ForestPlaytest
var checks := 0
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("CARD_READABILITY_FAIL: " + message)

func _frames(count := 6) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(OUT.path_join(name + ".png")) == OK, "保存 " + name)

func _label(parent: Control, text: String, at: Vector2, size: int, color := Color("#536154")) -> void:
	var label := ExpeditionUI.label(text, size, color)
	label.position = at
	parent.add_child(label)

func _image(parent: Control, path: String, at: Vector2, extent: Vector2) -> void:
	var image := TextureRect.new()
	image.texture = load(path) as Texture2D
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.position = at
	image.size = extent
	parent.add_child(image)

func _board(title: String, note: String) -> Control:
	var board := Control.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.theme = ExpeditionUI.make_theme()
	var paper := ColorRect.new()
	paper.color = Color("#f1eadf")
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.add_child(paper)
	_label(board, title, Vector2(56, 30), 34)
	_label(board, note, Vector2(58, 81), 18, Color("#798273"))
	return board

func _size_board() -> Control:
	var board := _board("卡面构图样稿", "箭矢 / 屏障 / 烟团：大图看表达，小图看能否认出用途")
	for i in range(3):
		var x := 60 + i * 450
		var color := Color("#a96549") if i == 0 else Color("#4e7b80")
		_label(board, NAMES[i], Vector2(x, 125), 28)
		_label(board, ROLES[i], Vector2(x + 126, 136), 17, color)
		_image(board, ART + IDS[i] + ".svg", Vector2(x, 182), Vector2(420, 262.5))
		_image(board, ART + IDS[i] + ".svg", Vector2(x + 148, 506), Vector2(128, 80))
		_image(board, ART + IDS[i] + ".svg", Vector2(x + 115, 657), Vector2(64, 40))
		_image(board, ART + "sketches/" + IDS[i] + "_a.svg", Vector2(x + 241, 657), Vector2(64, 40))
		_label(board, "彩色", Vector2(x + 128, 711), 14)
		_label(board, "灰度", Vector2(x + 252, 711), 14)
	_label(board, "实际手牌图尺寸 · 128 × 80", Vector2(60, 468), 18, Color("#798273"))
	_label(board, "更小尺寸对照 · 64 × 40（无文字、无类型角标）", Vector2(60, 616), 18, Color("#798273"))
	_label(board, "先验证这三张；主角造型、卡牌费用和战斗效果保持现状。", Vector2(60, 783), 17, Color("#798273"))
	return board

func _composition_board() -> Control:
	var board := _board("灰度构图对照", "A：当前细化方案    B：另一种构图探索    ·    对照主体形状、方向与明暗")
	for i in range(3):
		var x := 60 + i * 450
		_label(board, NAMES[i], Vector2(x, 123), 27)
		_image(board, ART + "sketches/" + IDS[i] + "_a.svg", Vector2(x, 176), Vector2(420, 262.5))
		_label(board, "A · " + ["弓与离弦箭", "完整保护轮廓", "低处烟团包覆"][i], Vector2(x, 447), 18)
		_image(board, ART + "sketches/" + IDS[i] + "_b.svg", Vector2(x, 503), Vector2(420, 262.5))
		_label(board, "B · " + ["箭矢向近处冲出", "铃下展开保护罩", "前景烟墙"][i], Vector2(x, 779), 18)
	return board

func _apply() -> void:
	for art in game._art_nodes(game.battle):
		var id: String = art.subject.trim_prefix("card.")
		if IDS.has(id):
			art._texture_key = art.subject + ":" + art.layer_id
			art._art_texture = load(ART + id + ".svg") as Texture2D
			art.queue_redraw()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1440, 850)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	for id in IDS:
		for suffix in [".svg", "_a.svg", "_b.svg"]:
			var resource: String = ART + ("sketches/" if suffix != ".svg" else "") + id + suffix
			_check(ResourceLoader.exists(resource) and load(resource) is Texture2D, "可加载 " + resource)
		if DisplayServer.get_name() != "headless":
			var texture := load(ART + id + ".svg") as Texture2D
			_check(texture.get_image().save_png(OUT.path_join(id + ".png")) == OK, "导出独立卡图 " + id)
	var board := _size_board()
	root.add_child(board)
	await _shot("01_color_and_small_sizes")
	board.queue_free()
	await _frames()
	board = _composition_board()
	root.add_child(board)
	await _shot("02_grayscale_compositions")
	board.queue_free()
	await _frames()
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	game = (load("res://scenes/forest_animation_playtest.tscn") as PackedScene).instantiate() as ForestPlaytest
	root.add_child(game)
	await _shot("03_in_game_before")
	var before := game.battle.combat.state.duplicate(true)
	var original_hero := game.battle._unit_art("p1")._resolve_texture()
	_apply()
	await _shot("04_in_game_study")
	_check(game.battle.combat.state == before, "比较画面保持同一战斗状态")
	_check(game.battle._unit_art("p1")._resolve_texture() == original_hero, "主角外观保持现状")
	# 让真实刷新继续使用三张样稿；不改造任何牌的定义。
	game.battle.presentation_refreshed.connect(_apply)
	game.battle._on_end_turn()
	await _frames()
	root.size = Vector2i(1024, 640)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	await create_timer(1.0).timeout
	await _shot("05_small_window_study")
	_check(game.battle.combat.state["round"] == 2, "真实结束回合正常")
	game.queue_free()
	await _frames()
	print("CARD_READABILITY_STUDY: %d checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
