extends SceneTree
const OUT := "E:/gpt/worktree/6bc4/farm/screenshots/visual_audit_2026-10-04"

func _initialize() -> void:
	_run.call_deferred()

func _shot(tag: String) -> void:
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(tag + ".png"))
	print("EXTRA_SHOT ", tag)

func _run() -> void:
	GameFlow.mode = GameFlow.Mode.NEW_GAME
	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	world.game.state["tutorial_step"] = 5
	world.game.state["coins"] = 800
	world._refresh_all()
	world.game.plant(1, int(Time.get_unix_time_from_system()))
	world.hud.open_plot_care(1)
	await _shot("26_plot_care")
	world.hud._close_modal()
	world._debug_mature_all()
	world._do_harvest(1)
	await _shot("27_harvest")
	world.hud._close_modal()
	world.hud.open_warehouse("seeds")
	await _shot("28_seed_warehouse")
	world.hud._close_modal()
	world.hud.open_equipment_warehouse()
	await _shot("29_equipment_warehouse")
	world.hud.equipment_warehouse_panel.close()
	world.queue_free()
	await process_frame
	var bridge := OnlineFarmBridge.new()
	root.add_child(bridge)
	bridge.add_child(bridge.client)
	bridge.client.account_id = 1
	bridge.game.new_game(int(Time.get_unix_time_from_system()))
	bridge.mirror_room = {"code": "123456", "creator_account_id": 1, "phase": "waiting", "members": [{"account_id": 1, "nick": "阿禾", "ready": true, "online": true}, {"account_id": 2, "nick": "小满", "ready": false, "online": true}]}
	bridge.mirror_run = {
		"run_id": "visual-demo", "layer_id": "moss_stone_shallow", "coop": true,
		"player": {"hp": 28, "max_hp": 40}, "guest": {"hp": 30, "max_hp": 40},
		"inventory": ExpeditionGame._snapshot_loadout(bridge.game), "guest_inventory": ExpeditionGame._snapshot_loadout(bridge.game),
		"map": ExpeditionGame._build_map("moss_stone_shallow"), "current": {"row": 0, "col": 0},
		"resolved": {}, "node_drops": [], "battle": {}, "phase": "map", "outcome": "", "votes": {},
		"log": ["视觉巡检镜像（没有连接服务器）"]
	}
	bridge.mirror_run_version = 1
	var panel := OnlineRunPanel.new()
	root.add_child(panel)
	panel.open(bridge)
	await _shot("30_online_route_demo")
	bridge.mirror_run["phase"] = "over"
	bridge.mirror_run["outcome"] = "extract"
	bridge.mirror_run_version = 2
	panel._refresh()
	await _shot("31_online_settlement_demo")
	panel.close()
	var room := OnlineRoomPanel.new()
	root.add_child(room)
	room.open(bridge)
	await _shot("32_online_room_demo")
	room.close()
	print("EXTRA_CAPTURE_DONE")
	quit(0)
