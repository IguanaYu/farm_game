class_name ExpeditionGame
extends RefCounted
## 单人洞窟局（2.4）：出发事务、地图推进、节点裁定（奖励首裁后固定）、撤离／死亡结算。
## 局内背包是农场战备的深拷贝快照（InventoryGame 绑定局 state 的 inventory 块），
## 2.3 的领取/丢弃/整理逻辑全部复用。存档：局档 user://expeditions/run_<id>.json；
## 结算档 settlement_<id>.json；农场档只存占用与已应用结算（总计划 §9.3）。


const SETTLEMENT_FMT := 1

var run: Dictionary = {}
var game: FarmGame
var rng := RandomNumberGenerator.new()


func bind(farm_game: FarmGame) -> void:
	game = farm_game


# —— 出发事务（总计划 §9.3：生成局 ID → 写占用 → 写局初始快照 → 开始）——————

static func depart(farm_game: FarmGame, now: int) -> Dictionary:
	var inventory := InventoryGame.new()
	inventory.bind(farm_game.state["expedition"])
	var check := inventory.loadout_check()
	if not check["hard_blocks"].is_empty():
		return {"ok": false, "reason": "、".join(check["hard_blocks"])}
	if inventory.is_run_occupied():
		return {"ok": false, "reason": "已有活动局"}
	var preview := inventory.deck_preview()
	if int(preview["totals"][1]) <= 0:
		return {"ok": false, "reason": "首回合牌库为空，先在胸挂放入装备"}
	var run_id := ExpeditionStore.new_run_id(int(Time.get_unix_time_from_system() * 1000.0))
	if not inventory.set_run_occupied(run_id)["ok"]:
		return {"ok": false, "reason": "写入占用失败"}
	var expedition: Dictionary = farm_game.state["expedition"]
	var seed_value := run_id.hash() + int(Time.get_unix_time_from_system())
	var instance := ExpeditionGame.new()
	instance.game = farm_game
	instance.run = {
		"fmt": 1,
		"run_id": run_id,
		"rules_version": ExpeditionBaseline.PROTO_RULES_VERSION,
		"layer_id": "moss_stone_shallow",
		"rng_seed": seed_value,
		"rng_state": str(seed_value),
		"created_at": now,
		"player": {"hp": ExpeditionBaseline.MAX_HP, "max_hp": ExpeditionBaseline.MAX_HP, "extra_draw_next": false},
		"inventory": _snapshot_loadout(farm_game),
		"next_instance_id": int(expedition.get("next_instance_id", 1000)),
		"map": _build_map("moss_stone_shallow"),
		"current": {"row": 0, "col": 0},
		"resolved": {},
		"node_drops": [],
		"battle": {},
		"phase": "map",
		"outcome": "",
		"settlement_id": "",
		"carried_from_farm": _carried_ids(farm_game),
		"consumed": [],
		"log": ["出发：生命 %d/%d，携带牌 %d 张" % [ExpeditionBaseline.MAX_HP, ExpeditionBaseline.MAX_HP, preview["totals"][1] + preview["totals"][2] + preview["totals"][3]]],
	}
	expedition["active_run_ref"] = run_id
	if not ExpeditionStore.save_run(run_id, instance.run):
		inventory.clear_run_occupied(run_id)
		expedition["active_run_ref"] = ""
		return {"ok": false, "reason": "局档写入失败，已恢复出发前状态"}
	instance.rng.seed = seed_value
	return {"ok": true, "reason": "", "run": instance.run, "game": instance}


static func _snapshot_loadout(farm_game: FarmGame) -> Dictionary:
	## 局内背包＝农场战备三容器深拷贝＋空仓库；实例 ID 与农场一致（结算时按 ID 对账）。
	var loadout: Dictionary = farm_game.state["expedition"]["inventory"]["loadout"]
	return {
		"warehouse": [],
		"loadout": loadout.duplicate(true),
		"occupied_by_run": "",
	}


static func _carried_ids(farm_game: FarmGame) -> Array:
	var ids: Array = []
	var loadout: Dictionary = farm_game.state["expedition"]["inventory"]["loadout"]
	for container in ExpeditionBaseline.CONTAINERS:
		for instance in loadout.get(container, []):
			ids.append(int(instance["instance_id"]))
	return ids


## 把定义表展开成局内地图（节点带列号；行/列即坐标，node_id 为 r<行>c<列>）。
static func _build_map(layer_id: String) -> Dictionary:
	var layer := ExpeditionDefs.layer(layer_id)
	var rows: Array = []
	for row_index in range(int(layer.get("rows", 9))):
		var cols: Array = []
		for col_index in range(int(layer["map"][row_index].size())):
			var node: Dictionary = layer["map"][row_index][col_index].duplicate()
			node["col"] = col_index
			cols.append(node)
		rows.append(cols)
	return {"rows": rows}


# —— 双人扩展（2.6）：成员 p2（客机）以 run["guest"] 并列存放 ——————————————

