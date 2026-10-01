class_name ExpeditionDefs
extends RefCounted
## 第一层内容定义（2.4 设计 §3/§4/§5）：固定合法图先行，分支生成闭环跑通后加入。
## 全部数值为未试玩初值；调整须保持地图连通、奖励固定、结算清晰三约束。


const EXIT_ROWS := [4, 7]
const GATE_ROW := 8

const NODE_TYPE_DISPLAY := {
	"start": "起点",
	"battle": "普通战斗",
	"elite": "精英战斗",
	"chest": "宝箱",
	"gather": "采集",
	"event": "事件",
	"rest_exit": "休整·撤离站",
	"exit": "撤离站",
	"gate": "守门战·层末出口",
}

const LAYERS := {
	"iron_root_deeps": {
		"name": "铁根矿窟（第二层）",
		"rows": 9,
		"map": [
			[{"type": "start", "risk": "none", "hint": "层间入口"}],
			[{"type": "battle", "risk": "mid", "hint": "深层敌人", "encounter": "deep_pair"},
				{"type": "gather", "risk": "none", "hint": "铁矿脉"}],
			[{"type": "event", "risk": "mid", "hint": "深层取舍"},
				{"type": "battle", "risk": "mid", "hint": "深层敌人", "encounter": "deep_hard"}],
			[{"type": "chest", "risk": "none", "hint": "深层装备与货物"},
				{"type": "battle", "risk": "mid", "hint": "深层敌人", "encounter": "deep_pair"}],
			[{"type": "rest_exit", "risk": "none", "hint": "休整·撤离站"}],
			[{"type": "gather", "risk": "none", "hint": "铁矿与晶石"},
				{"type": "event", "risk": "mid", "hint": "深层取舍"}],
			[{"type": "battle", "risk": "mid", "hint": "深层敌人", "encounter": "deep_hard"},
				{"type": "elite", "risk": "high", "hint": "高风险·深层精英"}],
			[{"type": "exit", "risk": "none", "hint": "撤离或继续"}],
			[{"type": "gate", "risk": "high", "hint": "首领：根须守卫", "encounter": "layer2_guardian"}],
		],
	},
	"moss_stone_shallow": {
		"name": "苔石浅洞",
		"rows": 9,
		## 固定图：每排 1~3 个候选；相邻排全连通（任意路线可达第 4、7 排撤离站，无断路；
		## 每条路线至少一处非战斗资源来源——第 2 排起各路线都有宝箱/采集/事件）。
		"map": [
			[{"type": "start", "risk": "none", "hint": "查看配装"}],
			[{"type": "battle", "risk": "low", "hint": "浅层敌人", "encounter": "tutorial"},
				{"type": "battle", "risk": "low", "hint": "双敌组合", "encounter": "normal"}],
			[{"type": "gather", "risk": "none", "hint": "偏材料"},
				{"type": "battle", "risk": "low", "hint": "浅层敌人", "encounter": "tutorial"}],
			[{"type": "event", "risk": "mid", "hint": "取舍"},
				{"type": "battle", "risk": "low", "hint": "浅层敌人", "encounter": "normal"}],
			[{"type": "rest_exit", "risk": "none", "hint": "免费小休整＋撤离"}],
			[{"type": "chest", "risk": "none", "hint": "偏装备与货物"},
				{"type": "event", "risk": "mid", "hint": "取舍"}],
			[{"type": "battle", "risk": "low", "hint": "浅层敌人", "encounter": "normal"},
				{"type": "elite", "risk": "high", "hint": "高风险·偏装备与稀有资源"}],
			[{"type": "exit", "risk": "none", "hint": "撤离或继续"}],
			[{"type": "gate", "risk": "high", "hint": "守门战·层末出口", "encounter": "gate"}],
		],
	},
}

## 战斗遭遇：浅层组合（gate 用强化组合；精英用双敌）。
const ENCOUNTER_TABLE := {
	"shallow_easy": ["slime"],
	"shallow_pair": ["slime", "cave_bat"],
	"elite_double": ["cave_bat", "rock_crab"],
	"gate_keeper": ["rock_crab", "slime", "cave_bat"],
}


## 普通战斗个人奖励：二选一候选池（设计 §5：以浅层物资为主，铁矿不混入浅层）。
const BATTLE_PERSONAL_POOL := ["copper_scrap", "fiber_clump", "small_potion", "bandage", "copper_scrap", "glow_crystal"]
## 普通战斗公共物资（不占个人选择次数）。
const BATTLE_PUBLIC_POOL := ["copper_scrap", "fiber_clump", "bandage", "small_potion"]
## 精英战斗候选（更好，但不保证全部带得走）。
const ELITE_POOL := ["reinforced_shield", "glow_crystal", "antique_ornament", "small_potion"]
## 采集节点（2~3 件候选，偏材料；铁矿是第二层专有，不混入浅层）。
const GATHER_POOL := ["copper_scrap", "fiber_clump", "bandage"]
## 宝箱节点（偏装备与货物）。
const CHEST_POOL := ["copper_shortsword", "leather_bracer", "antique_ornament", "bandage"]
## 摆件制造带货选择；守门战固定给一份稀有向奖励。
const GATE_REWARDS := ["glow_crystal", "reinforced_shield"]

