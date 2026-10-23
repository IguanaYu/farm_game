class_name CombatGame
extends RefCounted
## 单人卡牌战斗规则层（2.2 详细设计）。玩家状态按玩家键索引（2.6 加键即可支持双人）；
## 敌人与意图共享。所有方法返回结果字典并输出事件列表，UI 只消费事件，不参与裁定。
## 时序（设计 §3）：回合开始清格挡→加入到期物品牌→能量重置→抽 5→出牌→结束弃牌→
## 敌人逐个行动（各自先清旧格挡、结算中毒）→玩家行动开始结算中毒→发放资源。


const ENEMIES := {
	# 数值专项入口使用的固定压力场；不加入正式地图遭遇池。
	"anchor_dummy_7": {"name": "压力样例 · 7点轻击", "hp": 72, "cycle": [{"kind": "attack", "value": 7}]},
	"anchor_dummy_10": {"name": "压力样例 · 10点轻击", "hp": 72, "cycle": [{"kind": "attack", "value": 10}]},
	"anchor_dummy_15": {"name": "压力样例 · 15点重击", "hp": 72, "cycle": [{"kind": "attack", "value": 15}]},
	# 人形敌人带 equipment：尸体顶部生成掉落装备槽区（主武→副武→头盔→护甲）。
	# equipment 键：weapon→主武器槽、offhand→副武器槽、helmet→头盔槽、armor→护甲槽。
	# 可选 drop_odds：按键独立掷掉落概率（默认 1.0 必掉；当前内容先必掉，概率留接口）。
	"skeleton_scout": {
		"name": "骷髅巡逻兵", "hp": 26,
		"equipment": {"weapon": "copper_shortsword", "armor": "leather_bracer"},
		"cycle": [{"kind": "attack", "value": 7}, {"kind": "block", "value": 5}, {"kind": "attack", "value": 9}],
	},
	"slime": {
		"name": "小泥团", "hp": 18,
		"cycle": [
			{"kind": "attack", "value": 5},
			{"kind": "block", "value": 4},
			{"kind": "attack", "value": 7},
		],
	},
	"cave_bat": {
		"name": "洞穴蝠", "hp": 14,
		"cycle": [
			{"kind": "attack", "value": 3, "times": 2},
			{"kind": "attack", "value": 4, "status": "weak", "status_stacks": 1},
		],
	},
	"deep_bat": {
		"name": "深层蝠", "hp": 20,
		"cycle": [
			{"kind": "attack", "value": 4, "times": 2},
			{"kind": "attack", "value": 6},
			{"kind": "block", "value": 5},
		],
	},
	"ore_golem": {
		"name": "矿偶", "hp": 32,
		"cycle": [
			{"kind": "block", "value": 8},
			{"kind": "attack", "value": 11},
			{"kind": "attack", "value": 11},
		],
	},
	"crystal_spider": {
		"name": "晶蛛", "hp": 22,
		"cycle": [
			{"kind": "attack", "value": 5, "status": "weak", "status_stacks": 1},
			{"kind": "attack", "value": 8},
		],
	},
	"root_guardian": {
		"name": "根须守卫（首领）", "hp": 60,
		"cycle": [
			{"kind": "attack", "value": 6, "times": 2},
			{"kind": "block", "value": 10},
			{"kind": "attack", "value": 14},
			{"kind": "attack", "value": 5, "status": "vulnerable", "status_stacks": 1},
		],
	},
	"rock_crab": {
		"name": "碎石蟹", "hp": 26,
		"cycle": [
			{"kind": "block", "value": 6},
			{"kind": "attack", "value": 9},
		],
	},
	# —— 第三层晶脉矿窟（内容扩展轮）——
	"vein_crawler": {
		"name": "晶脉爬虫", "hp": 28,
		"cycle": [
			{"kind": "attack", "value": 6, "times": 2},
			{"kind": "attack", "value": 9},
			{"kind": "block", "value": 6},
		],
	},
	"void_moth": {
		"name": "暗渊蛾", "hp": 32,
		"cycle": [
			{"kind": "attack", "value": 5, "status": "vulnerable", "status_stacks": 1},
			{"kind": "attack", "value": 7, "times": 2},
			{"kind": "attack", "value": 10},
		],
	},
	"prism_golem": {
		"name": "棱镜魔像", "hp": 42,
		"cycle": [
			{"kind": "block", "value": 10},
			{"kind": "attack", "value": 12},
			{"kind": "attack", "value": 12, "status": "weak", "status_stacks": 1},
		],
	},
	"crystal_tyrant": {
		"name": "晶暴君（首领）", "hp": 90,
		"cycle": [
			{"kind": "attack", "value": 7, "times": 2},
			{"kind": "block", "value": 12},
			{"kind": "attack", "value": 16},
			{"kind": "attack", "value": 6, "status": "poison", "status_stacks": 3},
		],
	},
}

## 双人敌人生命缩放（2.6 设计 §5 初值）。
const HP_SCALE_2P := 1.6