## 出发（双人）：主机侧事务。guest_profile 由客机在出发握手时提供：
## {name, player_id, loadout(实例快照), carried(实例 id 列表), next_instance_id, hp}。
## 主机只占用主机农场；客机在自己的存档里自行占用（握手协议负责）。
static func depart_coop(farm_game: FarmGame, guest_profile: Dictionary, now: int, run_id_override := "") -> Dictionary:
	var inventory := InventoryGame.new()
	inventory.bind(farm_game.state["expedition"])
	var check := inventory.loadout_check()
	if not check["hard_blocks"].is_empty():
		return {"ok": false, "reason": "主机战备未通过检查"}
	var preview := inventory.deck_preview()
	if int(preview["totals"][1]) <= 0:
		return {"ok": false, "reason": "主机首回合牌库为空"}
	var run_id := run_id_override if run_id_override != "" else ExpeditionStore.new_run_id(int(Time.get_unix_time_from_system() * 1000.0))
	if not inventory.set_run_occupied(run_id)["ok"]:
		return {"ok": false, "reason": "写入占用失败"}
	var expedition: Dictionary = farm_game.state["expedition"]
	var seed_value := run_id.hash() + int(Time.get_unix_time_from_system())
	var instance := ExpeditionGame.new()
	instance.game = farm_game
	instance.run = {
		"fmt": 1,
		"run_id": run_id,
		"coop": true,
		"rules_version": ExpeditionBaseline.PROTO_RULES_VERSION,
		"layer_id": "moss_stone_shallow",
		"rng_seed": seed_value,
		"rng_state": str(seed_value),
		"created_at": now,
		"player": {"hp": ExpeditionBaseline.MAX_HP, "max_hp": ExpeditionBaseline.MAX_HP, "extra_draw_next": false},
		"inventory": _snapshot_loadout(farm_game),
		"guest": _guest_member(guest_profile),
		"next_instance_id": maxi(int(expedition.get("next_instance_id", 1000)), int(guest_profile.get("next_instance_id", 1000))),
		"map": _build_map("moss_stone_shallow"),
		"current": {"row": 0, "col": 0},
		"resolved": {},
		"node_drops": [],
		"battle": {},
		"phase": "map",
		"outcome": "",
		"settlement_id": "",
		"carried_from_farm": _carried_ids(farm_game),
		"consumed": [],
		"votes": {"p1": "", "p2": ""},
		"extract_votes": {"p1": false, "p2": false},
		"log": ["双人出发：主机与 %s" % str(guest_profile.get("name", "队友"))],
	}
	expedition["active_run_ref"] = run_id
	if not ExpeditionStore.save_run(run_id, instance.run):
		inventory.clear_run_occupied(run_id)
		expedition["active_run_ref"] = ""
		return {"ok": false, "reason": "局档写入失败，已恢复出发前状态"}
	instance.rng.seed = seed_value
	return {"ok": true, "reason": "", "run": instance.run, "game": instance}


static func _guest_member(profile: Dictionary) -> Dictionary:
	return {
		"name": str(profile.get("name", "队友")),
		"player_id": str(profile.get("player_id", "p-guest")),
		"hp": int(profile.get("hp", ExpeditionBaseline.MAX_HP)),
		"max_hp": ExpeditionBaseline.MAX_HP,
		"extra_draw_next": false,
		"inventory": {
			"warehouse": [],
			"loadout": (profile.get("loadout", {}) as Dictionary).duplicate(true),
			"occupied_by_run": "",
		},
		"carried_from_farm": (profile.get("carried", []) as Array).duplicate(),
		"consumed": [],
	}


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func member_keys() -> Array:
	if bool(run.get("coop", false)):
		return ["p1", "p2"]
	return ["p1"]


## 成员统一视图：{name, hp, max_hp, inventory(块), carried, consumed, extra_draw_next}。
func member(member_key: String) -> Dictionary:
	if member_key == "p2" and bool(run.get("coop", false)):
		var guest: Dictionary = run["guest"]
		return {
			"name": guest["name"], "hp": guest["hp"], "max_hp": guest["max_hp"],
			"inventory": guest["inventory"],
			"carried": guest.get("carried_from_farm", []),
			"consumed": guest.get("consumed", []),
			"extra_draw_next": guest.get("extra_draw_next", false),
		}
	return {
		"name": "主机农夫",
		"hp": int(run["player"]["hp"]), "max_hp": int(run["player"]["max_hp"]),
		"inventory": run["inventory"], "carried": run["carried_from_farm"], "consumed": run["consumed"],
		"extra_draw_next": bool(run["player"].get("extra_draw_next", false)),
	}


func _write_member_hp(member_key: String, hp: int) -> void:
	if member_key == "p2" and bool(run.get("coop", false)):
		run["guest"]["hp"] = hp
	else:
		run["player"]["hp"] = hp


func member_inventory(member_key: String) -> InventoryGame:
	var info := member(member_key)
	var inventory := InventoryGame.new()
	inventory.bind({"inventory": info["inventory"], "next_instance_id": run["next_instance_id"]})
	return inventory


## —— 共同选路：两人投同一个节点才移动（2.6 设计 §7）——————————————


func vote_move(member_key: String, row: int, col: int) -> Dictionary:
	if not member_keys().has(member_key):
		return {"ok": false, "reason": "未知成员"}
	if run["phase"] != "map":
		return {"ok": false, "reason": "当前不在地图阶段"}
	run["votes"][member_key] = "%d,%d" % [row, col]
	var votes: Dictionary = run["votes"]
	if str(votes.get("p1", "")) != "" and str(votes.get("p2", "")) != "":
		if str(votes["p1"]) == str(votes["p2"]):
			var parts := str(votes["p1"]).split(",")
			run["votes"] = {"p1": "", "p2": ""}
			return move_to(int(parts[0]), int(parts[1]))
	return {"ok": true, "reason": "", "waiting": true}


## —— 撤离确认：两人都确认才结算 ——————————————————————————————


