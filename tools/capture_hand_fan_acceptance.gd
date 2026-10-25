extends "res://tests/hand_fan_smoke.gd"
## 正式控件验收截图：通过真实输入切换状态，不手工改动牌面变换。

const CAPTURE_OUT := "res://screenshots/hand_fan_acceptance_2026-10-25/"
var forest: Control
var captures: Array[Dictionary] = []

func _resize_to(extent: Vector2i) -> void:
	root.size = extent
	root.content_scale_size = extent
	DisplayServer.window_set_size(extent)
	await _frames(12)

func _fresh(count := 5) -> void:
	forest._begin_battle()
	await _frames(12)
	if count > 5:
		screen.combat.draw_extra_for("p1", count - 5)
		screen._refresh()
		await _frames(12)
	await _move(Vector2(10, 60))

func _capture(filename: String, title: String, note: String) -> void:
	await _move(mouse_at, 1, root.gui_is_dragging())
	_bounds()
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(CAPTURE_OUT + filename + ".png") == OK, "截图保存 " + filename)
	var player: Dictionary = screen.combat.state.players[screen.player_key]
	captures.append({"file": filename + ".png", "title": title, "note": note, "width": root.size.x, "height": root.size.y,
		"actor": screen.player_key, "hand": player.hand.size(), "energy": player.energy,
		"selected_uid": screen.selected_uid, "hovered_uid": screen.hovered_uid,
		"dragging": root.gui_is_dragging(), "pending": screen.pending_action})

func _play_first() -> void:
	var player: Dictionary = screen.combat.state.players[screen.player_key]
	var card: Dictionary = player.hand[0]
	var uid := int(card.uid)
	var definition := screen._card_definition(str(card.card_id))
	var button := screen.hand_row.get_node("Card_%d" % uid) as BattleScreen.CardButton
	await _move(Vector2(10, 60))
	await _click(screen.hand_row.slot_point(uid, Vector2(23, 26)))
	if screen.selected_uid >= 0:
		var target := "e1" if str(definition.target) == "enemy" else screen.player_key
		await _click(screen.target_controls[target].get_global_rect().get_center())
	await _frames(70)
	_check(screen._hand_card(uid).is_empty() and not is_instance_valid(button), "真实出牌后原牌离手")
	await _move(Vector2(10, 60))

func _overview() -> void:
	forest.hide()
	await _resize_to(Vector2i(1640, 1780))
	var board := Control.new()
	board.theme = ExpeditionUI.make_theme()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(board)
	var background := ColorRect.new()
	background.color = Color("#eeeadf")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.add_child(background)
	var title := ExpeditionUI.label("扇形手牌 · 实机验收截图", 36, Color("#405649"))
	title.position = Vector2(40, 24)
	board.add_child(title)
	var subtitle := ExpeditionUI.label("2026-10-25  /  正式控件与真实输入  /  原图见编号文件", 20, Color("#727a6c"))
	subtitle.position = Vector2(43, 80)
	board.add_child(subtitle)
	var selected := [1, 2, 5, 6, 11, 17]
	for i in range(selected.size()):
		var record: Dictionary = captures[selected[i]]
		var at := Vector2(40 + (i % 2) * 800, 165 + (i / 2) * 530)
		var caption := ExpeditionUI.label(record.title + "  ·  %d×%d" % [record.width, record.height], 21, Color("#405649"))
		caption.position = at - Vector2(0, 35)
		board.add_child(caption)
		var rect := TextureRect.new()
		rect.texture = ImageTexture.create_from_image(Image.load_from_file(CAPTURE_OUT + str(record.file)))
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.position = at
		rect.size = Vector2(760, 475)
		board.add_child(rect)
	var footer := ExpeditionUI.label("总览为原始截图的缩略排版；单张 PNG 保留原始分辨率。", 18, Color("#727a6c"))
	footer.position = Vector2(42, 1732)
	board.add_child(footer)
	await _frames()
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(CAPTURE_OUT + "00_overview.png") == OK, "保存截图总览")
	board.queue_free()

