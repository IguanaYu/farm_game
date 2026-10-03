class_name InventoryGame
extends RefCounted
## 物品实例、归属与占用规则（2.1 设计 D2.1-02/05/06）。
## 归属唯一：任何时刻一个实例只出现在 warehouse／chest／pack／safe 之一（owner_of 为断言口径）。
## 演示实例（demo=true）只在内存，保存前由 strip_demo_instances 清除。


var expedition: Dictionary
## 实例编号权威池（F-01 修复）：局内视图与农场块的库存结构不同，但编号必须落在
## 同一份字典上。空字典＝编号就在 expedition 块自身（农场侧用法）。
var id_pool: Dictionary = {}


func bind(expedition_block: Dictionary, pool: Dictionary = {}) -> void:
	expedition = expedition_block
	id_pool = pool


func _inventory() -> Dictionary:
	return expedition.get("inventory", {})


func warehouse_list() -> Array:
	return _inventory().get("warehouse", [])


func loadout_list(container: String) -> Array:
	return _inventory()["loadout"].get(container, [])


## —— 实例与归属 ——————————————————————————————————————————————


func all_instances() -> Array:
	var result: Array = []
	result.append_array(_inventory().get("warehouse", []))
	for container in ExpeditionBaseline.CONTAINERS:
		result.append_array(_inventory()["loadout"].get(container, []))
	return result


func find_instance(instance_id: int) -> Dictionary:
	for instance in all_instances():
		if int(instance["instance_id"]) == instance_id:
			return instance
	return {}


func owner_of(instance_id: int) -> String:
	var instance := find_instance(instance_id)
	if instance.is_empty():
		return "none"
	return str(instance.get("container", ""))


func next_instance_id() -> int:
	## 编号从权威池分配并立即递增；池缺键时按基线起点补齐，保证全局单调。
	var pool := expedition if id_pool.is_empty() else id_pool
	var result: int = int(pool.get("next_instance_id", ExpeditionBaseline.FIRST_INSTANCE_ID))
	pool["next_instance_id"] = result + 1
	return result


func count_of_def(def_id: String) -> int:
	## 真实与演示实例都计入拥有（基础部件"每种一件"的查重口径）。
	var total := 0
	for instance in all_instances():
		if str(instance.get("def_id", "")) == def_id:
			total += 1
	return total


func add_instance(def_id: String, source := "", quality := 1, demo := false) -> Dictionary:
	var def := ItemDefs.get_item(def_id)
	if def.is_empty():
		return _fail("未知物品：%s" % def_id)
	if bool(def.get("basic_kit", false)) and count_of_def(def_id) > 0:
		return _fail("基础装备 %s 每种只能拥有一件" % def["name"])
	if is_run_occupied():
		return _fail("物品正在探险中，不能改动库存")
	var instance := {
		"instance_id": next_instance_id(),
		"def_id": def_id,
		"quality": quality,
		"container": "warehouse",
		"cell": [0, 0],
		"rotated": false,
		"demo": demo,
		"source": source,
		"uses_remaining": int(def.get("uses", 1)),
	}
	_inventory()["warehouse"].append(instance)
	return {"ok": true, "reason": "", "instance_id": instance["instance_id"]}


## 在 container 内找第一个合法位置（先原向后旋转）；返回 [x, y, rotated] 或 null。
func find_first_fit(container: String, size: Vector2i) -> Variant:
	if not ExpeditionBaseline.CONTAINER_SIZE.has(container):
		return null
	var bounds: Vector2i = ExpeditionBaseline.size_for(expedition, container)
	var occupied := ExpeditionBaseline.occupancy_map(_inventory()["loadout"].get(container, []), container)
	for rotated in [false, true]:
		for y in range(bounds.y):
			for x in range(bounds.x):
				if ExpeditionBaseline.can_place_in(bounds, size, Vector2i(x, y), rotated, occupied):
					return [x, y, rotated]
	return null