func vote_extract(member_key: String, agree: bool) -> Dictionary:
	if not member_keys().has(member_key):
		return {"ok": false, "reason": "未知成员"}
	run["extract_votes"][member_key] = agree
	var votes: Dictionary = run["extract_votes"]
	if bool(votes.get("p1", false)) and bool(votes.get("p2", false)):
		return _settle_run("extract", int(run["player"]["hp"]))
	if not agree:
		run["extract_votes"] = {"p1": false, "p2": false}
	return {"ok": true, "reason": "", "waiting": true}


## —— 分享（2.6 设计 §9）：提出→确认→一次移动；取消/满包留在原主人 ———————


func share_offer(from_key: String, instance_id: int) -> Dictionary:
	var from_inv := member_inventory(from_key)
	var instance := from_inv.find_instance(instance_id)
	if instance.is_empty():
		return _fail("物品不存在")
	if not ExpeditionBaseline.JOIN_ROUND.has(str(instance.get("container", ""))):
		return _fail("只能分享随身携带的物品")
	if ItemDefs.is_basic(str(instance["def_id"])):
		return _fail("基础装备不允许分享")
	if not (run.get("share_offer", {}) as Dictionary).is_empty():
		return _fail("已有一笔分享进行中")
	run["share_offer"] = {"from": from_key, "instance_id": instance_id, "state": "pending"}
	return {"ok": true, "reason": ""}


func share_accept(to_key: String, container: String) -> Dictionary:
	var offer: Dictionary = run.get("share_offer", {})
	if offer.is_empty() or str(offer.get("state", "")) != "pending":
		return _fail("没有待确认的分享")
	var from_key := str(offer["from"])
	if to_key == from_key:
		return _fail("不能分享给自己")
	var from_inv := member_inventory(from_key)
	var to_inv := member_inventory(to_key)
	var instance := from_inv.find_instance(int(offer["instance_id"]))
	if instance.is_empty():
		run["share_offer"] = {}
		return _fail("物品已不存在，分享取消")
	## 原子转移：先从来源移除，目标放不下则原样回滚（两边都不变）。
	var snapshot: Dictionary = instance.duplicate(true)
	from_inv.discard_instance(int(offer["instance_id"]))
	var added := to_inv.add_instance(str(instance["def_id"]), "share", int(instance.get("quality", 1)))
	var placed := false
	if added["ok"]:
		placed = to_inv.move_to_loadout(int(added["instance_id"]), container)["ok"]
	if not placed:
		if added["ok"]:
			to_inv.discard_instance(int(added["instance_id"]))
		var back := from_inv.add_instance(str(snapshot["def_id"]), "share", int(snapshot.get("quality", 1)))
		if back["ok"]:
			from_inv.move_to_loadout(int(back["instance_id"]), str(snapshot["container"]))
		run["share_offer"] = {}
		return _fail("接收方放不下，物品留在原主人处")
	var moved := to_inv.find_instance(int(added["instance_id"]))
	moved["uses_remaining"] = int(snapshot.get("uses_remaining", 1))
	moved["seed_traits"] = snapshot.get("seed_traits", [])
	run["share_offer"] = {}
	run["log"].append("分享：%s → %s（%s）" % [member(from_key)["name"], member(to_key)["name"], ItemDefs.get_item(str(snapshot["def_id"]))["name"]])
	return {"ok": true, "reason": ""}


func share_cancel() -> Dictionary:
	if (run.get("share_offer", {}) as Dictionary).is_empty():
		return _fail("没有进行中的分享")
	run["share_offer"] = {}
	return {"ok": true, "reason": ""}


## 个人放弃（2.6 设计 §10）：只结算本人；剩余成员继续。
func abandon_member(member_key: String) -> Dictionary:
	if not member_keys().has(member_key):
		return _fail("未知成员")
	return _settle_run("abandon", int(run["player"]["hp"]), member_key)


## 恢复已有活动局（启动／重开时）。
static func resume(farm_game: FarmGame) -> Dictionary:
	var run_id := str(farm_game.state["expedition"].get("active_run_ref", ""))
	if run_id == "":
		return {"ok": false, "reason": "没有活动局"}
	var saved := ExpeditionStore.load_run(run_id)
	if saved.is_empty():
		return {"ok": false, "reason": "局档不可达：%s（保持占用，不自动返还装备）" % run_id}
	var instance := ExpeditionGame.new()
	instance.game = farm_game
	instance.run = saved
	instance.rng.seed = int(saved.get("rng_seed", 0))
	instance.rng.state = int(saved.get("rng_state", "0"))
	return {"ok": true, "reason": "", "run": saved, "game": instance}


# —— 局内工具 ——————————————————————————————————————————————————————


func run_inventory() -> InventoryGame:
	var inventory := InventoryGame.new()
	inventory.bind({"inventory": run["inventory"], "next_instance_id": run["next_instance_id"]})
	return inventory


func save() -> bool:
	run["rng_state"] = str(rng.state)
	return ExpeditionStore.save_run(str(run["run_id"]), run)


func current_node() -> Dictionary:
	var rows: Array = run["map"]["rows"]
	var row: int = int(run["current"]["row"])
	var col: int = int(run["current"]["col"])
	if row < 0 or row >= rows.size() or col < 0 or col >= rows[row].size():
		return {}
	return rows[row][col]


func node_id(row: int, col: int) -> String:
	return "r%dc%d" % [row, col]


# —— 地图推进 ————————————————————————————————————————————————


