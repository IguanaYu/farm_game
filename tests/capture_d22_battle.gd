extends SceneTree
## 2.2 界面截图：演示战斗的遭遇选择、战斗中、结束回合后三个画面。需带窗口运行。


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var hud: FarmHud = world.get_node("FarmCanvas/FarmHud")
	hud.open_battle_demo()
	var screen: BattleScreen = hud.battle_screen
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d22_battle_chooser.png")

	screen._on_choose_encounter("normal")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d22_battle_round1.png")

	# 打一张牌（点手牌再点目标）。
	for card in screen.combat.state["players"]["p1"]["hand"]:
		if str(card["card_id"]) == "slash":
			screen._on_card_clicked(int(card["uid"]))
			screen._on_target_clicked("e1")
			break
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d22_battle_played.png")

	screen._on_end_turn()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("res://screenshots/d22_battle_after_enemy.png")

	screen._on_close()
	world.queue_free()
	quit(0)