func move_to_loadout(instance_id: int, container: String) -> Dictionary:
	var instance := find_instance(instance_id)
	if instance.is_empty():
		return _fail("物品不存在")
	if is_run_occupied():
		return _fail("物品正在探险中，不能调整战备")
	if not ExpeditionBaseline.JOIN_ROUND.has(container):
		return _fail("未知容器：%s" % container)
	var def := ItemDefs.get_item(str(instance["def_id"]))
	if container == "safe" and not bool(def.get("safe_allowed", false)):
		return _fail("保险箱只允许存放小型材料与稀有种子，%s 放不进去" % def["name"])
	var fit = find_first_fit(container, def["size"])
	if fit == null:
		var free := ExpeditionBaseline.largest_free_rect(container, _inventory()["loadout"].get(container, []), expedition)
		return _fail("%s 已放不下%s（最大连续空位 %d×%d，需要 %d×%d）" % [
			ExpeditionBaseline.CONTAINER_DISPLAY[container], def["name"], free.x, free.y, def["size"].x, def["size"].y])
	_remove_from_current(instance)
	instance["container"] = container
	instance["cell"] = [int(fit[0]), int(fit[1])]
	instance["rotated"] = bool(fit[2])
	_inventory()["loadout"][container].append(instance)
	return {"ok": true, "reason": "", "cell": instance["cell"], "rotated": instance["rotated"]}


func move_to_warehouse(instance_id: int) -> Dictionary:
	var instance := find_instance(instance_id)
	if instance.is_empty():
		return _fail("物品不存在")
	if is_run_occupied():
		return _fail("物品正在探险中，不能调整战备")
	_remove_from_current(instance)
	instance["container"] = "warehouse"
	instance["cell"] = [0, 0]
	instance["rotated"] = false
	_inventory()["warehouse"].append(instance)
	return {"ok": true, "reason": ""}


## —— 格子交互（2.3 D2.3-02/03）———————————————————————————————


## 拖放的精确放置：整块占格合法才接受；不挤走旧物品。
func place_at(instance_id: int, container: String, cell: Vector2i, rotated: bool) -> Dictionary:
	var instance := find_instance(instance_id)
	if instance.is_empty():
		return _fail("物品不存在")
	if is_run_occupied():
		return _fail("物品正在探险中，不能调整战备")
	if not ExpeditionBaseline.JOIN_ROUND.has(container):
		return _fail("未知容器：%s" % container)
	var def := ItemDefs.get_item(str(instance["def_id"]))
	if container == "safe" and not bool(def.get("safe_allowed", false)):
		return _fail("保险箱只允许存放白名单物品，%s 放不进去" % def["name"])
	var occupied := ExpeditionBaseline.occupancy_map(_inventory()["loadout"].get(container, []), container)
	var bounds := ExpeditionBaseline.size_for(expedition, container)
	if not ExpeditionBaseline.can_place_in(bounds, def["size"], cell, rotated, occupied, int(instance["instance_id"])):
		var free := ExpeditionBaseline.largest_free_rect(container, _inventory()["loadout"].get(container, []), expedition)
		return _fail("放不下：%s 的最大连续空位是 %d×%d，需要 %d×%d" % [
			ExpeditionBaseline.CONTAINER_DISPLAY[container], free.x, free.y,
			def["size"].x if not rotated else def["size"].y,
			def["size"].y if not rotated else def["size"].x])
	_remove_from_current(instance)
	instance["container"] = container
	instance["cell"] = [cell.x, cell.y]
	instance["rotated"] = rotated
	_inventory()["loadout"][container].append(instance)
	return {"ok": true, "reason": ""}