## 选择下一排的节点（不回头）；进入即裁定并固定该节点内容（奖励/事件结果种子）。
func move_to(row: int, col: int) -> Dictionary:
	if run["phase"] != "map":
		return {"ok": false, "reason": "当前不在地图阶段"}
	var rows: Array = run["map"]["rows"]
	if row != int(run["current"]["row"]) + 1 or row >= rows.size():
		return {"ok": false, "reason": "只能进入相邻的下一排"}
	if col < 0 or col >= rows[row].size():
		return {"ok": false, "reason": "该排没有这个位置"}
	run["current"] = {"row": row, "col": col}
	run["phase"] = "node"
	var node := current_node()
	_resolve_node(node)
	run["log"].append("进入第 %d 排：%s（%s）" % [row, ExpeditionDefs.NODE_TYPE_DISPLAY.get(str(node["type"]), "?"), str(node.get("hint", ""))])
	save()
	return {"ok": true, "reason": ""}


func _resolve_node(node: Dictionary) -> void:
	## 首次进入裁定节点内容并固定：恢复同一局不重新生成（设计 §6 / 总计划 §6.1）。
	var key := node_id(int(run["current"]["row"]), int(run["current"]["col"]))
	if run["resolved"].has(key):
		return
	if str(run["layer_id"]) == "iron_root_deeps":
		node["deep"] = true
	var resolved: Dictionary = {"type": str(node["type"]), "rewards": [], "public": [], "event_id": "", "event_rolls": {}, "rest_taken": false, "completed": false}
	var pools: Array = ExpeditionDefs.battle_pools(str(run["layer_id"]))
	match str(node["type"]):
		"battle":
			resolved["rewards"] = _pick_no_repeat(pools[0], 2)
			resolved["public"] = [_pick(pools[1])]
		"elite":
			resolved["rewards"] = _pick_no_repeat(pools[2], 2)
			resolved["public"] = [_pick(pools[2])]
		"gather":
			resolved["rewards"] = _pick_no_repeat(pools[3], 3)
		"chest":
			resolved["rewards"] = _pick_no_repeat(pools[4], 3)
		"event":
			var events: Array = ExpeditionDefs.events_for_node(int(run["current"]["row"]), str(run["layer_id"]))
			resolved["event_id"] = str(events[col_to_event_index(int(run["current"]["col"]), events.size())])
			resolved["event_rolls"] = {"dig_outcome": _roll_dig_outcome()}
		"gate":
			resolved["rewards"] = (ExpeditionDefs.DEEP_GATE_REWARDS if str(run["layer_id"]) == "iron_root_deeps" else ExpeditionDefs.GATE_REWARDS).duplicate()
	run["resolved"][key] = resolved


func col_to_event_index(col: int, count: int) -> int:
	return clampi(col, 0, maxi(0, count - 1))


func _pick(pool: Array) -> String:
	return str(pool[rng.randi_range(0, pool.size() - 1)])


func _pick_no_repeat(pool: Array, count: int) -> Array:
	var bag := pool.duplicate()
	var result: Array = []
	for attempt in range(mini(count, bag.size())):
		var index := rng.randi_range(0, bag.size() - 1)
		result.append(str(bag[index]))
		bag.remove_at(index)
	return result


## 洞壁幼芽"挖掘根部"的 60/40 预抽（进入节点时固定，不随后续重抽）。
func _roll_dig_outcome() -> String:
	return "trait_seed" if rng.randf() < 0.6 else "fiber"


# —— 节点交互 ————————————————————————————————————————————————


## 战斗节点：生成战斗（牌组来自局内布局，生命延续）。
func start_battle() -> Dictionary:
	var node := current_node()
	if str(node.get("type", "")) not in ["battle", "elite", "gate"]:
		return {"ok": false, "reason": "这里没有战斗"}
	if not run["battle"].is_empty():
		return {"ok": false, "reason": "战斗已在进行"}
	var battle_seed := int(run["rng_seed"]) + int(run["current"]["row"]) * 31 + int(run["current"]["col"])
	var players: Array = []
	var inventories := {}
	for member_key in member_keys():
		var info := member(member_key)
		var inv := member_inventory(member_key)
		inventories[member_key] = inv
		players.append({
			"key": member_key,
			"name": str(info["name"]),
			"max_hp": int(info["max_hp"]),
			"hp": int(info["hp"]),
			"deck": DeckBuilder.build(inv)["entries"],
		})
	## 消耗品扣减统一挂主机侧（p1）库存；p2 实体由其抽牌命中时经同一 InventoryGame 接口扣。
	var encounter_id := _encounter_id(node)
	var combat := CombatGame.create(players, encounter_id, battle_seed, inventories.get("p1"))
	## p2 的消耗品来源走各自库存：为每个玩家挂自己的库存视图。
	if run["phase"] != null and run.get("coop", false):
		combat.member_inventories = inventories
	for member_key in member_keys():
		var info2 := member(member_key)
		if bool(info2.get("extra_draw_next", false)):
			combat.draw_extra_for(member_key, 1)
			_write_member_flag(member_key, "extra_draw_next", false)
			run["log"].append("%s 检查装备生效：本场首回合多抽 1 张" % str(info2["name"]))
	run["phase"] = "battle"
	run["battle"] = combat.to_dict()
	save()
	return {"ok": true, "reason": "", "combat": combat}


func _encounter_id(node: Dictionary) -> String:
	var table_key := ExpeditionDefs.encounter_for(node)
	if CombatGame.ENCOUNTERS.has(table_key):
		return table_key
	return str(node.get("encounter", "tutorial"))


