extends SceneTree
## d45：M3 房间/洞窟/结算全链路（计划：docs/plan/Godot_合并路线_R1_M3_洞窟与资产闭环_代码执行计划_v0.1.md §7）。
## 自编排（沿 d42 模式）：进程内建库生成邀请码 → 子进程跑 server_main → 四客户端走真实
## WSS+证书钉扎。覆盖：
##   段1 房间生命周期（C01/C03/C04：错误码/满员/准备/重复建房）
##   段2 出发事务与强杀重启（S01/S07：占用写入/重启恢复/重连回局/动作重放去重）
##   段3 双人全链路（C06~C08/C10/S03：投票选路/真打牌取胜/搜刮/休整/共同撤离/双方逐件对账）
##   段4 单人全链路（C05/S03：直通选路/撤离结算/占用解除）
##   段5 双房并行（C02/T08：两 run 交错动作不串局）
##   段6 去重与冲突（S02/T04：同号同参 duplicate/同号异参冲突）
## 输出：D45-PASS/D45-FAIL 逐条；退出码 0=通过。
## 用法：Godot --headless --path . --script res://tests/d45_online_room_run_smoke.gd

const PORT := 31989
const REQ_TIMEOUT_MS := 8000

var godot_exe := ""
var project_dir := ""
var db_path := ""
var cert_path := ""
var key_path := ""
var server_pid := 0
var failed := false
var fail_count := 0
var checks := 0
var req_seq := 0


func _initialize() -> void:
	_setup()
	_run()
	_cleanup()
	quit(1 if failed else 0)


