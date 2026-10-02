extends SceneTree
## 修复轮批次 B2（F-04）：合作局可玩闭环——共同投票选路、双端独立出牌与结束回合、
## 双方领取、共同撤离、跨端结算。全程真实面板路径（按钮信号/面板处理器），
## 不绕过会话裁定入口。存档落盘由面板子类拦截。


var failed := false


class ProbeRoomPanel extends RoomPanel:
	var fail_save := false

	func _save_farm() -> bool:
		return not fail_save


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# —— 建房→加入→准备→出发（真实按钮）——
	var host_panel := ProbeRoomPanel.new()
	host_panel.listen_port = 31984
	root.add_child(host_panel)
	host_panel.open(_fresh_game(1))
	_click(host_panel, "创建房间（主机）")

	var guest_panel := ProbeRoomPanel.new()
	guest_panel.listen_port = 31984
	root.add_child(guest_panel)
	guest_panel.open(_fresh_game(2))
	guest_panel.address_edit.text = "127.0.0.1"
	_click(guest_panel, "加入房间")
	await _pump(20)
	_click(host_panel, "准备／取消准备")
	await _pump(6)
	_click(guest_panel, "准备／取消准备")
	await _pump(6)
	_click(host_panel, "出发（主机，需全员准备）")
	await _pump(40)

	var host: SessionHost = host_panel.host
	var client: SessionClient = guest_panel.client
	if not _check(host != null and host.expedition != null, "出发：合作局已开局"):
		_finish()
		return
	var expedition: ExpeditionGame = host.expedition
	var run: Dictionary = expedition.run

	# —— 客机界面（真实 CoopClientPanel）——
	var coop_panel := CoopClientPanel.new()
	root.add_child(coop_panel)
	coop_panel.open(client)
	await _pump(10)

	# —— 主机地图与战斗界面（按 farm_hud 同款接线）——
	var map_panel := ExpeditionMapPanel.new()
	root.add_child(map_panel)
	map_panel.host_action_sink = func(kind: String, args: Dictionary) -> Dictionary:
		return host.host_action(kind, args)
	map_panel.open(expedition)
	var battle_screen: BattleScreen = preload("res://scenes/battle_screen.tscn").instantiate()
	battle_screen.action_sink = map_panel.host_action_sink
	battle_screen.combat_refresher = func() -> CombatGame:
		return host.expedition.restore_battle()
	battle_screen.player_key = "p1"
	root.add_child(battle_screen)
	map_panel.battle_start_requested.connect(func(combat: CombatGame) -> void:
		battle_screen.open_run(combat, "p1"))
	battle_screen.battle_closed.connect(func() -> void:
		map_panel.report_battle_result(battle_screen.last_combat)
		map_panel.battle_finished())

	## 摆拍地图：1 战斗、2/3 采集、4 休整撤离（客机镜像仍显示原图，但投票按行列号一致）。
	var rows: Array = run["map"]["rows"]
	rows[1] = [{"type": "battle", "risk": "normal", "hint": "对局测试", "col": 0}]
	rows[2] = [{"type": "gather", "risk": "normal", "hint": "对局测试", "col": 0}]
	rows[3] = [{"type": "gather", "risk": "normal", "hint": "对局测试", "col": 0}]
	rows[4] = [{"type": "rest_exit", "risk": "normal", "hint": "对局测试", "col": 0}]

	# —— F-04 验收1：一人投票不前进，双方同票才前进 ——
	map_panel._on_move(1, 0)
	await _pump(8)
	_check(int(run["current"]["row"]) == 0, "投票：主机单方投票不前进")
	_check(str((client.mirror_run.get("votes", {}) as Dictionary).get("p1", "")) == "1,0", "镜像：客机看到主机投票")
	if not _click(coop_panel, "·列 0"):
		_check(false, "投票：客机界面有列 0 投票按钮")
	await _pump(10)
	_check(int(run["current"]["row"]) == 1, "投票：双方同票后进入第 1 排")
	_check(int(client.mirror_run.get("current", {}).get("row", -1)) == 1, "镜像：客机位置同步")

	# —— F-04 验收2：双端独立出牌与结束回合 ——
	map_panel._on_start_battle()
	await _pump(10)
	_check(battle_screen.visible and battle_screen.combat != null, "战斗：主机界面打开")
	_check(int(battle_screen.combat.state["round"]) >= 1, "战斗：开局即第 1 回合（F-09 联动）")
	await _pump(10)
	var guest_battle: BattleScreen = coop_panel.battle_screen
	_check(guest_battle != null and guest_battle.visible, "战斗：客机战斗界面打开（p2 视角）")
	if _check(guest_battle.combat != null and guest_battle.combat.state["players"].has("p2"), "战斗：客机视角含 p2"):
		var p2: Dictionary = guest_battle.combat.state["players"]["p2"]
		var hand_before: int = (p2["hand"] as Array).size()
		var energy_before := int(p2["energy"])
		var played := false
		for card in (p2["hand"] as Array).duplicate():
			guest_battle._on_card_clicked(int(card["uid"]))
			guest_battle._on_target_clicked("e1")
			await _pump(12)
			var combat_now: CombatGame = host.expedition.restore_battle()
			var p2_now: Dictionary = combat_now.state["players"]["p2"]
			if (p2_now["hand"] as Array).size() < hand_before or int(p2_now["energy"]) < energy_before:
				played = true
				break
			## 该牌对 e1 不合法（掩护/自愈等）：换下一张继续试。
		_check(played, "出牌：客机出牌经主机裁定生效")
		_check(int(guest_battle.combat.state["players"]["p2"]["energy"]) <= energy_before,
			"出牌：客机界面按镜像刷新")
		guest_battle._on_end_turn()
		await _pump(10)
		_check(int(host.expedition.restore_battle().state["round"]) == 1, "共同回合：客机先结束不推进回合")
		battle_screen._on_end_turn()
		await _pump(10)
		_check(int(host.expedition.restore_battle().state["round"]) >= 2, "共同回合：双方结束后进入敌方阶段")

	# —— 强制胜利并收尾战斗（战斗规则已由 d26 覆盖）——
	var forced := host.expedition.restore_battle()
	for enemy in forced.state["enemies"]:
		enemy["hp"] = 0
		enemy["alive"] = false
	forced._events_check_outcome([])
	run["battle"] = forced.to_dict()
	battle_screen.combat = forced
	battle_screen._on_close()
	await _pump(12)
	_check(str(run["phase"]) == "node" and bool(run["resolved"]["r1c0"].get("battle_won", false)), "战斗：胜利收尾经裁定完成")
	await _pump(6)
	_check(guest_battle == null or not guest_battle.visible, "战斗：客机界面随阶段关闭")

	# —— F-04 验收3：双方各自领取（各自计领，编号不冲突）——
	var key1 := expedition.node_id(1, 0)
	var resolved1: Dictionary = run["resolved"][key1]
	var host_pack_before: int = expedition.member_inventory("p1").loadout_list("pack").size()
	map_panel._on_claim_reward(key1, str(resolved1["rewards"][0]), "pack", true)
	await _pump(6)
	_check(expedition.member_inventory("p1").loadout_list("pack").size() == host_pack_before + 1, "领取：主机领取成功")
	if not _click(coop_panel, "放入背包"):
		_check(false, "领取：客机界面有领取按钮")
	await _pump(10)
	var guest_items: Array = expedition.member_inventory("p2").loadout_list("pack")
	_check(guest_items.size() >= 1, "领取：客机领取经主机裁定成功")
	if guest_items.size() >= 1 and host_pack_before >= 0:
		var host_ids := {}
		for instance in expedition.member_inventory("p1").loadout_list("pack"):
			host_ids[int(instance["instance_id"])] = true
		for instance in guest_items:
			_check(not host_ids.has(int(instance["instance_id"])), "领取：双端实例编号不冲突（F-01 联动）")

	# —— 采集两排 + 休整撤离站（先离开当前节点，再双票前进）——
	for target_row in [2, 3, 4]:
		if not _click(coop_panel, "离开本节点"):
			_check(false, "节点：客机离开按钮存在（第 %d 排前）" % target_row)
		await _pump(10)
		map_panel._on_move(target_row, 0)
		await _pump(6)
		if not _click(coop_panel, "·列 0"):
			_check(false, "投票：第 %d 排客机投票按钮存在" % target_row)
		await _pump(10)
		_check(int(run["current"]["row"]) == target_row, "推进：第 %d 排经双票到达" % target_row)

	# —— F-04 验收4：共同撤离与跨端结算 ——
	_click(coop_panel, "投票撤离")
	await _pump(10)
	_check(str(run.get("outcome", "")) == "", "撤离：客机单方确认不结算")
	map_panel._open_extract_confirm()
	await _pump(4)
	if not _click(map_panel, "带着这些回家"):
		_check(false, "撤离：主机撤离按钮存在")
	await _pump(20)
	_check(str(run.get("outcome", "")) == "extract", "撤离：双方确认后整局结算")
	var guest_game: FarmGame = guest_panel.game
	_check(str(guest_game.state["expedition"]["inventory"]["occupied_by_run"]) == "", "跨端：客机占用解除")
	_check((guest_game.state["expedition"].get("applied_settlements", []) as Array).size() >= 1, "跨端：客机结算已应用")
	_finish()


func _click(panel: Control, text: String) -> bool:
	for button in panel.find_children("*", "Button", true, false):
		if str(button.text).find(text) != -1 and not button.disabled:
			button.pressed.emit()
			return true
	return false


func _pump(frames: int) -> void:
	for attempt in range(frames):
		await process_frame
		OS.delay_msec(3)


func _fresh_game(marker: int) -> FarmGame:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261200 + marker)
	game.new_game(1000)
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	for instance in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	return game


func _finish() -> void:
	if failed:
		push_error("D32_COOP_PLAY_UI_FAIL")
	else:
		print("D32_COOP_PLAY_UI_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> bool:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
	return ok
