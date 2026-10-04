class_name ExpeditionNodePreview
extends RefCounted
## Shared preview: reading/selecting a route never advances the local or authoritative run.
static func subject(node: Dictionary) -> String:
	var type := str(node.get("type","start"))
	var encounter := str(node.get("encounter",""))
	if CombatGame.ENCOUNTERS.has(encounter):
		var enemies: Array = CombatGame.ENCOUNTERS[encounter].get("enemies",[])
		if not enemies.is_empty():
			return str(enemies[0])
	return {"battle":"slime","elite":"ore_golem","gate":"ore_golem","gather":"ore","chest":"chest","rest_exit":"exit","exit":"exit","event":"relic"}.get(type,"start")

static func build(node: Dictionary, layer: String, caption: String, confirm: Callable) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	var art := ExpeditionArt.new()
	art.name = "NodeScene"
	art.subject = subject(node)
	art.layer_id = layer
	art.stage_scene = true
	art.tint = ExpeditionUI.RED if str(node.get("risk","")) == "high" else ExpeditionUI.GOLD
	art.custom_minimum_size = Vector2(300,210)
	column.add_child(art)
	column.add_child(ExpeditionUI.label("下一站 · %s" % ExpeditionDefs.NODE_TYPE_DISPLAY.get(str(node.get("type","start")),"洞口"),26))
	column.add_child(ExpeditionUI.label(ExpeditionRoute.risk_text(str(node.get("risk","none"))),18,art.tint))
	var hint := ExpeditionUI.label(str(node.get("hint","")),18,ExpeditionUI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var encounter := str(node.get("encounter",""))
	if CombatGame.ENCOUNTERS.has(encounter):
		var names: Array[String] = []
		for id in CombatGame.ENCOUNTERS[encounter]["enemies"]:
			names.append(str(CombatGame.ENEMIES[id]["name"]))
		var info := ExpeditionUI.label("可能遭遇："+"、".join(names),18,ExpeditionUI.MUTED)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(info)
	var button := ExpeditionUI.button(caption,true)
	button.name = "ConfirmRoute"
	button.pressed.connect(confirm)
	column.add_child(button)
	return column