func _setup() -> void:
	godot_exe = OS.get_executable_path()
	project_dir = ProjectSettings.globalize_path("res://")
	db_path = project_dir.path_join(".zcode/m1/run/d45_farm.db")
	cert_path = project_dir.path_join("server/secrets/farm_server.crt")
	key_path = project_dir.path_join("server/secrets/farm_server.key")
	DirAccess.make_dir_recursive_absolute(project_dir.path_join(".zcode/m1/run"))
	for suffix in ["", "-wal", "-shm"]:
		var path: String = db_path + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _run() -> void:
	var store := ServerDB.new()
	if not store.open(db_path):
		_check(false, "测试库打开失败（SQLite 扩展未加载？）")
		return
	var auth := AuthService.new()
	auth.store = store
	var codes: Array = auth.generate_invites(4, "d45")
	store.close()
	if codes.size() != 4:
		_check(false, "邀请码生成失败")
		return
	if not _spawn_server():
		return
	var a := _client()
	var b := _client()
	var c := _client()
	var d := _client()
	for client in [a, b, c, d]:
		if not client.connect_to(PORT):
			_check(false, "四客户端连接失败")
			return
	_check(true, "四客户端 WSS 连接（证书钉扎）")

	# —— 段0：激活 + 基础套装入胸挂（首回合牌库非空） ——
	var tokens := {}
	for pair in [["a", a, codes[0], "玩家甲"], ["b", b, codes[1], "玩家乙"], ["c", c, codes[2], "玩家丙"], ["d", d, codes[3], "玩家丁"]]:
		var welcome: Dictionary = (pair[1] as WsClient).activate(str(pair[2]), str(pair[3]))
		if str(welcome.get("t", "")) != "welcome":
			_check(false, "%s 激活失败：%s" % [pair[0], JSON.stringify(welcome).substr(0, 160)])
			return
		tokens[pair[0]] = str(welcome["token"])
		if not _prepare_loadout(pair[1] as WsClient, str(pair[0])):
			return
	_check(true, "四账户激活并完成战备（基础套装入胸挂）")

	# —— 段1：房间生命周期 ——
	var created: Dictionary = a.request("room.create", {}, _rid("a"))
	if not _check_ok(created, "甲建房"):
		return
	var code := str(created["result"].get("code", ""))
	_check(code.length() == 6, "房码 6 位（%s）" % code)
	var dup_create: Dictionary = a.request("room.create", {}, _rid("a"))
	_check(_is_op_failed(dup_create, "已在房间中"), "重复建房 → op_failed 已在房间中")

	var bad_join: Dictionary = b.request("room.join", {"code": "ZZZZZZ"}, _rid("b"))
	_check(_is_op_failed(bad_join, "房码无效"), "无效房码 → op_failed 房码无效")
	var joined: Dictionary = b.request("room.join", {"code": code}, _rid("b"))
	if not _check_ok(joined, "乙按房码加入"):
		return
	var rejoined: Dictionary = b.request("room.join", {"code": code}, _rid("b"))
	_check(_is_op_failed(rejoined, "已在这个房间"), "重复加入 → op_failed 已在这个房间")
	var full: Dictionary = c.request("room.join", {"code": code}, _rid("c"))
	_check(_is_op_failed(full, "房间已满"), "第三人加入 → op_failed 房间已满（双人）")

	var early: Dictionary = a.request("room.begin_depart", {}, _rid("a"))
	_check(_is_op_failed(early, "未准备"), "无人准备出发 → op_failed 还有成员未准备")

	var ready_b: Dictionary = b.request("room.ready", {"ready": true}, _rid("b"))
	if not _check_ok(ready_b, "乙准备"):
		return
	var ready_a: Dictionary = a.request("room.ready", {"ready": true}, _rid("a"))
	if not _check_ok(ready_a, "甲准备"):
		return
	var push_a := a.wait_push("room", 3000)
	_check(push_a.get("room", {}).get("members", []).size() == 2, "甲收到房间推送（含乙）")

	# —— 段2：出发事务 ——
	var depart: Dictionary = a.request("room.begin_depart", {}, _rid("a"))
	if not _check_ok(depart, "双方就绪后出发"):
		print("  D45-DBG depart=", JSON.stringify(depart).substr(0, 300))
		return
	var run_id := str(depart["result"].get("run", {}).get("run_id", ""))
	_check(run_id.begins_with("run-"), "局 ID 下发（%s）" % run_id)
	_check(bool(depart["result"]["run"].get("coop", false)), "双人局 coop=true")
	_check(str(depart["result"].get("room", {}).get("phase", "")) == "running", "房间 phase=running")
	var push_b := b.wait_push("run", 3000)
	_check(str(push_b.get("run", {}).get("run_id", "")) == run_id, "乙收到开局推送（同一局）")
	_check(int(push_b.get("version", 0)) == 1, "局快照版本 1")

	var welcome_back: Dictionary = _rehello(a, str(tokens["a"]))
	_check(str(welcome_back.get("run", {}).get("run_id", "")) == run_id, "甲重连：welcome 带活动局")
	_check(str(welcome_back.get("room", {}).get("phase", "")) == "running", "甲重连：welcome 带房间")
	var farm_a_block: Dictionary = welcome_back.get("snapshot", {}).get("farm", {}).get("expedition", {})
	_check(str(farm_a_block.get("inventory", {}).get("occupied_by_run", "")) == run_id, "甲农场占用=局 ID")
	_check(str(farm_a_block.get("active_run_ref", "")) == run_id, "甲活动局引用")

	var solo_busy: Dictionary = c.request("room.create", {}, _rid("c"))
	if not _check_ok(solo_busy, "丙建第二个房间（与甲乙房并存）"):
		return
	var solo_in_room: Dictionary = c.request("run.depart_solo", {}, _rid("c"))
	_check(_is_op_failed(solo_in_room, "已在房间"), "在等待房间中单人出发 → op_failed 已在房间")
	var c_leave: Dictionary = c.request("room.leave", {}, _rid("c"))
	_check_ok(c_leave, "丙离房")

	# 强杀重启（S07）
	var before_row := int(depart["result"]["run"]["current"]["row"])
	if not _kill_server_and_wait():
		return
	if not _spawn_server():
		return
	for client in [a, b, c, d]:
		client.reconnect(PORT)
	_rehello(a, str(tokens["a"]))
	_rehello(c, str(tokens["c"]))
	_rehello(d, str(tokens["d"]))
	var rb := _rehello(b, str(tokens["b"]))
	_check(str(rb.get("run", {}).get("run_id", "")) == run_id, "强杀重启后乙重连：局恢复（同 run_id）")
	_check(int(rb.get("run", {}).get("current", {}).get("row", -1)) == before_row, "局位置不变（row=%d）" % before_row)

	# —— 段3：双人全链路 ——
	var v1: Dictionary = _act(a, "vote_move", {"row": 1, "col": 0})
	_check(bool(v1.get("waiting", false)), "甲先投票 → 等待乙")
	var v2: Dictionary = _act(b, "vote_move", {"row": 1, "col": 0})
	if not _check(bool(v2.get("ok", false)), "乙同票 → 前进到第 1 排"):
		print("  D45-DBG v2=", JSON.stringify(v2).substr(0, 200))
	var run_now: Dictionary = _latest_run(a)
	_check(int(run_now.get("current", {}).get("row", -1)) == 1, "局位置=第 1 排")

	var started: Dictionary = _act(a, "start_battle", {})
	_check(bool(started.get("ok", false)), "发起战斗")
	var outcome := _auto_battle([["p1", a], ["p2", b]])
	_check(outcome == "won", "双人战斗胜利（自动出牌，outcome=%s）" % outcome)
	if outcome != "won":
		return
	var finished: Dictionary = _act(a, "finish_battle", {})
	_check(bool(finished.get("ok", false)) and str(_latest_run(a).get("phase", "")) == "node", "结束战斗进入搜刮")

	# 搜刮：真实 WSS 搜索计时，共享已发现物品，各实例只能拿一次
	var key := "r1c0"
	var resolved: Dictionary = _latest_run(a)["resolved"][key]
	_check(resolved["corpses"][0]["regions"][0]["items"].is_empty(), "初始网络快照隐藏未知物品")
	_search_online(a)
	resolved = _latest_run(a)["resolved"][key]
	var reward0 := int(resolved["corpses"][0]["regions"][0]["items"][0]["instance_id"])
	var reward1 := int(resolved["corpses"][0]["regions"][0]["items"][1]["instance_id"])
	var claim: Dictionary = _act(a, "claim_corpse", {"instance_id": reward0, "container": "pack"})
	_check(bool(claim.get("ok", false)), "甲领取候选奖励")
	var claim_again: Dictionary = _act(a, "claim_corpse", {"instance_id": reward0, "container": "pack"})
	_check(not bool(claim_again.get("ok", false)), "重复领取同一候选被拒")
	var public_claim: Dictionary = _act(b, "claim_corpse", {"instance_id": reward1})
	_check(bool(public_claim.get("ok", false)), "乙领取已发现的另一件物品")
	_check(not _act(b, "claim_corpse", {"instance_id": reward0})["ok"], "另一账户不能复制领取甲的物品")

	# 段6 顺带：去重与冲突（用 signal 动作）
	var sig: Dictionary = _act(a, "signal", {"text": "集合"})
	_check(bool(sig.get("ok", false)), "快捷信号（C10）")
	var dup_req := a.request("run.action", {"kind": "signal", "args": {"text": "集合"}}, _last_rid)
	_check(bool(dup_req.get("duplicate", false)), "同号同参重放 → duplicate=true")
	var conflict_req := a.request("run.action", {"kind": "signal", "args": {"text": "别的"}}, _last_rid)
	_check(str(conflict_req.get("code", "")) == OnlineProtocol.ERR_REQ_ID_CONFLICT, "同号异参 → req_id_conflict")

	var left: Dictionary = _act(a, "leave_node", {})
	_check(bool(left.get("ok", false)), "离开节点回地图")
	_act(b, "vote_move", {"row": 2, "col": 0})
	_act(a, "vote_move", {"row": 2, "col": 0})
	_act(b, "leave_node", {})
	_act(a, "leave_node", {})
	# 第 3 排事件
	_act(a, "vote_move", {"row": 3, "col": 0})
	_act(b, "vote_move", {"row": 3, "col": 0})
	var event_run := _latest_run(a)
	var event_key := "r3c0"
	var event_id := str(event_run["resolved"][event_key].get("event_id", ""))
	var options: Array = ExpeditionDefs.EVENTS.get(event_id, {}).get("options", [])
	if options.size() > 0:
		var chosen: Dictionary = _act(a, "choose_event", {"option": str(options[0]["id"])})
		_check(bool(chosen.get("ok", false)), "事件选择（%s）" % event_id)
	_act(a, "leave_node", {})
	# 第 4 排休整·撤离站
	_act(a, "vote_move", {"row": 4, "col": 0})
	_act(b, "vote_move", {"row": 4, "col": 0})
	var rest: Dictionary = _act(a, "take_rest", {"option": "heal"})
	_check(bool(rest.get("ok", false)), "休整恢复")

	var ex1: Dictionary = _act(a, "vote_extract", {"agree": true})
	_check(bool(ex1.get("waiting", false)) or bool(ex1.get("ok", false)), "甲同意撤离")
	var ex2: Dictionary = _act(b, "vote_extract", {"agree": true})
	_check(bool(ex2.get("ok", false)), "乙确认撤离（双票达成）")
	var settle_a := a.wait_push("settlement", 6000)
	var settle_b := b.wait_push("settlement", 6000)
	_check(not settle_a.is_empty() and not settle_b.is_empty(), "双方都收到结算推送")
	var s1: Dictionary = settle_a.get("settlement", {})
	var s2: Dictionary = settle_b.get("settlement", {})
	_check(str(s1.get("kind", "")) == "extract" and str(s2.get("kind", "")) == "extract", "结算类型=extract（甲/乙）")
	_check(str(s1.get("settlement_id", "")) != "" and str(s1.get("settlement_id", "")) != str(s2.get("settlement_id", "")), "结算 ID 唯一且不同")

	# 双方农场对账
	var after_a: Dictionary = _rehello(a, str(tokens["a"]))
	var after_b: Dictionary = _rehello(b, str(tokens["b"]))
	for pair in [["甲", after_a, s1], ["乙", after_b, s2]]:
		var exp_block: Dictionary = pair[1].get("snapshot", {}).get("farm", {}).get("expedition", {})
		_check(str(exp_block.get("active_run_ref", "x")) == "", "%s：占用解除（active_run_ref 清空）" % pair[0])
		_check(str(exp_block.get("inventory", {}).get("occupied_by_run", "x")) == "", "%s：occupied_by_run 清空" % pair[0])
		var applied: Array = exp_block.get("applied_settlements", [])
		_check(applied.has(str((pair[2] as Dictionary).get("settlement_id", ""))), "%s：结算已登记应用" % pair[0])
	_check((s1.get("returned", []) as Array).size() > 0, "甲结算：带入装备返还清单非空")

	# —— 段4：单人全链路（丙） ——
	var solo: Dictionary = c.request("run.depart_solo", {}, _rid("c"))
	if not _check_ok(solo, "丙单人出发"):
		return
	var solo_run: Dictionary = solo["result"].get("run", {})
	_check(not bool(solo_run.get("coop", false)), "单人局 coop=false")
	var solo_again: Dictionary = c.request("run.depart_solo", {}, _rid("c"))
	_check(_is_op_failed(solo_again, "已有进行中的探险"), "局中再出发 → op_failed 已有进行中的探险")
	var outsider: Dictionary = b.request("run.action", {"kind": "move_to", "args": {"row": 1, "col": 0}}, _rid("b"))
	_check(_is_op_failed(outsider, "没有进行中的探险"), "乙无局时发动作 → op_failed 没有进行中的探险")
	var m1r: Dictionary = _act(c, "move_to", {"row": 1, "col": 0})
	_check(bool(m1r.get("ok", false)), "丙直通选路（无投票）")
	_act(c, "start_battle", {})
	var solo_outcome := _auto_battle([["p1", c]])
	_check(solo_outcome == "won", "丙单人战斗胜利（outcome=%s）" % solo_outcome)
	if solo_outcome != "won":
		return
	_act(c, "finish_battle", {})
	_search_online(c)
	var solo_resolved: Dictionary = _latest_run(c)["resolved"]["r1c0"]
	_act(c, "claim_corpse", {"instance_id": int(solo_resolved["corpses"][0]["regions"][0]["items"][0]["instance_id"]), "container": "pack"})
	_act(c, "leave_node", {})
	_act(c, "move_to", {"row": 2, "col": 0})
	_act(c, "leave_node", {})
	_act(c, "move_to", {"row": 3, "col": 0})
	var solo_event := str(_latest_run(c)["resolved"]["r3c0"].get("event_id", ""))
	var solo_options: Array = ExpeditionDefs.EVENTS.get(solo_event, {}).get("options", [])
	if solo_options.size() > 0:
		_act(c, "choose_event", {"option": str(solo_options[0]["id"])})
	_act(c, "leave_node", {})
	_act(c, "move_to", {"row": 4, "col": 0})
	_act(c, "take_rest", {"option": "heal"})
	var solo_extract: Dictionary = _act(c, "extract", {})
	_check(bool(solo_extract.get("ok", false)), "丙撤离（单人无投票）")
	var solo_settle: Dictionary = solo_extract.get("settlement", {})
	_check(str(solo_settle.get("kind", "")) == "extract", "丙结算类型=extract")
	var after_c: Dictionary = _rehello(c, str(tokens["c"]))
	var exp_c: Dictionary = after_c.get("snapshot", {}).get("farm", {}).get("expedition", {})
	_check(str(exp_c.get("active_run_ref", "x")) == "" and str(exp_c.get("inventory", {}).get("occupied_by_run", "x")) == "", "丙：占用解除")
	var gained_ids := {}
	for entry in solo_settle.get("gained", []):
		gained_ids[int(entry.get("instance_id", 0))] = true
	var warehouse_c: Array = exp_c.get("inventory", {}).get("warehouse", [])
	var warehouse_ids := {}
	for instance in warehouse_c:
		warehouse_ids[int(instance["instance_id"])] = true
	var all_gained_in_warehouse := true
	for gid in gained_ids:
		if not warehouse_ids.has(int(gid)):
			all_gained_in_warehouse = false
	_check(all_gained_in_warehouse, "丙：获得物全部入仓（逐件对账）")

	# —— 段5：双房并行（甲乙 / 丙丁） ——
	var r1: Dictionary = a.request("room.create", {}, _rid("a"))
	var r2: Dictionary = c.request("room.create", {}, _rid("c"))
	var code1 := str(r1["result"].get("code", ""))
	var code2 := str(r2["result"].get("code", ""))
	_check(code1 != "" and code2 != "" and code1 != code2, "双房建立（房码不同）")
	b.request("room.join", {"code": code1}, _rid("b"))
	d.request("room.join", {"code": code2}, _rid("d"))
	b.request("room.ready", {"ready": true}, _rid("b"))
	d.request("room.ready", {"ready": true}, _rid("d"))
	a.request("room.ready", {"ready": true}, _rid("a"))
	c.request("room.ready", {"ready": true}, _rid("c"))
	var dep1: Dictionary = a.request("room.begin_depart", {}, _rid("a"))
	var dep2: Dictionary = c.request("room.begin_depart", {}, _rid("c"))
	if not (_check_ok(dep1, "房1 出发") and _check_ok(dep2, "房2 出发")):
		return
	var run1_id := str(dep1["result"]["run"]["run_id"])
	var run2_id := str(dep2["result"]["run"]["run_id"])
	_check(run1_id != run2_id, "两局 ID 不同")
	# 交错动作：房1 走 (1,0)，房2 走 (1,1)
	_act(a, "vote_move", {"row": 1, "col": 0})
	_act(c, "vote_move", {"row": 1, "col": 1})
	_act(b, "vote_move", {"row": 1, "col": 0})
	_act(d, "vote_move", {"row": 1, "col": 1})
	var run1 := _latest_run(a)
	var run2 := _latest_run(c)
	_check(int(run1["current"]["col"]) == 0 and int(run2["current"]["col"]) == 1, "两局位置互不串扰（col 0 vs 1）")
	_check(str(run1["run_id"]) == run1_id and str(run2["run_id"]) == run2_id, "各自仍在自己的局")
	# 各自放弃收尾：房主放弃会终局（规则层语义），服务器为未结算队友自动补一份放弃结算
	var ab1: Dictionary = _act(a, "abandon_member", {})
	_check(bool(ab1.get("ok", false)), "房1 甲个人放弃（终局）")
	var after_b2: Dictionary = _rehello(b, str(tokens["b"]))
	_check(not after_b2.has("run"), "房1 终局后乙重连无活动局（自动补结算）")
	var exp_b2: Dictionary = after_b2.get("snapshot", {}).get("farm", {}).get("expedition", {})
	_check(str(exp_b2.get("inventory", {}).get("occupied_by_run", "x")) == "", "乙占用解除（自动补结算）")
	_act(c, "abandon_member", {})
	var after_d: Dictionary = _rehello(d, str(tokens["d"]))
	_check(not after_d.has("run"), "房2 终局后丁无活动局")
	var final_a: Dictionary = _rehello(a, str(tokens["a"]))
	_check(not final_a.has("run"), "局终后重连无活动局")
	var exp_final: Dictionary = final_a.get("snapshot", {}).get("farm", {}).get("expedition", {})
	_check(str(exp_final.get("active_run_ref", "x")) == "", "局终后占用解除（放弃路径）")


