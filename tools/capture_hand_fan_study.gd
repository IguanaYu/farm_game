extends SceneTree
## 接入后复拍真实扇形布局；旧静态样稿保留在原目录供对照。

const OUT := "res://screenshots/hand_fan_live_2026-10-25/study_capture/"
var game: Control
var cards: Array[Control] = []
var failed := false
var shot_count := 0

func _initialize() -> void:
	_run.call_deferred()

func _frames(count := 8) -> void:
	for i in range(count):
		await process_frame

func _shot(filename: String) -> void:
	await _frames()
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(OUT + filename + ".png") != OK:
		failed = true
		push_error("HAND_FAN_STUDY: cannot save " + filename)
	else:
		shot_count += 1

func _start(extent: Vector2i, hand_count := 5) -> void:
	if is_instance_valid(game):
		root.remove_child(game)
		game.queue_free()
		await _frames(2)
	cards.clear()
	root.size = extent
	root.content_scale_size = extent
	DisplayServer.window_set_size(extent)
	game = (load("res://scenes/forest_story_expansion_playtest.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _frames(12)
	if hand_count > 5:
		# Build an isolated full-hand fixture through the existing draw API.
		game.battle.combat.draw_extra_for("p1", hand_count - 5)
		game.battle._refresh()
		await _frames()
		if game.battle.combat.state.players.p1.hand.size() != hand_count:
			failed = true
			push_error("HAND_FAN_STUDY: wrong fixture hand count")

func _fan(hover_index := -1) -> void:
	var screen: BattleScreen = game.battle
	if cards.is_empty():
		for card in screen.hand_row.get_children():
			cards.append(card)
	var motion := InputEventMouseMotion.new()
	motion.position = screen.hand_row.slot_point(cards[hover_index].card_uid, Vector2(23, 26)) if hover_index >= 0 else Vector2(10, 60)
	motion.global_position = motion.position
	root.push_input(motion, true)

func _check_state(before: Dictionary) -> void:
	if game.battle.combat.to_dict() != before:
		failed = true
		push_error("HAND_FAN_STUDY: layout changed combat state")
	for card in cards:
		for point in [Vector2.ZERO, Vector2(card.size.x, 0), card.size, Vector2(0, card.size.y)]:
			if not Rect2(Vector2.ZERO, Vector2(root.size)).has_point(card.get_global_transform() * point):
				failed = true
				push_error("HAND_FAN_STUDY: card corner outside window")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	if "--ten-only" in OS.get_cmdline_user_args():
		await _ten_card_study()
		print("HAND_FAN_STUDY: %s; %d screenshots; ten-card fixture; layout-only; combat unchanged after fixture" % [("FAIL" if failed else "PASS"), shot_count])
		quit(1 if failed else 0)
		return
	await _start(Vector2i(1280, 800))
	var before: Dictionary = game.battle.combat.to_dict().duplicate(true)
	await _shot("01_current_1280")
	_fan()
	await _shot("02_fan_1280")
	_check_state(before)
	_fan(1)
	await _shot("03_fan_hover_1280")
	_check_state(before)
	await _start(Vector2i(1024, 640))
	before = game.battle.combat.to_dict().duplicate(true)
	_fan()
	await _shot("04_fan_1024")
	_check_state(before)
	_fan(1)
	await _shot("05_fan_hover_1024")
	_check_state(before)
	game.queue_free()
	await _frames()
	print("HAND_FAN_STUDY: %s; 5 screenshots; layout-only; combat unchanged" % ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)

func _ten_card_study() -> void:
	for extent in [Vector2i(1280, 800), Vector2i(1024, 640)]:
		await _start(extent, 10)
		var before: Dictionary = game.battle.combat.to_dict().duplicate(true)
		var suffix := "1280" if extent.x == 1280 else "1024"
		_fan()
		await _shot("10_ten_fan_" + suffix)
		_check_state(before)
		_fan(4)
		await _shot("11_ten_hover_middle_" + suffix)
		_check_state(before)
		_fan(0)
		await _shot("12_ten_hover_left_" + suffix)
		_check_state(before)
		_fan(9)
		await _shot("13_ten_hover_right_" + suffix)
		_check_state(before)
	game.queue_free()
	await _frames()