func _write_index() -> void:
	var lines := PackedStringArray([
		"# 扇形手牌验收截图", "", "2026-10-25。18 张原始实机截图，另附 1 张总览。", "",
		"使用正式 BattleScreen / HandFan，通过真实鼠标和键盘输入切换状态；保留原始分辨率，不手动重排卡牌或修饰画面。十张满手通过独立试玩额外抽五张构造；空手牌与合作等待使用独立内存用例，合作图展示模拟等待界面。", "",
		"![截图总览](00_overview.png)", "", "| 截图 | 分辨率 | 验收观察 |", "| --- | --- | --- |"
	])
	for record in captures:
		lines.append("| [%s](%s) | %d×%d | %s |" % [record.title, record.file, record.width, record.height, record.note])
	lines.append("")
	lines.append("运行：Godot 4.6.1，OpenGL compatibility；脚本 tools/capture_hand_fan_acceptance.gd。运行结果和逐图状态摘要见 capture_result.json。")
	var index := FileAccess.open(CAPTURE_OUT + "README.md", FileAccess.WRITE)
	index.store_string("\n".join(lines) + "\n")
	var manifest := FileAccess.open(CAPTURE_OUT + "capture_result.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"passed": not failed, "checks": checks, "screenshots": captures}, "\t") + "\n")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("验收截图需要图形渲染，不使用 headless")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_OUT))
	var saved_motion := SettingsStore.get_reduce_motion()
	SettingsStore.set_reduce_motion(false)
	await _resize_to(Vector2i(1280, 800))
	forest = (load("res://scenes/forest_story_expansion_playtest.tscn") as PackedScene).instantiate()
	root.add_child(forest)
	await _frames(16)
	screen = forest.battle
	await _fresh()
	await _capture("01_five_1280", "01 · 五张常态", "浅扇形、能量在左、牌堆与结束回合保持可见")
	await _fresh(10)
	var snapshot := screen.combat.to_dict().duplicate(true)
	await _capture("02_ten_1280", "02 · 十张满手", "十张同时在屏内，费用区域逐张露出，无横向滚动")
	await _hover(screen.hand_row.cards[4])
	await _capture("03_hover_middle_1280", "03 · 中部抬牌", "抬高、放大、转正，邻牌让位")
	await _hover(screen.hand_row.cards[0])
	await _capture("04_hover_left_1280", "04 · 最左抬牌", "左端卡面完整，牌堆按钮仍可见")
	await _hover(screen.hand_row.cards[9])
	await _capture("05_hover_right_1280", "05 · 最右抬牌", "右端卡面完整，结束回合仍可见")
	_check(screen.combat.to_dict() == snapshot, "常态与三处悬停不改变战斗")
	await _move(Vector2(10, 60))
	var uid := int(screen.combat.state.players.p1.hand[0].uid)
	await _click(screen.hand_row.slot_point(uid, Vector2(23, 26)))
	await _move(screen.target_controls.e1.get_global_rect().get_center())
	_check(screen.selected_uid == uid and screen.combat.to_dict() == snapshot, "选中与目标预览尚未结算")
	await _capture("06_target_preview_1280", "06 · 选择目标", "所选牌保持抬起，目标高亮与效果预览可见")
	await _click(mouse_at, MOUSE_BUTTON_RIGHT)
	await _move(screen.hand_row.slot_point(uid, Vector2(23, 26)))
	await _mouse_button(true)
	await _move(Vector2(1010, 420), 12, true)
	_check(root.gui_is_dragging(), "完整卡面拖放已启动")
	var drag_art := root.find_child("CardDragArt", true, false) as TextureRect
	_check(drag_art != null and drag_art.texture == ChapterArtRegistry.texture(ChapterArtRegistry.card("forest_throw_net")), "拖放预览保留原卡插图")
	await _capture("07_dragging_1280", "07 · 拖放过程", "完整卡面跟随鼠标，手中原牌淡化并保留槽位")
	await _move(screen.target_controls.e1.get_global_rect().get_center(), 8, true)
	await _mouse_button(false)
	await _frames(70)
	await _move(Vector2(10, 60))
	_check(screen.combat.state.players.p1.hand.size() == 9 and screen.combat.state.players.p1.energy == 2, "拖放实际出牌一次")
	await _capture("08_after_play_1280", "08 · 出牌后补位", "十张变九张，能量 3→2；敌方获得实际结算状态")
	await _play_first()
	await _play_first()
	_check(screen.combat.state.players.p1.energy == 0, "三次真实出牌用完能量")
	await _hover(screen.hand_row.cards[0])
	await _capture("09_no_energy_1280", "09 · 无能量阅读", "费用不足置灰，仍可悬停查看完整牌面")
	await _move(Vector2(10, 60))
	await _click(screen.pile_panel.get_child(2).get_global_rect().get_center())
	_check(screen.inspector_panel.visible and not screen._hand_input_open(), "移除区弹窗阻断背后输入")
	await _capture("10_pile_modal_1280", "10 · 移除区弹窗", "已打出的道具牌可查看，弹窗覆盖并阻断手牌输入")
	await _key(KEY_ESCAPE)
	await _resize_to(Vector2i(1024, 640))
	await _fresh()
	await _capture("11_five_1024", "11 · 小窗口五张", "132×204 卡面，全部操作留在窗口内")
	await _fresh(10)
	await _capture("12_ten_1024", "12 · 小窗口十张", "密集扇形，左右操作区和十个费用区域可见")
	await _hover(screen.hand_row.cards[4])
	await _capture("13_hover_middle_1024", "13 · 小窗口中部抬牌", "展开后不遮挡角色生命与敌人意图")
	await _hover(screen.hand_row.cards[9])
	await _capture("14_hover_right_1024", "14 · 小窗口右端抬牌", "右端放大不出屏，结束回合可见")
	await _move(Vector2(10, 60))
	uid = int(screen.combat.state.players.p1.hand[0].uid)
	await _click(screen.hand_row.slot_point(uid, Vector2(23, 26)))
	await _move(screen.target_controls.e1.get_global_rect().get_center())
	await _capture("15_target_preview_1024", "15 · 小窗口目标预览", "选牌、角色信息与目标预览同时可读")
	await _fresh()
	for i in range(3): await _play_first()
	_check(screen.combat.state.players.p1.hand.size() == 2, "真实出牌后剩两张")
	await _capture("16_two_cards_1024", "16 · 两张剩牌", "少牌自动居中收拢，无大角度倾斜")
	screen.presentation_caption = "空手牌布局验收"
	_fixture(0)
	await _frames(12)
	await _move(Vector2(10, 60))
	await _capture("17_empty_hand_1024", "17 · 空手牌", "提示手牌用尽，结束回合仍可操作")
	screen.presentation_caption = "合作验收 · 队友视角"
	_fixture(10, "p2", true)
	await _frames(12)
	await _key(KEY_0)
	var wait_snapshot := screen.combat.to_dict().duplicate(true)
	screen.action_sink = func(_kind: String, _args: Dictionary) -> Variant: return "capture-wait"
	await _click(screen.target_controls.e1.get_global_rect().get_center())
	_check(screen.pending_action and screen.combat.to_dict() == wait_snapshot, "模拟合作等待保留镜像与十张手牌")
	await _capture("18_coop_waiting_1024", "18 · 合作视角等待", "p2 的第十张保持槽位；模拟等待期间禁用重复提交")
	await _overview()
	_write_index()
	forest.queue_free()
	await _frames()
	SettingsStore.set_reduce_motion(saved_motion)
	print("HAND_FAN_ACCEPTANCE: %d original screenshots + overview; checks=%d; %s" % [captures.size(), checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
