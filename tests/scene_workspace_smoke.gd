extends SceneTree
## Fixture snapshots exercise view intent and acknowledgement boundaries; this is not a public-server test.
class IntentBridge extends OnlineFarmBridge:
	var sent: Array = []
	func run_action(kind: String, args: Dictionary = {}) -> Dictionary:
		sent.append({"kind":kind,"args":args.duplicate(true)})
		return {"ok":true}
class IntentClient extends SessionClient:
	var sent: Array = []
	func send_action(kind: String, args: Dictionary = {}) -> String:
		sent.append({"kind":kind,"args":args.duplicate(true)})
		return "fixture-action-%d" % sent.size()
var failures: Array[String] = []
var checks := 0
var output := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	var game := FarmGame.new()
	game.new_game(1000)
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	for item in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(item["instance_id"]),"chest")
	var bridge := IntentBridge.new()
	bridge.game = game
	bridge.client.account_id = 1
	bridge.mirror_run = ExpeditionGame.compose_run(game,{},"fixture-route",1000,false,"演示快照")
	bridge.mirror_run_version = 1
	var panel := OnlineRunPanel.new()
	root.add_child(panel)
	panel.open(bridge)
	await _frames()
	var route := panel.find_child("Route_1_0",true,false) as Button
	await _click(route)
	_check(bridge.sent.is_empty(),"online selection sends no move")
	_check(panel.selected_route==Vector2i(1,0),"online route shows selected preview")
	await _shot("24_online_route_fixture")
	bridge.mirror_run["layer_id"] = "iron_root_deeps"
	bridge.mirror_run["map"] = ExpeditionGame._build_map("iron_root_deeps")
	panel._refresh()
	await _shot("37_iron_layer_fixture")
	bridge.mirror_run["layer_id"] = "crystal_vein_deeps"
	bridge.mirror_run["map"] = ExpeditionGame._build_map("crystal_vein_deeps")
	panel._refresh()
	await _shot("38_crystal_layer_fixture")
	bridge.mirror_run["layer_id"] = "moss_stone_shallow"
	bridge.mirror_run["map"] = ExpeditionGame._build_map("moss_stone_shallow")
	panel._refresh()
	await _click(panel.find_child("ConfirmRoute",true,false))
	_check(bridge.sent.size()==1 and bridge.sent[0]["kind"]=="move_to","online confirmation sends one move intent")
	_check(int(bridge.mirror_run["current"]["row"])==0,"online confirmation does not mutate mirror")
	bridge.mirror_run["coop"] = true
	bridge.mirror_run["guest"] = {"hp":40,"max_hp":40,"inventory":bridge.mirror_run["inventory"].duplicate(true)}
	bridge.mirror_run["votes"] = {"p1":"1,0","p2":"1,1"}
	bridge.mirror_run_version += 1
	panel._refresh()
	await _shot("25_online_votes_fixture")
	var receipt := {"kind":"extract","settlement_id":"fixture-receipt","run_id":"fixture-route","returned":[],"gained":[{"def_id":"copper_scrap"}],"protected":[],"lost":[],"consumed":[]}
	bridge.mirror_run["phase"] = "over"
	bridge.mirror_run["outcome"] = "extract"
	bridge.mirror_settlement = receipt
	bridge.mirror_run_version += 1
	panel._refresh()
	_check(not panel.action_row.visible,"ended online run hides live actions")
	_check(not panel._settlement_applied(),"unapplied receipt is not claimed applied")
	await _shot("26_online_receipt_pending_fixture")
	game.state["expedition"]["applied_settlements"].append("fixture-receipt")
	await _frames()
	_check(panel._settlement_applied(),"applied label follows authoritative farm snapshot")
	await _shot("27_online_receipt_applied_fixture")
	panel.close()
	var client := IntentClient.new()
	client.farm_game = game
	client.mirror_run = ExpeditionGame.compose_run(game,{},"fixture-coop",1000,false,"演示快照")
	client.mirror_run["coop"] = true
	client.mirror_run["guest"] = {"hp":40,"max_hp":40,"inventory":client.mirror_run["inventory"].duplicate(true)}
	client.mirror_run["votes"] = {"p1":"","p2":""}
	var coop := CoopClientPanel.new()
	root.add_child(coop)
	coop.open(client)
	await _frames()
	await _click(coop.find_child("Route_1_0",true,false))
	_check(client.sent.is_empty(),"coop selection sends no vote")
	await _click(coop.find_child("ConfirmRoute",true,false))
	_check(client.sent.size()==1 and client.sent[0]["kind"]=="vote_move","coop confirmation sends vote intent")
	await _shot("28_local_coop_route_fixture")
	coop.close()
	var directory := OnlineVisitPanel.new()
	root.add_child(directory)
	directory.neighbors = [{"account_id":1,"nick":"小满","online":true,"visits_open":true},{"account_id":2,"nick":"阿树","online":false,"visits_open":true},{"account_id":3,"nick":"山雀","online":true,"visits_open":false}]
	directory.visible = true
	directory._render_entries()
	await _shot("29_directory_fixture")
	directory.search_edit.text = "阿树"
	await _frames()
	_check(directory.list_column.get_child_count()==1,"nickname search filters directory")
	directory.close()
	var room := OnlineRoomPanel.new()
	root.add_child(room)
	bridge.mirror_room = {"code":"ABC123","phase":"waiting","creator_account_id":1,"members":[{"account_id":1,"nick":"小满","ready":true,"online":true},{"account_id":2,"nick":"阿树","ready":false,"online":false}]}
	room.open(bridge)
	await _shot("30_online_room_fixture")
	room.close()
	panel.queue_free()
	coop.queue_free()
	directory.queue_free()
	room.queue_free()
	bridge.client.free()
	bridge.free()
	await _frames()
	print("SCENE_WORKSPACES ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _frames() -> void:
	for i in range(8):
		await process_frame

func _click(button: Button) -> void:
	_check(button!=null and button.is_visible_in_tree() and not button.disabled,"fixture UI button available")
	if button == null:
		return
	var event := InputEventMouseButton.new()
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)
	await _frames()

func _shot(title: String) -> void:
	await _frames()
	if DisplayServer.get_name()!="headless":
		var limit := root.get_visible_rect()
		for button in root.find_children("*","Button",true,false):
			var clipped := false
			var parent: Node = button.get_parent()
			while parent!=null:
				if parent is ScrollContainer:
					clipped = true
				parent = parent.get_parent()
			if button.is_visible_in_tree() and not clipped:
				_check(limit.encloses(button.get_global_rect()),title+" button fits "+str(button.name))
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/"+title+".png")

func _check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures.append(title)
		push_error(title)