## 恢复进行中的战斗（重开/崩溃后从局档快照重建）。
func restore_battle() -> CombatGame:
	if run["battle"].is_empty():
		return null
	var combat := CombatGame.new()
	if not combat.load_dict(run["battle"]):
		return null
	combat.inventory = run_inventory()
	return combat


## 休整二选一（第 4 排）：恢复 8 或下一场首回合多抽 1。确认后不能切换。
func take_rest(option: String) -> Dictionary:
	var node := current_node()
	if str(node.get("type", "")) != "rest_exit":
		return {"ok": false, "reason": "这里不是休整点"}
	var key := node_id(int(run["current"]["row"]), int(run["current"]["col"]))
	var resolved: Dictionary = run["resolved"][key]
	if bool(resolved.get("rest_taken", false)):
		return {"ok": false, "reason": "本休整点的选择已确认，不能刷两份"}
	match option:
		"heal":
			run["player"]["hp"] = mini(int(run["player"]["hp"]) + 8, int(run["player"]["max_hp"]))
			run["log"].append("休整：恢复 8 生命（→ %d）" % int(run["player"]["hp"]))
		"prepare":
			run["player"]["extra_draw_next"] = true
			run["log"].append("休整：检查装备，下一场首回合多抽 1 张")
		_:
			return {"ok": false, "reason": "未知休整选项"}
	resolved["rest_taken"] = true
	run["resolved"][key] = resolved
	save()
	return {"ok": true, "reason": ""}


## 事件选项：一次选择后完成（不可重选）；生命代价至少留 1。
func choose_event(option_id: String) -> Dictionary:
	var node := current_node()
	if str(node.get("type", "")) != "event":
		return {"ok": false, "reason": "这里没有事件"}
	var key := node_id(int(run["current"]["row"]), int(run["current"]["col"]))
	var resolved: Dictionary = run["resolved"][key]
	if bool(resolved.get("completed", false)):
		return {"ok": false, "reason": "事件已完成，不能重选"}
	var event: Dictionary = ExpeditionDefs.EVENTS.get(str(resolved.get("event_id", "")), {})
	var chosen: Dictionary = {}
	for option in event.get("options", []):
		if str(option["id"]) == option_id:
			chosen = option
	if chosen.is_empty():
		return {"ok": false, "reason": "未知事件选项"}
	var hp := int(run["player"]["hp"])
	if int(chosen.get("hp_cost", 0)) > 0 and hp - int(chosen["hp_cost"]) < 1:
		return {"ok": false, "reason": "生命不足（事件代价至少留下 1 点生命）"}
	if int(chosen.get("hp_cost", 0)) > 0:
		run["player"]["hp"] = hp - int(chosen["hp_cost"])
	var grants: Array = chosen.get("grants", []).duplicate()
	## 洞壁幼芽·挖掘：按进入节点时固定的预抽结果给奖励。
	if option_id == "dig":
		var outcome := str(resolved.get("event_rolls", {}).get("dig_outcome", "fiber"))
		grants = ["rock_sprout_seed"] if outcome == "trait_seed" else ["fiber_clump", "fiber_clump"]
	for def_id in grants:
		_add_run_reward(str(def_id))
	resolved["completed"] = true
	resolved["chosen_option"] = option_id
	run["resolved"][key] = resolved
	run["log"].append("事件「%s」：%s" % [event.get("name", "?"), str(chosen.get("label", option_id))])
	save()
	return {"ok": true, "reason": "", "grants": grants}


## 战斗胜利后进入搜刮（节点奖励区由出发裁定的 resolved 提供）。
func finish_battle(combat: CombatGame) -> Dictionary:
	if run["phase"] != "battle":
		return {"ok": false, "reason": "没有进行中的战斗"}
	var outcome := str(combat.state.get("outcome", ""))
	for member_key in member_keys():
		if combat.state["players"].has(member_key):
			_write_member_hp(member_key, int(combat.state["players"][member_key]["hp"]))
	run["battle"] = {}
	if outcome == "won":
		run["phase"] = "node"
		var node := current_node()
		var key := node_id(int(run["current"]["row"]), int(run["current"]["col"]))
		var resolved: Dictionary = run["resolved"][key]
		resolved["battle_won"] = true
		run["resolved"][key] = resolved
		run["log"].append("战斗胜利（第 %d 回合，剩余生命 %d）" % [int(combat.state["round"]), int(run["player"]["hp"])])
		_record_consumed()
		save()
		return {"ok": true, "reason": "", "outcome": "won"}
	return _settle_run("death", combat.state["round"])


## 完成搜刮/节点处理：离开当前节点（未领取奖励与节点公共区物品全部放弃）。
func leave_node() -> Dictionary:
	if run["phase"] != "node":
		return {"ok": false, "reason": "当前不在节点内"}
	var node := current_node()
	var key := node_id(int(run["current"]["row"]), int(run["current"]["col"]))
	var resolved: Dictionary = run["resolved"][key]
	if str(node["type"]) in ["battle", "elite", "gate"] and not bool(resolved.get("battle_won", false)):
		return {"ok": false, "reason": "先处理这里的战斗"}
	resolved["completed"] = true
	run["resolved"][key] = resolved
	if not run["node_drops"].is_empty():
		run["log"].append("离开节点：公共区 %d 件物品被放弃" % run["node_drops"].size())
		run["node_drops"] = []
	if int(run["current"]["row"]) == ExpeditionDefs.GATE_ROW:
		if str(run["layer_id"]) == "moss_stone_shallow":
			## 层间衔接（2.8）：第一层守门战胜利 → 进入第二层，同一局继续。
			run["layer_id"] = "iron_root_deeps"
			run["map"] = _build_map("iron_root_deeps")
			run["current"] = {"row": 0, "col": 0}
			run["resolved"] = {}
			run["phase"] = "map"
			run["log"].append("击败守门战：进入第二层「铁根矿窟」（携带与生命延续）")
			save()
			return {"ok": true, "reason": "", "layer_changed": "iron_root_deeps"}
		return _settle_run("gate_clear", int(run["player"]["hp"]))
	run["phase"] = "map"
	save()
	return {"ok": true, "reason": ""}


