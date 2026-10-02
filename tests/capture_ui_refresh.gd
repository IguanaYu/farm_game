extends SceneTree
## 带窗口运行；--headless 仅跑交互/布局断言。独立内存新档，不加载或保存玩家档案。
## godot --path . --script res://tests/capture_ui_refresh.gd

class PreviewWorld extends "res://scripts/world/farm_world.gd":
	func _ready() -> void:
		game = FarmGame.new()
		game.set_debug_random_seed(20261002)
		game.new_game(_now())
		_build_farm()
		var canvas := CanvasLayer.new()
		canvas.name = "FarmCanvas"
		add_child(canvas)
		hud = FarmHud.new()
		hud.game = game
		hud.view_now = _now()
		canvas.add_child(hud)
		_refresh_all()

var failed := false
var hud: FarmHud
var game: FarmGame
var snapshot: Dictionary
var shot_count := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error("UI_REFRESH_FAIL: " + message)


func _settle() -> void:
	for _i in range(5):
		await process_frame


func _shot(name: String) -> void:
	await _settle()
	if hud.modal_overlay.visible:
		_check(hud.modal_content.size.x <= hud.modal_scroll.size.x + 1, name + " content fits horizontally")
		_check(hud.modal_panel.get_global_rect().end.x <= root.get_visible_rect().end.x + 1, name + " panel fits viewport")
		_check(hud.modal_panel.get_global_rect().position.y >= -1, name + " panel fits vertically")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://screenshots/ui_refresh/%s.png" % name)
	shot_count += 1
	print("UI_REFRESH_SCREEN ", name)


func _button(parent: Node, caption: String) -> Button:
	for node in parent.find_children("*", "Button", true, false):
		if node.text == caption:
			return node
	return null


func _click(button: Button) -> void:
	_check(button != null and button.is_visible_in_tree(), "click target is visible")
	if button == null:
		return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await _settle()


