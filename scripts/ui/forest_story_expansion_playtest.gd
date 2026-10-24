extends "res://scripts/ui/forest_animation_playtest.gd"

var group_index := 0
var switch_group: Button

func _build() -> void:
	super._build()
	switch_group = ExpeditionUI.button("换组：铃火与冰光", true)
	switch_group.name = "ExpansionGroupButton"
	switch_group.pressed.connect(func() -> void:
		group_index = 1 - group_index
		_begin_battle())
	var choices := test_options.get_parent()
	choices.add_child(switch_group)
	choices.move_child(switch_group, 2)

func _begin_battle() -> void:
	super._begin_battle()
	if battle.combat == null:
		return
	var session := ForestStoryExpansionCombat.create_expansion(str(battle.combat.state["encounter_id"]), 20261024, expedition.run_inventory(), group_index)
	for pile in ["hand", "draw_pile"]:
		for card in session.state["players"]["p1"][pile]:
			var id := str(card["card_id"])
			card["preview_source_name"] = ForestStoryExpansionCombat.ADDITION_SOURCES.get(id, ForestCardStudyCombat.SOURCES.get(id, "样稿牌组"))
	battle.presentation_caption = "%s · 带伤样例 30/40" % ForestStoryExpansionCombat.GROUP_NAMES[group_index]
	battle.open_run(session)
	if switch_group != null:
		switch_group.text = "换组：" + str(ForestStoryExpansionCombat.GROUP_NAMES[1 - group_index])