const ENCOUNTERS := {
	"anchor_pressure_7": {"name": "费用锚点：7点轻击", "enemies": ["anchor_dummy_7"]},
	"anchor_pressure_10": {"name": "费用锚点：10点轻击", "enemies": ["anchor_dummy_10"]},
	"anchor_pressure_15": {"name": "费用锚点：15点重击", "enemies": ["anchor_dummy_15"]},
	"skeleton_patrol": {"name": "骷髅巡逻兵", "enemies": ["skeleton_scout"]},
	"tutorial": {"name": "教学场（单只小泥团）", "enemies": ["slime"]},
	"normal": {"name": "普通验证场（泥团＋蝠）", "enemies": ["slime", "cave_bat"]},
	"defensive": {"name": "防御验证场（碎石蟹）", "enemies": ["rock_crab"]},
	"gate_keeper": {"name": "第一层守门战", "enemies": ["rock_crab", "slime", "cave_bat"]},
	"deep_pair": {"name": "深层巡逻（蝠＋晶蛛）", "enemies": ["deep_bat", "crystal_spider"]},
	"deep_hard": {"name": "深层硬仗（矿偶＋蝠）", "enemies": ["ore_golem", "deep_bat"]},
	"layer2_elite": {"name": "深层精英（矿偶＋晶蛛）", "enemies": ["ore_golem", "crystal_spider"]},
	"layer2_guardian": {"name": "首领：根须守卫", "enemies": ["root_guardian"]},
	"deep3_pair": {"name": "晶脉巡逻（爬虫＋蛾）", "enemies": ["vein_crawler", "void_moth"]},
	"deep3_hard": {"name": "晶脉硬仗（魔像＋爬虫）", "enemies": ["prism_golem", "vein_crawler"]},
	"layer3_elite": {"name": "晶脉精英（魔像＋蛾）", "enemies": ["prism_golem", "void_moth"]},
	"layer3_guardian": {"name": "首领：晶暴君", "enemies": ["crystal_tyrant"]},
}


## 2.2 演示入口的固定牌组：基础套装 8 张、全部第 1 回合加入（2.2 计划 W9）。
static func basic_kit_demo_deck() -> Array:
	var deck: Array = []
	for def_id in ItemDefs.basic_kit_ids():
		var def := ItemDefs.get_item(def_id)
		var seq := 0
		for card_id in def["cards"]:
			deck.append({"card_id": card_id, "source_instance_id": 0, "source_def_id": def_id, "source_quality": int(def.get("quality", 1)), "source_seq": seq, "join_round": 1})
			seq += 1
	return deck


var state: Dictionary = {}
var rng := RandomNumberGenerator.new()
var inventory: InventoryGame = null
## 双人：各成员的消耗品实体走自己的库存视图（键＝玩家键）。
var member_inventories: Dictionary = {}

## 表现试玩可在独立会话子类提供样例牌；正式战斗仍只读取 CardDefs。
func card_definition(card_id: String) -> Dictionary:
	return CardDefs.get_card(card_id)


## players：[{key: "p1", name: "农夫", max_hp: 40, deck: [{card_id, source_instance_id, source_seq, join_round}…]}]
## deck 来源在 2.3 由 DeckBuilder 从背包布局生成；2.2 演示入口直接给固定牌表。
## fixed_draw_order：测试注入的抽牌堆顺序（不洗牌），生产不传。
static func create(players: Array, encounter_id: String, seed_value: int, player_inventory: InventoryGame = null, fixed_draw_order: Array = []) -> CombatGame:
	var combat := CombatGame.new()
	combat.inventory = player_inventory
	combat.rng.seed = seed_value
	if not ENCOUNTERS.has(encounter_id):
		push_error("未知遭遇：%s" % encounter_id)
		return combat
	var enemy_list: Array = []
	var suffix := 0
	## 双人：普通敌人生命×1.6 向上取整，攻击不变（2.6 设计 §5；不与数量加成叠加）。
	var hp_scale := 1.0 if players.size() < 2 else HP_SCALE_2P
	var player_keys: Array = []
	for entry in players:
		player_keys.append(str(entry.get("key", "p1")))
	for def_id in ENCOUNTERS[encounter_id]["enemies"]:
		suffix += 1
		var def: Dictionary = ENEMIES[def_id]
		var scaled_hp := int(ceil(float(def["hp"]) * hp_scale))
		enemy_list.append({
			"id": "e%d" % suffix,
			"def_id": def_id,
			"name": def["name"],
			"target_key": str(player_keys[(suffix - 1) % player_keys.size()]),
			"hp": scaled_hp, "max_hp": scaled_hp, "block": 0,
			"statuses": {},
			"cycle_index": 0,
			"intent": {},
			"alive": true,
			"equipment": def.get("equipment", {}).duplicate(true),
		})
	var player_map := {}
	var next_uid := 1
	for player in players:
		var key := str(player["key"])
		var deck_entries: Array = player.get("deck", [])
		var all_cards: Array = []
		var pending: Dictionary = {"1": [], "2": [], "3": []}
		for entry in deck_entries:
			var card: Dictionary = {
				"uid": next_uid,
				"card_id": str(entry["card_id"]),
				"source_instance_id": int(entry.get("source_instance_id", 0)),
				"source_def_id": str(entry.get("source_def_id", "")),
				"source_quality": clampi(int(entry.get("source_quality", 1)), 1, 5),
				"source_seq": int(entry.get("source_seq", 0)),
				"owner": key,
			}
			next_uid += 1
			all_cards.append(card)
			var join_round := int(entry.get("join_round", 1))
			if join_round <= 1:
				pending["1"].append(card)
			else:
				pending[str(join_round)].append(card)
		player_map[key] = {
			"name": str(player.get("name", "农夫")),
			"hp": int(player.get("hp", player.get("max_hp", ExpeditionBaseline.MAX_HP))),
			"max_hp": int(player.get("max_hp", ExpeditionBaseline.MAX_HP)),
			"block": 0,
			"downed": false,
			"rescued_once": false,
			"missed_round_start": false,
			"energy": 0,
			"hand": [],
			"draw_pile": [],
			"discard_pile": [],
			"exhaust_pile": [],
			"pending_join": pending,
			"statuses": {},
			"ended": false,
		}
	combat.state = {
		"fmt": 1,
		"rules_version": ExpeditionBaseline.PROTO_RULES_VERSION,
		"seed": seed_value,
		"rng_state": str(combat.rng.state),
		"encounter_id": encounter_id,
		"round": 0,
		"phase": "player",
		"players": player_map,
		"enemies": enemy_list,
		"log": [],
		"next_uid": next_uid,
		"outcome": "",
		"fixed_deck": not fixed_draw_order.is_empty(),
	}
	if not fixed_draw_order.is_empty():
		# 按测试给定顺序重排已带 uid 的首回合牌（不引入无 uid 的裸条目）。
		var wanted: Array = []
		for entry in fixed_draw_order:
			var want_id := str(entry["card_id"])
			for card in player_map["p1"]["pending_join"]["1"]:
				if str(card["card_id"]) == want_id and not wanted.has(card):
					wanted.append(card)
					break
		player_map["p1"]["pending_join"]["1"] = wanted
	return combat


