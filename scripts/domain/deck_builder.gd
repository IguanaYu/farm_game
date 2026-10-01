class_name DeckBuilder
extends RefCounted
## 布局 → 牌组快照（2.3 设计 D2.3-04）。战斗开始时按当前布局构建一次，战斗中锁定；
## 下一场开始前根据最新布局重新构建。已耗尽的物品不再生成牌。


## 返回 {entries: [{card_id, source_instance_id, source_seq, join_round}…], totals: {1: n, 2: n, 3: n}}
static func build(inventory: InventoryGame) -> Dictionary:
	var entries: Array = []
	var totals := {1: 0, 2: 0, 3: 0}
	for container in ExpeditionBaseline.CONTAINERS:
		var join_round: int = ExpeditionBaseline.JOIN_ROUND[container]
		for instance in inventory.loadout_list(container):
			if int(instance.get("uses_remaining", 1)) <= 0:
				continue
			var def := ItemDefs.get_item(str(instance["def_id"]))
			var seq := 0
			for card_id in def.get("cards", []):
				entries.append({
					"card_id": card_id,
					"source_instance_id": int(instance["instance_id"]),
					"source_seq": seq,
					"join_round": join_round,
				})
				seq += 1
			totals[join_round] = int(totals[join_round]) + seq
	return {"entries": entries, "totals": totals}


## 牌反查来源物品（UI 互查口径）。
static func source_summary(inventory: InventoryGame, instance_id: int) -> String:
	var instance := inventory.find_instance(instance_id)
	if instance.is_empty():
		return "来源物品已不存在"
	var def := ItemDefs.get_item(str(instance["def_id"]))
	var owner := str(instance.get("container", ""))
	var display: String = ExpeditionBaseline.CONTAINER_DISPLAY.get(owner, owner)
	return "来源：%s（%s）" % [def["name"], display]
