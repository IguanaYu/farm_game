class_name CoopClientPanel
extends Control
## 合作局·客机界面（2.6 最小可用版）。展示主机广播的局快照，把操作以意图发给主机裁定；
## 完整并排视图与快捷信号条在 2.8 表现层打磨。本面板 _process 泵网络。

signal close_requested

const FOREST := Color("#294f3c")
const CREAM := Color("#fff9ed")
const TEXT_DARK := Color("#35513d")
const TEXT_MUTED := Color("#788678")
const BAD_RED := Color("#a4543f")
const WARN_GOLD := Color("#9b713a")

var client: SessionClient
var status_label: Label
var state_label: Label
var log_label: RichTextLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var theme_root := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	theme_root.default_font = font
	theme_root.default_font_size = 15
	theme = theme_root
	_build()
	set_process(true)


func open(target_client: SessionClient) -> void:
	client = target_client
	client.run_received.connect(_on_run)
	client.action_result_received.connect(_on_result)
	client.settlement_received.connect(_on_settlement)
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _process(_delta: float) -> void:
	if client != null:
		client.poll()
		if visible:
			_refresh()


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.09, 0.13, 0.10, 0.9)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := _panel(Color("#20332a"), Color("#6f9b71"), 16)
	panel.custom_minimum_size = Vector2(760, 520)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(_label("合作探险（客机视角·最小界面）", 22, CREAM))
	state_label = _label("", 15, Color("#e8d9a8"))
	column.add_child(state_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var vote_button := _button("投票前进（下一排·列 0）", Color("#eaf4df"), Color("#87b06f"))
	vote_button.pressed.connect(func() -> void:
		var next_row := int(client.mirror_run.get("current", {}).get("row", 0)) + 1
		client.send_action("vote_move", {"row": next_row, "col": 0})
		_flash("已投票前进第 %d 排·列 0（需主机同票）。" % next_row))
	row.add_child(vote_button)
	var claim_button := _button("领取候选（入背包）", Color("#fff5df"), Color("#d5b87d"))
	claim_button.pressed.connect(_on_claim)
	row.add_child(claim_button)
	var extract_button := _button("投票撤离", Color("#ffd98a"), Color("#9b713a"))
	extract_button.pressed.connect(func() -> void:
		client.send_action("vote_extract", {"agree": true})
		_flash("已确认撤离（需主机也确认）。"))
	row.add_child(extract_button)
	var abandon_button := _button("个人放弃（损失未保护物）", Color("#f0d9cf"), Color("#a4543f"))
	abandon_button.pressed.connect(func() -> void:
		client.send_action("abandon_member", {}))
	row.add_child(abandon_button)
	status_label = _label("", 13, WARN_GOLD)
	column.add_child(status_label)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = false
	log_label.scroll_following = true
	log_label.custom_minimum_size = Vector2(0, 200)
	log_label.add_theme_font_size_override("normal_font_size", 13)
	log_label.add_theme_color_override("default_color", Color("#cfe2c2"))
	column.add_child(log_label)
	var close_button := _button("返回农场并暂停（局保留）", Color("#fff5df"), Color("#d5b87d"))
	close_button.pressed.connect(_on_close)
	column.add_child(close_button)


func _on_claim() -> void:
	## 客机领取：向主机请求当前节点的第一件候选（裁定与空间校验都在主机）。
	var current: Dictionary = client.mirror_run.get("current", {})
	var key := "r%dc%d" % [int(current.get("row", 0)), int(current.get("col", 0))]
	var resolved: Dictionary = (client.mirror_run.get("resolved", {}) as Dictionary).get(key, {})
	var rewards: Array = resolved.get("rewards", [])
	if rewards.is_empty():
		_flash("当前节点没有可领取的候选。")
		return
	client.send_action("claim_reward", {"def_id": str(rewards[0]), "container": "pack"})
	_flash("已请求领取 %s（主机裁定）。" % ItemDefs.get_item(str(rewards[0]))["name"])


func _on_result(action_id: String, result: Dictionary) -> void:
	if not bool(result.get("ok", true)):
		_flash("主机裁定：%s" % str(result.get("reason", "")))


func _on_settlement(settlement: Dictionary) -> void:
	_flash("结算已应用到你的农场：%s（%s）" % [str(settlement.get("kind", "")), str(settlement.get("settlement_id", ""))])


func _on_run(_run: Dictionary) -> void:
	_refresh()


func _refresh() -> void:
	if client == null:
		return
	var run: Dictionary = client.mirror_run
	if run.is_empty():
		state_label.text = "等待主机开局……"
		return
	var me: Dictionary = run.get("guest", {})
	state_label.text = "%s ｜ 第 %d/8 排 ｜ 你的生命 %d/40 ｜ 阶段：%s" % [
		ExpeditionDefs.layer(str(run.get("layer_id", ""))).get("name", "?"),
		int(run.get("current", {}).get("row", 0)),
		int(me.get("hp", 40)),
		_phase_text(str(run.get("phase", "")))]
	var entries: Array = run.get("log", [])
	log_label.text = "\n".join(entries.slice(maxi(0, entries.size() - 8), entries.size()))


func _phase_text(phase: String) -> String:
	match phase:
		"map":
			return "地图（投票选路）"
		"node":
			return "节点内（搜刮/事件/休整由主机推进）"
		"battle":
			return "战斗（出牌由主机界面或测试入口裁定）"
		"over":
			return "本局结束"
	return phase


func _flash(message: String) -> void:
	status_label.text = message


func _on_close() -> void:
	close_requested.emit()


func _panel(fill: Color, border: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _label(content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(content: String, fill: Color, border: Color) -> Button:
	var button := Button.new()
	button.text = content
	button.add_theme_font_size_override("font_size", 14)
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 8
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	return button
