extends SceneTree

## 阶段 5 关键界面截图生成器：农场全景、引导条、收获面板、仓库、集市、育种机。
## 仅在内存里摆拍，不写磁盘存档。用法：
## --headless --script res://tests/capture_stage5_previews.gd


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var hud: FarmHud = world.get_node("FarmCanvas/FarmHud")
	var game: FarmGame = world.game
	var now: int = hud.view_now
	# 造一点可视状态：三块地生长、两块成熟
	for plot_id in [1, 2, 3]:
		if game.plant(plot_id, now - 300) == "":
			game.water(plot_id, now - 200)
	for plot_id in [4, 5]:
		if game.plant(plot_id, now - 1300) == "":
			game.get_plot(plot_id)["ready_at"] = now - 5
	game.state["tutorial_step"] = 1
	hud.refresh(game.state)
	await _shot("farm_panorama.png")
	# 引导条特写（同一帧即可，已随 refresh 显示）
	hud.open_seed_picker(6)
	await _shot("tutorial_and_seed_picker.png")
	hud.close_modal_after_action()
	# 收获面板
	var harvest: Dictionary = game.harvest(4, now)
	if not harvest["ok"]:
		push_error("CAPTURE_FAIL harvest: " + str(harvest))
	hud.refresh(game.state)
	if harvest["ok"]:
		hud.show_harvest(harvest)
		await _shot("harvest_breakdown.png")
		hud.close_modal_after_action()
	# 仓库种子区（含筛选行）
	hud.open_warehouse("seeds")
	await _shot("warehouse_seeds.png")
	hud.close_modal_after_action()
	# 集市（有批次可卖）
	var batch: Dictionary = harvest.get("batch", {})
	if not batch.is_empty():
		hud.open_market()
		await _shot("market_quotes.png")
		hud.close_modal_after_action()
	# 育种机
	hud.open_breeder()
	await _shot("breeder.png")
	hud.close_modal_after_action()
	quit(0)


func _shot(file_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("res://screenshots/preview_%s" % file_name)