func start() -> Dictionary:
	## 第 1 回合准备：意图生成＋回合开始流程。
	if not state.is_empty() and state["phase"] == "player" and state["round"] == 0:
		for enemy in state["enemies"]:
			_roll_intent(enemy)
		var events: Array = _round_events(1)
		_begin_player_round(events)
		return {"ok": true, "events": events}
	return {"ok": false, "reason": "战斗已在进行", "events": []}


# —— 出牌 ————————————————————————————————————————————————————————


## 合法目标键："e1" 等敌人 id，或玩家键（自己/队友）。
func play_card(owner_key: String, uid: int, target_key: String) -> Dictionary:
	var events: Array = []
	if state["phase"] != "player":
		return _deny("当前不是玩家回合", events)
	var player: Dictionary = state["players"].get(owner_key)
	if player.is_empty() or int(player.get("hp", 0)) <= 0:
		return _deny("倒地的玩家不能出牌", events)
	if bool(player.get("ended", false)):
		return _deny("已经结束行动", events)
	var card := _hand_card(owner_key, uid)
	if card.is_empty():
		return _deny("这张牌已不在手牌中", events)
	var def := card_definition(str(card["card_id"]))
	if def.is_empty():
		return _deny("未知牌型", events)
	var target := _resolve_target(def["target"], target_key, owner_key)
	if target.is_empty():
		return _deny("目标不合法", events)
	for effect in def["effects"]:
		if _effect_target(owner_key, target_key, effect).is_empty():
			return _deny("效果目标不合法", events)
	if int(player["energy"]) < int(def["cost"]):
		return _deny("能量不足", events)
	if str(def["after"]) == "exhaust_source":
		var consume := _consume_source_for(owner_key, int(card["source_instance_id"]))
		if not consume["ok"]:
			return _deny(consume["reason"], events)
		if int(consume.get("uses_left", 1)) <= 0:
			_purge_source_cards(owner_key, int(card["source_instance_id"]), events)
	player["energy"] = int(player["energy"]) - int(def["cost"])
	_remove_from_hand(owner_key, uid)
	events.append({"type": "card_played", "owner": owner_key, "card": str(def["name"]), "card_id": str(card["card_id"]), "cost": int(def["cost"]), "target": target_key})
	for effect in def["effects"]:
		var effect_target := _effect_target(owner_key, target_key, effect)
		if effect_target.is_empty():
			continue
		_apply_effect(owner_key, _unit_id(effect_target), effect, events)
		_events_check_outcome(events)
		if is_over():
			break
	# 出牌去向：弃牌／移除（exhaust_source 的关联牌清理由 2.3 的实体耗尽联动补全）。
	if str(def["after"]) == "discard":
		player["discard_pile"].append(card)
	else:
		player["exhaust_pile"].append(card)
	_events_check_outcome(events)
	_log_use(def, player, target_key)
	return {"ok": true, "events": events}


## 预计效果（不改状态）：返回主要数值变化，供 UI 高亮。
func preview_play(owner_key: String, uid: int, target_key: String) -> Dictionary:
	var player: Dictionary = state["players"].get(owner_key, {})
	var card := _hand_card(owner_key, uid)
	if player.is_empty() or card.is_empty():
		return {"ok": false}
	var def := card_definition(str(card["card_id"]))
	var target := _resolve_target(def.get("target", ""), target_key, owner_key)
	if target.is_empty():
		return {"ok": false, "reason": "目标不合法"}
	for effect in def.get("effects", []):
		if _effect_target(owner_key, target_key, effect).is_empty():
			return {"ok": false, "reason": "效果目标不合法"}
	# 在独立状态与 RNG 上调用同一效果入口，顺序、格挡与死亡中断均与实战一致。
	var simulation := CombatGame.new()
	simulation.load_dict(to_dict())
	var preview := {"ok": true, "effects": []}
	for effect in def.get("effects", []):
		var effect_target := simulation._effect_target(owner_key, target_key, effect)
		if effect_target.is_empty():
			continue
		var events: Array = []
		simulation._apply_effect(owner_key, simulation._unit_id(effect_target), effect, events)
		for event in events:
			var kind := str(event.get("type", ""))
			if kind in ["damage", "block", "heal", "draw", "status", "rescue"]:
				var detail: Dictionary = event.duplicate(true)
				detail["kind"] = kind
				detail["times"] = 1
				preview["effects"].append(detail)
				if kind == "status":
					preview["status"] = CardDefs.STATUS_DISPLAY.get(str(event["status"]), str(event["status"]))
				else:
					preview[kind] = int(preview.get(kind, 0)) + int(event.get("amount", event.get("count", 0)))
		simulation._events_check_outcome(events)
		if simulation.is_over():
			break
	return preview


