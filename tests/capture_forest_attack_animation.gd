extends SceneTree
## 真实出牌和结束回合驱动；录制逐帧画面，同时检查动画不改变裁定和点击区域。

const OUT := "res://screenshots/forest_attack_animation"
var checks := 0
var failed := false
var frame_number := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error("FOREST_ATTACK_FAIL: " + message)

func _frames(count: int, capture := false) -> void:
	for i in range(count):
		await process_frame
		if capture and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var path := OUT.path_join("frame_%04d.png" % frame_number)
			root.get_texture().get_image().save_png(path)
			frame_number += 1

func _motion(screen: BattleScreen) -> BattleCutoutMotion:
	for child in screen.get_children():
		if child is BattleCutoutMotion:
			return child
	return null

func _run() -> void:
	var settings_before := SettingsStore._load()
	SettingsStore.set_reduce_motion(false)
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	DisplayServer.window_set_size(root.size)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var game := (load("res://scenes/forest_animation_playtest.tscn") as PackedScene).instantiate() as ForestPlaytest
	root.add_child(game)
	await _frames(8)
	var screen := game.battle
	var uid := -1
	# 实际试玩洗牌随机；通过真实回合抽到攻击牌再开始录制，不假定首手牌序。
	for turn in range(4):
		for card in screen.combat.state["players"]["p1"]["hand"]:
			var definition := screen._card_definition(str(card["card_id"]))
			if str(definition["target"]) == "enemy" and str(definition.get("motion", "")) != "projectile":
				uid = int(card["uid"])
				break
		if uid != -1:
			break
		screen._on_end_turn()
		await _frames(32)
	_check(uid != -1, "真实抽牌获得攻击牌")
	await _frames(18, true)
	var before_hp := int(screen.combat.state["enemies"][0]["hp"])
	screen._on_card_clicked(uid)
	screen._on_target_clicked("e1")
	var after_play: Dictionary = screen.combat.state.duplicate(true)
	_check(int(after_play["enemies"][0]["hp"]) < before_hp, "攻击由规则正常结算")
	await _frames(5, true)
	var motion := _motion(screen)
	_check(motion != null and not motion.ranged, "真实近战事件触发前冲")
	var hitbox := screen.target_controls["p1"].get_global_rect() as Rect2
	await _frames(6, true)
	_check(screen.target_controls["p1"].get_global_rect() == hitbox, "移动插图不会移动点击区域")
	await _frames(27, true)
	_check(screen.combat.state == after_play, "整段挥砍没有重复伤害或改变规则")
	_check(_motion(screen) == null, "动作结束后清理覆盖层")
	_check(screen._unit_art("p1").self_modulate.a == 1, "恢复原人物显示")
	await _frames(12, true)
	before_hp = int(screen.combat.state["players"]["p1"]["hp"])
	screen._on_end_turn()
	var after_enemy: Dictionary = screen.combat.state.duplicate(true)
	_check(int(after_enemy["players"]["p1"]["hp"]) < before_hp, "敌人真实回合造成伤害")
	await _frames(5, true)
	motion = _motion(screen)
	_check(motion != null and motion.ranged, "弓手外观使用箭矢动作")
	await _frames(38, true)
	_check(screen.combat.state == after_enemy, "箭矢演出不改变裁定")
	await _frames(18, true)
	# 取消和快速刷新必须恢复图像，不能遗留幽灵或隐身。
	var art := screen._unit_art("p1")
	motion = screen._animate_attack("p1", "e1")
	_check(art.self_modulate.a == 0, "动作时隐藏静态原图")
	screen._clear_feedback()
	_check(art.self_modulate.a == 1, "取消立刻恢复角色")
	screen._refresh()
	await _frames(3)
	_check(_motion(screen) == null, "快速刷新没有残留覆盖层")
	SettingsStore.set_reduce_motion(true)
	screen._flash_events([{"type": "damage", "source": "e1", "target": "p1", "amount": 1, "to_hp": 1}])
	await _frames(5)
	_check(_motion(screen) == null, "减少动态效果设置禁用前冲与箭矢")
	_check(screen.combat.state == after_enemy, "减少动态效果也不触碰战斗数据")
	settings_before.save(SettingsStore.SETTINGS_PATH)
	game.queue_free()
	await _frames(3)
	print("FOREST_ATTACK_ANIMATION: %d checks, %d captured frames, %s" % [checks, frame_number, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)