func _run() -> void:
	var world := PreviewWorld.new()
	root.add_child(world)
	await _settle()
	hud = world.hud
	game = world.game
	var now := hud.view_now
	game.state["coins"] = 800
	game.plant(1, now - 1300)
	game.plant(2, now - 1300)
	game.plant(3, now - 180)
	game.water(3, now - 120)
	game.state["tutorial_step"] = 1
	game.add_seed_with_traits("cabbage", [{"effect": "water_guarantee", "tier": 2}, {"effect": "fiber_tendency", "tier": 3}, {"effect": "color_guarantee", "tier": 2}, {"effect": "water_tendency", "tier": 3}])
	game.add_seed_with_traits("carrot", [{"effect": "color_tendency", "tier": 1}])
	game.add_seed_with_traits("glow_berry", [{"effect": "water_tendency", "tier": 0}])
	game.add_seed_with_traits("rock_sprout", [])
	world._refresh_all()
	await _shot("01_farm")
	_check(hud.harvest_all_entry.visible, "mature plots expose harvest action")
	_check(hud.harvest_all_entry.get_node("ActionStack/ActionCaption").text == "收获 · 2", "harvest count updates visible caption")
	_check(not hud.get_node("FarmCounters").get_global_rect().intersects(hud.tutorial_panel.get_global_rect()), "tutorial does not cover resource counters")

	snapshot = game.state.duplicate(true)
	hud.open_shop()
	await _shot("02_shop")
	var details := hud.modal_content.find_child("Disclosure_product_cabbage", true, false)
	_check(not details.get_node("DetailsBody").visible, "product rules start collapsed")
	details.get_child(0).button_pressed = true
	_check(details.get_node("DetailsBody").visible, "rules expand")
	hud.refresh(game.state)
	details = hud.modal_content.find_child("Disclosure_product_cabbage", true, false)
	_check(details.get_node("DetailsBody").visible, "expanded state survives refresh")
	await _shot("03_shop_details")
	hud.expanded_details.clear()
	await _click(_button(hud.modal_content, "肥料"))
	_check(hud.shop_tab == "fertilizers", "shop tab switches category")
	await _shot("04_fertilizers")
	_button(hud.modal_content, "设施").pressed.emit()
	await _shot("05_facilities")

	hud.open_seed_picker(4)
	await _shot("06_seed_picker")
	var selected := {"plot": 0, "seed": 0}
	hud.plant_seed_requested.connect(func(plot_id: int, seed_id: int): selected["plot"] = plot_id; selected["seed"] = seed_id)
	_button(hud.modal_content, "播种").pressed.emit()
	_check(selected["plot"] == 4 and game.state["seeds"].any(func(seed): return seed["id"] == selected["seed"]), "plant action carries real selected seed ID")
	hud.open_warehouse("seeds")
	await _shot("07_seeds")
	_button(hud.modal_content, "萤果").pressed.emit()
	_check(hud.modal_content.find_children("SeedCard_*", "PanelContainer", true, false).size() == 1, "rare seed filter works")
	hud._change_seed_filter("all")
	hud.open_plot_care(3)
	await _shot("08_care")
	var label_before := hud.care_remaining_label
	hud.tick_update(now + 1)
	_check(label_before == hud.care_remaining_label, "care countdown does not rebuild controls")
	_check(hud.care_water_button.disabled, "used watering segment disables level-one watering")
	hud.tick_update(game.get_plot(3)["ready_at"])
	_check(hud.care_remaining_label.text.contains("已成熟") and not hud.care_water_button.visible, "care changes state at maturity")
	_check(game.state == snapshot, "UI browsing and signal dispatch do not alter rules or inventory")

	var harvest := game.harvest(1, now)
	_check(harvest["ok"], "preview harvest succeeds")
	hud.refresh(game.state)
	hud.show_harvest(harvest)
	await _shot("09_harvest")
	var score := hud.modal_content.find_child("Disclosure_harvest_score", true, false)
	score.get_child(0).button_pressed = true
	await _shot("10_harvest_details")
	var all := game.harvest_all(now)
	hud.refresh(game.state)
	hud.show_harvest_all(all)
	await _shot("11_harvest_all")
	hud.open_warehouse()
	await _shot("12_crops")
	hud.open_market()
	await _shot("13_market")
	var batch: Dictionary = game.state["crop_batches"][0]
	var market_card := hud.modal_content.find_child("MarketBatch_%d" % batch["id"], true, false)
	var option: OptionButton = market_card.find_child("SellCountOption", true, false)
	option.select(0)
	option.item_selected.emit(0)
	_check(hud.market_sell_counts[batch["id"]] == 1, "split quantity is retained after refresh")
	var sold := {"batch": 0, "count": 0, "guest": 0}
	hud.sell_batch_to_requested.connect(func(batch_id: int, count: int, guest_id: int): sold["batch"] = batch_id; sold["count"] = count; sold["guest"] = guest_id)
	_button(hud.modal_content, "卖给他").pressed.emit()
	_check(sold["batch"] == batch["id"] and sold["count"] == 1, "sale action uses selected split quantity")
	var config := hud.modal_content.find_child("Disclosure_market_config", true, false)
	config.get_child(0).button_pressed = true
	await _shot("14_market_details")

	# 高等级折扣与待领取：不要让精简展示误报价格或隐藏溢出产出。
	game.state["shop_level"] = 3
	game.state["pending"]["crops"].append(batch.duplicate(true))
	game.state["pending"]["seeds"].append(game.state["seeds"][0].duplicate(true))
	hud.refresh(game.state)
	hud.shop_tab = "seeds"
	hud.open_shop()
	var actual_price := MarketDefs.discounted_total(PlantDefs.get_plant("cabbage")["seed_price"], 3)
	_check(_button(hud.modal_content, "1 粒 · %d 金" % actual_price) != null, "seed price reflects rule-layer discount")
	await _shot("15_discount_shop")
	hud.open_warehouse()
	await _shot("16_pending")
	var pending := hud.modal_content.find_child("Disclosure_pending_items", true, false)
	pending.get_child(0).button_pressed = true
	await _shot("16b_pending_details")
	hud.open_breeder()
	await _shot("17_breeder")
	game.state["coins"] = 30000
	game.state["farming_exp"] = 120
	game.state["breeder"]["owned"] = true
	var trait_seed: Dictionary = game.state["seeds"].filter(func(seed): return seed.get("traits", []).size() == 4)[0]
	game.set_breeder_template(trait_seed["id"], now)
	game.breeder_settle(now + 1800)
	hud.refresh(game.state)
	await _shot("18_breeder_template")
	hud.close_modal_after_action()
	_check(not hud.modal_overlay.visible and hud.active_modal == "", "modal closes completely")
	print("UI_REFRESH_%s · %d screens" % ["FAIL" if failed else "PASS", shot_count])
	quit(1 if failed else 0)