## 原位旋转（占格与牌数不变）；放不下时失败并给原因。
func rotate_instance(instance_id: int) -> Dictionary:
	var instance := find_instance(instance_id)
	if instance.is_empty():
		return _fail("物品不存在")
	if not ExpeditionBaseline.JOIN_ROUND.has(str(instance.get("container", ""))):
		return _fail("仓库中的物品放入容器时再旋转")
	if is_run_occupied():
		return _fail("物品正在探险中，不能调整战备")
	var cell := Vector2i(int(instance["cell"][0]), int(instance["cell"][1]))
	var rotated := not bool(instance.get("rotated", false))
	var def := ItemDefs.get_item(str(instance["def_id"]))
	var container := str(instance["container"])
	var occupied := ExpeditionBaseline.occupancy_map(_inventory()["loadout"].get(container, []), container)
	if not ExpeditionBaseline.can_place_in(ExpeditionBaseline.size_for(expedition, container), def["size"], cell, rotated, occupied, int(instance["instance_id"])):
		return _fail("旋转后放不下（会越界或重叠）")
	instance["rotated"] = rotated
	return {"ok": true, "reason": ""}


## 自动整理：只重排同一容器内部（可旋转），容器归属不变；失败整体恢复原布局。
func auto_tidy(container: String) -> Dictionary:
	if not ExpeditionBaseline.CONTAINER_SIZE.has(container):
		return _fail("未知容器")
	if is_run_occupied():
		return _fail("物品正在探险中，不能调整战备")
	var original: Array = _inventory()["loadout"].get(container, []).duplicate(true)
	var items: Array = original.duplicate(true)
	# 按面积从大到小放置，减少碎片。
	items.sort_custom(func(a, b):
		var da := ItemDefs.get_item(str(a["def_id"]))
		var db := ItemDefs.get_item(str(b["def_id"]))
		return da["size"].x * da["size"].y > db["size"].x * db["size"].y)
	_inventory()["loadout"][container] = []
	for instance in items:
		var def := ItemDefs.get_item(str(instance["def_id"]))
		var fit = find_first_fit(container, def["size"])
		if fit == null:
			_inventory()["loadout"][container] = original
			return _fail("自动整理找不到可行布局，已恢复原布局")
		var placed: Dictionary = instance
		placed["container"] = container
		placed["cell"] = [int(fit[0]), int(fit[1])]
		placed["rotated"] = bool(fit[2])
		_inventory()["loadout"][container].append(placed)
	var problems: Array = ExpeditionBaseline.layout_integrity(_inventory()["loadout"], expedition)
	if not problems.is_empty():
		_inventory()["loadout"][container] = original
		return _fail("自动整理结果异常，已恢复原布局")
	return {"ok": true, "reason": "", "moved": original.size()}


## 非战斗丢弃：实体离开库存进入节点公共区（2.3 用内存列表承接；2.4 接入地图节点）。
## 已打过的伤害或治疗不回滚；丢弃受保护物品即失去保护。
var public_drops: Array = []


func discard_instance(instance_id: int) -> Dictionary:
	var instance := find_instance(instance_id)
	if instance.is_empty():
		return _fail("物品不存在")
	if is_run_occupied():
		return _fail("物品正在探险中，不能丢弃")
	_remove_from_current(instance)
	public_drops.append(instance)
	return {"ok": true, "reason": ""}


## 战后奖励领取事务：奖励区 → 指定容器（只找合法空位，不替玩家丢装备、不自动占保险箱）。
func claim_reward(def_id: String, container: String, cell := Vector2i(-1, -1), rotated := false) -> Dictionary:
	if is_run_occupied():
		return _fail("物品正在探险中")
	var def := ItemDefs.get_item(def_id)
	if def.is_empty():
		return _fail("未知物品：%s" % def_id)
	if container == "safe" and not bool(def.get("safe_allowed", false)):
		return _fail("%s 不在保险箱白名单内" % def["name"])
	var added := add_instance(def_id, "loot", int(def.get("quality", 1)))
	if not added["ok"]:
		return added
	var moved := place_at(int(added["instance_id"]), container, cell, rotated) if cell.x >= 0 else move_to_loadout(int(added["instance_id"]), container)
	if not moved["ok"]:
		# 放不下就退回：奖励留在奖励区，不产生半领取状态（ID 作废不复用，无害）。
		var stale := find_instance(int(added["instance_id"]))
		if not stale.is_empty():
			_inventory()["warehouse"].erase(stale)
		return _fail(moved["reason"])
	return {"ok": true, "reason": "", "instance_id": added["instance_id"]}