## 结束行动：非保留手牌全部弃掉 → 敌方阶段 → 下一回合（或终局）。
func end_turn(owner_key: String) -> Dictionary:
	var events: Array = []
	if state["phase"] != "player":
		return _deny("当前不是玩家回合", events)
	var player: Dictionary = state["players"].get(owner_key, {})
	if player.is_empty() or int(player["hp"]) <= 0 or bool(player.get("ended", false)):
		return _deny("当前玩家无法结束行动", events)
	player["ended"] = true
	## 共同回合：全部可行动玩家（未倒地）都结束才进入敌方阶段；倒地者不计入。
	for key in state["players"]:
		var each: Dictionary = state["players"][key]
		if int(each["hp"]) > 0 and not each["ended"]:
			return {"ok": true, "events": events, "waiting": true}
	events.append({"type": "turn_ended", "round": int(state["round"])})
	_run_discard_phase(events)
	_run_enemy_phase(events)
	if state["outcome"] != "":
		return {"ok": true, "events": events, "outcome": state["outcome"]}
	_begin_player_round(events)
	return {"ok": true, "events": events, "outcome": state["outcome"]}


# —— 查询 ————————————————————————————————————————————————————————


## 休整"检查装备"等效果：额外抽牌（2.4 休整二选一）。
func draw_extra(count: int) -> void:
	_draw_cards(state["players"]["p1"], count)


func draw_extra_for(player_key: String, count: int) -> void:
	if state["players"].has(player_key):
		_draw_cards(state["players"][player_key], count)


func enemy_intents() -> Array:
	var result: Array = []
	for enemy in state["enemies"]:
		if not bool(enemy["alive"]):
			continue
		var intent: Dictionary = enemy.get("intent", {})
		result.append({
			"enemy_id": enemy["id"],
			"name": enemy["name"],
			"text": intent_text(enemy),
		})
	return result


func combat_log() -> Array:
	return state.get("log", [])


func is_over() -> bool:
	return str(state.get("outcome", "")) != ""


# —— 序列化（2.4 局快照 / 2.7 恢复的基础）—————————————————————


func to_dict() -> Dictionary:
	var snapshot := state.duplicate(true)
	snapshot["rng_state"] = str(rng.state)
	return snapshot


func load_dict(snapshot: Dictionary) -> bool:
	if int(snapshot.get("fmt", -1)) != 1:
		return false
	state = snapshot.duplicate(true)
	for unit in state.get("players", {}).values() + state.get("enemies", []):
		if not unit.has("statuses"):
			unit["statuses"] = {}
	rng.seed = int(state.get("seed", 0))
	rng.state = int(state.get("rng_state", "0"))
	return true


# —— 内部：回合流程 ————————————————————————————————————————————


func _begin_player_round(events: Array = []) -> void:
	state["round"] = int(state["round"]) + 1
	state["phase"] = "player"
	for key in state["players"]:
		var player: Dictionary = state["players"][key]
		player["ended"] = false
		player["block"] = 0
		if int(player["hp"]) <= 0:
			## 倒地者不清手牌与能量（保留），但不发新资源；被救起时按标记补发。
			player["missed_round_start"] = true
			continue
		_apply_poison(player, events)
		_events_check_outcome(events)
		if is_over():
			return
		if int(player["hp"]) <= 0:
			player["missed_round_start"] = true
			continue
		_join_due_cards(player)
		player["energy"] = ExpeditionBaseline.ENERGY_PER_TURN
		_draw_cards(player, ExpeditionBaseline.DRAW_PER_TURN)
		state["log"].append("—— 第 %d 回合开始：能量 %d，抽 %d 张 ——" % [int(state["round"]), ExpeditionBaseline.ENERGY_PER_TURN, ExpeditionBaseline.DRAW_PER_TURN])
	for enemy in state["enemies"]:
		if bool(enemy["alive"]):
			_roll_intent(enemy)


func _run_discard_phase(events: Array) -> void:
	for key in state["players"]:
		var player: Dictionary = state["players"][key]
		if int(player["hp"]) <= 0:
			continue
		for card in player["hand"].duplicate():
			player["discard_pile"].append(card)
		player["hand"] = []
		# 易伤/虚弱在受影响单位完成自身行动阶段后减 1（设计 §4）：玩家阶段在此结束。
		if int(player["hp"]) > 0:
			_decrement_own_statuses(player)
	events.append({"type": "discarded"})


func _run_enemy_phase(events: Array) -> void:
	state["phase"] = "enemy"
	for enemy in state["enemies"]:
		if not bool(enemy["alive"]):
			continue
		# 每个敌人行动开始先清自己的旧格挡，再结算自己的持续伤害。
		enemy["block"] = 0
		_apply_poison(enemy, events)
		_events_check_outcome(events)
		if is_over():
			return
		if not bool(enemy["alive"]):
			continue
		_execute_intent(enemy, events)
		_decrement_own_statuses(enemy)
		if state["outcome"] != "":
			return
	_events_check_outcome(events)