func _prepare_loadout(client: WsClient, label: String) -> bool:
	var kit: Dictionary = client.request("inv.grant_basic_kit", {}, _rid(label))
	if str(kit.get("t", "")) != "req_ok":
		_check(false, "%s 基础套装领取失败" % label)
		return false
	var warehouse: Array = kit["snapshot"]["farm"]["expedition"]["inventory"]["warehouse"]
	var moved := 0
	for instance in warehouse.duplicate():
		var reply: Dictionary = client.request(
			"inv.move_to_loadout", {"instance_id": int(instance["instance_id"]), "container": "chest"}, _rid(label)
		)
		if str(reply.get("t", "")) == "req_ok":
			moved += 1
	if moved < 3:
		_check(false, "%s 战备迁移不足（%d/3）" % [label, moved])
		return false
	return true


# —— 动作助手 ————————————————————————————————————————————————————————


var _last_rid := ""


func _rid(label: String) -> String:
	req_seq += 1
	_last_rid = "%s-%04d" % [label, req_seq]
	return _last_rid


func _search_online(client: WsClient) -> void:
	_check(_act(client, "search_start", {"source": "e1", "region": "body"})["ok"], "开始在线尸体搜索")
	_check(not _act(client, "search_step", {})["ok"], "权威端拒绝提前完成搜索")
	for i in range(32):
		var session: Dictionary = _latest_run(client).get("loot_searches", {}).get("p1", {})
		if session.is_empty():
			return
		OS.delay_msec(int(session["remaining"]) + 90)
		_check(_act(client, "search_step", {})["ok"], "在线逐格揭晓")
	_check(false, "在线搜索超出区域容量")

