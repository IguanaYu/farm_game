class_name ForestCardStudyCombat
extends CombatGame
## 独立样稿牌组，定位与新费用锚点对照；不写入正式物品或存档。

const CARDS := {
	"forest_shoot": {"name": "谁扎我啦！", "cost": 1, "target": "enemy", "after": "discard", "motion": "projectile", "effects": [{"kind": "damage", "value": 8}], "desc": "对一名敌人造成 8 点攻击伤害（标准档）。"},
	"forest_thrust": {"name": "不许过来！", "cost": 1, "target": "enemy", "after": "discard", "effects": [{"kind": "damage", "value": 5}], "desc": "对一名敌人造成 5 点攻击伤害（拼装武器初始档）。"},
	"forest_power_shot": {"name": "哎呀，太用力！", "cost": 2, "target": "enemy", "after": "discard", "motion": "projectile", "effects": [{"kind": "damage", "value": 16}], "desc": "对一名敌人造成 16 点攻击伤害（2 费标准档）。"},
	"forest_bell_strike": {"name": "借你的壳敲一下", "cost": 1, "target": "enemy", "after": "discard", "effects": [{"kind": "damage", "value": 3, "target": "selected"}, {"kind": "block", "value": 3, "target": "self"}], "desc": "对选定敌人造成 3 点攻击伤害，自己获得 3 点格挡（初始混合档）。"},
	"forest_guard_bell": {"name": "躲我后面", "cost": 1, "target": "ally", "after": "discard", "effects": [{"kind": "block", "value": 8}], "desc": "自己或一名队友获得 8 点格挡（标准档），使用出牌者敏捷。"},
	"forest_smoke_screen": {"name": "藏好了吗？", "cost": 1, "target": "ally", "after": "discard", "effects": [{"kind": "block", "value": 5}], "desc": "自己或一名队友获得 5 点格挡（简易工具初始档），使用出牌者敏捷。"},
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
