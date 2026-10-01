extends SceneTree
## 2.7：故障矩阵（总计划 §9.4 表的自动化子集）——掉线暂停、重连恢复、
## 主机重启接回、未确认结算重发（幂等）。单人暂停/强退恢复由 d24_recovery_sim 覆盖。


var failed := false
var pump_list: Array = []
var client_settlements: Array = []


func _initialize() -> void:
	# ========== 场景一：出牌中掉线 → 重连；撤离后结算补发 ==========
	var host_game := _fresh_game()
	var client_game := _fresh_game()
	var host := SessionHost.new()
	host.listen(host_game, 31990)
	var client := SessionClient.new()
	client.connect_to_host("127.0.0.1", client_game, 31990)
	pump_list = [host, client]
	_pump(300)
	var inv := InventoryGame.new()
	inv.bind(client_game.state["expedition"])
	client.hello_with("p-recovery", inv)
	host.host_set_ready(true)
	client.set_ready(true)
	_pump(60)
	host.begin_depart()
	_pump(60)
	var confirm := client.confirm_depart()
	_check(confirm["ok"], "开局前：客机写入占用并回执")
	_pump(150)
	_check(host.expedition != null, "开局：双人局建立")

	host.host_action("vote_move", {"row": 1, "col": 0})
	client.send_action("vote_move", {"row": 1, "col": 0})
	_pump(60)
	host.host_action("start_battle")
	_check(str(host.expedition.run["phase"]) == "battle", "战斗：进行中")

	# —— 重连：同 player_id 换新连接对象接回原成员位（旧连接先断开）——
	client.disconnect_link()
	_pump(30)
	var client2 := SessionClient.new()
	client2.connect_to_host("127.0.0.1", client_game, 31990)
	pump_list = [host, client2]
	_pump(40)
	var inv2 := InventoryGame.new()
	inv2.bind(client_game.state["expedition"])
	client2.hello_with("p-recovery", inv2)
	_pump(60)
	var rejoined := false
	var member_count := 0
	for member_id in host.room["members"]:
		member_count += 1
		if int(member_id) != 1 and str(host.room["members"][member_id].get("player_id", "")) == "p-recovery":
			rejoined = true
	_check(rejoined and member_count == 2, "重连：同 player_id 接回原成员位（不新增占位）")

	_check(not client2.mirror_run.is_empty() and str(client2.mirror_run.get("phase", "")) == "battle", "重连：收到完整快照（战斗阶段）")
	var combat_after := host.expedition.restore_battle()
	var mirror_battle: Dictionary = client2.mirror_run.get("battle", {})
	_check(int(mirror_battle.get("round", -1)) == int(combat_after.state["round"]), "重连：回合一致")
	var mirror_p2: Dictionary = (mirror_battle.get("players", {}) as Dictionary).get("p2", {})
	_check(int(mirror_p2.get("hand", []).size()) == int(combat_after.state["players"]["p2"]["hand"].size()), "重连：手牌一致（不重抽）")

	# —— 掉线期间：主机暂停推进 ——
	for member_id in host.room["members"].keys():
		if int(member_id) != 1:
			host.room["members"][member_id]["online"] = false
	var paused := host.host_action("vote_move", {"row": 2, "col": 0})
	_check(not paused["ok"] and str(paused["reason"]).find("暂停") >= 0, "掉线：主机暂停推进（不判撤离也不判失败）")
	for member_id in host.room["members"].keys():
		if int(member_id) != 1:
			host.room["members"][member_id]["online"] = true

	# —— 打完整局并撤离（客机用 client2 继续）——
	var quick := host.expedition.restore_battle()
	for enemy in quick.state["enemies"]:
		enemy["hp"] = 0
		enemy["alive"] = false
	quick._events_check_outcome([])
	host.expedition.run["battle"] = quick.to_dict()
	host.host_action("finish_battle")
	host.host_action("leave_node")
	for row in [2, 3]:
		client2.send_action("vote_move", {"row": row, "col": 0})
		_pump(40)
		host.host_action("vote_move", {"row": row, "col": 0})
		if str(host.expedition.current_node()["type"]) in ["battle", "elite", "gate"]:
			host.host_action("start_battle")
			var q := host.expedition.restore_battle()
			for enemy in q.state["enemies"]:
				enemy["hp"] = 0
				enemy["alive"] = false
			q._events_check_outcome([])
			host.expedition.run["battle"] = q.to_dict()
			host.host_action("finish_battle")
		host.host_action("leave_node")
	client2.send_action("vote_move", {"row": 4, "col": 0})
	_pump(40)
	host.host_action("vote_move", {"row": 4, "col": 0})
	client2.send_action("vote_extract", {"agree": true})
	_pump(60)
	host.host_action("vote_extract", {"agree": true})
	_pump(80)
	_check(str(host.expedition.run["outcome"]) == "extract", "撤离：双确认结算完成")
	_check(client_game.state["expedition"]["applied_settlements"].size() >= 1, "撤离：客机已应用结算")

	# —— 结算补发（幂等）：新连接重连触发未确认重发，重复应用不双发 ——
	var applied_before: int = client_game.state["expedition"]["inventory"]["warehouse"].size()
	var client3 := SessionClient.new()
	client3.connect_to_host("127.0.0.1", client_game, 31990)
	pump_list = [host, client3]
	_pump(40)
	var inv3 := InventoryGame.new()
	inv3.bind(client_game.state["expedition"])
	client3.hello_with("p-recovery", inv3)
	_pump(100)
	_check(client_game.state["expedition"]["applied_settlements"].size() >= 1, "重发：结算重复送达只回执（幂等）")
	_check(client_game.state["expedition"]["inventory"]["warehouse"].size() == applied_before, "重发：不重复发放物品")

	# ========== 场景二：主机"崩溃"→ 局档恢复 → 成员接回 ==========
	var host2_game := _fresh_game()
	var client4_game := _fresh_game()
	var host2 := SessionHost.new()
	host2.listen(host2_game, 31991)
	var client4 := SessionClient.new()
	client4.connect_to_host("127.0.0.1", client4_game, 31991)
	pump_list = [host2, client4]
	_pump(300)
	var inv4 := InventoryGame.new()
	inv4.bind(client4_game.state["expedition"])
	client4.hello_with("p-host-recovery", inv4)
	host2.host_set_ready(true)
	client4.set_ready(true)
	_pump(60)
	host2.begin_depart()
	_pump(60)
	_check(client4.confirm_depart()["ok"], "第二局：客机确认")
	_pump(150)
	_check(host2.expedition != null, "第二局：开局成功")
	host2.host_action("vote_move", {"row": 1, "col": 0})
	client4.send_action("vote_move", {"row": 1, "col": 0})
	_pump(60)
	host2.host_action("start_battle")
	host2.expedition.save()
	var run_id := str(host2.expedition.run["run_id"])

	## 主机"崩溃"＝丢弃会话对象；新主机用同一农场档恢复局并接回成员。
	pump_list = []
	var resurrected := ExpeditionGame.resume(host2_game)
	_check(resurrected["ok"], "主机恢复：从局档接回活动局")
	_check(str(resurrected["game"].run["run_id"]) == run_id, "主机恢复：局 ID 不变（不重开一局）")
	var host3 := SessionHost.new()
	host3.listen(host2_game, 31992)
	host3.attach_resumed_run(resurrected["game"])
	var client5 := SessionClient.new()
	client5.connect_to_host("127.0.0.1", client4_game, 31992)
	pump_list = [host3, client5]
	_pump(300)
	var inv5 := InventoryGame.new()
	inv5.bind(client4_game.state["expedition"])
	client5.hello_with("p-host-recovery", inv5)
	_pump(80)
	var rejoined3 := false
	for member_id in host3.room["members"]:
		if int(member_id) != 1 and str(host3.room["members"][member_id].get("player_id", "")) == "p-host-recovery":
			rejoined3 = true
	_check(rejoined3, "主机恢复：成员在新主机上接回原成员位")
	_check(not client5.mirror_run.is_empty() and int(client5.mirror_run.get("current", {}).get("row", -1)) == 1, "主机恢复：快照为崩溃前进度（第 1 排，战斗阶段）")
	_check(str(client5.mirror_run.get("phase", "")) == "battle", "主机恢复：阶段一致（战斗中）")

	_finish()


func _pump(frames: int) -> void:
	for attempt in range(frames):
		for entry in pump_list:
			if entry != null:
				entry.poll()
		OS.delay_msec(5)


func _fresh_game() -> FarmGame:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261100 + (_fresh_seed))
	_fresh_seed += 1
	game.new_game(1000)
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	for instance in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	return game


var _fresh_seed := 0


func _finish() -> void:
	if failed:
		push_error("D27_RECOVERY_MATRIX_FAIL")
	else:
		print("D27_RECOVERY_MATRIX_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