func clear_loadout() -> Dictionary:
	## 清空配置：把三容器内全部物品放回仓库（保留保险箱保护选择信息随实例一起离开）。
	var moved := 0
	for container in ExpeditionBaseline.CONTAINERS:
		for instance in _inventory()["loadout"].get(container, []).duplicate():
			if move_to_warehouse(int(instance["instance_id"]))["ok"]:
				moved += 1
	return {"ok": true, "reason": "", "moved": moved}


## 把一件已离开库存的实体重新登记进仓库（节点丢弃区捡回路径；不做布局校验）。
func restore_to_warehouse(instance: Dictionary) -> void:
	_inventory()["warehouse"].append(instance)


func _remove_from_current(instance: Dictionary) -> void:
	var current := str(instance.get("container", "warehouse"))
	if current == "warehouse":
		_inventory()["warehouse"].erase(instance)
	else:
		_inventory()["loadout"].get(current, []).erase(instance)


## —— 基础装备底线（D2.1-05）———————————————————————————————


func basic_kit_missing() -> Array:
	var result: Array = []
	for def_id in ItemDefs.basic_kit_ids():
		if count_of_def(def_id) == 0:
			result.append(def_id)
	return result


func grant_basic_kit() -> Dictionary:
	## 首次全赠；之后只补缺失部件（活动局中的也计入拥有，2.1 设计 §7）。
	var granted: Array = []
	var already: Array = []
	for def_id in basic_kit_missing():
		var result := add_instance(def_id, "basic_kit")
		if result["ok"]:
			granted.append(def_id)
	for def_id in ItemDefs.basic_kit_ids():
		if def_id not in granted:
			already.append(def_id)
	return {"ok": true, "reason": "", "granted": granted, "already_had": already}


## —— 占用与生命周期（D2.1-06）——————————————————————————————


func set_run_occupied(run_id: String) -> Dictionary:
	if run_id == "":
		return _fail("缺少局 ID")
	if is_run_occupied():
		return _fail("已有活动局占用中")
	_inventory()["occupied_by_run"] = run_id
	return {"ok": true, "reason": ""}


func clear_run_occupied(run_id: String) -> Dictionary:
	if str(_inventory().get("occupied_by_run", "")) != run_id:
		return _fail("占用局 ID 不匹配，不能解除")
	_inventory()["occupied_by_run"] = ""
	return {"ok": true, "reason": ""}


func is_run_occupied() -> bool:
	return str(_inventory().get("occupied_by_run", "")) != ""


## —— 牌组预览与准备检查（D2.1-03/04）———————————————————————


func deck_preview() -> Dictionary:
	## 按加入回合分组的牌实例快照；同时给出每回合的叠卡计数。
	var rounds := {1: [], 2: [], 3: []}
	var counts := {1: {}, 2: {}, 3: {}}
	for container in ExpeditionBaseline.CONTAINERS:
		var join_round: int = ExpeditionBaseline.JOIN_ROUND[container]
		for instance in _inventory()["loadout"].get(container, []):
			var def := ItemDefs.get_item(str(instance["def_id"]))
			var seq := 0
			for card_id in def.get("cards", []):
				rounds[join_round].append({
					"card_id": card_id,
					"instance_id": int(instance["instance_id"]),
					"seq": seq,
					"demo": bool(instance.get("demo", false)),
				})
				counts[join_round][card_id] = int(counts[join_round].get(card_id, 0)) + 1
				seq += 1
	return {"rounds": rounds, "counts": counts,
			"totals": {1: rounds[1].size(), 2: rounds[2].size(), 3: rounds[3].size()}}