func _act(client: WsClient, kind: String, args: Dictionary) -> Dictionary:
	var reply: Dictionary = client.request("run.action", {"kind": kind, "args": args}, _rid("act"))
	if str(reply.get("t", "")) == "req_ok":
		var run: Dictionary = reply.get("run", {})
		if not run.is_empty():
			client.latest_run = run
		var result: Dictionary = reply.get("result", {})
		return result if result is Dictionary else {}
	if str(reply.get("t", "")) == "req_err":
		return {"ok": false, "reason": str(reply.get("msg", reply.get("code", "")))}
	return {"ok": false, "reason": "timeout"}


func _latest_run(client: WsClient) -> Dictionary:
	client.drain_pushes()
	return client.latest_run


## 自动出牌直到战斗分出胜负：按目标类型选目标（enemy→首个存活敌人，self/ally→自己），
## 失败（能量/目标不合法）忽略；两人都结束回合后敌方行动。返回 "won"/"lost"/"timeout"。
func _auto_battle(members: Array) -> String:
	for round in range(40):
		var battle: Dictionary = _latest_run((members[0][1] as WsClient)).get("battle", {})
		if battle.is_empty():
			return "no-battle"
		var outcome := str(battle.get("outcome", ""))
		if outcome != "":
			return outcome
		for pair in members:
			var key := str(pair[0])
			var client: WsClient = pair[1]
			var hand: Array = battle.get("players", {}).get(key, {}).get("hand", [])
			for card in hand:
				var target := _auto_target(str(card.get("card_id", "")), key, battle)
				_act(client, "play_card", {"uid": int(card["uid"]), "target": target})
				battle = _latest_run(client).get("battle", battle)
				if str(battle.get("outcome", "")) != "":
					return str(battle["outcome"])
			_act(client, "end_turn", {})
			battle = _latest_run(client).get("battle", battle)
			if str(battle.get("outcome", "")) != "":
				return str(battle["outcome"])
	return "timeout"