func _events_check_outcome(events: Array) -> void:
	if state["outcome"] != "":
		return
	var any_alive := false
	for enemy in state["enemies"]:
		if bool(enemy["alive"]):
			any_alive = true
	if not any_alive:
		_set_outcome("won", events)
		return
	var any_standing := false
	for key in state["players"]:
		if int(state["players"][key]["hp"]) > 0:
			any_standing = true
	if not any_standing:
		_set_outcome("lost", events)


func _set_outcome(outcome: String, events: Array) -> void:
	if is_over():
		return
	if outcome == "won":
		## 战斗胜利：倒地但队伍未失败的玩家恢复到 4 生命（2.6 设计 §5）。
		for key in state["players"]:
			var player: Dictionary = state["players"][key]
			if int(player["hp"]) <= 0:
				player["hp"] = mini(4, int(player["max_hp"]))
				player["downed"] = false
				events.append({"type": "revived_at_victory", "player": key})
				state["log"].append("%s 在胜利后恢复到 %d 生命" % [player["name"], int(player["hp"])])
	# 状态仅属于当前战斗，终局与新建战斗都不保留。
	for player in state["players"].values():
		player["statuses"] = {}
	for enemy in state["enemies"]:
		enemy["statuses"] = {}
	state["outcome"] = outcome
	state["phase"] = "finished"
	state["log"].append("战斗%s（第 %d 回合）" % ["胜利" if outcome == "won" else "失败", int(state["round"])])
	events.append({"type": "outcome", "outcome": outcome, "round": int(state["round"])})


# —— 内部：效果结算 ————————————————————————————————————————————


func _apply_effect(owner_key: String, target_key: String, effect: Dictionary, events: Array) -> void:
	var recipient := _find_unit(target_key)
	if recipient.is_empty():
		return
	if int(recipient.get("hp", 0)) <= 0 and str(effect.get("kind", "")) not in ["rescue", "draw"]:
		return
	match str(effect.get("kind", "")):
		"damage":
			var target := _find_unit(target_key)
			for strike in range(maxi(1, int(effect.get("times", 1)))):
				if int(target.get("hp", 0)) <= 0 or is_over():
					break
				var amount := _outgoing_damage(owner_key, target, int(effect["value"]))
				_deal_damage(owner_key, target, amount, events)
				_events_check_outcome(events)
		"block":
			var target := _find_unit(target_key)
			var amount := _block_gain(owner_key, int(effect["value"]))
			target["block"] = int(target["block"]) + amount
			events.append({"type": "block", "target": target_key, "amount": amount})
			state["log"].append("%s 获得 %d 格挡" % [_unit_name(target), amount])
		"heal":
			var target := _find_unit(target_key)
			var healed := mini(int(effect["value"]), int(target["max_hp"]) - int(target["hp"]))
			target["hp"] = int(target["hp"]) + maxi(0, healed)
			events.append({"type": "heal", "target": target_key, "amount": maxi(0, healed)})
			state["log"].append("%s 恢复 %d 生命（上限内）" % [_unit_name(target), maxi(0, healed)])
		"draw":
			var player: Dictionary = state["players"][owner_key]
			_draw_cards(player, int(effect["value"]))
			events.append({"type": "draw", "who": owner_key, "count": int(effect["value"])})
		"rescue":
			# 救援：倒地队友恢复到 value 生命；每人每场最多一次（2.6 设计 §5）。
			var target := _find_unit(target_key)
			if bool(target.get("rescued_once", false)):
				events.append({"type": "rescue_denied", "target": target_key})
				state["log"].append("%s 本场已被救起过一次，无法再救" % target["name"])
			else:
				target["hp"] = mini(int(effect["value"]), int(target["max_hp"]))
				target["downed"] = false
				target["rescued_once"] = true
				if bool(target.get("missed_round_start", false)):
					target["missed_round_start"] = false
					_join_due_cards(target)
					target["energy"] = ExpeditionBaseline.ENERGY_PER_TURN
					_draw_cards(target, ExpeditionBaseline.DRAW_PER_TURN)
				events.append({"type": "rescue", "target": target_key, "hp": int(target["hp"])})
				state["log"].append("%s 被救起，恢复到 %d 生命" % [target["name"], int(target["hp"])])
		"status":
			var target := _find_unit(target_key)
			if int(target.get("hp", 0)) <= 0:
				return
			var status := str(effect.get("status", ""))
			var stacks := int(effect.get("stacks", 1))
			_add_status(target, status, stacks)
			events.append({"type": "status", "target": target_key, "status": status, "stacks": stacks})
			state["log"].append("%s 获得 %s ×%d" % [_unit_name(target), CardDefs.STATUS_DISPLAY.get(status, status), stacks])


## 基础值先加力量，再乘虚弱与易伤；中间保留精度，最后统一向下取整。
func _outgoing_damage(attacker_key: String, target: Dictionary, base: int) -> int:
	var attacker := _find_unit(attacker_key)
	return _attack_amount(attacker, target, base)


func _attack_amount(attacker: Dictionary, target: Dictionary, base: int) -> int:
	var amount := float(maxi(0, base + _status_stacks(attacker, "strength")))
	if _has_status(attacker, "weak"):
		amount *= 0.75
	if _has_status(target, "vulnerable"):
		amount *= 1.5
	return int(floor(amount))


func _block_gain(caster_key: String, base: int) -> int:
	return maxi(0, base + _status_stacks(_find_unit(caster_key), "dexterity"))