## 撤离：撤离站确认后结算。
func extract() -> Dictionary:
	var node := current_node()
	if str(node.get("type", "")) not in ["rest_exit", "exit"]:
		return {"ok": false, "reason": "当前不在撤离点"}
	return _settle_run("extract", int(run["player"]["hp"]))


## 主动放弃（暂停菜单）：损失规则与死亡一致。
func abandon() -> Dictionary:
	return _settle_run("abandon", int(run["player"]["hp"]))


func _add_run_reward(def_id: String) -> void:
	## 奖励先进入当前节点奖励区（pending 奖励，由领取事务入包）。
	var key := node_id(int(run["current"]["row"]), int(run["current"]["col"]))
	var resolved: Dictionary = run["resolved"].get(key, {})
	resolved["rewards"] = resolved.get("rewards", []) + [def_id]
	run["resolved"][key] = resolved


func _record_consumed() -> void:
	## 记录本节点战斗中耗尽的补给（结算报告用；uses 在实体上已扣）。
	for container in ExpeditionBaseline.CONTAINERS:
		for instance in run["inventory"]["loadout"][container]:
			if int(instance.get("uses_remaining", 1)) == 0 and int(instance["instance_id"]) > 0:
				if not run["consumed"].has(int(instance["instance_id"])):
					run["consumed"].append(int(instance["instance_id"]))


# —— 结算事务（总计划 §9.3：唯一结算 ID → 结算档 → 农场单次保存应用并登记 → 重复只回执）——


func _settle_run(kind: String, detail: int, member_key := "") -> Dictionary:
	if member_key != "":
		return _settle_member(kind, detail, member_key)
	if bool(run.get("coop", false)):
		return _settle_coop(kind, detail)
	var settlement_id := ExpeditionStore.new_settlement_id(int(Time.get_unix_time_from_system() * 1000.0))
	var inventory := run_inventory()
	var carried: Array = run["carried_from_farm"]
	var returned_items: Array = []
	var gained_items: Array = []
	var lost_items: Array = []
	var protected_items: Array = []
	var kept_ids := {}
	var all_instances: Array = inventory.all_instances()
	## 已耗尽的补给（uses 0）实体不存在：不列入返还/获得/损失，并入消耗记录。
	var held: Array = []
	for instance in all_instances:
		if int(instance.get("uses_remaining", 1)) > 0:
			held.append(instance)
		elif not (run["consumed"] as Array).has(int(instance.get("instance_id", 0))):
			run["consumed"].append(int(instance.get("instance_id", 0)))
	if kind == "extract" or kind == "gate_clear":
		## 撤离/通关：全部仍持有的物品返还（带入＝返还，新增＝获得）。
		for instance in held:
			var entry := _settle_entry(instance)
			if int(instance["instance_id"]) in carried:
				returned_items.append(entry)
				kept_ids[int(instance["instance_id"])] = true
			else:
				gained_items.append(entry)
				kept_ids[int(instance["instance_id"])] = true
	else:
		## 死亡/放弃：未保护携带物损失，保险箱白名单保留。
		for instance in held:
			var entry := _settle_entry(instance)
			if str(instance.get("container", "")) == "safe":
				protected_items.append(entry)
				kept_ids[int(instance["instance_id"])] = true
			else:
				lost_items.append(entry)
	var settlement := {
		"fmt": SETTLEMENT_FMT,
		"settlement_id": settlement_id,
		"run_id": str(run["run_id"]),
		"kind": kind,
		"detail": detail,
		"created_at": int(Time.get_unix_time_from_system()),
		"player_id": str(game.state["expedition"].get("player_id", "")),
		"returned": returned_items,
		"gained": gained_items,
		"lost": lost_items,
		"protected": protected_items,
		"consumed": (run["consumed"] as Array).duplicate(),
		"next_instance_id": int(run.get("next_instance_id", 1000)),
		"applied": false,
	}
	if not ExpeditionStore.save_settlement(settlement_id, settlement):
		return {"ok": false, "reason": "结算档写入失败（本局保持未决，可重试）"}
	run["outcome"] = kind
	run["phase"] = "over"
	run["settlement_id"] = settlement_id
	save()
	var apply := apply_settlement(game, settlement)
	if not apply["ok"]:
		return {"ok": false, "reason": apply["reason"], "settlement": settlement}
	return {"ok": true, "reason": "", "settlement": settlement}


## 双人整局结算：主机侧结算自己并应用；客机侧只生成结算单（由客机自行应用，
## 主机不代替客户端写农场档——总计划 §10-2.6 验收红线）。
func _settle_coop(kind: String, detail: int) -> Dictionary:
	var result := {"ok": true, "settlements": {}}
	var host_settle := _settle_one_member(kind, detail, "p1", true)
	if not host_settle["ok"]:
		return host_settle
	result["settlements"]["p1"] = host_settle["settlement"]
	if bool(run.get("guest", {}).get("player_id", "x") != "x" or true):
		var guest_settle := _settle_one_member(kind, detail, "p2", false)
		if not guest_settle["ok"]:
			return guest_settle
		result["settlements"]["p2"] = guest_settle["settlement"]
		run["guest_settlement"] = guest_settle["settlement"]
	result["settlement"] = host_settle["settlement"]
	return result