func _auto_target(card_id: String, member_key: String, battle: Dictionary) -> String:
	var def: Dictionary = CardDefs.CARDS.get(card_id, {})
	match str(def.get("target", "enemy")):
		"enemy":
			for enemy in battle.get("enemies", []):
				if bool(enemy.get("alive", true)):
					return str(enemy.get("id", "e1"))
			return "e1"
		_:
			return member_key


func _rehello(client: WsClient, token: String) -> Dictionary:
	return client.hello(token)


func _check_ok(reply: Dictionary, label: String) -> bool:
	return _check(reply.get("t", "") == "req_ok" and not bool(reply.get("duplicate", false)), label)


func _is_op_failed(reply: Dictionary, fragment: String) -> bool:
	return str(reply.get("t", "")) == "req_err" \
		and str(reply.get("code", "")) == OnlineProtocol.ERR_OP_FAILED \
		and str(reply.get("msg", "")).find(fragment) >= 0


func _check(ok: bool, label: String, _extra := "") -> bool:
	checks += 1
	if ok:
		print("D45-PASS %s" % label)
	else:
		failed = true
		fail_count += 1
		print("D45-FAIL %s" % label)
	return ok


# —— 服务器子进程 ————————————————————————————————————————————————


func _spawn_server() -> bool:
	var args := [
		"--headless", "--path", project_dir, "res://scenes/server_main.tscn", "--",
		"--port", str(PORT), "--db", db_path,
		"--cert", cert_path, "--key", key_path, "--tag", "d45",
	]
	server_pid = OS.create_process(godot_exe, args)
	if server_pid < 0:
		_check(false, "服务端子进程启动失败")
		return false
	var probe := WebSocketMultiplayerPeer.new()
	var cert := X509Certificate.new()
	cert.load(cert_path)
	probe.create_client("wss://127.0.0.1:%d" % PORT, TLSOptions.client(cert))
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		probe.poll()
		if probe.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			probe.close()
			return true
		if probe.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			break
		OS.delay_msec(20)
	_check(false, "服务端 15 秒内未就绪")
	return false


