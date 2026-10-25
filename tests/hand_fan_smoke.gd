extends SceneTree
## 真实输入验收：多手牌、稳定悬停、点选、拖放、模态与合作等待。

const GEO := preload("res://tests/helpers/control_geometry.gd")
const OUT := "res://screenshots/hand_fan_live_2026-10-25/"
var checks := 0
var failed := false
var screen: BattleScreen
var mouse_at := Vector2.ZERO

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("HAND_FAN_FAIL: " + note)

func _frames(count := 10) -> void:
	for i in range(count): await process_frame

func _move(point: Vector2, frames := 10, held := false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.relative = point - mouse_at
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	mouse_at = point
	root.push_input(motion, true)
	await _frames(frames)

func _mouse_button(pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = mouse_at
	event.global_position = mouse_at
	event.button_index = button
	event.pressed = pressed
	root.push_input(event, true)
	await _frames(1)

func _click(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	await _move(point)
	await _mouse_button(true, button)
	await _mouse_button(false, button)
	await _frames()

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await _frames()

func _fixture(count: int, actor := "p1", coop := false) -> CombatGame:
	var deck: Array = []
	for i in range(count):
		deck.append({"card_id": "slash8", "join_round": 1})
	var players: Array = [{"key": "p1", "name": "农夫", "max_hp": 40, "deck": deck}]
	if coop:
		players.append({"key": "p2", "name": "队友", "max_hp": 40, "deck": deck})
	var combat := CombatGame.create(players, "defensive", 20261025, null, deck)
	combat.start()
	if count > 5: combat.draw_extra_for(actor, count - 5)
	screen.open_run(combat, actor)
	return combat

func _hover(card: BattleScreen.CardButton) -> void:
	await _move(Vector2(10, 60))
	await _move(screen.hand_row.slot_point(card.card_uid, Vector2(23, 26)))
	_check(screen.hovered_uid == card.card_uid, "鼠标悬停正确 UID %d" % card.card_uid)
	_check(absf(card.rotation) < 0.01 and card.scale.is_equal_approx(Vector2.ONE * 1.18), "悬停牌转正放大")
	var pose := card.get_global_transform()
	await _frames(18)
	_check(screen.hovered_uid == card.card_uid and card.get_global_transform().is_equal_approx(pose), "静止悬停不抖动")

func _bounds() -> void:
	for card in screen.hand_row.cards:
		_check(GEO.in_rect(root.get_visible_rect(), card), "旋转后的四角不出屏")
		for name in ["CardTitle", "CardEffect", "CardKind"]:
			_check(GEO.contains_control(card, card.find_child(name, true, false)), "卡内文字不溢出 " + name)
	for button in screen.pile_panel.get_children():
		_check(GEO.in_rect(root.get_visible_rect(), button), "牌堆按钮在窗口内")
	_check(GEO.in_rect(root.get_visible_rect(), screen.end_button), "结束回合按钮在窗口内")

func _shot(name: String) -> void:
	# Capture the settled lifted face before the optional long-description dwell tooltip.
	await _move(mouse_at, 1)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(OUT + name + ".png") == OK, "保存正式接入截图 " + name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var saved_motion := SettingsStore.get_reduce_motion()
	SettingsStore.set_reduce_motion(false)
	screen = BattleScreen.new()
	root.add_child(screen)
	for extent in [Vector2i(1280, 800), Vector2i(1024, 640)]:
		root.size = extent
		root.content_scale_size = extent
		DisplayServer.window_set_size(extent)
		for count in [0, 1, 2, 5, 8, 10]:
			var combat := _fixture(count)
			await _frames()
			await _move(Vector2(10, 60))
			_check(screen.hand_row.cards.size() == count, "布局牌数 %d" % count)
			var snapshot := combat.to_dict().duplicate(true)
			_bounds()
			for card in screen.hand_row.cards:
				await _hover(card)
				_bounds()
			_check(combat.to_dict() == snapshot, "所有悬停不改变战斗与 RNG")
			if count == 10:
				await _move(Vector2(10, 60))
				for card in screen.hand_row.cards:
					await _move(screen.hand_row.slot_point(card.card_uid, Vector2(23, 26)), 1)
					_check(screen.hovered_uid == card.card_uid, "连续划过十张牌不跳牌")
				await _move(Vector2(10, 60))
				await _shot("ten_" + str(extent.x))
				await _hover(screen.hand_row.cards[4])
				await _shot("ten_hover_" + str(extent.x))
	# Click selection, stable UID identity, target preview and real play.
	var combat := _fixture(5)
	await _frames()
	var card := screen.hand_row.cards[0] as BattleScreen.CardButton
	var uid := card.card_uid
	var identity := card.get_instance_id()
	var snapshot := combat.to_dict().duplicate(true)
	await _click(screen.hand_row.slot_point(uid, Vector2(23, 26)))
	_check(screen.selected_uid == uid, "真实点击选中卡牌")
	_check(screen.hand_row.cards[0].get_instance_id() == identity, "选牌刷新复用按钮")
	await _move(screen.target_controls["e1"].get_global_rect().get_center())
	_check(combat.to_dict() == snapshot, "选牌和伤害预览不结算")
	_check(absf(card.rotation) < 0.01, "移向目标后所选牌保持抬起")
	await _click(mouse_at, MOUSE_BUTTON_RIGHT)
	_check(screen.selected_uid == -1 and combat.to_dict() == snapshot, "右键取消不结算")
	await _key(KEY_1)
	_check(screen.selected_uid == uid, "数字键选中原序第一张")
	await _key(KEY_ESCAPE)
	_check(screen.selected_uid == -1, "Esc 取消")
	await _key(KEY_1)
	await _click(screen.target_controls["e1"].get_global_rect().get_center())
	_check(screen._hand_card(uid).is_empty() and combat.state.players.p1.energy == 2, "点目标出牌仅扣一次费用")
	_check(screen.hand_row.cards.size() == 4, "出牌后补位")
	_bounds()
	# Disabled cards still lift for inspection, with no play or drag.
	combat.state.players.p1.energy = 0
	screen._refresh()
	await _frames()
	card = screen.hand_row.cards[0]
	snapshot = combat.to_dict().duplicate(true)
	await _hover(card)
	_check(card.disabled, "能量不足显示禁用")
	await _click(mouse_at)
	_check(screen.selected_uid == -1 and combat.to_dict() == snapshot, "禁用牌可读但不能打出")
	# Native drag success and cancellation.
	combat = _fixture(5)
	await _frames()
	card = screen.hand_row.cards[1]
	uid = card.card_uid
	await _hover(card)
	await _mouse_button(true)
	await _move(mouse_at + Vector2(0, -40), 4, true)
	_check(root.gui_is_dragging(), "真实鼠标启动拖放")
	var drag_preview := root.find_child("CardDragPreview", true, false) as Control
	_check(drag_preview != null, "拖放显示完整卡面预览")
	if drag_preview != null:
		var source_art: ExpeditionArt
		for child in card.find_children("*", "Control", true, false):
			if child is ExpeditionArt: source_art = child
		var drag_image := drag_preview.find_child("CardDragArt", true, false) as TextureRect
		var drag_fallback := drag_preview.find_child("CardDragFallback", true, false) as ExpeditionArt
		if source_art._resolve_texture() != null:
			_check(drag_image != null and drag_image.texture == source_art._resolve_texture(), "拖放插图与原牌使用相同纹理")
		else:
			_check(drag_fallback != null and drag_fallback.subject == source_art.subject, "拖放保留原生卡牌插图")
	await _move(screen.target_controls["e1"].get_global_rect().get_center(), 5, true)
	await _mouse_button(false)
	await _frames()
	_check(screen._hand_card(uid).is_empty() and not root.gui_is_dragging(), "释放到合法目标成功出牌")
	card = screen.hand_row.cards[0]
	snapshot = combat.to_dict().duplicate(true)
	await _hover(card)
	await _mouse_button(true)
	await _move(mouse_at + Vector2(0, -40), 4, true)
	await _move(Vector2(12, 80), 4, true)
	await _mouse_button(false)
	await _frames()
	_check(not root.gui_is_dragging() and screen.drag_uid == -1, "非法区域释放恢复手牌")
	_check(combat.to_dict() == snapshot and card.modulate.a == 1.0, "取消拖放不结算、原牌恢复")
	await _hover(card)
	await _mouse_button(true)
	await _move(mouse_at + Vector2(0, -40), 4, true)
	await _mouse_button(true, MOUSE_BUTTON_RIGHT)
	await _mouse_button(false, MOUSE_BUTTON_RIGHT)
	await _mouse_button(false)
	await _frames()
	_check(not root.gui_is_dragging() and screen.selected_uid == -1 and combat.to_dict() == snapshot, "右键取消正在拖放的牌")
	# Pile modal and external settings block the same buttons and hotkeys.
	screen._open_pile("draw_pile", "抽牌")
	await _frames()
	snapshot = combat.to_dict().duplicate(true)
	await _key(KEY_1)
	await _key(KEY_E)
	_check(combat.to_dict() == snapshot, "牌堆弹窗阻止快捷键")
	_check(not screen._hand_input_open(), "牌堆弹窗阻止手牌命中")
	await _key(KEY_ESCAPE)
	_check(not screen.inspector_panel.visible, "Esc 关闭牌堆弹窗")
	screen.input_blocked = func() -> bool: return true
	await _key(KEY_1)
	await _click(screen.hand_row.slot_point(card.card_uid, Vector2(23, 26)))
	_check(combat.to_dict() == snapshot and not screen._hand_input_open(), "设置菜单阻止输入")
	screen.input_blocked = Callable()
	# p2 ten-card view and asynchronous host acknowledgement retain the slot.
	combat = _fixture(10, "p2", true)
	await _frames()
	await _key(KEY_0)
	uid = screen.hand_row.cards[9].card_uid
	_check(screen.selected_uid == uid, "合作 p2 的 0 键选中第十张")
	var sends := [0]
	screen.action_sink = func(_kind: String, _args: Dictionary) -> Variant:
		sends[0] += 1
		return "fan-pending"
	snapshot = combat.to_dict().duplicate(true)
	await _click(screen.target_controls["e1"].get_global_rect().get_center())
	await _click(screen.target_controls["e1"].get_global_rect().get_center())
	_check(sends[0] == 1 and screen.pending_action, "合作等待时不重复提交")
	_check(screen.hand_row.cards.size() == 10 and screen.hand_row.active_uid() == uid, "裁定前保留原牌与槽位")
	_check(combat.to_dict() == snapshot, "客机等待不改镜像")
	var kept_identity := screen.hand_row.cards[0].get_instance_id()
	_check(combat.play_card("p2", uid, "e1").get("ok", false), "模拟主机接受原请求")
	screen.pending_action = false
	screen.action_sink = Callable()
	screen._refresh()
	await _frames()
	_check(screen.hand_row.cards.size() == 9 and screen.hand_row.cards[0].get_instance_id() == kept_identity, "接受回执后移除一张并复用剩余手牌")
	# Reduced motion keeps the same geometry without an animation delay.
	SettingsStore.set_reduce_motion(true)
	_fixture(5)
	await _frames()
	card = screen.hand_row.cards[0]
	await _move(Vector2(10, 60))
	await _move(screen.hand_row.slot_point(card.card_uid, Vector2(23, 26)), 1)
	_check(absf(card.rotation) < 0.01 and card.scale.is_equal_approx(Vector2.ONE * 1.18), "减少动态时立即抬牌")
	screen.queue_free()
	await _frames()
	# Capture the actual forest card art through the shared production component.
	var forest = (load("res://scenes/forest_story_expansion_playtest.tscn") as PackedScene).instantiate()
	root.add_child(forest)
	await _frames()
	screen = forest.battle
	for extent in [Vector2i(1280, 800), Vector2i(1024, 640)]:
		root.size = extent
		root.content_scale_size = extent
		DisplayServer.window_set_size(extent)
		forest._begin_battle()
		await _frames()
		await _move(Vector2(10, 60))
		await _shot("forest_five_" + str(extent.x))
		screen.combat.draw_extra_for("p1", 5)
		screen._refresh()
		await _frames()
		_bounds()
		await _shot("forest_ten_" + str(extent.x))
		await _hover(screen.hand_row.cards[4])
		_bounds()
		await _shot("forest_ten_hover_" + str(extent.x))
	forest.queue_free()
	await _frames()
	SettingsStore.set_reduce_motion(saved_motion)
	print("HAND_FAN_LIVE: %d checks; %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
