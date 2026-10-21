extends SceneTree
## 单场景、同一战斗快照的风格校准；不覆盖正式资源，不改战斗规则。

const STUDY := "res://assets/art_studies/forest_cohesion_v02/"
const OUT := "res://screenshots/forest_style_study_v02"

class ContactShadows extends Control:
	var battle: BattleScreen
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		for target in battle.target_controls.values():
			var rect: Rect2 = target.get_global_rect()
			var unit := minf(rect.size.x, rect.size.y)
			var point := rect.get_center() - global_position + Vector2(0, unit * 0.445)
			draw_set_transform(point, 0, Vector2(unit * 0.27, unit * 0.045))
			draw_circle(Vector2.ZERO, 1, Color("#485a50", 0.24))
		draw_set_transform(Vector2.ZERO)

func _initialize() -> void:
	_run.call_deferred()

func _frames() -> void:
	for i in range(8):
		await process_frame

func _replace(art: ExpeditionArt, filename: String) -> void:
	art._texture_key = art.subject + ":" + art.layer_id
	art._art_texture = load(STUDY + filename + ".svg") as Texture2D
	assert(art._art_texture != null)
	art.queue_redraw()

func _shot(name: String) -> void:
	await _frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	assert(root.get_texture().get_image().save_png(OUT.path_join(name + ".png")) == OK)

func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	var game := (load("res://scenes/forest_playtest.tscn") as PackedScene).instantiate() as ForestPlaytest
	root.add_child(game)
	game.select_enemy(ChapterOneDefs.ENEMIES.keys().find("forest_goblin_archer"))
	game._begin_battle()
	await _shot("01_before")
	var snapshot: Dictionary = game.battle.combat.state.duplicate(true)
	_replace(game.battle.find_child("CaveBackdrop", true, false), "trail")
	for art in _art_nodes(game.battle):
		if art.subject == "enemy.forest_goblin_archer":
			_replace(art, "goblin_archer")
		elif art.subject == "item.copper_shortsword":
			_replace(art, "copper_sword")
	game.battle.battlefield_ground.hide()
	var shadows := ContactShadows.new()
	shadows.battle = game.battle
	shadows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.battle.battlefield.add_child(shadows)
	game.battle.battlefield.move_child(shadows, 0)
	await _shot("02_unified_study")
	assert(game.battle.combat.state == snapshot)
	game.queue_free()
	await _frames()
	print("FOREST_STYLE_STUDY_PASS: same combat state, original farmer and UI preserved")
	quit()

func _art_nodes(parent: Node) -> Array[ExpeditionArt]:
	var result: Array[ExpeditionArt] = []
	for child in parent.get_children():
		if child is ExpeditionArt:
			result.append(child)
		result.append_array(_art_nodes(child))
	return result
