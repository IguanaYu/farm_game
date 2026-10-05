extends SceneTree
## 矿洞现状截图（2026-10-05）：洞口营地 3D → 探险营地面板 → 第一层地图 →
## 自动打穿一/二层 → 第三层晶脉矿窟（地图/战斗/搜刮/采集/守门战/结算）。
## 需带窗口运行（headless 无渲染纹理）。


const OUT := "res://screenshots/mine_live_20261005"


func _initialize() -> void:
	_capture.call_deferred()


func _shot(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)


func _capture() -> void:
	var world: Node3D = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var hud: FarmHud = world.get_node("FarmCanvas/FarmHud")
	DirAccess.make_dir_recursive_absolute(OUT)

	# —— 1. 洞口营地 3D 场景（石拱洞口/篝火/战备台） ————————————————
	world.router.switch_to("cave_camp")
	await _shot("%s/01_cave_camp_3d.png" % OUT)

	# —— 2. 洞口点击后的探险营地面板（DEPTH 01/02/03 层级章节卡） ——————
	hud.open_expedition_hub()
	await _shot("%s/02_expedition_hub.png" % OUT)
	hud.close_expedition_panels()
	world.router.switch_to("farm")
	await process_frame

	# —— 3. 出发（内存摆拍：基础套装入胸挂，不写农场档） —————————————————
	var inventory := InventoryGame.new()
	inventory.bind(world.game.state["expedition"])
	inventory.grant_basic_kit()
	# 三栏改版：武器与草帽先上装备槽（保证第 1 回合有牌），其余基础件入胸挂。
	for instance in inventory.warehouse_list().duplicate():
		if str(instance["def_id"]) == "old_shortsword":
			inventory.equip(int(instance["instance_id"]), "main_weapon")
		elif str(instance["def_id"]) == "straw_hat":
			inventory.equip(int(instance["instance_id"]), "helmet")
	for instance in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	var depart := ExpeditionGame.depart(world.game, int(Time.get_unix_time_from_system()))
	if not depart["ok"]:
		push_error("CAPTURE_MINE_DEPART_FAIL: " + str(depart["reason"]))
		quit(1)
		return
	var expedition: ExpeditionGame = depart["game"]
	hud.active_expedition = expedition
	hud.map_panel.open(expedition)
	await _shot("%s/03_l1_map_start.png" % OUT)

	# —— 4. 自动打穿第一、二层（每排走 col 0，战斗自动判胜、不掉血） —————
	for expected in ["iron_root_deeps", "crystal_vein_deeps"]:
		var changed := _clear_layer(expedition)
		if changed != expected:
			push_error("CAPTURE_MINE_LAYER_FAIL: " + changed)
			quit(1)
			return

	# —— 5. 第三层：晶脉矿窟开局地图 ————————————————————————————————————
	hud.map_panel._refresh()
	await _shot("%s/04_l3_crystal_map_start.png" % OUT)

	# —— 6. 第三层首场战斗：节点预览 → 真实战斗 UI → 搜刮台 ————————————
	expedition.move_to(1, 0)
	hud.map_panel._refresh()
	await _shot("%s/05_l3_battle_node.png" % OUT)
	hud.map_panel._on_start_battle()
	await _shot("%s/06_l3_battle_screen.png" % OUT)
	_win_open_battle(hud)
	hud.battle_screen._on_close()
	await _shot("%s/07_l3_loot_panel.png" % OUT)
	expedition.leave_node()

	# —— 7. 中段推进到第 5 排采集点（辉晶矿脉） ————————————————————————
	for row in [2, 3, 4]:
		expedition.move_to(row, 0)
		if str(expedition.current_node()["type"]) in ["battle", "elite", "gate"]:
			_win_silent(expedition)
		expedition.leave_node()
	expedition.move_to(5, 0)
	hud.map_panel._refresh()
	await _shot("%s/08_l3_gather_node.png" % OUT)
	expedition.leave_node()
	expedition.move_to(6, 0)
	_win_silent(expedition)
	expedition.leave_node()
	expedition.move_to(7, 0)
	expedition.leave_node()

	# —— 8. 第 8 排守门战：晶暴君 ————————————————————————————————————————
	expedition.move_to(8, 0)
	hud.map_panel._refresh()
	await _shot("%s/09_l3_gate_node.png" % OUT)
	hud.map_panel._on_start_battle()
	await _shot("%s/10_l3_gate_battle_crystal_tyrant.png" % OUT)
	_win_open_battle(hud)
	hud.battle_screen._on_close()
	await process_frame

	# —— 9. 通关结算回执（gate_clear） ——————————————————————————————————
	var settled := expedition.leave_node()
	if not settled["ok"] or not settled.get("settlement", {}).has("settlement_id"):
		push_error("CAPTURE_MINE_SETTLE_FAIL: " + str(settled))
		quit(1)
		return
	hud.map_panel._show_settlement(settled["settlement"])
	await _shot("%s/11_l3_gate_clear_settlement.png" % OUT)
	print("CAPTURE_MINE_OK 11 screens -> ", OUT)
	world.queue_free()
	quit(0)


## 打穿一层：每排 col 0；战斗节点自动判胜；返回 layer_changed 或错误描述。
func _clear_layer(expedition: ExpeditionGame) -> String:
	for row in range(1, 9):
		var moved := expedition.move_to(row, 0)
		if not moved["ok"]:
			return "move r%dc0: %s" % [row, str(moved["reason"])]
		if str(expedition.current_node()["type"]) in ["battle", "elite", "gate"]:
			_win_silent(expedition)
		var left := expedition.leave_node()
		if not left["ok"]:
			return "leave r%dc0: %s" % [row, str(left["reason"])]
		if str(left.get("layer_changed", "")) != "":
			return str(left["layer_changed"])
	return "layer ended without gate change"


## 后台判胜（不经过战斗 UI）：清空敌人血量并直接结算。
func _win_silent(expedition: ExpeditionGame) -> void:
	var started := expedition.start_battle()
	var combat: CombatGame = started["combat"]
	_zero_enemies(combat)
	expedition.finish_battle(combat)


## 战斗 UI 判胜：对当前打开的战斗屏里的敌人清血（真实关闭走 _on_close 闭环）。
func _win_open_battle(hud: FarmHud) -> void:
	_zero_enemies(hud.battle_screen.combat)


func _zero_enemies(combat: CombatGame) -> void:
	for enemy in combat.state["enemies"]:
		enemy["hp"] = 0
		enemy["alive"] = false
	combat._events_check_outcome([])