## 第二层（2.8）：铁矿在此层出现；深层种子与更好装备。
const DEEP_BATTLE_POOL := ["iron_ore", "copper_scrap", "small_potion", "glow_crystal", "iron_ore"]
const DEEP_PUBLIC_POOL := ["iron_ore", "copper_scrap", "bandage"]
const DEEP_ELITE_POOL := ["iron_shortsword", "glow_crystal", "antique_ornament", "rescue_kit"]
const DEEP_GATHER_POOL := ["iron_ore", "iron_ore", "copper_scrap"]
const DEEP_CHEST_POOL := ["iron_shortsword", "glow_crystal", "reinforced_shield", "antique_ornament"]
const DEEP_GATE_REWARDS := ["glow_berry_seed", "iron_shortsword"]
## 深层事件表（2.8 新增 4 个）。
const DEEP_EVENTS := {
	"collapsed_shaft": {
		"name": "塌陷的竖井",
		"desc": "碎石下压着铁矿，搬开要花力气。",
		"options": [
			{"id": "dig", "label": "搬开碎石（失去 5 生命，获得铁矿×2）", "hp_cost": 5, "grants": ["iron_ore", "iron_ore"]},
			{"id": "leave", "label": "离开", "hp_cost": 0, "grants": []},
		],
	},
	"crystal_heart": {
		"name": "晶簇心脏",
		"desc": "完整的晶石就在够得到的地方，深挖可能得不偿失。",
		"options": [
			{"id": "take", "label": "小心敲取（获得微光晶石）", "hp_cost": 0, "grants": ["glow_crystal"]},
			{"id": "leave", "label": "离开", "hp_cost": 0, "grants": []},
		],
	},
	"old_campsite": {
		"name": "旧营地",
		"desc": "前人留下的补给和一粒种子。",
		"options": [
			{"id": "supply", "label": "取补给（药水＋绷带）", "hp_cost": 0, "grants": ["small_potion", "bandage"]},
			{"id": "seed", "label": "翻种子（萤果种子）", "hp_cost": 0, "grants": ["glow_berry_seed"]},
			{"id": "leave", "label": "不动", "hp_cost": 0, "grants": []},
		],
	},
	"guardian_root": {
		"name": "守卫的根须",
		"desc": "首领的力量来自这些根。割断它们会受伤，也许值得。",
		"options": [
			{"id": "cut", "label": "割断根须（失去 6 生命，本层探索无事发生……或有一点收获）", "hp_cost": 6, "grants": []},
			{"id": "leave", "label": "不去招惹", "hp_cost": 0, "grants": []},
		],
	},
}


## 事件表（2.4 设计 §4）：一次选择后完成，不可重选；生命代价至少留 1。
const EVENTS := {
	"narrow_crevice": {
		"name": "狭窄裂隙",
		"desc": "石缝深处好像放着两份铜片，钻进去要蹭掉一些血。",
		"options": [
			{"id": "squeeze", "label": "钻进去（失去 4 生命，获得铜片×2）", "hp_cost": 4, "grants": ["copper_scrap", "copper_scrap"]},
			{"id": "leave", "label": "离开", "hp_cost": 0, "grants": []},
		],
	},
	"abandoned_kit": {
		"name": "荒废药箱",
		"desc": "还能用的药水，或者拆成纤维。",
		"options": [
			{"id": "take_potion", "label": "取药（获得小药水）", "hp_cost": 0, "grants": ["small_potion"]},
			{"id": "salvage", "label": "拆材料（获得纤维×2）", "hp_cost": 0, "grants": ["fiber_clump", "fiber_clump"]},
			{"id": "skip", "label": "不动", "hp_cost": 0, "grants": []},
		],
	},
	"wall_sprout": {
		"name": "洞壁幼芽",
		"desc": "小心取下能得种子；挖根部可能得到更好的种子，但会受伤。",
		"options": [
			{"id": "careful", "label": "小心取下（获得岩芽菜种子）", "hp_cost": 0, "grants": ["rock_sprout_seed"]},
			{"id": "dig", "label": "挖掘根部（失去 6 生命：60% 词条种子／40% 纤维×2）", "hp_cost": 6, "grants": []},
			{"id": "leave", "label": "离开", "hp_cost": 0, "grants": []},
		],
	},
}


static func layer(layer_id: String) -> Dictionary:
	return LAYERS.get(layer_id, {})


static func events_for_node(node_row: int, layer_id := "moss_stone_shallow") -> Array:
	## 事件节点从事件表顺序取用（固定图配固定事件，奖励进入节点才裁定）。
	if layer_id == "iron_root_deeps":
		match node_row:
			2:
				return ["collapsed_shaft", "crystal_heart"]
			5:
				return ["old_campsite", "guardian_root"]
			_:
				return ["collapsed_shaft", "old_campsite"]
	match node_row:
		3:
			return ["narrow_crevice", "wall_sprout"]
		5:
			return ["abandoned_kit", "wall_sprout"]
		_:
			return ["narrow_crevice", "abandoned_kit", "wall_sprout"]


static func encounter_for(node: Dictionary) -> String:
	match str(node.get("type", "")):
		"elite":
			return "layer2_elite" if bool(node.get("deep", false)) else "elite_double"
		"gate":
			return "layer2_guardian" if bool(node.get("deep", false)) else "gate_keeper"
		_:
			return str(node.get("encounter", "shallow_pair"))


## 按层取奖励池（2.8）：[个人, 公共, 精英, 采集, 宝箱]。
static func battle_pools(layer_id: String) -> Array:
	if layer_id == "iron_root_deeps":
		return [DEEP_BATTLE_POOL, DEEP_PUBLIC_POOL, DEEP_ELITE_POOL, DEEP_GATHER_POOL, DEEP_CHEST_POOL]
	return [BATTLE_PERSONAL_POOL, BATTLE_PUBLIC_POOL, ELITE_POOL, GATHER_POOL, CHEST_POOL]