## 个人放弃：只结算本人；剩余成员继续（2.6 设计 §10）。
func _settle_member(kind: String, detail: int, member_key: String) -> Dictionary:
	var is_host := member_key == "p1"
	var result := _settle_one_member(kind, detail, member_key, is_host)
	if not result["ok"]:
		return result
	if is_host:
		## 主机个人放弃：本局转为由客机视角继续过于复杂，首版按"会话暂停"处理并记录。
		run["log"].append("主机个人放弃：结算本人，会话保留待客机侧处理（2.7 扩展恢复）")
		run["host_forfeited"] = true
	else:
		run["guest_forfeited"] = true
		run["guest_settlement"] = result["settlement"]
	if bool(run.get("host_forfeited", false)) and bool(run.get("guest_forfeited", false)):
		run["outcome"] = kind
		run["phase"] = "over"
	save()
	return result


## 单成员结算：is_host 决定是否在本机农场档应用。
func _settle_one_member(kind: String, detail: int, member_key: String, is_host: bool) -> Dictionary:
	var settlement_id := ExpeditionStore.new_settlement_id(int(Time.get_unix_time_from_system() * 1000.0) + (0 if is_host else 1))
	var info := member(member_key)
	var inv := member_inventory(member_key)
	var carried: Array = info["carried"]
	var returned_items: Array = []
	var gained_items: Array = []
	var lost_items: Array = []
	var protected_items: Array = []
	var held: Array = []
	for instance in inv.all_instances():
		if int(instance.get("uses_remaining", 1)) > 0:
			held.append(instance)
		else:
			(info["consumed"] as Array).append(int(instance.get("instance_id", 0)))
	if kind == "extract" or kind == "gate_clear":
		for instance in held:
			var entry := _settle_entry(instance)
			if int(instance["instance_id"]) in carried:
				returned_items.append(entry)
			else:
				gained_items.append(entry)
	else:
		for instance in held:
			var entry := _settle_entry(instance)
			if str(instance.get("container", "")) == "safe":
				protected_items.append(entry)
			else:
				lost_items.append(entry)
	var settlement := {
		"fmt": SETTLEMENT_FMT,
		"settlement_id": settlement_id,
		"run_id": str(run["run_id"]),
		"kind": kind,
		"detail": detail,
		"member": member_key,
		"created_at": int(Time.get_unix_time_from_system()),
		"player_id": str(game.state["expedition"].get("player_id", "")) if is_host else str(run.get("guest", {}).get("player_id", "")),
		"returned": returned_items,
		"gained": gained_items,
		"lost": lost_items,
		"protected": protected_items,
		"consumed": (info["consumed"] as Array).duplicate(),
		"next_instance_id": int(run.get("next_instance_id", 1000)),
		"applied": false,
	}
	if not is_host:
		## 客机结算单：仅落盘等待客机拉取应用；主机的 run 标记继续。
		settlement["guest_handoff"] = true
		settlement["player_id"] = str(run.get("guest", {}).get("player_id", ""))
		ExpeditionStore.save_settlement(settlement_id, settlement)
		return {"ok": true, "reason": "", "settlement": settlement}
	if not ExpeditionStore.save_settlement(settlement_id, settlement):
		return {"ok": false, "reason": "结算档写入失败（本局保持未决，可重试）"}
	var apply := apply_settlement(game, settlement)
	if not apply["ok"]:
		return {"ok": false, "reason": apply["reason"]}
	if kind == "extract" or kind == "gate_clear":
		run["outcome"] = kind
		run["phase"] = "over"
		run["settlement_id"] = settlement_id
	else:
		run["outcome"] = kind
		run["phase"] = "over"
	save()
	return {"ok": true, "reason": "", "settlement": settlement}


func _write_member_flag(member_key: String, flag: String, value: bool) -> void:
	if member_key == "p2" and bool(run.get("coop", false)):
		run["guest"][flag] = value
	else:
		run["player"][flag] = value


static func _settle_entry(instance: Dictionary) -> Dictionary:
	var def := ItemDefs.get_item(str(instance.get("def_id", "")))
	return {
		"instance_id": int(instance.get("instance_id", 0)),
		"def_id": str(instance.get("def_id", "")),
		"name": str(def.get("name", instance.get("def_id", "?"))),
		"container": str(instance.get("container", "")),
		"uses_remaining": int(instance.get("uses_remaining", 1)),
		"seed_traits": instance.get("seed_traits", []),
		"sell_value": int(def.get("base_value", 0)) if bool(def.get("sellable", false)) else 0,
	}


