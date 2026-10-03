class_name ExpeditionRoute
extends Control
## 路线连线取自现有规则：相邻排全连通；只有下一排可进入。

signal node_selected(row: int, col: int)
var run: Dictionary = {}
var buttons: Array[Button] = []

func _ready() -> void:
	custom_minimum_size = Vector2(340, 360)
	resized.connect(_layout)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func display(snapshot: Dictionary) -> void:
	run = snapshot
	ExpeditionUI.clear(self)
	buttons.clear()
	var rows: Array = run.get("map", {}).get("rows", [])
	var current: Dictionary = run.get("current", {})
	var current_row := int(current.get("row", 0))
	for row in range(rows.size()):
		for col in range(rows[row].size()):
			var node: Dictionary = rows[row][col]
			var type := str(node["type"])
			var button := ExpeditionUI.button(ExpeditionDefs.NODE_TYPE_DISPLAY.get(type, "?"))
			button.name = "Route_%d_%d" % [row, col]
			button.set_meta("row", row)
			button.set_meta("col", col)
			button.add_theme_font_size_override("font_size", 13)
			button.custom_minimum_size = Vector2(90, 38)
			var here := row == current_row and col == int(current.get("col", 0))
			var completed := bool(run.get("resolved", {}).get("r%dc%d" % [row, col], {}).get("completed", false))
			button.disabled = row != current_row + 1 or str(run.get("phase", "")) != "map"
			button.text = ("◆ " if here else ("✓ " if completed else "")) + button.text
			var border := ExpeditionUI.RED if str(node.get("risk", "")) == "high" else ExpeditionUI.LINE
			button.add_theme_stylebox_override("normal", ExpeditionUI.style(Color("#29474d"), ExpeditionUI.GOLD, 18, 6))
			button.add_theme_stylebox_override("disabled", ExpeditionUI.style(Color("#3c5351") if here else Color("#1c2c34"), ExpeditionUI.GOLD if here else border, 18, 6))
			button.tooltip_text = "%s · %s" % [risk_text(str(node.get("risk", "none"))), str(node.get("hint", ""))]
			button.pressed.connect(func() -> void: node_selected.emit(row, col))
			buttons.append(button)
			add_child(button)
	_layout()

static func risk_text(risk: String) -> String:
	return {"none": "无战斗风险", "low": "低风险", "normal": "普通风险", "mid": "中等风险", "high": "高风险"}.get(risk, "未知风险")

func _point(row: int, col: int) -> Vector2:
	var rows: Array = run.get("map", {}).get("rows", [])
	var count: int = rows[row].size()
	var x := size.x * (col + 1.0) / (count + 1.0)
	return Vector2(x, size.y - (row + 0.5) * size.y / maxi(1, rows.size()))

func _layout() -> void:
	for button in buttons:
		button.size = Vector2(96, minf(48, size.y / 9.0 - 6))
		button.position = _point(int(button.get_meta("row")), int(button.get_meta("col"))) - button.size / 2
	queue_redraw()

func _draw() -> void:
	if run.is_empty():
		return
	var rows: Array = run.get("map", {}).get("rows", [])
	var current_row := int(run.get("current", {}).get("row", 0))
	for row in range(rows.size() - 1):
		for col in range(rows[row].size()):
			for next_col in range(rows[row + 1].size()):
				var from := _point(row, col)
				var to := _point(row + 1, next_col)
				var color := Color("#48606966")
				if row == current_row and col == int(run["current"]["col"]):
					color = Color("#e5bd7899")
				draw_dashed_line(from, to, color, 1.5, 5, true)
