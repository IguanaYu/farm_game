extends ForestPlaytest
## 单场景的纸片动作样稿；仍然消费真实卡牌试玩的裁定事件。

const STUDY := "res://assets/art_studies/forest_cohesion_v02/"
const CUTE_CARDS := "res://assets/art_studies/cute_adventurer_v03/"

class ContactShadows extends Control:
	var screen: BattleScreen
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		for target in screen.target_controls.values():
			var rect: Rect2 = target.get_global_rect()
			var unit := minf(rect.size.x, rect.size.y)
			var point := rect.get_center() - global_position + Vector2(0, unit * 0.445)
			draw_set_transform(point, 0, Vector2(unit * 0.27, unit * 0.045))
			draw_circle(Vector2.ZERO, 1, Color("#485a50", 0.24))
		draw_set_transform(Vector2.ZERO)

var shadows: ContactShadows
var appearance_picker: OptionButton
var star_appearance := false

func _begin_battle() -> void:
	super._begin_battle()
	if battle.combat == null:
		return
	var session := ForestCardStudyCombat.create_study(str(battle.combat.state["encounter_id"]), 20261021, expedition.run_inventory())
	for pile in ["hand", "draw_pile"]:
		for card in session.state["players"]["p1"][pile]:
			card["preview_source_name"] = ForestCardStudyCombat.SOURCES.get(str(card["card_id"]), "样稿牌组")
	battle.presentation_caption = "森林新卡样稿 · 敌人沿用样例规则"
	battle.open_run(session)

func _ready() -> void:
	super._ready()
	battle.presentation_refreshed.connect(_apply_study)
	shadows = ContactShadows.new()
	shadows.screen = battle
	shadows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	battle.battlefield.add_child(shadows)
	battle.battlefield.move_child(shadows, 0)
	appearance_picker = OptionButton.new()
	appearance_picker.name = "HeroAppearancePicker"
	appearance_picker.add_item("红格帽")
	appearance_picker.add_item("星星发饰")
	appearance_picker.custom_minimum_size.x = 136
	appearance_picker.item_selected.connect(_select_appearance)
	var top := battle.round_label.get_parent().get_parent()
	top.add_child(appearance_picker)
	top.move_child(appearance_picker, top.get_child_count() - 2)
	select_enemy(ChapterOneDefs.ENEMIES.keys().find("forest_goblin_archer"))
	_begin_battle()

func _select_appearance(index: int) -> void:
	battle._clear_feedback()
	star_appearance = index == 1
	appearance_picker.select(index)
	_apply_study()

func _battle_closed() -> void:
	super._battle_closed()
	_apply_study.call_deferred()

func _apply_study() -> void:
	for art in _art_nodes(self):
		if art.subject == "farmer":
			art._texture_key = art.subject + ":" + art.layer_id
			art._art_texture = load("res://assets/characters/farmer_star.svg" if star_appearance else "res://assets/characters/farmer_cute.svg") as Texture2D
			art.queue_redraw()
		if art.subject.begins_with("card.forest_"):
			var card_path := CUTE_CARDS + ("star/" if star_appearance else "") + art.subject.trim_prefix("card.") + ".svg"
			if ResourceLoader.exists(card_path):
				art._texture_key = art.subject + ":" + art.layer_id
				art._art_texture = load(card_path) as Texture2D
				art.queue_redraw()
		var filename: String = {"cave": "trail", "enemy.forest_goblin_archer": "goblin_archer", "item.copper_shortsword": "copper_sword"}.get(art.subject, "")
		if filename != "":
			art._texture_key = art.subject + ":" + art.layer_id
			art._art_texture = load(STUDY + filename + ".svg") as Texture2D
			art.queue_redraw()
	battle.battlefield_ground.hide()
	shadows.queue_redraw.call_deferred()

func _art_nodes(parent: Node) -> Array[ExpeditionArt]:
	var result: Array[ExpeditionArt] = []
	for child in parent.get_children():
		if child is ExpeditionArt:
			result.append(child)
		result.append_array(_art_nodes(child))
	return result
