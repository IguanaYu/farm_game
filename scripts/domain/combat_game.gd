class_name CombatGame
extends RefCounted
## 单人卡牌战斗规则层（2.2 详细设计）。玩家状态按玩家键索引（2.6 加键即可支持双人）；
## 敌人与意图共享。所有方法返回结果字典并输出事件列表，UI 只消费事件，不参与裁定。
## 时序（设计 §3）：回合开始清格挡→加入到期物品牌→能量重置→抽 5→出牌→结束弃牌→
## 敌人逐个行动（各自先清旧格挡、结算中毒）→玩家结算中毒→胜负判定。


const ENEMIES := {
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
	"rock_crab": {
		"name": "碎石蟹", "hp": 26,
		"cycle": [
			{"kind": "block", "value": 6},
			{"kind": "attack", "value": 9},
		],
	},
}

const ENCOUNTERS := {
	"tutorial": {"name": "教学场（单只小泥团）", "enemies": ["slime"]},
	"normal": {"name": "普通验证场（泥团＋蝠）", "enemies": ["slime", "cave_bat"]},
	"defensive": {"name": "防御验证场（碎石蟹）", "enemies": ["rock_crab"]},
}


## 2.2 演示入口的固定牌组：基础套装 8 张、全部第 1 回合加入（2.2 计划 W9）。
static func basic_kit_demo_deck() -> Array:
	var deck: Array = []
	for def_id in ItemDefs.basic_kit_ids():
		var def := ItemDefs.get_item(def_id)
		var seq := 0
		for card_id in def["cards"]:
			deck.append({"card_id": card_id, "source_instance_id": 0, "source_seq": seq, "join_round": 1})
			seq += 1
	return deck


