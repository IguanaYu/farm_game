class_name ForestCardStudyCombat
extends CombatGame
## 独立样稿牌组，数值来自森林内容设计 §10.2；不写入正式牌表、物品或存档。

const CARDS := {
	"forest_shoot": {"name": "射击", "cost": 1, "target": "enemy", "after": "discard", "motion": "projectile", "effects": [{"kind": "damage", "value": 6}], "desc": "对一名敌人造成 6 点伤害。"},
	"forest_thrust": {"name": "突刺", "cost": 1, "target": "enemy", "after": "discard", "effects": [{"kind": "damage", "value": 6}], "desc": "对一名敌人造成 6 点伤害。"},
	"forest_power_shot": {"name": "强射", "cost": 2, "target": "enemy", "after": "discard", "motion": "projectile", "effects": [{"kind": "damage", "value": 13}], "desc": "对一名敌人造成 13 点伤害。"},
	"forest_bell_strike": {"name": "敲击", "cost": 1, "target": "enemy", "after": "discard", "effects": [{"kind": "damage", "value": 4}], "desc": "对一名敌人造成 4 点伤害。"},
	"forest_guard_bell": {"name": "守护铃", "cost": 1, "target": "ally", "after": "discard", "effects": [{"kind": "block", "value": 5}], "desc": "自己或一名队友获得 5 点格挡。"},
	"forest_smoke_screen": {"name": "烟幕", "cost": 1, "target": "ally", "after": "discard", "effects": [{"kind": "block", "value": 4}], "desc": "自己或一名队友获得 4 点格挡。"},
}
const SOURCES := {
	"forest_shoot": "短弓", "forest_thrust": "长矛", "forest_power_shot": "旧猎弩",
	"forest_bell_strike": "祭铃杖", "forest_guard_bell": "祭铃杖", "forest_smoke_screen": "树脂火把",
}
const DECK := ["forest_shoot", "forest_thrust", "forest_guard_bell", "forest_power_shot", "forest_smoke_screen", "forest_bell_strike", "forest_shoot", "forest_guard_bell", "forest_thrust", "forest_smoke_screen"]

func card_definition(card_id: String) -> Dictionary:
	return CARDS.get(card_id, super.card_definition(card_id))

static func create_study(encounter: String, seed_value: int, source_inventory: InventoryGame) -> ForestCardStudyCombat:
	var deck: Array = []
	for card_id in DECK:
		deck.append({"card_id": card_id, "join_round": 1})
	var base := CombatGame.create([{"key": "p1", "name": "农夫", "max_hp": 40, "deck": deck}], encounter, seed_value, source_inventory, deck)
	var session := ForestCardStudyCombat.new()
	session.load_dict(base.to_dict())
	session.inventory = source_inventory
	session.start()
	return session
