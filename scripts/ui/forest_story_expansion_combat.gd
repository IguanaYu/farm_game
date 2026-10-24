class_name ForestStoryExpansionCombat
extends ForestCardStudyCombat
## 第二批十张情境卡；道具在本场移除，不消费玩家农场库存。

const ADDITIONS := {
	"forest_rest_bell": {"name": "坏心情走开！", "cost": 1, "target": "ally", "after": "discard", "effects": [{"kind": "cleanse"}], "desc": "移除自己或一名队友的全部易伤、虚弱和中毒；保留力量与敏捷。"},
	"forest_glow_bolt": {"name": "门缝借过！", "cost": 1, "target": "enemy", "after": "discard", "motion": "projectile", "effects": [{"kind": "damage", "value": 5, "pierce": 3}], "desc": "造成 5 点攻击伤害，其中最多 3 点不被格挡抵消。穿透部分不消耗格挡，不增加总伤害。"},
	"forest_apply_gel": {"name": "凉凉就不疼", "cost": 1, "target": "ally", "after": "exhaust", "effects": [{"kind": "heal", "value": 6}], "desc": "自己或一名队友恢复 6 生命，不超过上限。本场移除。"},
	"forest_throw_fire_sac": {"name": "烫烫烫！", "cost": 1, "target": "enemy", "after": "exhaust", "motion": "projectile", "effects": [{"kind": "damage", "value": 13}], "desc": "对一名敌人造成 13 点攻击伤害。本场移除。"},
	"forest_throw_frost_sac": {"name": "先冷静一下", "cost": 1, "target": "enemy", "after": "exhaust", "motion": "projectile", "effects": [{"kind": "damage", "value": 3}, {"kind": "status", "status": "weak", "stacks": 2}], "desc": "造成 3 点攻击伤害，然后施加 2 层虚弱。本场移除。"},
	"forest_eat_honey": {"name": "只舔一小口", "cost": 1, "target": "self", "after": "exhaust", "effects": [{"kind": "heal", "value": 3}, {"kind": "draw", "value": 1}], "desc": "自己恢复 3 生命，然后抽 1 张牌。本场移除。"},
	"forest_scatter_stings": {"name": "这根有点麻", "cost": 1, "target": "enemy", "after": "exhaust", "motion": "projectile", "effects": [{"kind": "damage", "value": 3}, {"kind": "status", "status": "poison", "stacks": 2}], "desc": "造成 3 点攻击伤害，然后施加 2 层中毒。本场移除。"},
	"forest_torch_strike": {"name": "眉毛小心！", "cost": 1, "target": "enemy", "after": "discard", "effects": [{"kind": "damage", "value": 5}], "desc": "对一名敌人造成 5 点攻击伤害（简易工具初始档）。"},
	"forest_throw_net": {"name": "抓到大块头！", "cost": 1, "target": "enemy", "after": "exhaust", "motion": "projectile", "effects": [{"kind": "damage", "value": 3}, {"kind": "status", "status": "weak", "stacks": 3}], "desc": "造成 3 点攻击伤害，然后施加 3 层虚弱。本场移除。"},
	"forest_throw_spores": {"name": "阿嚏，别吸气！", "cost": 1, "target": "enemy", "after": "exhaust", "motion": "projectile", "effects": [{"kind": "status", "status": "poison", "stacks": 3}], "desc": "对一名敌人施加 3 层中毒；在其行动开始按 3、2、1 结算。本场移除。"},
}
const ADDITION_SOURCES := {
	"forest_rest_bell": "祭铃杖", "forest_glow_bolt": "刻符短杖", "forest_apply_gel": "绿凝胶", "forest_throw_fire_sac": "赤凝胶囊", "forest_throw_frost_sac": "蓝凝胶囊",
	"forest_eat_honey": "蜂蜜块", "forest_scatter_stings": "蜂针囊", "forest_torch_strike": "树脂火把", "forest_throw_net": "绳网", "forest_throw_spores": "腐菌囊",
}
const GROUP_NAMES := ["林间小道具", "铃火与冰光"]
const GROUPS := [
	["forest_throw_net", "forest_scatter_stings", "forest_apply_gel", "forest_eat_honey", "forest_throw_spores"],
	["forest_rest_bell", "forest_glow_bolt", "forest_throw_fire_sac", "forest_throw_frost_sac", "forest_torch_strike"],
]

func card_definition(card_id: String) -> Dictionary:
	return ADDITIONS.get(card_id, super.card_definition(card_id))

static func create_expansion(encounter: String, seed_value: int, source_inventory: InventoryGame, group := 0) -> ForestStoryExpansionCombat:
	var deck: Array = []
	for id in GROUPS[clampi(group, 0, 1)] + ["forest_shoot", "forest_guard_bell", "forest_thrust", "forest_guard_bell", "forest_smoke_screen"]:
		deck.append({"card_id": id, "join_round": 1})
	var base := CombatGame.create([{"key": "p1", "name": "农夫", "hp": 30, "max_hp": 40, "deck": deck}], encounter, seed_value, source_inventory, deck)
	var session := ForestStoryExpansionCombat.new()
	session.load_dict(base.to_dict())
	session.inventory = source_inventory
	session.start()
	# 带伤样例让治疗有实际用途；第二组附带可净化的旧伤，非正式存档。
	if group == 1:
		session.state["players"]["p1"]["statuses"] = {"weak": {"stacks": 1}, "poison": {"stacks": 2}}
	return session