func _status_stacks(unit: Dictionary, status: String) -> int:
	return maxi(0, int(unit.get("statuses", {}).get(status, {}).get("stacks", 0)))


func _deal_damage(attacker_key: String, target: Dictionary, amount: int, events: Array) -> void:
	if int(target.get("hp", 0)) <= 0:
		return
	amount = maxi(0, amount)
	var blocked := mini(amount, int(target["block"]))
	target["block"] = int(target["block"]) - blocked
	var to_hp := amount - blocked
	target["hp"] = int(target["hp"]) - to_hp
	events.append({"type": "damage", "source": attacker_key, "target": _unit_id(target), "amount": amount, "blocked": blocked, "to_hp": to_hp})
	state["log"].append("%s 受到 %d 伤害（格挡抵消 %d，生命 -%d）" % [_unit_name(target), amount, blocked, to_hp])
	if int(target["hp"]) <= 0:
		if state["players"].has(_unit_id(target)):
			target["hp"] = 0
			target["downed"] = true
			target["block"] = 0
			state["log"].append("%s 倒地（不能出牌；队友可救援，全部倒地则失败）" % target["name"])
			events.append({"type": "player_downed", "player": _unit_id(target)})
		else:
			target["alive"] = false
			target["hp"] = 0
			state["log"].append("%s 被击败" % target["name"])
			events.append({"type": "enemy_died", "enemy_id": _unit_id(target)})


func _apply_poison(unit: Dictionary, events: Array) -> void:
	if int(unit.get("hp", 0)) <= 0:
		return
	var stacks := _status_stacks(unit, "poison")
	if stacks <= 0:
		return
	# 中毒绕过格挡（设计 §4）。
	unit["hp"] = int(unit["hp"]) - stacks
	unit["statuses"]["poison"]["stacks"] = stacks - 1
	if unit["statuses"]["poison"]["stacks"] <= 0:
		unit["statuses"].erase("poison")
	events.append({"type": "poison", "target": _unit_id(unit), "amount": stacks})
	state["log"].append("%s 中毒受到 %d 伤害（绕过格挡）" % [_unit_name(unit), stacks])
	if int(unit["hp"]) <= 0:
		if state["players"].has(_unit_id(unit)):
			unit["hp"] = 0
			unit["downed"] = true
			unit["block"] = 0
			state["log"].append("%s 中毒倒地" % unit["name"])
			events.append({"type": "player_downed", "player": _unit_id(unit)})
		else:
			unit["alive"] = false
			unit["hp"] = 0
			state["log"].append("%s 被毒死" % unit["name"])
			events.append({"type": "enemy_died", "enemy_id": _unit_id(unit)})


func _add_status(unit: Dictionary, status: String, stacks: int) -> void:
	if stacks <= 0 or not CardDefs.STATUS_DISPLAY.has(status):
		return
	var current: Dictionary = unit["statuses"].get(status, {"stacks": 0})
	current["stacks"] = int(current["stacks"]) + stacks
	unit["statuses"][status] = current


func _has_status(unit: Dictionary, status: String) -> bool:
	return _status_stacks(unit, status) > 0


## 易伤/虚弱在受影响单位完成自身行动阶段后减 1 回合（设计 §4 状态表）。
func _decrement_own_statuses(unit: Dictionary) -> void:
	for status in ["vulnerable", "weak"]:
		if _has_status(unit, status):
			var entry: Dictionary = unit["statuses"][status]
			entry["stacks"] = int(entry["stacks"]) - 1
			if int(entry["stacks"]) <= 0:
				unit["statuses"].erase(status)


# —— 内部：敌人意图 ————————————————————————————————————————————


func _roll_intent(enemy: Dictionary) -> void:
	var def: Dictionary = ENEMIES[enemy["def_id"]]
	var index := int(enemy["cycle_index"]) % int(def["cycle"].size())
	enemy["intent"] = def["cycle"][index].duplicate(true)
	# 意图一经本回合确定，不因查看卡牌或等待而变（设计 §6）。
	enemy["intent"]["seed_locked"] = true


func _execute_intent(enemy: Dictionary, events: Array) -> void:
	var intent: Dictionary = enemy["intent"]
	var def: Dictionary = ENEMIES[enemy["def_id"]]
	enemy["cycle_index"] = (int(enemy["cycle_index"]) + 1) % int(def["cycle"].size())
	var times := int(intent.get("times", 1))
	match str(intent.get("kind", "")):
		"attack":
			for strike in range(times):
				## 单体攻击只打意图目标；原目标倒地则行动前重选存活者（2.6 设计 §5）。
				var victim := _intent_victim(enemy)
				if victim.is_empty():
					break
				var amount := _outgoing_damage(enemy["id"], victim, int(intent["value"]))
				_deal_damage(enemy["id"], victim, amount, events)
				if str(intent.get("status", "")) != "" and int(victim["hp"]) > 0:
					_add_status(victim, str(intent["status"]), int(intent.get("status_stacks", 1)))
					events.append({"type": "status", "target": _unit_id(victim), "status": str(intent["status"]), "stacks": int(intent.get("status_stacks", 1))})
					state["log"].append("%s 获得 %s ×%d" % [victim["name"], CardDefs.STATUS_DISPLAY.get(str(intent["status"]), str(intent["status"])), int(intent.get("status_stacks", 1))])
				if _all_players_downed():
					_set_outcome("lost", events)
					return
		"block":
			var amount := _block_gain(str(enemy["id"]), int(intent["value"]))
			enemy["block"] = int(enemy["block"]) + amount
			events.append({"type": "enemy_block", "enemy_id": enemy["id"], "amount": amount})
			state["log"].append("%s 获得 %d 格挡" % [enemy["name"], amount])
		"status":
			_add_status(enemy, str(intent.get("status", "")), int(intent.get("status_stacks", 1)))
			events.append({"type": "status", "target": enemy["id"], "status": str(intent.get("status", "")), "stacks": int(intent.get("status_stacks", 1))})
	events.append({"type": "enemy_acted", "enemy_id": enemy["id"]})


