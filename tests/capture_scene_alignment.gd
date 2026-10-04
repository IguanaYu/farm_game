extends SceneTree
## Engine screenshots and actual viewport picking. Run in a project with an isolated application name.
var output := ProjectSettings.globalize_path("res://screenshots/scene_alignment_2026-10-04")
var world: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output)
	GameFlow.mode = GameFlow.Mode.NEW_GAME
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	await _frames(8)
	if world.hud == null:
		push_error("World did not initialize")
		quit(1)
		return
	world.game.state["tutorial_step"] = 5
	world.game.state["coins"] = 800
	world._refresh_all()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--farm-view="):
			world.get_node("FarmCamera").size = float(arg.trim_prefix("--farm-view="))
			world.get_node("FarmCamera").look_at(Vector3(0,0.4,-2.2))
	await _capture("01_farm")
	world.game.plant(1,int(Time.get_unix_time_from_system()))
	world.game.plant(2,int(Time.get_unix_time_from_system()))
	world._debug_mature_all()
	await _capture("02_farm_crops")
	await _click(world.farm_location.get_node("Plot_08"),Vector3(0,0.1,0))
	_check(world.hud.active_modal == "expansion","actual unowned plot opens expansion")
	await _capture("11_expansion")
	world.hud._close_modal()
	world.hud.open_seed_picker(3)
	await _capture("03_seed_workspace")
	world.hud._close_modal()
	world._do_harvest(1)
	world._do_harvest(2)
	await _click(world.farm_location.get_node("ShopBuilding"),Vector3(0,1.5,0))
	_check(world.router.current=="shop","actual cottage click enters shop")
	await _capture("04_shop")
	world.hud.open_basket()
	await _capture("05_basket")
	world.hud._close_modal()
	var guest_id := int(world.game.state["market"]["guest_ids"][0])
	var batch: Dictionary = world.hud.selected_basket()
	_check(not batch.is_empty(),"basket has harvested batch")
	var batch_id := int(batch["id"])
	world.hud.market_sell_counts[batch_id] = 1
	world.hud._refresh_world_quotes()
	await _click(world.guest_slots[0],Vector3(0,1,0))
	_check(world.hud.active_modal=="guest" and world.hud.selected_guest_id==guest_id,"actual guest selects that guest")
	await _capture("06_guest_trade")
	var before_coins := int(world.game.state["coins"])
	var price: Dictionary = world.game.quote(batch,1,guest_id)
	await _button(world.hud.find_child("GuestConfirmSale",true,false))
	_check(int(world.game.state["coins"])==before_coins+int(price["coins"]),"one-item sale matches quote")
	world.hud._close_modal()
	world.hud.shop_tab = "seeds"
	world.hud.open_shop()
	await _capture("12_shop_shelf")
	world.hud._close_modal()
	world.router.switch_to("farm",false)
	world.hud.open_warehouse()
	await _capture("13_warehouse")
	world.hud._close_modal()
	world.hud.open_breeder()
	await _capture("14_breeder")
	world.hud._close_modal()
	world.hud.open_crafting()
	await _capture("15_crafting")
	await _button(world.hud.crafting_panel.find_child("Recipe_copper_shortsword",true,false))
	_check(world.hud.crafting_panel.selected_recipe=="copper_shortsword","recipe selection opens material and product detail")
	world.hud.crafting_panel.close()
	await _click(world.farm_location.get_node("HillStairs"),Vector3(0,1,0))
	_check(world.router.current=="cave_camp","actual stairs click enters camp")
	await _capture("07_camp")
	var member_client := SessionClient.new()
	world.hud.room_panel.client = member_client
	world.hud.room_panel.room_view = {"members":{"p1":{"name":"小满","ready":true,"online":true},"p2":{"name":"阿树","ready":false,"online":false}}}
	world._refresh_camp_party()
	_check(world.get_node("CaveCamp/PartyStand").get_child_count()==2,"camp renders members from room snapshot")
	_check(world.get_node("CaveCamp/PartyStand/CampMember_1").find_children("*","Label3D",true,false)[0].text.contains("离线"),"camp member label reflects offline state")
	await _capture("32_camp_party_fixture")
	world.hud.room_panel.client = null
	member_client = null
	world._refresh_camp_party()
	await _click(world.get_node("CaveCamp/WarBench"),Vector3(0,1,0))
	_check(world.hud.loadout_panel.visible,"actual war bench opens loadout")
	world.hud.loadout_panel._on_grant_kit()
	var inv: InventoryGame = world.hud.loadout_panel.inventory
	for item in inv.warehouse_list().duplicate():
		inv.move_to_loadout(int(item["instance_id"]),"chest")
	world.hud.loadout_panel._refresh()
	await _frames(4)
	var grid: EquipmentGrid = world.hud.loadout_panel.container_boxes["chest"].get_meta("grid")
	var instance: Dictionary = inv.loadout_list("chest")[0]
	var id := int(instance["instance_id"])
	await _drag(grid.global_position+grid._item_rect(instance).get_center(),grid.global_position+grid.origin+Vector2(1.5,2.5)*grid.cell_size)
	_check(inv.find_instance(id)["cell"]==[1,2],"actual equipment drag places item in selected cells")
	await _capture("16_loadout")
	world.hud.loadout_panel.close()
	world.hud.open_equipment_warehouse()
	await _capture("17_equipment_warehouse")
	world.hud.equipment_warehouse_panel.close()
	world.hud.open_room()
	await _capture("18_local_room")
	world.hud.room_panel.close()
	world.hud.expedition_hub_panel.open(world.game)
	await _capture("19_cave_workspace")
	world.hud.expedition_hub_panel.close()
	world.router.switch_to("farm",false)
	var snapshot: Dictionary = world.game.state.duplicate(true)
	var now := int(Time.get_unix_time_from_system())
	for i in range(3):
		var plot: Dictionary = snapshot["plots"][i]
		plot["seed_id"] = 800+i
		plot["kind"] = "cabbage"
		plot["planted_at"] = now-[0,700,1400][i]
		plot["ready_at"] = now+[1200,600,-1][i]
	world.enter_visit({"account_id":1,"nick":"小满","online":false},snapshot)
	await _capture("08_yard")
	_check(root.get_camera_3d().name == "VisitYardCamera","yard camera")
	var shown := 0
	for i in range(1,11):
		if world.visit_yard.get_node("VisitPlot_%02d" % i).get_node_or_null("VisitCrop") != null:
			shown += 1
	_check(shown==world.game.owned_plot_ids().size(),"visit renders every owned plot")
	for i in range(3):
		var appearance: Node = world.visit_yard.get_node("VisitPlot_%02d/VisitCrop" % (i+1))
		_check(["sprout","growing","mature"][i] in appearance.scene_file_path,"visit crop stage %d uses correct model" % i)
	await _click(world.visit_yard.get_node("VisitHouse"),Vector3(0,1.5,0))
	_check(world.router.current == "visit_house","actual house click enters interior")
	await _capture("09_house")
	_check(world.hud.owner_quote.size.y<180 and root.get_visible_rect().encloses(world.hud.owner_quote.get_global_rect()),"owner welcome fits beside the visible host")
	_check(root.get_camera_3d().name == "VisitHouseCamera","house camera")
	var original := JSON.stringify(world.game.state)
	await _click(world.visit_house.get_node("MessageBoard"),Vector3(0,1,0))
	_check(world.hud.active_modal=="readonly","actual welcome board opens readonly content")
	_check(JSON.stringify(world.game.state)==original,"readonly visit does not mutate own farm")
	world.hud._close_modal()
	await _click(world.visit_house.get_node("HostFigure"),Vector3(0,1,0))
	_check(world.hud.active_modal=="readonly","actual host click opens static welcome")
	world.hud._close_modal()
	await _click(world.visit_house.get_node("DisplayShelf"),Vector3(0,1,0))
	_check(world.hud.active_modal=="readonly","actual household shelf opens readonly details")
	world.hud._close_modal()
	await _click(world.visit_house.get_node("HouseWindow"),Vector3(0,1,0))
	_check(world.router.current=="visit_yard","actual window returns to the same yard")
	await _click(world.visit_yard.get_node("VisitHouse"),Vector3(0,1.5,0))
	await _click(world.visit_house.get_node("HouseDoor"),Vector3(0,1,0))
	_check(world.router.current == "visit_yard","actual door click returns to yard")
	await _click(world.visit_yard.get_node("VisitGate"),Vector3(0,1,0))
	_check(world.router.current == "farm" and world.farm_location.visible,"actual gate click returns to visible farm")
	await _capture("10_return_farm")
	for i in range(10):
		world.enter_visit({"account_id":1,"nick":"小满","online":false},snapshot)
		await _frames(3)
		world.router.switch_to("visit_house",false)
		world.leave_visit()
		await _frames(3)
		_check(world.farm_location.visible and root.get_camera_3d().name=="FarmCamera","visit roundtrip %d" % i)
	for plot in snapshot["plots"]:
		plot["owned"] = true
	world.enter_visit({"account_id":1,"nick":"小满","online":false},snapshot)
	for i in range(1,11):
		_check(world.visit_yard.get_node("VisitPlot_%02d" % i).get_node_or_null("VisitCrop")!=null,"all ten owned visit plots display %d" % i)
	await _click(world.visit_yard.get_node("VisitPlot_08"),Vector3(0,0.1,0))
	_check(world.hud.active_modal=="readonly","actual owned plot inspection remains readonly")
	_check(JSON.stringify(world.game.state)==original,"crop and household inspection leave own farm unchanged")
	world.hud._close_modal()
	await _capture("33_yard_all_ten")
	world.leave_visit()
	for i in range(20):
		world.router.switch_to("shop",false)
		world.router.switch_to("cave_camp",false)
		world.router.switch_to("farm",false)
	await _frames(25)
	_check(world.router._fade_rect.color.a<0.01 and world.farm_location.visible,"rapid scene transitions settle on visible farm without competing fades")
	world.hud.online_visit_panel.visible = true
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	await _frames(3)
	_check(not world.hud.online_visit_panel.visible and not world.hud.pause_overlay.visible,"one ESC closes directory without pause")
	world.game.add_seed_with_traits("rock_sprout",[])
	world.game.add_seed_with_traits("glow_berry",[])
	world.hud.open_seed_picker(3)
	await _capture("34_rare_seeds")
	world.hud._close_modal()
	world.hud._open_pause()
	await _capture("35_pause")
	world.hud._close_pause()
	root.size = Vector2i(1024,640)
	world.hud.open_loadout()
	await _capture("20_loadout_1024")
	world.hud.loadout_panel.close()
	world.hud.open_crafting()
	await _capture("21_crafting_1024")
	world.hud.crafting_panel.close()
	root.size = Vector2i(1440,900)
	await _capture("22_farm_1440")
	root.size = Vector2i(1280,800)
	world.queue_free()
	await _frames(3)
	var menu := MainMenu.new()
	root.add_child(menu)
	await _capture("23_main_menu")
	menu._on_online()
	await _capture("31_online_login")
	menu._on_settings()
	await _capture("36_settings")
	var result := {"checks":checks,"failures":failures}
	var f := FileAccess.open(output+"/checks.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(result,"\t"))
	print("SCENE_ALIGNMENT ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame
		await physics_frame

func _capture(title: String) -> void:
	await _frames(8)
	_check_button_layout(title)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(output+"/"+title+".png")
	print("CAPTURE ",title)

func _check_button_layout(title: String) -> void:
	var limit := root.get_visible_rect()
	for button in root.find_children("*","Button",true,false):
		if not button.is_visible_in_tree():
			continue
		var clipped := false
		var parent: Node = button.get_parent()
		while parent != null:
			if parent is ScrollContainer:
				clipped = true
			parent = parent.get_parent()
		if not clipped:
			_check(limit.encloses(button.get_global_rect()),title+" button fits "+str(button.name))

func _click(body: Node3D, offset: Vector3) -> void:
	await _frames(3)
	var at := root.get_camera_3d().unproject_position(body.global_position+offset)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion,true)
	await _frames(3)
	var press := InputEventMouseButton.new()
	press.position = at
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press,true)
	await _frames(3)
	press = press.duplicate()
	press.pressed = false
	root.push_input(press,true)
	await _frames(3)

func _check(condition: bool, title: String) -> void:
	checks += 1
	if not condition:
		failures.append(title)
		push_error(title)

func _button(button: Button) -> void:
	_check(button != null and button.is_visible_in_tree() and not button.disabled,"real UI button is available")
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
	await _frames(4)

func _drag(start: Vector2, end: Vector2) -> void:
	root.warp_mouse(start)
	var press := InputEventMouseButton.new()
	press.position = start
	press.global_position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press,true)
	var move := InputEventMouseMotion.new()
	move.position = start+Vector2(20,-30)
	move.global_position = move.position
	move.relative = Vector2(20,-30)
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(move)
	await _frames(4)
	_check(root.gui_is_dragging(),"real equipment drag starts")
	move = move.duplicate()
	move.position = end
	move.global_position = end
	root.warp_mouse(end)
	Input.parse_input_event(move)
	await _frames(4)
	press = press.duplicate()
	press.position = end
	press.global_position = end
	press.pressed = false
	Input.parse_input_event(press)
	await _frames(4)