var state: Dictionary = {}
var rng := RandomNumberGenerator.new()
var inventory: InventoryGame = null


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
	for def_id in ENCOUNTERS[encounter_id]["enemies"]:
		suffix += 1
		var def: Dictionary = ENEMIES[def_id]
		enemy_list.append({
			"id": "e%d" % suffix,
			"def_id": def_id,
			"name": def["name"],
			"hp": def["hp"], "max_hp": def["hp"], "block": 0,
			"statuses": {},
			"cycle_index": 0,
			"intent": {},
			"alive": true,
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
			"hp": int(player.get("max_hp", ExpeditionBaseline.MAX_HP)),
			"max_hp": int(player.get("max_hp", ExpeditionBaseline.MAX_HP)),
			"block": 0,
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
		_begin_player_round()
		return {"ok": true, "events": _round_events(1)}
	return {"ok": false, "reason": "战斗已在进行", "events": []}


# —— 出牌 ————————————————————————————————————————————————————————


## 合法目标键："e1" 等敌人 id，或玩家键（自己/队友）。
func play_card(owner_key: String, uid: int, target_key: String) -> Dictionary:
	var events: Array = []
	if state["phase"] != "player":
		return _deny("当前不是玩家回合", events)
	var player: Dictionary = state["players"].get(owner_key)
	if player.is_empty() or int(player.get("hp", 0)) <= 0:
		return _deny("该玩家不能行动", events)
	var card := _hand_card(owner_key, uid)
	if card.is_empty():
		return _deny("这张牌已不在手牌中", events)
	var def := CardDefs.get_card(str(card["card_id"]))
	if def.is_empty():
		return _deny("未知牌型", events)
	var target := _resolve_target(def["target"], target_key, owner_key)
	if target.is_empty():
		return _deny("目标不合法", events)
	if int(player["energy"]) < int(def["cost"]):
		return _deny("能量不足", events)
	if str(def["after"]) == "exhaust_source":
		var consume := _consume_source(int(card["source_instance_id"]))
		if not consume["ok"]:
			return _deny(consume["reason"], events)
	player["energy"] = int(player["energy"]) - int(def["cost"])
	_remove_from_hand(owner_key, uid)
	events.append({"type": "card_played", "owner": owner_key, "card": str(def["name"]), "cost": int(def["cost"]), "target": target_key})
	for effect in def["effects"]:
		_apply_effect(owner_key, target_key, effect, events)
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
	var def := CardDefs.get_card(str(card["card_id"]))
	var target := _resolve_target(def.get("target", ""), target_key, owner_key)
	if target.is_empty():
		return {"ok": false, "reason": "目标不合法"}
	var preview := {"ok": true}
	for effect in def.get("effects", []):
		match str(effect.get("kind", "")):
			"damage":
				preview["damage"] = _outgoing_damage(owner_key, target, int(effect["value"]))
			"block":
				preview["block"] = int(effect["value"])
			"heal":
				preview["heal"] = maxi(0, mini(int(effect["value"]), int(target["max_hp"]) - int(target["hp"])))
			"draw":
				preview["draw"] = int(effect["value"])
			"status":
				preview["status"] = CardDefs.STATUS_DISPLAY.get(str(effect.get("status", "")), str(effect.get("status", "")))
	return preview


## 结束行动：非保留手牌全部弃掉 → 敌方阶段 → 下一回合（或终局）。
func end_turn(owner_key: String) -> Dictionary:
	var events: Array = []
	if state["phase"] != "player":
		return _deny("当前不是玩家回合", events)
	var player: Dictionary = state["players"][owner_key]
	player["ended"] = true
	# 单人：立即进入敌方阶段。2.6 在此改为"全员结束才推进"。
	for key in state["players"]:
		var each: Dictionary = state["players"][key]
		if int(each["hp"]) > 0 and not each["ended"]:
			return {"ok": true, "events": events, "waiting": true}
	events.append({"type": "turn_ended", "round": int(state["round"])})
	_run_discard_phase(events)
	_run_enemy_phase(events)
	if state["outcome"] != "":
		return {"ok": true, "events": events, "outcome": state["outcome"]}
	_begin_player_round()
	return {"ok": true, "events": events, "outcome": ""}


# —— 查询 ————————————————————————————————————————————————————————


func enemy_intents() -> Array:
	var result: Array = []
	for enemy in state["enemies"]:
		if not bool(enemy["alive"]):
			continue
		var intent: Dictionary = enemy.get("intent", {})
		result.append({
			"enemy_id": enemy["id"],
			"name": enemy["name"],
			"text": _intent_text(intent),
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
	rng.seed = int(state.get("seed", 0))
	rng.state = int(state.get("rng_state", "0"))
	return true


# —— 内部：回合流程 ————————————————————————————————————————————


func _begin_player_round() -> void:
	state["round"] = int(state["round"]) + 1
	state["phase"] = "player"
	for key in state["players"]:
		var player: Dictionary = state["players"][key]
		player["ended"] = false
		player["block"] = 0
		# 加入本回合到期的物品牌（洗入抽牌堆；延后加入只代表进入抽牌堆，不保证抽到）。
		var join_round := int(state["round"])
		var due: Array = player["pending_join"].get(str(join_round), [])
		if not due.is_empty():
			if bool(state.get("fixed_deck", false)):
				# 测试注入的固定牌序不洗牌，保证算例可手算复现。
				player["draw_pile"].append_array(due)
			else:
				_shuffle_into_draw(player, due)
			player["pending_join"][str(join_round)] = []
		player["energy"] = ExpeditionBaseline.ENERGY_PER_TURN
		_draw_cards(player, ExpeditionBaseline.DRAW_PER_TURN)
		state["log"].append("—— 第 %d 回合开始：能量 %d，抽 %d 张 ——" % [int(state["round"]), ExpeditionBaseline.ENERGY_PER_TURN, ExpeditionBaseline.DRAW_PER_TURN])
	for enemy in state["enemies"]:
		if bool(enemy["alive"]):
			_roll_intent(enemy)


func _run_discard_phase(events: Array) -> void:
	for key in state["players"]:
		var player: Dictionary = state["players"][key]
		for card in player["hand"].duplicate():
			player["discard_pile"].append(card)
		player["hand"] = []
		# 易伤/虚弱在受影响单位完成自身行动阶段后减 1（设计 §4）：玩家阶段在此结束。
		_decrement_own_statuses(player)
	events.append({"type": "discarded"})


func _run_enemy_phase(events: Array) -> void:
	state["phase"] = "enemy"
	for enemy in state["enemies"]:
		if not bool(enemy["alive"]):
			continue
		# 每个敌人行动开始先清自己的旧格挡，再结算自己的持续伤害。
		enemy["block"] = 0
		_decrement_own_statuses(enemy)
		_apply_poison(enemy, events)
		if not bool(enemy["alive"]):
			continue
		_execute_intent(enemy, events)
		_decrement_own_statuses(enemy)
		if state["outcome"] != "":
			return
	# 敌方阶段结束，玩家结算自己的持续伤害。
	for key in state["players"]:
		var player: Dictionary = state["players"][key]
		_apply_poison(player, events)
		if int(player["hp"]) <= 0:
			_set_outcome("lost", events)
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
	state["outcome"] = outcome
	state["phase"] = "finished"
	state["log"].append("战斗%s（第 %d 回合）" % ["胜利" if outcome == "won" else "失败", int(state["round"])])
	events.append({"type": "outcome", "outcome": outcome, "round": int(state["round"])})


# —— 内部：效果结算 ————————————————————————————————————————————


func _apply_effect(owner_key: String, target_key: String, effect: Dictionary, events: Array) -> void:
	match str(effect.get("kind", "")):
		"damage":
			var target := _find_unit(target_key)
			var amount := _outgoing_damage(owner_key, target, int(effect["value"]))
			_deal_damage(owner_key, target, amount, events)
		"block":
			var target := _find_unit(target_key)
			var amount := int(effect["value"])
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
		"status":
			var target := _find_unit(target_key)
			var status := str(effect.get("status", ""))
			var stacks := int(effect.get("stacks", 1))
			_add_status(target, status, stacks)
			events.append({"type": "status", "target": target_key, "status": status, "stacks": stacks})
			state["log"].append("%s 获得 %s ×%d" % [_unit_name(target), CardDefs.STATUS_DISPLAY.get(status, status), stacks])


## 伤害计算（设计 §4）：基础值 ×易伤(×1.5，受击方) ×虚弱(×0.75，攻击方)，向下取整且≥0。
func _outgoing_damage(attacker_key: String, target: Dictionary, base: int) -> int:
	var amount := base
	if _has_status(target, "vulnerable"):
		amount = int(amount * 1.5)
	var attacker := _find_unit(attacker_key)
	if not attacker.is_empty() and _has_status(attacker, "weak"):
		amount = int(amount * 0.75)
	return maxi(0, amount)


func _deal_damage(attacker_key: String, target: Dictionary, amount: int, events: Array) -> void:
	var blocked := mini(amount, int(target["block"]))
	target["block"] = int(target["block"]) - blocked
	var to_hp := amount - blocked
	target["hp"] = int(target["hp"]) - to_hp
	events.append({"type": "damage", "source": attacker_key, "target": _unit_id(target), "amount": amount, "blocked": blocked, "to_hp": to_hp})
	state["log"].append("%s 受到 %d 伤害（格挡抵消 %d，生命 -%d）" % [_unit_name(target), amount, blocked, to_hp])
	if int(target["hp"]) <= 0:
		if state["players"].has(_unit_id(target)):
			target["hp"] = 0
		else:
			target["alive"] = false
			target["hp"] = 0
			state["log"].append("%s 被击败" % target["name"])
			events.append({"type": "enemy_died", "enemy_id": _unit_id(target)})


func _apply_poison(unit: Dictionary, events: Array) -> void:
	var stacks := int(unit["statuses"].get("poison", {}).get("stacks", 0))
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
		else:
			unit["alive"] = false
			unit["hp"] = 0
			state["log"].append("%s 被毒死" % unit["name"])
			events.append({"type": "enemy_died", "enemy_id": _unit_id(unit)})


func _add_status(unit: Dictionary, status: String, stacks: int) -> void:
	var current: Dictionary = unit["statuses"].get(status, {"stacks": 0})
	current["stacks"] = int(current["stacks"]) + stacks
	unit["statuses"][status] = current


func _has_status(unit: Dictionary, status: String) -> bool:
	return int(unit["statuses"].get(status, {}).get("stacks", 0)) > 0


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
				for key in state["players"]:
					var player: Dictionary = state["players"][key]
					if int(player["hp"]) <= 0:
						continue
					var amount := _outgoing_damage(enemy["id"], player, int(intent["value"]))
					_deal_damage(enemy["id"], player, amount, events)
					if str(intent.get("status", "")) != "":
						_add_status(player, str(intent["status"]), int(intent.get("status_stacks", 1)))
						state["log"].append("%s 获得 %s ×%d" % [player["name"], CardDefs.STATUS_DISPLAY.get(str(intent["status"]), str(intent["status"])), int(intent.get("status_stacks", 1))])
					if int(player["hp"]) <= 0:
						_set_outcome("lost", events)
						return
				if str(intent.get("status", "")) != "":
					break
		"block":
			enemy["block"] = int(enemy["block"]) + int(intent["value"])
			events.append({"type": "enemy_block", "enemy_id": enemy["id"], "amount": int(intent["value"])})
			state["log"].append("%s 获得 %d 格挡" % [enemy["name"], int(intent["value"])])
	events.append({"type": "enemy_acted", "enemy_id": enemy["id"]})


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


func _consume_source(instance_id: int) -> Dictionary:
	if inventory == null:
		return {"ok": false, "reason": "这张牌需要来源物品（演示战斗不提供）"}
	return inventory.consume_use(instance_id)


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
	return {}


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
