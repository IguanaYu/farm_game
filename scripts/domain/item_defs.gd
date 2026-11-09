class_name ItemDefs
extends RefCounted
## 物品定义表。2.1 只包含基础套装与演示物品；2.3 扩到 12~16 种。
## cards 序列长度必须等于占格数（占 N 格给 N 张牌实例，可重复）。

const ITEMS := {
	# —— 免费基础套装（2.1 设计 §7）：死亡后可补领缺失部件，不可出售／分享／制作。
	"old_shortsword": {
		"name": "旧短刀", "category": "weapon", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 0, "sellable": false, "basic_kit": true, "demo": false,
		"safe_allowed": false, "cards": ["slash", "slash"],
		"desc": "基础装备：占 2 格，提供 2 张切击。不能出售或分享。",
	},
	"wooden_shield": {
		"name": "木盾", "category": "armor", "size": Vector2i(2, 2), "quality": 1,
		"base_value": 0, "sellable": false, "basic_kit": true, "demo": false,
		"safe_allowed": false, "cards": ["shield_up", "shield_up", "cover", "brace"],
		"desc": "基础装备：占 4 格，提供 架盾×2／掩护／稳住。不能出售或分享。",
	},
	"pack_tools": {
		"name": "行囊工具", "category": "tool", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 0, "sellable": false, "basic_kit": true, "demo": false,
		"safe_allowed": false, "cards": ["deep_breath", "observe"],
		"desc": "基础装备：占 2 格，提供 调整呼吸／观察。不能出售或分享。",
	},
	"straw_hat": {
		"name": "草帽", "category": "helmet", "size": Vector2i(2, 2), "quality": 1,
		"base_value": 0, "sellable": false, "basic_kit": true, "demo": false,
		"safe_allowed": false, "cards": ["brace", "cover", "deep_breath", "observe"],
		"desc": "基础装备：装备在头盔槽，第 1 回合就提供 稳住／掩护／调整呼吸／观察。不能出售或分享。",
	},
	# —— 演示物品（2.1 设计 §5）：只在战备预览中使用，不写入正式库存。
	"demo_iron_sword": {
		"name": "铁剑（演示）", "category": "weapon", "size": Vector2i(1, 3), "quality": 2,
		"base_value": 30, "sellable": true, "basic_kit": false, "demo": true,
		"safe_allowed": false, "cards": ["slash", "heavy_strike", "slash"],
		"desc": "演示用：看看正式武器会提供什么样的牌。",
	},
	"demo_ore": {
		"name": "铁矿石（演示）", "category": "material", "size": Vector2i(2, 2), "quality": 1,
		"base_value": 24, "sellable": true, "basic_kit": false, "demo": true,
		"safe_allowed": true, "cards": ["heavy_cargo", "heavy_cargo", "heavy_cargo", "heavy_cargo"],
		"desc": "演示用：值钱但拖累战斗——4 张笨重货物会塞满手牌。",
	},
	"demo_potion": {
		"name": "小药水（演示）", "category": "supply", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 8, "sellable": true, "basic_kit": false, "demo": true,
		"safe_allowed": true, "cards": ["drink_potion"], "uses": 2,
		"desc": "演示用：消耗品，同一瓶的牌共享剩余次数。",
	},
	# —— 正式物品池（2.3 设计 §4）：12~16 种预算内新增 12 种。
	"copper_shortsword": {
		"name": "铜短剑", "category": "weapon", "size": Vector2i(1, 3), "quality": 1,
		"base_value": 40, "buy_price": 70, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["slash", "slash", "heavy_strike"],
		"desc": "普通攻击装备：占 3 格，切击×2＋重击。",
	},
	"reinforced_shield": {
		"name": "加固盾", "category": "armor", "size": Vector2i(2, 2), "quality": 2,
		"base_value": 50, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["shield_up", "shield_up", "cover", "brace"],
		"desc": "品质版防御：牌构成与木盾相同（后续品质提升改数值，不改占格规则）。",
	},
	"leather_bracer": {
		"name": "皮护腕", "category": "armor", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 25, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["brace", "shield_up"],
		"desc": "小体积防御补充：占 2 格，稳住＋架盾。",
	},
	"scout_whistle": {
		"name": "侦察哨", "category": "tool", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 30, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["observe", "deep_breath"],
		"desc": "抽牌工具：观察＋调整呼吸。",
	},
	"small_potion": {
		"name": "小药水", "category": "supply", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 6, "buy_price": 8, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["drink_potion"], "uses": 1,
		"desc": "一次恢复补给：使用一次后实体消耗、关联牌清除。",
	},
	"bandage": {
		"name": "绷带", "category": "supply", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 5, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["first_aid"], "uses": 1,
		"desc": "一次恢复补给：给自己或队友包扎。",
	},
	"copper_scrap": {
		"name": "铜片", "category": "material", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 8, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": true, "cards": ["heavy_cargo"],
		"desc": "基础制作材料，可放保险箱；携带时是一张笨重货物。",
	},
	"fiber_clump": {
		"name": "纤维团", "category": "material", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 6, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["heavy_cargo"],
		"desc": "护具制作材料；不能放保险箱。",
	},
	"iron_ore": {
		"name": "铁矿", "category": "material", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 18, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": true, "cards": ["heavy_cargo", "heavy_cargo"],
		"desc": "深层装备材料，可放保险箱；占 2 格＝2 张笨重货物。",
	},
	"rock_sprout_seed": {
		"name": "岩芽菜种子", "category": "rare_seed", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 2, "sellable": false, "basic_kit": false, "demo": false,
		"safe_allowed": true, "cards": ["heavy_cargo"],
		"desc": "新植物的种子（暂名）：保险箱可保护；回家按种子回收规则处理（2.5 接入）。",
	},
	"antique_ornament": {
		"name": "古旧摆件", "category": "cargo", "size": Vector2i(2, 2), "quality": 1,
		"base_value": 90, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["heavy_cargo", "heavy_cargo", "heavy_cargo", "heavy_cargo"],
		"desc": "高价值出售货物：值 90 金币，但 4 张笨重货物会拖累战斗；不可保护。",
	},
	"glow_berry_seed": {
		"name": "萤果种子", "category": "rare_seed", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 5, "sellable": false, "basic_kit": false, "demo": false,
		"safe_allowed": true, "cards": ["heavy_cargo"],
		"desc": "深层植物的种子（第二层带回）：保险箱可保护；回家转为种子（2.8 接入种植）。",
	},
	"glow_crystal": {
		"name": "微光晶石", "category": "material", "size": Vector2i(1, 2), "quality": 2,
		"base_value": 60, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["brace", "observe"],
		"desc": "小型高价值资源：值钱也能打（稳住＋观察）；不可保护。",
	},
	# —— 2.5 制作产物与深层装备 ——
	"cabbage_soup": {
		"name": "白菜汤", "category": "supply", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 4, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["drink_soup"], "uses": 1,
		"desc": "农场自产补给：恢复 6 生命，一次使用。",
	},
	"rock_elixir": {
		"name": "岩芽药剂", "category": "supply", "size": Vector2i(1, 1), "quality": 2,
		"base_value": 8, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["drink_elixir"], "uses": 1,
		"desc": "洞窟植物制成：恢复 10 生命，一次使用。",
	},
	"iron_shortsword": {
		"name": "铁短剑", "category": "weapon", "size": Vector2i(1, 3), "quality": 2,
		"base_value": 90, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["slash7", "slash7", "heavy_strike15"],
		"desc": "深层装备：切击(7)×2＋重击(15)。",
	},
	"rescue_kit": {
		"name": "救援包", "category": "supply", "size": Vector2i(1, 2), "quality": 2,
		"base_value": 20, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["first_aid", "rescue_signal"], "uses": 1,
		"desc": "共享一次使用的恢复＋救援（救援牌在 2.6 合作接入；单人可自用恢复）。",
	},
	# —— 第三层晶脉矿窟（内容扩展轮）：辉晶材料、三阶装备与星瓣花种子 ——
	"radiant_cluster": {
		"name": "辉晶簇", "category": "material", "size": Vector2i(1, 2), "quality": 2,
		"base_value": 40, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": true, "cards": ["heavy_cargo", "heavy_cargo"],
		"desc": "第三层制作材料，可放保险箱；占 2 格＝2 张笨重货物。",
	},
	"crystal_blade": {
		"name": "辉晶刃", "category": "weapon", "size": Vector2i(1, 3), "quality": 2,
		"base_value": 170, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["slash8", "slash8", "heavy_strike17"],
		"desc": "第三层装备：晶刃斩(8)×2＋裂石一击(17)。",
	},
	"crystal_aegis": {
		"name": "辉晶盾", "category": "armor", "size": Vector2i(2, 2), "quality": 2,
		"base_value": 100, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["shield_up", "shield_up", "cover", "brace"],
		"desc": "第三层品质防具：牌构成与加固盾相同，价值更高。",
	},
	"iron_helm": {
		"name": "铁盔", "category": "helmet", "size": Vector2i(2, 2), "quality": 2,
		"base_value": 110, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["shield_up", "shield_up", "cover", "brace"],
		"desc": "第三层头盔：装备在头盔槽即生效，第 1 回合提供 架盾×2／掩护／稳住。",
	},
	"star_bloom_seed": {
		"name": "星瓣花种子", "category": "rare_seed", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 8, "sellable": false, "basic_kit": false, "demo": false,
		"safe_allowed": true, "cards": ["heavy_cargo"],
		"desc": "第三层植物的种子：保险箱可保护；回家转为种子（种植解锁后进市场）。",
	},
	# —— 第一章苔冠森林（P1）：31 件新物品。规格＝内容设计 §9 表（面积=牌数）；
	# 数值为未试玩初值（P8 统一调平）。类别：弓/匕/斧/铃杖/符杖/矛/弩=weapon，护甲/披肩=armor，
	# 羽饰/号角/火把/提灯=tool（走容器，不设饰品槽）；只有两种新种子进保险白名单。——
	"forest_goblin_bow": {
		"name": "哥布林短弓", "category": "weapon", "size": Vector2i(1, 3), "quality": 1,
		"base_value": 40, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["forest_shoot", "forest_shoot", "expose"],
		"desc": "森林装备：占 3 格，射击×2＋破绽——先标记再输出。",
	},
	"forest_bone_dagger": {
		"name": "猎骨匕首", "category": "weapon", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 30, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["slash", "venom_stab"],
		"desc": "森林装备：占 2 格，切击＋毒刺——小体积持续伤害武器。",
	},
	"forest_logging_axe": {
		"name": "伐木斧", "category": "weapon", "size": Vector2i(2, 2), "quality": 1,
		"base_value": 55, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["slash", "slash", "heavy_strike", "expose"],
		"desc": "森林装备：占 4 格，切击×2＋重击＋破绽——牌组更厚的重武器。",
	},
	"forest_resin_armor": {
		"name": "树脂护甲", "category": "armor", "size": Vector2i(2, 2), "quality": 2,
		"base_value": 55, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["shield_up", "shield_up", "brace", "brace"],
		"desc": "森林防具：占 4 格，架盾×2＋稳住×2——稳定防御，缺少抽牌。",
	},
	"forest_bat_mantle": {
		"name": "蝠纹披肩", "category": "armor", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 25, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["brace", "observe"],
		"desc": "森林轻防具：占 2 格，稳住＋观察——轻防御与过牌。",
	},
	"forest_ritual_bellstaff": {
		"name": "祭铃杖", "category": "weapon", "size": Vector2i(1, 3), "quality": 2,
		"base_value": 60, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["forest_bell_strike", "forest_rest_bell", "forest_guard_bell"],
		"desc": "森林装备：占 3 格，敲击＋安息铃＋守护铃——偏净化与队友保护。",
	},
	"forest_runic_wand": {
		"name": "刻符短杖", "category": "weapon", "size": Vector2i(1, 3), "quality": 2,
		"base_value": 65, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["forest_glow_bolt", "forest_glow_bolt", "observe"],
		"desc": "森林装备：占 3 格，微光弹×2＋观察——对格挡有优势，普通直伤较低。",
	},
	"forest_feather_charm": {
		"name": "斑羽饰", "category": "tool", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 28, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["observe", "deep_breath"],
		"desc": "森林工具：占 2 格，观察＋调整呼吸——辅助抽牌。",
	},
	"forest_hunting_horn": {
		"name": "猎人号角", "category": "tool", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 28, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["cover", "observe"],
		"desc": "森林工具：占 2 格，掩护＋观察——支援防御与过牌。",
	},
	"forest_resin_torch": {
		"name": "树脂火把", "category": "tool", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 20, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["forest_torch_strike", "forest_smoke_screen"],
		"desc": "森林工具：占 2 格，火把挥击＋烟幕——可反复使用的火源。",
	},
	"forest_old_lantern": {
		"name": "旧提灯", "category": "tool", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 22, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["observe", "brace"],
		"desc": "森林工具：占 2 格，观察＋稳住——偏辅助，也可带回做照明装饰。",
	},
	"forest_salvaged_spear": {
		"name": "拼装长矛", "category": "weapon", "size": Vector2i(1, 3), "quality": 1,
		"base_value": 40, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["forest_thrust", "forest_thrust", "heavy_strike"],
		"desc": "森林装备：占 3 格，突刺×2＋重击。",
	},
	"forest_hunting_crossbow": {
		"name": "旧猎弩", "category": "weapon", "size": Vector2i(2, 2), "quality": 2,
		"base_value": 75, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["forest_shoot", "forest_shoot", "forest_power_shot", "heavy_cargo"],
		"desc": "森林装备：占 4 格，射击×2＋强射＋笨重货物——兼有爆发与装填负担。",
	},
	"forest_green_gel": {
		"name": "绿凝胶", "category": "supply", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 6, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["forest_apply_gel"], "uses": 1,
		"desc": "森林补给：恢复 6 生命，一次使用；也可带回制药。",
	},
	"forest_fire_gel_sac": {
		"name": "赤凝胶囊", "category": "supply", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 8, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["forest_throw_fire_sac"], "uses": 1,
		"desc": "森林补给：一次火系攻击并附加灼烧。",
	},
	"forest_frost_gel_sac": {
		"name": "蓝凝胶囊", "category": "supply", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 8, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["forest_throw_frost_sac"], "uses": 1,
		"desc": "森林补给：一次冰系攻击并附加寒冷减攻。",
	},
	"forest_honey_chunk": {
		"name": "蜂蜜块", "category": "supply", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 5, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["forest_eat_honey"], "uses": 1,
		"desc": "森林补给：少量恢复并抽 1 张牌，一次使用；也可带回烹饪。",
	},
	"forest_healing_moss": {
		"name": "敷伤苔", "category": "supply", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 5, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["first_aid"], "uses": 1,
		"desc": "森林补给：复用应急包扎（恢复 4 生命），一次使用。",
	},
	"forest_sting_sac": {
		"name": "蜂针囊", "category": "supply", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 7, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["forest_scatter_stings"], "uses": 1,
		"desc": "森林补给：带中毒的单体投掷物，一次使用。",
	},
	"forest_rope_net": {
		"name": "绳网", "category": "supply", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 10, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["forest_throw_net", "heavy_cargo"], "uses": 1,
		"desc": "森林补给：投网（伤害＋虚弱）与笨重货物并存；投网后整件消耗、负担牌一并移除。",
	},
	"forest_rot_spore_sac": {
		"name": "腐菌囊", "category": "supply", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 7, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["forest_throw_spores"], "uses": 1,
		"desc": "森林补给：纯中毒投掷物，无即时直伤；一次使用。",
	},
	"forest_silverleaf_seed": {
		"name": "银叶草种子", "category": "rare_seed", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 4, "sellable": false, "basic_kit": false, "demo": false,
		"safe_allowed": true, "cards": ["heavy_cargo"],
		"desc": "森林植物的种子：保险箱可保护；回家解锁药草种植（P6 接入）。",
	},
	"forest_glowcap_spawn": {
		"name": "萤菇孢种", "category": "rare_seed", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 4, "sellable": false, "basic_kit": false, "demo": false,
		"safe_allowed": true, "cards": ["heavy_cargo"],
		"desc": "森林菌类的孢种：保险箱可保护；回家解锁菌类栽培（P6 接入）。",
	},
	"forest_resin_chunk": {
		"name": "树脂块", "category": "material", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 7, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["heavy_cargo"],
		"desc": "森林制作材料：火把、护甲与封存都用得上。",
	},
	"forest_clean_linen": {
		"name": "干净麻布", "category": "material", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 7, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["heavy_cargo"],
		"desc": "森林制作材料：来自完整封存区的未污损布料。",
	},
	"forest_hide_roll": {
		"name": "兽皮卷", "category": "material", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 16, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["heavy_cargo", "heavy_cargo"],
		"desc": "森林材料：占 2 格＝2 张笨重货物；制作皮具或出售。",
	},
	"forest_antique_silver": {
		"name": "古银器", "category": "cargo", "size": Vector2i(2, 2), "quality": 2,
		"base_value": 95, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["heavy_cargo", "heavy_cargo", "heavy_cargo", "heavy_cargo"],
		"desc": "高价出售货物：值 95 金币，但 4 张笨重货物明确制造带货压力；不可保护。",
	},
	"forest_prayer_carving": {
		"name": "祈愿木雕", "category": "cargo", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 45, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["deep_breath", "heavy_cargo"],
		"desc": "出售、收藏与家园摆设：调整呼吸只部分抵消其负担。",
	},
	"forest_warden_badge": {
		"name": "守林徽记", "category": "cargo", "size": Vector2i(1, 1), "quality": 2,
		"base_value": 35, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["brace"],
		"desc": "稀有身份物：可交换教团物资或收藏；不是必须反复携带的钥匙。",
	},
	"forest_bell_ring": {
		"name": "碎钟铜环", "category": "material", "size": Vector2i(1, 2), "quality": 1,
		"base_value": 16, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["heavy_cargo", "heavy_cargo"],
		"desc": "森林材料：占 2 格＝2 张笨重货物；制作铃器、出售或装饰。",
	},
	"forest_bat_wing": {
		"name": "蝠翼", "category": "material", "size": Vector2i(1, 1), "quality": 1,
		"base_value": 6, "sellable": true, "basic_kit": false, "demo": false,
		"safe_allowed": false, "cards": ["heavy_cargo"],
		"desc": "森林材料：制作蝠纹披肩；不直接等于一张闪避神牌。",
	},
}

