extends SceneTree
## 固定内存战斗：五状态图标、混合牌预览、敌人多段意图与 1024×640 布局。

var failed := false
var checks := 0
var output_dir := "res://screenshots/anchor_states"
var screen: BattleScreen

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("ANCHOR_UI_FAIL: " + message)

func _frames(count := 6) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(output_dir.path_join(name + ".png")) == OK, "截图保存 " + name)

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_dir = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = Vector2i(1024, 640)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	var deck: Array = []
	for card_id in ["guarded_strike", "slash7", "guard_standard", "battle_focus", "nimble_stance"]:
		deck.append({"card_id": card_id, "source_instance_id": 0, "join_round": 1})
	var combat := CombatGame.create([
		{"key": "p1", "name": "农夫", "max_hp": 40, "deck": deck},
		{"key": "p2", "name": "队友", "max_hp": 40, "deck": deck},
	], "gate_keeper", 20261022, null, deck)
	combat.start()
	var statuses := {"vulnerable": {"stacks": 2}, "weak": {"stacks": 1}, "poison": {"stacks": 3}, "strength": {"stacks": 2}, "dexterity": {"stacks": 2}}
	combat.state["players"]["p1"]["statuses"] = statuses.duplicate(true)
	combat.state["enemies"][0]["statuses"] = statuses.duplicate(true)
	combat.state["enemies"][0]["block"] = 2
	combat.state["enemies"][0]["intent"] = {"kind": "attack", "value": 7, "times": 2}
	var snapshot := combat.to_dict()
	screen = BattleScreen.new()
	root.add_child(screen)
	screen.open_run(combat)
	await _frames()
	var uid := int(combat.state["players"]["p1"]["hand"][0]["uid"])
	screen._on_card_clicked(uid)
	var motion := InputEventMouseMotion.new()
	motion.position = screen.target_controls["e1"].get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion, true)
	await _frames()
	# 固定悬停上下文，避免桌面鼠标在其他位置时覆盖截图的确定性目标。
	screen.hovered_target = "e1"
	screen._refresh_detail()
	var first_card := screen.hand_row.get_child(0) as Button
	_check(screen.selected_uid == uid, "混合牌保持选中")
	_check(screen._target_preview(uid, "e1").contains("自己：格挡 +5"), "混合牌自身格挡包含敏捷")
	_check(screen._target_preview(uid, "e1").contains("生命 −3"), "混合牌伤害预览包含状态与目标格挡")
	_check((first_card.find_child("CardEffect", true, false) as Label).text.contains("5 伤害"), "卡面伤害使用实际状态")
	_check(combat.to_dict() == snapshot, "全部 UI 预览不修改战斗状态")
	for unit in ["p1", "e1"]:
		for status in BattleScreen.STATUS_ORDER:
			var chip := screen.find_child("Status_" + unit + "_" + str(status), true, false) as Control
			_check(chip != null and chip.is_visible_in_tree(), "状态图标显示 " + unit + "/" + str(status))
			if chip != null:
				_check(chip.tooltip_text.contains(str(CardDefs.STATUS_DISPLAY[status])) and chip.tooltip_text.contains("层"), "悬停包含状态名称与层数")
	var intent := screen.find_child("EnemyIntent_e1", true, false) as Control
	_check(intent != null and intent.tooltip_text.contains("10×2"), "敌人意图显示修正后每段与段数")
	for button in screen.hand_row.get_children():
		if button is BattleScreen.CardButton:
			var effect_label := button.find_child("CardEffect", true, false) as Control
			_check(button.get_global_rect().encloses(effect_label.get_global_rect()), "卡面效果位于卡内")
	var dock_top := (screen.hand_row.get_parent().get_parent().get_parent() as Control).global_position.y
	for label in screen.target_previews.values():
		_check(label.get_global_rect().end.y <= dock_top, "角色预览没有被手牌区遮挡（底部 %.1f，手牌顶部 %.1f）" % [label.get_global_rect().end.y, dock_top])
	_check(screen.end_button.get_global_rect().end.y <= 640, "结束回合按钮位于小窗口内")
	await _shot("01_mixed_preview_1024x640")
	var chip := screen.find_child("Status_p1_strength", true, false) as Control
	motion.position = chip.get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion, true)
	await create_timer(0.8).timeout
	await _shot("02_strength_tooltip_1024x640")
	# 第一段打倒原目标后转向队友，意图必须保留不同目标各自的实际数值。
	combat.state["players"]["p1"]["hp"] = 2
	combat.state["players"]["p1"]["statuses"] = {"vulnerable": {"stacks": 2}}
	combat.state["enemies"][0]["statuses"] = {}
	combat.state["enemies"][0]["intent"] = {"kind": "attack", "value": 3, "times": 2}
	screen._refresh()
	await _frames()
	var intent_label := screen.find_child("IntentValue_e1", true, false) as Label
	_check(intent_label.text.contains("4→农夫") and intent_label.text.contains("3→队友"), "连击倒地后改目标时分别显示每段伤害和目标")
	_check(not intent_label.text.contains("4×2"), "变化伤害不简化成错误的同值连击")
	await _shot("03_retargeted_intent_1024x640")
	# 第一段攻击后施加的易伤只影响第二段，UI 直接展示规则层顺序模拟的文本。
	combat.state["players"]["p1"]["hp"] = 40
	combat.state["players"]["p1"]["statuses"] = {}
	combat.state["enemies"][0]["intent"] = {"kind": "attack", "value": 3, "times": 2, "status": "vulnerable", "status_stacks": 1}
	screen._refresh()
	await _frames()
	intent_label = screen.find_child("IntentValue_e1", true, false) as Label
	_check(intent_label.text.contains("3→农夫") and intent_label.text.contains("4→农夫"), "连击后施加易伤时显示不同的逐段数值")
	_check(screen._actor_width() + 1 >= (screen.find_child("EnemyIntent_e1", true, false) as Control).size.x, "变化连击意图没有撑宽角色栏")
	await _shot("04_sequential_intent_1024x640")
	combat.state["players"]["p1"]["hp"] = 2
	combat.state["players"]["p2"]["hp"] = 1
	combat.state["enemies"][0]["intent"] = {"kind": "attack", "value": 3, "times": 2}
	screen._refresh()
	await _frames()
	var no_action_row := screen.find_child("EnemyIntent_e2", true, false) as Control
	_check((no_action_row.get_child(0) as Label).text == "队伍已倒地", "此前敌人打倒队伍时正确显示无法行动原因")
	combat.state["enemies"][0]["statuses"] = {"poison": {"stacks": 99}}
	screen._refresh()
	await _frames()
	no_action_row = screen.find_child("EnemyIntent_e1", true, false) as Control
	_check((no_action_row.get_child(0) as Label).text == "中毒倒下", "中毒致死的敌人显示中毒倒下")
	print("ANCHOR_UI_%s checks=%d" % ["FAIL" if failed else "PASS", checks])
	screen.queue_free()
	await _frames()
	quit(1 if failed else 0)