func _kill_server_and_wait() -> bool:
	if server_pid <= 0:
		return true
	OS.kill(server_pid)
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline and OS.is_process_running(server_pid):
		OS.delay_msec(50)
	var gone := not OS.is_process_running(server_pid)
	_check(gone, "强杀服务端进程退出")
	server_pid = 0
	OS.delay_msec(250)
	return gone


func _cleanup() -> void:
	if server_pid > 0:
		OS.kill(server_pid)
	print("D45-SUMMARY checks=%d failed=%d" % [checks, fail_count])


func _client() -> WsClient:
	var client := WsClient.new()
	client.cert_path = cert_path
	return client


# —— WSS 测试客户端（沿 d42；增 push 收集与重连） ——————————————————————

class WsClient:
	const REPLY_TIMEOUT_MS := 8000
	var peer := WebSocketMultiplayerPeer.new()
	var cert_path := ""
	var inbox: Array = []
	var kicked := false
	var latest_run := {}

	func connect_to(port: int) -> bool:
		var cert := X509Certificate.new()
		if cert.load(cert_path) != OK:
			return false
		if peer.create_client("wss://127.0.0.1:%d" % port, TLSOptions.client(cert)) != OK:
			return false
		return _wait_connected(8000)

	func reconnect(port: int) -> bool:
		peer.close()
		OS.delay_msec(150)
		inbox.clear()
		return connect_to(port)

	func _wait_connected(timeout_ms: int) -> bool:
		var deadline := Time.get_ticks_msec() + timeout_ms
		while Time.get_ticks_msec() < deadline:
			peer.poll()
			var status := peer.get_connection_status()
			if status == MultiplayerPeer.CONNECTION_CONNECTED:
				return true
			if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
				return false
			OS.delay_msec(5)
		return false

	func poll_packets() -> void:
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var raw := peer.get_packet().get_string_from_utf8()
			var parsed := JSON.new()
			if parsed.parse(raw) != OK or not (parsed.data is Dictionary):
				continue
			var msg: Dictionary = parsed.data
			if str(msg.get("t", "")) == "kicked":
				kicked = true
			if str(msg.get("t", "")) == "push":
				if str(msg.get("kind", "")) == "run":
					latest_run = msg.get("run", {})
			inbox.append(msg)

	func drain_pushes() -> void:
		poll_packets()

	func wait_push(kind: String, timeout_ms: int) -> Dictionary:
		var deadline := Time.get_ticks_msec() + timeout_ms
		while Time.get_ticks_msec() < deadline:
			poll_packets()
			for i in range(inbox.size()):
				var msg: Dictionary = inbox[i]
				if str(msg.get("t", "")) == "push" and str(msg.get("kind", "")) == kind:
					inbox.remove_at(i)
					return msg
			OS.delay_msec(3)
		return {}

	func send_json(payload: Dictionary) -> bool:
		poll_packets()
		peer.set_target_peer(1)
		return peer.put_packet(JSON.stringify(payload).to_utf8_buffer()) == OK

	func wait_for(predicate: Callable, timeout_ms: int) -> Dictionary:
		for i in range(inbox.size()):
			var msg: Dictionary = inbox[i]
			if predicate.call(msg):
				inbox.remove_at(i)
				return msg
		var deadline := Time.get_ticks_msec() + timeout_ms
		while Time.get_ticks_msec() < deadline:
			poll_packets()
			for i in range(inbox.size()):
				var msg: Dictionary = inbox[i]
				if predicate.call(msg):
					inbox.remove_at(i)
					return msg
			OS.delay_msec(3)
		return {}

	func _hello_payload(token: String) -> Dictionary:
		return {
			"t": "hello", "token": token,
			"proto": OnlineProtocol.PROTO_VERSION,
			"rules": OnlineProtocol.RULES_VERSION,
			"build": OnlineProtocol.CLIENT_BUILD,
		}

	func hello(token: String) -> Dictionary:
		send_json(_hello_payload(token))
		return wait_for(func(m): return str(m.get("t", "")) == "welcome" or str(m.get("t", "")) == "error", REPLY_TIMEOUT_MS)

	func activate(invite: String, nick: String) -> Dictionary:
		var payload := _hello_payload("")
		payload["t"] = "activate"
		payload["invite"] = invite
		payload["nick"] = nick
		send_json(payload)
		return wait_for(func(m): return str(m.get("t", "")) == "welcome" or str(m.get("t", "")) == "error", REPLY_TIMEOUT_MS)

	func request(op: String, args: Dictionary, req_id: String) -> Dictionary:
		send_json({"t": "req", "req_id": req_id, "op": op, "args": args})
		var reply := wait_for(
			func(m): return (str(m.get("t", "")) == "req_ok" or str(m.get("t", "")) == "req_err") and str(m.get("req_id", "")) == req_id,
			REPLY_TIMEOUT_MS
		)
		if str(reply.get("t", "")) == "req_ok" and reply.has("run"):
			latest_run = reply.get("run", {})
		return reply