func loadout_check() -> Dictionary:
	## 硬性阻止：未解决活动局／布局非法／首回合牌库为空。建议项只提示不阻止。
	var hard_blocks: Array = []
	var advises: Array = []
	if is_run_occupied():
		hard_blocks.append("有未解决的活动局：先完成结算或放弃当前探险")
	hard_blocks.append_array(ExpeditionBaseline.layout_integrity(_inventory()["loadout"], expedition))
	var preview := deck_preview()
	if preview["rounds"][1].is_empty():
		hard_blocks.append("首回合牌库为空：把装备放进胸挂（背包牌第 2 回合、保险箱牌第 3 回合才加入）")
	var has_attack := false
	var defense_cards := 0
	for entry in preview["rounds"][1]:
		if CardDefs.is_attack_card(str(entry["card_id"])):
			has_attack = true
	for join_round in [1, 2, 3]:
		for card_id in preview["counts"][join_round]:
			if CardDefs.is_defense_card(str(card_id)):
				defense_cards += int(preview["counts"][join_round][card_id])
	if not has_attack and preview["rounds"][1].size() > 0:
		advises.append("首回合没有攻击牌，遇到敌人会非常被动")
	if defense_cards < 2:
		advises.append("缺少可重复使用的防御手段（格挡牌少于 2 张）")
	if preview["rounds"][1].size() in range(1, 5):
		advises.append("首回合牌只有 %d 张，第一回合抽不满 5 张（背包／保险箱的牌第 2／3 回合才加入）" % int(preview["totals"][1]))
	return {"hard_blocks": hard_blocks, "advises": advises}


## —— 价值统计（D2.1-02"四项价值"口径）——————————————————————


func carry_sell_value() -> int:
	## 携带可售价值：只算可出售物品（基础装备不计）。
	var total := 0
	for container in ExpeditionBaseline.CONTAINERS:
		for instance in _inventory()["loadout"].get(container, []):
			var def := ItemDefs.get_item(str(instance["def_id"]))
			if bool(def.get("sellable", false)):
				total += int(def.get("base_value", 0))
	return total


func protected_value() -> int:
	## 失败保护价值：保险箱内允许保护的物品价值。
	var total := 0
	for instance in _inventory()["loadout"].get("safe", []):
		total += int(ItemDefs.get_item(str(instance["def_id"])).get("base_value", 0))
	return total


func has_basic_in_loadout() -> bool:
	for container in ExpeditionBaseline.CONTAINERS:
		for instance in _inventory()["loadout"].get(container, []):
			if ItemDefs.is_basic(str(instance["def_id"])):
				return true
	return false


## —— 演示物品（D2.1-03）—————————————————————————————————————


func inject_demo_items() -> Dictionary:
	## 战备预览的演示内容：只在内存，不与真实物品混写（保存前统一剔除）。
	var added: Array = []
	for def_id in ItemDefs.ITEMS:
		if not bool(ItemDefs.ITEMS[def_id].get("demo", false)):
			continue
		if count_of_def(def_id) == 0:
			var result := add_instance(def_id, "demo", 1, true)
			if result["ok"]:
				added.append(def_id)
	return {"ok": true, "reason": "", "added": added}


func strip_demo_instances() -> void:
	_inventory()["warehouse"] = _inventory()["warehouse"].filter(func(instance): return not bool(instance.get("demo", false)))
	for container in ExpeditionBaseline.CONTAINERS:
		_inventory()["loadout"][container] = _inventory()["loadout"][container].filter(func(instance): return not bool(instance.get("demo", false)))


## —— 消耗品实体（2.2 起用；2.3 扩展"耗尽清理关联牌"）————————————————


## 一份药水有多张来源牌时，使用一张只扣一次实体次数。
func consume_use(instance_id: int) -> Dictionary:
	var instance := find_instance(instance_id)
	if instance.is_empty():
		return _fail("来源物品不存在")
	if int(instance.get("uses_remaining", 1)) <= 0:
		return _fail("来源物品已耗尽")
	instance["uses_remaining"] = int(instance["uses_remaining"]) - 1
	return {"ok": true, "reason": "", "uses_left": int(instance["uses_remaining"])}


func uses_remaining(instance_id: int) -> int:
	var instance := find_instance(instance_id)
	if instance.is_empty():
		return 0
	return int(instance.get("uses_remaining", 1))


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
