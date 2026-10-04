class_name ExpeditionSettlement
extends RefCounted
## Display a receipt only. Applying inventory remains the domain/server transaction's responsibility.
static func build(receipt: Dictionary, applied: bool, done: Callable) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	var title: String = {"extract":"带着收获回来了","gate_clear":"探险完成","death":"这次没能走到出口","abandon":"本次探险已结束"}.get(str(receipt.get("kind","")),"探险结算")
	column.add_child(_label(title,28,ExpeditionUI.TEXT))
	column.add_child(_label("已入农场仓库" if applied else "结算单已收到 · 等待农场快照确认",18,ExpeditionUI.GOLD))
	for group in [["returned","带入物品 · 已带回"],["gained","本次新收获"],["protected","保险箱保护"],["lost","遗失"],["consumed","已消耗补给"]]:
		var entries: Array = receipt.get(group[0],[])
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel",LifeUI.style(Color("#f0efde"),LifeUI.LINE,12))
		column.add_child(card)
		var detail := VBoxContainer.new()
		card.add_child(detail)
		detail.add_child(_label("%s · %d 件" % [group[1],entries.size()],20,Color("#a56855") if group[0]=="lost" else LifeUI.INK))
		var names: Array[String] = []
		for entry in entries:
			if entry is Dictionary:
				names.append(str(entry.get("name",ItemDefs.get_item(str(entry.get("def_id",""))).get("name","物品"))))
		if not names.is_empty():
			var line := _label("、".join(names),18,LifeUI.INK)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			detail.add_child(line)
	var note := _label("货物回仓库后可以整理、出售；物品不会自动变成金币。",18,ExpeditionUI.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	var button := Button.new()
	button.text = "回洞口营地 · 整理收获"
	button.name = "SettlementReturnToCamp"
	button.theme = LifeUI.make_theme()
	button.pressed.connect(done)
	column.add_child(button)
	return column

static func _label(content: String, font_size: int, ink: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",ink)
	return label
