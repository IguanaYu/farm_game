extends SceneTree
## 实机与资源设计板：新主角、六张角色动作卡、小窗口和动作复制。

const OUT := "res://screenshots/gingham_forest_heroine"
const CARDS := "res://assets/art_studies/cute_adventurer_v03/"
var checks := 0
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("CUTE_HERO_FAIL: " + message)

func _frames(count := 6) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT.path_join(name + ".png"))

func _art_board(star_variant := false) -> Control:
	var board := Control.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.theme = ExpeditionUI.make_theme()
	var paper := ColorRect.new()
	paper.color = Color("#f1eadf")
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.add_child(paper)
	var title := ExpeditionUI.label("星星小姐姐" if star_variant else "红格帽小姐姐", 38, Color("#506353"))
	title.position = Vector2(54, 37)
	board.add_child(title)
	var subtitle := ExpeditionUI.label("深色卷发、薄刘海、米白开衫 · 星星发饰造型" if star_variant else "红白格宽檐帽、小黑蝴蝶结、长卷发 · 同一位主角的新造型", 18, Color("#75836c"))
	subtitle.position = Vector2(56, 89)
	board.add_child(subtitle)
	var portrait := ExpeditionArt.new()
	portrait.subject = "farmer"
	portrait.position = Vector2(40, 168)
	portrait.size = Vector2(350, 350)
	if star_variant:
		portrait._texture_key = portrait.subject + ":" + portrait.layer_id
		portrait._art_texture = load("res://assets/characters/farmer_star.svg") as Texture2D
	board.add_child(portrait)
	var caption := ExpeditionUI.label("粉白星星发饰、深色齐肩卷发\n米白开衫、小吊坠、浅绿裙装" if star_variant else "红白格帽、黑蝴蝶结、深色卷发\n灰蓝上衣、深色领口、编织背带", 20, Color("#75836c"))
	caption.position = Vector2(63, 568)
	board.add_child(caption)
	var index := 0
	for id in ForestCardStudyCombat.CARDS:
		var x := 433 + (index % 3) * 263
		var y := 155 + (index / 3) * 281
		var art := ExpeditionArt.new()
		art.subject = "card." + str(id)
		art.position = Vector2(x, y)
		art.size = Vector2(240, 150)
		art._texture_key = art.subject + ":" + art.layer_id
		art._art_texture = load(CARDS + ("star/" if star_variant else "") + str(id) + ".svg") as Texture2D
		board.add_child(art)
		var definition: Dictionary = ForestCardStudyCombat.CARDS[id]
		var label := ExpeditionUI.label(str(definition["name"]), 23, Color("#506353"))
		label.position = Vector2(x, y + 165)
		board.add_child(label)
		var effect := ExpeditionUI.label(CardPresentation.effect_text(definition), 16, Color("#75836c"))
		effect.position = Vector2(x, y + 202)
		board.add_child(effect)
		index += 1
	return board

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var game := (load("res://scenes/forest_animation_playtest.tscn") as PackedScene).instantiate() as ForestPlaytest
	root.add_child(game)
	await _frames()
	var screen := game.battle
	var snapshot := screen.combat.state.duplicate(true)
	var farmer := screen._unit_art("p1")
	_check(farmer._resolve_texture() == load("res://assets/characters/farmer_cute.svg"), "实机主角使用新草帽形象")
	for button in screen.hand_row.get_children():
		for child in button.find_children("*", "Control", true, false):
			if child is ExpeditionArt:
				var key := child.subject.trim_prefix("card.") as String
				_check(child._resolve_texture() == load(CARDS + key + ".svg"), "卡面使用同一位新主角 " + key)
	await _shot("01_in_game")
	_check(screen.combat.state == snapshot, "更换插图不改变战斗状态")
	game.get_node("PlaytestStage").find_child("HeroAppearancePicker", true, false).item_selected.emit(1)
	_check(screen._unit_art("p1")._resolve_texture() == load("res://assets/characters/farmer_star.svg"), "可切换到上一张照片的星星造型")
	_check(screen.combat.state == snapshot, "切换造型不改变战斗")
	await _shot("05_star_alternative")
	for button in screen.hand_row.get_children():
		for child in button.find_children("*", "Control", true, false):
			if child is ExpeditionArt:
				_check(child._resolve_texture() == load(CARDS + "star/" + child.subject.trim_prefix("card.") + ".svg"), "星星造型卡面同步")
	game.get_node("PlaytestStage").find_child("HeroAppearancePicker", true, false).item_selected.emit(0)
	_check(screen._unit_art("p1")._resolve_texture() == load("res://assets/characters/farmer_cute.svg"), "切回红格帽")
	var motion := screen._animate_attack("p1", "e1")
	_check(motion.attacker._resolve_texture() == farmer._resolve_texture(), "攻击复制层延续新形象")
	screen._clear_feedback()
	_check(farmer.self_modulate.a == 1, "取消攻击恢复主角")
	screen._on_end_turn()
	await create_timer(1.0).timeout
	await _shot("02_next_hand")
	game.hide()
	var board := _art_board()
	root.add_child(board)
	await _shot("03_character_and_cards")
	board.queue_free()
	await _frames()
	board = _art_board(true)
	root.add_child(board)
	await _shot("06_star_character_and_cards")
	board.queue_free()
	await _frames()
	game.show()
	root.size = Vector2i(1024, 640)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	await _shot("04_small_window")
	_check(screen._unit_art("p1")._resolve_texture() != null, "小窗口主角纹理正常")
	game.queue_free()
	await _frames()
	print("CUTE_FOREST_HERO: %d checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