# 装备与物资共用五档品质；实例优先，旧存档无字段时回退定义。
const QUALITY_NAMES := ["白色 · 普通", "蓝色 · 精良", "紫色 · 稀有", "金色 · 史诗", "红色 · 传说"]
const QUALITY_COLORS := [Color("#dce5eb"), Color("#58aaff"), Color("#bc83ff"), Color("#ffd064"), Color("#ff686e")]
const SEARCH_MS := [850, 1400, 2200, 3300, 4800]

static func quality_of(instance: Dictionary) -> int:
	return clampi(int(instance.get("quality", get_item(str(instance.get("def_id", ""))).get("quality", 1))), 1, 5)

static func quality_name(quality: int) -> String:
	return QUALITY_NAMES[clampi(quality, 1, 5) - 1]

static func quality_color(quality: int) -> Color:
	return QUALITY_COLORS[clampi(quality, 1, 5) - 1]

static func search_ms(quality: int) -> int:
	return SEARCH_MS[clampi(quality, 1, 5) - 1]


static func get_item(def_id: String) -> Dictionary:
	return ITEMS.get(def_id, {})


static func is_known_item(def_id: String) -> bool:
	return ITEMS.has(def_id)


static func is_basic(def_id: String) -> bool:
	return bool(ITEMS.get(def_id, {}).get("basic_kit", false))


static func basic_kit_ids() -> Array:
	var result: Array = []
	for def_id in ITEMS:
		if bool(ITEMS[def_id]["basic_kit"]):
			result.append(def_id)
	return result


## 校验定义表自身一致性：占格数=牌数、demo 与正式物品互斥、引用的牌都存在。
static func validate_definitions() -> Array:
	var problems: Array = []
	for def_id in ITEMS:
		var def: Dictionary = ITEMS[def_id]
		var cells: int = def["size"].x * def["size"].y
		if def["cards"].size() != cells:
			problems.append("%s 占 %d 格但提供 %d 张牌" % [def_id, cells, def["cards"].size()])
		for card_id in def["cards"]:
			if not CardDefs.CARDS.has(card_id):
				problems.append("%s 引用了未定义的牌 %s" % [def_id, card_id])
	return problems
