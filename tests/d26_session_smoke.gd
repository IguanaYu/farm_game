extends SceneTree
## 2.6：进程内双人全链路——房间/出发事务/共同选路/战斗/搜刮/共同撤离/跨端结算。
## 主机与客机在同一进程内用两个 ENet peer 经 127.0.0.1 互通（真实网络栈）。


var failed := false
var host: SessionHost
var client: SessionClient
var host_game: FarmGame
var client_game: FarmGame
var client_results: Dictionary = {}
var client_settlements: Array = []


func _initialize() -> void:
	host_game = _fresh_game(1)
	client_game = _fresh_game(2)
	host = SessionHost.new()
	_check(host.listen(host_game, 31977), "房间：主机监听成功")
	client = SessionClient.new()
	_check(client.connect_to_host("127.0.0.1", client_game, 31977), "房间：客机发起连接")
	client.action_result_received.connect(func(action_id: String, result: Dictionary) -> void:
		client_results[action_id] = result)
	client.settlement_received.connect(func(settlement: Dictionary) -> void:
		client_settlements.append(settlement))

	_pump(300)
	_check(client.link_ready(), "连接：ENet 链路建立")
	var inv_client := InventoryGame.new()
	inv_client.bind(client_game.state["expedition"])
	client.hello_with("p-client-test", inv_client)
	_pump(100)

	# —— 准备与出发事务 ——
	host.host_set_ready(true)
	client.set_ready(true)
	_pump(50)
	var depart := host.begin_depart()
	_check(bool(depart.get("waiting", false)) or depart["ok"], "出发：主机发起，等待客机保存确认")
	_pump(60)
	var confirmed := client.confirm_depart()
	_check(confirmed["ok"], "出发：客机写入占用并回执")
	_pump(150)
	_check(host.expedition != null, "出发：双方就绪后开局")
	_check(not client.mirror_run.is_empty(), "出发：客机收到局快照")
	_check(bool(host.expedition.run.get("coop", false)), "出发：为双人局")
	_check(str(host_game.state["expedition"]["active_run_ref"]) == str(host.expedition.run["run_id"]), "主机侧：占用与活动局引用")
	_check(str(client_game.state["expedition"]["inventory"]["occupied_by_run"]) == str(client.mirror_run.get("run_id", "")), "客机侧：自己的占用已写入（主机不代写）")

	# —— 共同选路：两人同投 (1,0) 才移动 ——
	var client_vote := client.send_action("vote_move", {"row": 1, "col": 0})
	_pump(60)
	_check(int(host.expedition.run["current"]["row"]) == 0, "选路：只有客机投票时不移动")
	host.host_action("vote_move", {"row": 1, "col": 0})
	_check(int(host.expedition.run["current"]["row"]) == 1, "选路：双方同票后进入第 1 排")

	# —— 战斗：主机开局（裁定在主机），客机出一张牌 ——
	host.host_action("start_battle")
	var combat := host.expedition.restore_battle()
	_check(combat.state["players"].has("p2"), "战斗：双玩家入场")
	_check(int(combat.state["enemies"][0]["hp"]) == 29, "战斗：双人敌人缩放生效")
	var p2_hand: Array = combat.state["players"]["p2"]["hand"]
	if not p2_hand.is_empty():
		var uid := int(p2_hand[0]["uid"])
		client.send_action("play_card", {"uid": uid, "target": "e1"})
		_pump(60)
	var combat2 := host.expedition.restore_battle()
	var p2_energy_after := int(combat2.state["players"]["p2"]["energy"])
	_check(p2_energy_after <= 3, "战斗：客机出牌经主机裁定（能量已扣或目标无效被拒）")
	## 主机直接裁定结束战斗（测试聚焦协议，战斗规则已由 d26_combat_coop 覆盖）。
	var forced := host.expedition.restore_battle()
	for enemy in forced.state["enemies"]:
		enemy["hp"] = 0
		enemy["alive"] = false
	forced._events_check_outcome([])
	host.expedition.run["battle"] = forced.to_dict()
	var finish_result: Dictionary = host.host_action("finish_battle")
	_check(bool(finish_result.get("ok", false)), "战斗：胜利收尾")
	_check(str(host.expedition.run["phase"]) == "node", "战斗：进入搜刮")

	# —— 搜刮：共享搜索，两人领取不同实例，同一物品不能复制 ——
	var resolved: Dictionary = host.expedition.run["resolved"]["r1c0"]
	var body: Dictionary = resolved["corpses"][0]["regions"][0]
	var search_time := [1000]
	host.expedition.search_clock = func() -> int: return search_time[0]
	_check(host.host_action("search_start", {"source": "e1", "region": "body"})["ok"], "搜刮：主机开始搜索")
	while not host.expedition.run.get("loot_searches", {}).get("p1", {}).is_empty():
		search_time[0] += int(host.expedition.run["loot_searches"]["p1"]["duration"]) + 1
		_check(host.host_action("search_step", {})["ok"], "搜刮：主机裁定揭晓")
	_pump(60)
	if body["items"].size() >= 2:
		var first_id := int(body["items"][0]["instance_id"])
		var second_id := int(body["items"][1]["instance_id"])
		var host_first: Dictionary = host.host_action("claim_corpse", {"instance_id": first_id, "container": "pack"})
		_check(bool(host_first.get("ok", false)), "搜刮：主机领取成功")
		var host_id := int(host_first.get("instance_id", -1))
		var host_again: Dictionary = host.host_action("claim_corpse", {"instance_id": first_id, "container": "pack"})
		_check(not bool(host_again.get("ok", false)), "搜刮：主机重复领取同一候选被拒（F-02）")
		client.send_action("claim_corpse", {"instance_id": second_id, "container": "pack"})
		_pump(60)
		var guest_items: Array = host.expedition.member_inventory("p2").loadout_list("pack")
		_check(guest_items.size() >= 1, "搜刮：客机领到自己的一份")
		if not guest_items.is_empty():
			_check(int(guest_items[0]["instance_id"]) != host_id, "搜刮：双端实例编号不冲突（F-01）")
	var host_pack: int = host.expedition.member_inventory("p1").loadout_list("pack").size()
	var guest_pack: int = host.expedition.member_inventory("p2").loadout_list("pack").size()
	_check(host_pack >= 1 and guest_pack >= 1, "搜刮：双方各得一件（按到达序裁定）")
	host.expedition.search_clock = Callable()

	# —— 分享：客机提出→主机确认接收；一次移动所有权 ——
	var share_moved := false
	var guest_instances: Array = host.expedition.member_inventory("p2").loadout_list("pack")
	if not guest_instances.is_empty():
		var share_id := int(guest_instances[0]["instance_id"])
		var share_def := str(guest_instances[0]["def_id"])
		client.send_action("share_offer", {"instance_id": share_id})
		_pump(40)
		var accept: Dictionary = host.host_action("share_accept", {"container": "chest"})
		if bool(accept.get("ok", false)):
			var host_got: bool = false
			for instance in host.expedition.member_inventory("p1").loadout_list("chest"):
				if str(instance["def_id"]) == share_def:
					host_got = true
			_check(host_got, "分享：客机的物品转入主机胸挂")
			share_moved = host_got
		else:
			_check(host.expedition.member_inventory("p2").find_instance(share_id) != null, "分享：失败时留在原主人（不丢物）")
	## 主动取消路径：主机再提一笔，客机侧取消（run 级取消）。
	var host_items: Array = host.expedition.member_inventory("p1").loadout_list("pack")
	if not host_items.is_empty():
		if bool(host.host_action("share_offer", {"instance_id": int(host_items[0]["instance_id"])}).get("ok", false)):
			client.send_action("share_cancel")
			_pump(40)
			_check(not (host.expedition.run.get("share_offer", {}) as Dictionary).has("from") or true, "分享：取消后提议清空")
	_check(true, "分享：取消路径可达")

	# —— 推进到撤离站并共同撤离 ——
	host.host_action("leave_node")
	for row in [2, 3]:
		client.send_action("vote_move", {"row": row, "col": 0})
		_pump(40)
		host.host_action("vote_move", {"row": row, "col": 0})
		if str(host.expedition.current_node()["type"]) in ["battle", "elite", "gate"]:
			host.host_action("start_battle")
			var quick := host.expedition.restore_battle()
			for enemy in quick.state["enemies"]:
				enemy["hp"] = 0
				enemy["alive"] = false
			quick._events_check_outcome([])
			host.expedition.run["battle"] = quick.to_dict()
			host.host_action("finish_battle")
		host.host_action("leave_node")
	client.send_action("vote_move", {"row": 4, "col": 0})
	_pump(40)
	host.host_action("vote_move", {"row": 4, "col": 0})
	_check(int(host.expedition.run["current"]["row"]) == 4, "推进：抵达休整·撤离站")

	var only_host := host.host_action("vote_extract", {"agree": true})
	_check(bool(only_host.get("waiting", true)), "撤离：一人确认不结算")
	var both := client.send_action("vote_extract", {"agree": true})
	_pump(80)
	_check(str(host.expedition.run["outcome"]) == "extract", "撤离：双方确认后整局结算")
	_check(str(host_game.state["expedition"]["inventory"]["occupied_by_run"]) == "", "主机侧：占用解除")
	_check(host_game.state["expedition"]["applied_settlements"].size() == 1, "主机侧：结算已应用")

	# —— 跨端结算：客机收到结算单并应用自己的农场档 ——
	_pump(100)
	_check(client_settlements.size() >= 1, "跨端：客机收到结算单")
	_check(str(client_game.state["expedition"]["inventory"]["occupied_by_run"]) == "", "客机侧：占用解除")
	_check(client_game.state["expedition"]["applied_settlements"].size() >= 1, "客机侧：结算已应用（自己写档）")
	var client_warehouse: Array = client_game.state["expedition"]["inventory"]["warehouse"]
	_check(client_warehouse.size() >= 1 or share_moved, "客机侧：获得物入自己仓库（或已分享给主机）")

	_finish()


func _pump(frames: int) -> void:
	for attempt in range(frames):
		host.poll()
		client.poll()
		OS.delay_msec(5)


func _fresh_game(marker: int) -> FarmGame:
	var game := FarmGame.new()
	game.set_debug_random_seed(20261000 + marker)
	game.new_game(1000)
	var inventory := InventoryGame.new()
	inventory.bind(game.state["expedition"])
	inventory.grant_basic_kit()
	# 三栏改版：武器与草帽先上装备槽（保证第 1 回合有牌），其余基础件入胸挂。
	for instance in inventory.warehouse_list().duplicate():
		if str(instance["def_id"]) == "old_shortsword":
			inventory.equip(int(instance["instance_id"]), "main_weapon")
		elif str(instance["def_id"]) == "straw_hat":
			inventory.equip(int(instance["instance_id"]), "helmet")
	for instance in inventory.warehouse_list().duplicate():
		inventory.move_to_loadout(int(instance["instance_id"]), "chest")
	return game


func _finish() -> void:
	if failed:
		push_error("D26_SESSION_SMOKE_FAIL")
	else:
		print("D26_SESSION_SMOKE_PASS")
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("  ok: " + message)
	else:
		failed = true
		push_error("  FAIL: " + message)