## 意图目标：固定指派；倒地时行动前重选存活者并记录（不暗中专打没格挡的人）。
func _intent_victim(enemy: Dictionary) -> Dictionary:
	var target_key := str(intent_target(enemy))
	if state["players"].has(target_key) and int(state["players"][target_key]["hp"]) > 0:
		return state["players"][target_key]
	for key in state["players"]:
		if int(state["players"][key]["hp"]) > 0:
			state["log"].append("%s 的原目标已倒地，转向 %s" % [enemy["name"], state["players"][key]["name"]])
			enemy["target_key"] = str(key)
			return state["players"][key]
	return {}


func intent_target(enemy: Dictionary) -> String:
	return str(enemy.get("target_key", "p1"))


## 预告敌人即将执行的数值：玩家共同阶段结束的减层也计入，不改变真实目标或状态。
func intent_preview(enemy: Dictionary) -> Dictionary:
	var preview: Dictionary = enemy.get("intent", {}).duplicate(true)
	preview["target"] = intent_target(enemy)
	if not bool(enemy.get("alive", false)) or _status_stacks(enemy, "poison") >= int(enemy.get("hp", 0)):
		return {"kind": "none", "value": 0, "times": 0, "strikes": [], "target": intent_target(enemy), "text": "行动开始中毒倒下"}
	var simulation := CombatGame.new()
	simulation.load_dict(to_dict())
	if str(state.get("phase", "")) == "player":
		for player in simulation.state["players"].values():
			if int(player["hp"]) > 0:
				simulation._decrement_own_statuses(player)
		# 同一阶段内，前一个敌人的附加状态、击倒和中毒死亡也影响后续意图。
		for preceding in simulation.state["enemies"]:
			if str(preceding["id"]) == str(enemy["id"]):
				break
			if not bool(preceding["alive"]):
				continue
			var prior_events: Array = []
			preceding["block"] = 0
			simulation._apply_poison(preceding, prior_events)
			simulation._events_check_outcome(prior_events)
			if not simulation.is_over() and bool(preceding["alive"]):
				simulation._execute_intent(preceding, prior_events)
				simulation._decrement_own_statuses(preceding)
			if simulation.is_over():
				return {"kind": "none", "value": 0, "times": 0, "strikes": [], "target": intent_target(enemy), "text": "队伍已倒地"}
	var simulated_enemy := simulation._find_unit(str(enemy["id"]))
	simulated_enemy["block"] = 0
	var events: Array = []
	simulation._apply_poison(simulated_enemy, events)
	simulation._execute_intent(simulated_enemy, events)
	var strikes: Array = []
	for event in events:
		if str(event.get("type", "")) == "damage":
			strikes.append(event.duplicate(true))
		elif str(event.get("type", "")) == "enemy_block":
			preview["value"] = int(event["amount"])
	preview["strikes"] = strikes
	preview["times"] = maxi(1, int(preview.get("times", 1)))
	if str(preview.get("kind", "")) == "attack" and not strikes.is_empty():
		preview["value"] = int(strikes[0]["amount"])
		preview["target"] = str(strikes[0]["target"])
		preview["times"] = strikes.size()
		var uniform := true
		var parts: Array[String] = []
		for strike in strikes:
			uniform = uniform and int(strike["amount"]) == int(preview["value"]) and str(strike["target"]) == str(preview["target"])
			parts.append("%d→%s" % [int(strike["amount"]), str(state["players"].get(str(strike["target"]), {}).get("name", strike["target"]))])
		preview["text"] = _intent_text(preview) if uniform else "攻击 " + " + ".join(parts)
	else:
		preview["text"] = _intent_text(preview)
	return preview


func intent_text(enemy: Dictionary) -> String:
	return str(intent_preview(enemy).get("text", "—"))


func _all_players_downed() -> bool:
	for key in state["players"]:
		if int(state["players"][key]["hp"]) > 0:
			return false
	return true


func _intent_text(intent: Dictionary) -> String:
	if intent.is_empty():
		return "—"
	match str(intent.get("kind", "")):
		"attack":
			var text := "攻击 %d" % int(intent["value"])
			if int(intent.get("times", 1)) > 1:
				text = "攻击 %d×%d" % [int(intent["value"]), int(intent["times"])]
			if str(intent.get("status", "")) != "":
				text += "（附带%s）" % CardDefs.STATUS_DISPLAY.get(str(intent["status"]), str(intent["status"]))
			return text
		"block":
			return "格挡 %d" % int(intent["value"])
	return "—"


# —— 内部：牌堆 —————————————————————————————————————————————————


## 救援补发也接收此前错过的到期牌；只清空已加入的槽，不重复发牌或结算中毒。
func _join_due_cards(player: Dictionary) -> void:
	for round_key in player["pending_join"]:
		if int(round_key) > int(state["round"]):
			continue
		var due: Array = player["pending_join"][round_key]
		if due.is_empty():
			continue
		if bool(state.get("fixed_deck", false)):
			player["draw_pile"].append_array(due)
		else:
			_shuffle_into_draw(player, due)
		player["pending_join"][round_key] = []


