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


static func events_for_node(node_row: int) -> Array:
	## 事件节点从事件表顺序取用（固定图配固定事件，奖励进入节点才裁定）。
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
			return "elite_double"
		"gate":
			return "gate_keeper"
		_:
			return str(node.get("encounter", "shallow_pair"))