## 幂等应用结算到农场档（重复应用只回执；同一次保存内完成应用与登记）。
static func apply_settlement(farm_game: FarmGame, settlement: Dictionary) -> Dictionary:
	if int(settlement.get("fmt", -1)) != SETTLEMENT_FMT:
		return {"ok": false, "reason": "结算档版本不认识"}
	var settlement_id := str(settlement.get("settlement_id", ""))
	var expedition: Dictionary = farm_game.state["expedition"]
	var applied: Array = expedition.get("applied_settlements", [])
	if settlement_id == "" or applied.has(settlement_id):
		return {"ok": true, "reason": "already-applied", "duplicate": true}
	var run_id := str(settlement.get("run_id", ""))
	if str(expedition.get("active_run_ref", "")) == run_id:
		var inventory := InventoryGame.new()
		inventory.bind(expedition)
		var clear := inventory.clear_run_occupied(run_id)
		if not clear["ok"]:
			return {"ok": false, "reason": clear["reason"]}
		expedition["active_run_ref"] = ""
	## 返还与获得：实例按原 ID 重建进仓库（跳过已存在的，防重复）。
	var restored := 0
	for group in ["returned", "gained", "protected"]:
		for entry in settlement.get(group, []):
			var instance_id := int(entry.get("instance_id", 0))
			var already := false
			for container in ExpeditionBaseline.CONTAINERS:
				for existing in expedition["inventory"]["loadout"][container]:
					if int(existing["instance_id"]) == instance_id:
						already = true
				if already:
					break
			for existing in expedition["inventory"]["warehouse"]:
				if int(existing["instance_id"]) == instance_id:
					already = true
			if already:
				continue
			## 新物品（带入清单之外的获得物）在农场侧重新登记：入仓库。
			var def := ItemDefs.get_item(str(entry.get("def_id", "")))
			if def.is_empty():
				continue
			var fresh := {
				"instance_id": instance_id,
				"def_id": str(entry.get("def_id", "")),
				"quality": int(def.get("quality", 1)),
				"container": "warehouse",
				"cell": [0, 0],
				"rotated": false,
				"demo": false,
				"source": "settlement",
				"uses_remaining": int(entry.get("uses_remaining", def.get("uses", 1))),
				"seed_traits": entry.get("seed_traits", []),
			}
			expedition["inventory"]["warehouse"].append(fresh)
			restored += 1
	## 损失：从农场侧清除对应带入实例（带入时它们仍在农场 loadout 里）。
	var removed := 0
	for entry in settlement.get("lost", []):
		var instance_id := int(entry.get("instance_id", 0))
		var target := {}
		for container in ExpeditionBaseline.CONTAINERS:
			for existing in expedition["inventory"]["loadout"][container]:
				if int(existing["instance_id"]) == instance_id:
					target = existing
		if target.is_empty():
			for existing in expedition["inventory"]["warehouse"]:
				if int(existing["instance_id"]) == instance_id:
					target = existing
		if not target.is_empty():
			expedition["inventory"]["warehouse"].erase(target)
			for container in ExpeditionBaseline.CONTAINERS:
				expedition["inventory"]["loadout"][container].erase(target)
			removed += 1
	expedition["next_instance_id"] = maxi(int(expedition.get("next_instance_id", 1000)), int(settlement.get("next_instance_id", 0)))
	## 已消耗的带入补给：实体不存在，农场侧移除（含数值型 consumed 记录）。
	for entry in settlement.get("consumed", []):
		var consumed_id := int(entry) if typeof(entry) != TYPE_DICTIONARY else int(entry.get("instance_id", 0))
		var target := {}
		for container in ExpeditionBaseline.CONTAINERS:
			for existing in expedition["inventory"]["loadout"][container]:
				if int(existing["instance_id"]) == consumed_id:
					target = existing
		if not target.is_empty():
			for container in ExpeditionBaseline.CONTAINERS:
				expedition["inventory"]["loadout"][container].erase(target)
			expedition["inventory"]["warehouse"].erase(target)
			removed += 1
	## 稀有种子进入原种子体系（2.5 设计 §6）：物品实例转为农场种子（保留实例上的词条）。
	var seed_tool := InventoryGame.new()
	seed_tool.bind(expedition)
	for group in ["gained", "protected"]:
		for entry in settlement.get(group, []):
			var plant_kind := FarmGame.seed_item_to_plant(str(entry.get("def_id", "")))
			if plant_kind == "":
				continue
			var instance := seed_tool.find_instance(int(entry.get("instance_id", 0)))
			var traits: Array = instance.get("seed_traits", []) if not instance.is_empty() else []
			farm_game.add_seed_with_traits(plant_kind, traits)
			if not instance.is_empty():
				expedition["inventory"]["warehouse"].erase(instance)
	## 成长统计与目标钩子（2.5）。
	var crafting := CraftingGame.new()
	crafting.bind(farm_game)
	var kind := str(settlement.get("kind", ""))
	if kind == "extract":
		crafting.record_event("extract", {})
	elif kind == "gate_clear":
		crafting.record_event("gate_clear", {})
	var brought_now := {}
	for group in ["gained", "protected"]:
		for entry in settlement.get(group, []):
			var def_id := str(entry.get("def_id", ""))
			if FarmGame.seed_item_to_plant(def_id) != "":
				## 种子已转种植体系：成长目标按"带回"口径仍计一次。
				brought_now[def_id] = int(brought_now.get(def_id, 0)) + 1
				continue
			brought_now[def_id] = int(brought_now.get(def_id, 0)) + 1
	for def_id in brought_now:
		crafting.record_event("brought", {"id": def_id, "count": int(brought_now[def_id])})
	applied.append(settlement_id)
	expedition["applied_settlements"] = applied
	settlement["applied"] = true
	ExpeditionStore.save_settlement(settlement_id, settlement)
	return {"ok": true, "reason": "", "restored": restored, "removed": removed}


static func _carried_ids_of(expedition: Dictionary) -> Array:
	var ids: Array = []
	for container in ExpeditionBaseline.CONTAINERS:
		for instance in expedition["inventory"]["loadout"].get(container, []):
			ids.append(int(instance["instance_id"]))
	return ids