func _hand_card(owner_key: String, uid: int) -> Dictionary:
	for card in state["players"][owner_key]["hand"]:
		if int(card["uid"]) == uid:
			return card
	return {}


func _remove_from_hand(owner_key: String, uid: int) -> void:
	var hand: Array = state["players"][owner_key]["hand"]
	for index in range(hand.size()):
		if int(hand[index]["uid"]) == uid:
			hand.remove_at(index)
			return


func _draw_cards(player: Dictionary, count: int) -> void:
	for attempt in range(count):
		if player["hand"].size() >= ExpeditionBaseline.HAND_LIMIT:
			state["log"].append("%s 手牌已满（%d 张），停止抽牌" % [player["name"], ExpeditionBaseline.HAND_LIMIT])
			return
		if player["draw_pile"].is_empty():
			if player["discard_pile"].is_empty():
				return
			player["draw_pile"] = player["discard_pile"]
			player["discard_pile"] = []
			_shuffle(player["draw_pile"])
			state["log"].append("%s 洗入弃牌堆" % player["name"])
		player["hand"].append(player["draw_pile"].pop_front())


func _shuffle_into_draw(player: Dictionary, cards: Array) -> void:
	_shuffle(cards)
	player["draw_pile"].append_array(cards)
	state["log"].append("%s 的 %d 张物品牌洗入抽牌堆" % [player["name"], cards.size()])


func _shuffle(cards: Array) -> void:
	# Fisher–Yates，用注入的 rng，保证同种子可复现。
	for index in range(cards.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var temp: Dictionary = cards[index]
		cards[index] = cards[swap]
		cards[swap] = temp


## 物品耗尽：该物品剩余手牌、抽牌堆与弃牌堆中的关联牌全部移除（设计 §5）。
func _purge_source_cards(owner_key: String, source_instance_id: int, events: Array) -> void:
	var player: Dictionary = state["players"][owner_key]
	for pile_name in ["hand", "draw_pile", "discard_pile"]:
		var pile: Array = player[pile_name]
		var kept: Array = []
		for card in pile:
			if int(card.get("source_instance_id", 0)) == source_instance_id:
				player["exhaust_pile"].append(card)
			else:
				kept.append(card)
		player[pile_name] = kept
	events.append({"type": "source_depleted", "source_instance_id": source_instance_id})
	state["log"].append("来源物品耗尽：其关联牌全部失效移除")


func _consume_source(instance_id: int) -> Dictionary:
	if inventory == null:
		return {"ok": false, "reason": "这张牌需要来源物品（演示战斗不提供）"}
	return inventory.consume_use(instance_id)


## 双人：按出牌者路由到其成员库存视图（主机回退到默认 inventory）。
func _consume_source_for(owner_key: String, instance_id: int) -> Dictionary:
	if member_inventories.has(owner_key):
		return (member_inventories[owner_key] as InventoryGame).consume_use(instance_id)
	return _consume_source(instance_id)


# —— 内部：目标与工具 ——————————————————————————————————————————


func _resolve_target(target_rule: String, target_key: String, owner_key: String) -> Dictionary:
	match target_rule:
		"enemy":
			for enemy in state["enemies"]:
				if enemy["id"] == target_key and bool(enemy["alive"]):
					return enemy
			return {}
		"self":
			if target_key == owner_key:
				return state["players"][owner_key]
			return {}
		"ally":
			# 存活友方（单人含自己，2.2 设计 §5）。
			if state["players"].has(target_key) and int(state["players"][target_key]["hp"]) > 0:
				return state["players"][target_key]
			return {}
		"rescue":
			# 救援牌只对倒地友方合法（2.6 设计 §5）。
			if state["players"].has(target_key) and int(state["players"][target_key]["hp"]) <= 0 and target_key != owner_key:
				return state["players"][target_key]
			return {}
	return {}


## 默认沿用整张牌所选目标；self 显式指向施放者，enemy/ally 检查所选目标类型。
func _effect_target(owner_key: String, selected_key: String, effect: Dictionary) -> Dictionary:
	var rule := str(effect.get("target", "selected"))
	if rule == "self":
		return _resolve_target("self", owner_key, owner_key)
	if rule == "selected":
		return _find_unit(selected_key)
	return _resolve_target(rule, selected_key, owner_key)


func _find_unit(unit_key: String) -> Dictionary:
	if state["players"].has(unit_key):
		return state["players"][unit_key]
	for enemy in state["enemies"]:
		if enemy["id"] == unit_key:
			return enemy
	return {}


func _unit_id(unit: Dictionary) -> String:
	if unit.has("intent") or unit.has("cycle_index"):
		return str(unit["id"])
	for key in state["players"]:
		if state["players"][key] == unit:
			return str(key)
	return "?"


func _unit_name(unit: Dictionary) -> String:
	return str(unit.get("name", "?"))


func _log_use(def: Dictionary, player: Dictionary, target_key: String) -> void:
	state["log"].append("%s 使用「%s」（费用 %d，目标 %s）" % [player["name"], def["name"], int(def["cost"]), _unit_name(_find_unit(target_key))])


func _round_events(round_number: int) -> Array:
	return [{"type": "round_start", "round": round_number}]


func _deny(reason: String, events: Array) -> Dictionary:
	return {"ok": false, "reason": reason, "events": events}
