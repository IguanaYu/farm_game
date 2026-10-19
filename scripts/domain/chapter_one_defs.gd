class_name ChapterOneDefs
extends RefCounted
## 第一章「苔冠森林」内容登记（开发计划 P0，docs/plan/Farm_第一章苔冠森林_开发计划_v0.1.md 附录 A）。
## 本阶段只登记 ID 与映射：五区、43 类搜索模板、23 个敌人、36 件物品映射、16 新增＋11 复用牌。
## 物资候选→权重/数量/预算的转换、路线模板与事件定义分别在 P3~P6 落地，不在本文提前声明数值。
## 展示名称以内容设计 v0.1 §2/§3~§7 为准；本文不改写原设定。


## 内容集与章节身份：局内存档记 content_set/content_version（开发计划 §4.2/§4.5）。
## 缺少 content_set 的局按旧洞窟恢复；字段不参与旧档判定，禁止给进行中的旧局补写。
const CONTENT_SET := "forest_ch1"
const CONTENT_VERSION := 1
const CHAPTER_ID := "moss_crown"

## 内容开关（开发计划 §7）：关闭时三个出发构造入口（本地单人/本地双人/专用服务端）
## 统一拒绝新的森林出发；已开始的森林局仍按同版本恢复，不受本开关影响。
## P0~P4 维持 false（路线与搜索闭环未落地），P5 两区样例交付时打开。
const DEPARTURE_ENABLED := false

## 五区（内容设计 §2）：显示名、表现基色（计划 §3 建议基色初值）、区域强敌与代表搜索物。
## palette 为占位绘制初值，正式美术就绪后由 ChapterArtRegistry 换资源，玩法 ID 不变。
const AREA_ORDER := ["trail", "temple", "tower", "camp", "wetland"]
const AREAS := {
	"trail": {
		"name": "林间古道",
		"art_id": "bg.forest_ch1.trail",
		"base": Color("#5c7a4a"), "accent": Color("#d8b866"),
		"boss": "forest_alpha_wolf",
		"representative": "trail_hollow_log",
	},
	"temple": {
		"name": "苔封神殿",
		"art_id": "bg.forest_ch1.temple",
		"base": Color("#82858c"), "accent": Color("#d9a94e"),
		"boss": "forest_root_coffin_priest",
		"representative": "temple_side_sarcophagus",
	},
	"tower": {
		"name": "空铃废塔",
		"art_id": "bg.forest_ch1.tower",
		"base": Color("#6f6478"), "accent": Color("#b0764f"),
		"boss": "forest_bell_keeper",
		"representative": "tower_bell_cache",
	},
	"camp": {
		"name": "废弃伐木营地",
		"art_id": "bg.forest_ch1.camp",
		"base": Color("#7a5a3a"), "accent": Color("#d97b3c"),
		"boss": "forest_bandit_captain",
		"representative": "camp_supply_crate",
	},
	"wetland": {
		"name": "荧沼湿地",
		"art_id": "bg.forest_ch1.wetland",
		"base": Color("#4a7a6e"), "accent": Color("#8fd8c0"),
		"boss": "forest_fungal_matriarch",
		"representative": "wetland_glowcap_patch",
	},
}

## 43 类搜索模板（附录 A1）：每类可产生多个实例；候选物资与可复现样例在 P3/P5/P6 按区登记。
## risk 字段只登记计划明确点名的风险对象（P3：蜂巢、活动石棺等先展示迹象与处理选项）；
## 其余留 "none"，不代表最终无风险——风险标注随 P3~P6 模板实施补充。
const SEARCH_TEMPLATES := {
	"trail_hollow_log": {"area": "trail", "name": "树洞", "risk": "none"},
	"trail_rotten_stump": {"area": "trail", "name": "腐树桩", "risk": "none"},
	"trail_wagon_crate": {"area": "trail", "name": "散货箱", "risk": "none"},
	"trail_wagon_lockbox": {"area": "trail", "name": "马车锁箱", "risk": "none"},
	"trail_bird_nest": {"area": "trail", "name": "鸟巢", "risk": "none"},
	"trail_beehive": {"area": "trail", "name": "蜂巢", "risk": "guarded"},
	"trail_traveler_remains": {"area": "trail", "name": "旅人遗骸", "risk": "none"},
	"trail_hunter_camp": {"area": "trail", "name": "猎人营地", "risk": "none"},
	"trail_herb_patch": {"area": "trail", "name": "药草", "risk": "none"},
	"trail_wolf_den_bag": {"area": "trail", "name": "狼巢猎袋", "risk": "guarded"},
	"temple_offering_box": {"area": "temple", "name": "供奉匣", "risk": "none"},
	"temple_shrine_cache": {"area": "temple", "name": "神龛夹层", "risk": "none"},
	"temple_side_sarcophagus": {"area": "temple", "name": "石棺", "risk": "guarded"},
	"temple_priest_sarcophagus": {"area": "temple", "name": "祭司棺", "risk": "guarded"},
	"temple_herb_casket": {"area": "temple", "name": "药草匣", "risk": "none"},
	"temple_cistern": {"area": "temple", "name": "水池", "risk": "none"},
	"temple_ember_niche": {"area": "temple", "name": "祭火石龛", "risk": "none"},
	"temple_root_chest": {"area": "temple", "name": "根须箱", "risk": "none"},
	"temple_warden_remains": {"area": "temple", "name": "守林人遗骸", "risk": "none"},
	"tower_guard_box": {"area": "tower", "name": "守卫箱", "risk": "none"},
	"tower_book_cabinet": {"area": "tower", "name": "藏书柜", "risk": "none"},
	"tower_repair_box": {"area": "tower", "name": "工具箱", "risk": "none"},
	"tower_bird_nest": {"area": "tower", "name": "檐下鸟巢", "risk": "none"},
	"tower_lamp_box": {"area": "tower", "name": "灯火箱", "risk": "none"},
	"tower_bell_cache": {"area": "tower", "name": "铃器箱", "risk": "none"},
	"tower_sealed_cache": {"area": "tower", "name": "封印匣", "risk": "none"},
	"tower_worker_bag": {"area": "tower", "name": "维修行囊", "risk": "none"},
	"camp_supply_crate": {"area": "camp", "name": "物资箱", "risk": "none"},
	"camp_weapon_rack": {"area": "camp", "name": "武器架", "risk": "none"},
	"camp_caravan_crate": {"area": "camp", "name": "商队封箱", "risk": "none"},
	"camp_medicine_box": {"area": "camp", "name": "药箱", "risk": "none"},
	"camp_kiln_gel_nest": {"area": "camp", "name": "炉旁胶巢", "risk": "none"},
	"camp_hunting_rack": {"area": "camp", "name": "猎货架", "risk": "none"},
	"camp_stump_stash": {"area": "camp", "name": "树桩私藏", "risk": "none"},
	"camp_captain_chest": {"area": "camp", "name": "头目箱", "risk": "none"},
	"wetland_glowcap_patch": {"area": "wetland", "name": "菌丛", "risk": "none"},
	"wetland_herb_roots": {"area": "wetland", "name": "根下草药", "risk": "none"},
	"wetland_sunken_crate": {"area": "wetland", "name": "沉箱", "risk": "none"},
	"wetland_abandoned_raft": {"area": "wetland", "name": "舟筏", "risk": "none"},
	"wetland_web_bundle": {"area": "wetland", "name": "蛛网包", "risk": "none"},
	"wetland_gel_pool": {"area": "wetland", "name": "胶洼", "risk": "none"},
	"wetland_fallen_hive": {"area": "wetland", "name": "倒塌蜂树", "risk": "guarded"},
	"wetland_fungal_bag": {"area": "wetland", "name": "菌丝货袋", "risk": "none"},
}

## 23 个敌人（附录 A2）：batch=落地阶段（2/6）；boss=true 为区域强敌（5 个）。
## 区域强敌按内容设计 §2 表归属区域；常规敌人跨区出现，区域遭遇配置在 P4/P6 登记。
const ENEMIES := {
	"forest_goblin_archer": {"name": "弓手", "batch": 2, "boss": false},
	"forest_goblin_shield": {"name": "剑盾兵", "batch": 2, "boss": false},
	"forest_green_slime": {"name": "绿史莱姆", "batch": 2, "boss": false},
	"forest_red_slime": {"name": "红史莱姆", "batch": 2, "boss": false},
	"forest_blue_slime": {"name": "蓝史莱姆", "batch": 2, "boss": false},
	"forest_wolf": {"name": "森林狼", "batch": 2, "boss": false},
	"forest_cave_bat": {"name": "穴蝠", "batch": 2, "boss": false},
	"forest_wrapped_guard": {"name": "裹尸守卫", "batch": 2, "boss": false},
	"forest_seal_priest": {"name": "封棺祭司", "batch": 2, "boss": false},
	"forest_alpha_wolf": {"name": "灰鬃头狼", "batch": 2, "boss": true, "area": "trail"},
	"forest_root_coffin_priest": {"name": "根棺祭司", "batch": 2, "boss": true, "area": "temple"},
	"forest_goblin_spearman": {"name": "长矛手", "batch": 6, "boss": false},
	"forest_goblin_herbalist": {"name": "采药者", "batch": 6, "boss": false},
	"forest_bandit_axeman": {"name": "斧匪", "batch": 6, "boss": false},
	"forest_bandit_crossbowman": {"name": "弩匪", "batch": 6, "boss": false},
	"forest_bandit_trapper": {"name": "绳网猎匪", "batch": 6, "boss": false},
	"forest_wood_guard": {"name": "木甲守卫", "batch": 6, "boss": false},
	"forest_bell_wisp": {"name": "铃影", "batch": 6, "boss": false},
	"forest_rotwood_spider": {"name": "腐木蛛", "batch": 6, "boss": false},
	"forest_fungal_walker": {"name": "菌寄行尸", "batch": 6, "boss": false},
	"forest_bell_keeper": {"name": "空铃守塔人", "batch": 6, "boss": true, "area": "tower"},
	"forest_bandit_captain": {"name": "劫路头目", "batch": 6, "boss": true, "area": "camp"},
	"forest_fungal_matriarch": {"name": "菌冠母体", "batch": 6, "boss": true, "area": "wetland"},
}

## 36 件物品映射（附录 A3）：设计编号→def_id。reuse=true 的 5 件直接用现有定义，
## 不创建同名重复；其余 31 件统一 forest_ 前缀，定义本体在 P1 写入 ItemDefs。
const ITEM_MAPPING := {
	"I01": {"def_id": "copper_shortsword", "name": "铜短剑", "reuse": true},
	"I02": {"def_id": "forest_goblin_bow", "name": "哥布林短弓", "reuse": false},
	"I03": {"def_id": "reinforced_shield", "name": "加固盾", "reuse": true},
	"I04": {"def_id": "forest_bone_dagger", "name": "猎骨匕首", "reuse": false},
	"I05": {"def_id": "forest_logging_axe", "name": "伐木斧", "reuse": false},
	"I06": {"def_id": "forest_resin_armor", "name": "树脂护甲", "reuse": false},
	"I07": {"def_id": "forest_bat_mantle", "name": "蝠纹披肩", "reuse": false},
	"I08": {"def_id": "forest_ritual_bellstaff", "name": "祭铃杖", "reuse": false},
	"I09": {"def_id": "forest_runic_wand", "name": "刻符短杖", "reuse": false},
	"I10": {"def_id": "forest_feather_charm", "name": "斑羽饰", "reuse": false},
	"I11": {"def_id": "forest_hunting_horn", "name": "猎人号角", "reuse": false},
	"I12": {"def_id": "forest_green_gel", "name": "绿凝胶", "reuse": false},
	"I13": {"def_id": "forest_fire_gel_sac", "name": "赤凝胶囊", "reuse": false},
	"I14": {"def_id": "forest_frost_gel_sac", "name": "蓝凝胶囊", "reuse": false},
	"I15": {"def_id": "forest_honey_chunk", "name": "蜂蜜块", "reuse": false},
	"I16": {"def_id": "forest_healing_moss", "name": "敷伤苔", "reuse": false},
	"I17": {"def_id": "forest_sting_sac", "name": "蜂针囊", "reuse": false},
	"I18": {"def_id": "forest_resin_torch", "name": "树脂火把", "reuse": false},
	"I19": {"def_id": "forest_old_lantern", "name": "旧提灯", "reuse": false},
	"I20": {"def_id": "forest_rope_net", "name": "绳网", "reuse": false},
	"I21": {"def_id": "forest_silverleaf_seed", "name": "银叶草种子", "reuse": false},
	"I22": {"def_id": "forest_glowcap_spawn", "name": "萤菇孢种", "reuse": false},
	"I23": {"def_id": "forest_resin_chunk", "name": "树脂块", "reuse": false},
	"I24": {"def_id": "forest_clean_linen", "name": "干净麻布", "reuse": false},
	"I25": {"def_id": "copper_scrap", "name": "铜片", "reuse": true},
	"I26": {"def_id": "forest_hide_roll", "name": "兽皮卷", "reuse": false},
	"I27": {"def_id": "forest_antique_silver", "name": "古银器", "reuse": false},
	"I28": {"def_id": "glow_crystal", "name": "微光晶石", "reuse": true},
	"I29": {"def_id": "forest_prayer_carving", "name": "祈愿木雕", "reuse": false},
	"I30": {"def_id": "forest_warden_badge", "name": "守林徽记", "reuse": false},
	"I31": {"def_id": "forest_bell_ring", "name": "碎钟铜环", "reuse": false},
	"I32": {"def_id": "forest_rot_spore_sac", "name": "腐菌囊", "reuse": false},
	"I33": {"def_id": "forest_bat_wing", "name": "蝠翼", "reuse": false},
	"I34": {"def_id": "fiber_clump", "name": "纤维团", "reuse": true},
	"I35": {"def_id": "forest_salvaged_spear", "name": "拼装长矛", "reuse": false},
	"I36": {"def_id": "forest_hunting_crossbow", "name": "旧猎弩", "reuse": false},
}

## 16 个新增牌（附录 A4）：card_id 已登记；牌定义本体与效果实现是 P1/P2 的工作，
## 本表只保证 ID 稳定与实现方式归类，不提前声明数值。
const NEW_CARDS := {
	"forest_shoot": {"name": "射击", "impl": "伤害模板"},
	"forest_thrust": {"name": "突刺", "impl": "伤害模板"},
	"forest_power_shot": {"name": "强射", "impl": "伤害模板"},
	"forest_bell_strike": {"name": "敲击", "impl": "伤害模板"},
	"forest_rest_bell": {"name": "安息铃", "impl": "新净化效果"},
	"forest_guard_bell": {"name": "守护铃", "impl": "格挡模板"},
	"forest_glow_bolt": {"name": "微光弹", "impl": "新部分穿透效果"},
	"forest_apply_gel": {"name": "凝胶敷药", "impl": "治疗＋消耗来源"},
	"forest_throw_fire_sac": {"name": "投掷火囊", "impl": "伤害＋灼烧＋消耗来源"},
	"forest_throw_frost_sac": {"name": "投掷冰囊", "impl": "伤害＋寒冷＋消耗来源"},
	"forest_eat_honey": {"name": "食蜜", "impl": "治疗＋抽牌＋消耗来源"},
	"forest_scatter_stings": {"name": "撒蜂针", "impl": "伤害＋中毒＋消耗来源"},
	"forest_torch_strike": {"name": "火把挥击", "impl": "伤害＋灼烧"},
	"forest_smoke_screen": {"name": "烟幕", "impl": "格挡模板"},
	"forest_throw_net": {"name": "投网", "impl": "伤害＋虚弱＋消耗来源"},
	"forest_throw_spores": {"name": "抛孢", "impl": "中毒＋消耗来源"},
}

## 11 个复用牌（附录 A4 末行）：直接使用现有 CardDefs 定义。
const REUSED_CARDS := [
	"slash", "heavy_strike", "shield_up", "cover", "brace", "observe",
	"deep_breath", "expose", "venom_stab", "first_aid", "heavy_cargo",
]


## 出发内容集检查（P0 版本检查入口；本地与专用服务端共用）。
## 返回空串=放行；非空为拒绝原因。空 content_set 表示旧洞窟，始终放行。
static func departure_problem(content_set: String, content_version := CONTENT_VERSION) -> String:
	if content_set == "":
		return ""
	if content_set != CONTENT_SET:
		return "未知内容集：%s" % content_set
	if int(content_version) != CONTENT_VERSION:
		return "森林内容版本不支持（本端支持 %d，请求为 %d）" % [CONTENT_VERSION, int(content_version)]
	if not DEPARTURE_ENABLED:
		return "森林内容尚未开放"
	return ""


## 已有局的恢复检查（区别于出发：不受 DEPARTURE_ENABLED 影响，只看版本）。
static func recovery_problem(content_set: String, content_version: Variant) -> String:
	if content_set == "":
		return ""
	if content_set != CONTENT_SET:
		return "未知内容集：%s" % content_set
	if int(content_version) != CONTENT_VERSION:
		return "森林内容版本不支持（本端支持 %d，存档为 %s）" % [CONTENT_VERSION, str(content_version)]
	return ""


static func area(area_id: String) -> Dictionary:
	return AREAS.get(area_id, {})


static func template(template_id: String) -> Dictionary:
	return SEARCH_TEMPLATES.get(template_id, {})


static func templates_for_area(area_id: String) -> Array:
	var result: Array = []
	for template_id in SEARCH_TEMPLATES:
		if str(SEARCH_TEMPLATES[template_id]["area"]) == area_id:
			result.append(template_id)
	return result


static func enemies_for_batch(batch: int) -> Array:
	var result: Array = []
	for enemy_id in ENEMIES:
		if int(ENEMIES[enemy_id]["batch"]) == batch:
			result.append(enemy_id)
	return result


## 登记表自检（tests/forest_defs_smoke.gd 使用）：数量、归属、前缀与跨表引用全部有效。
## reuse 物品必须已在 ItemDefs 存在；新增 def_id 不得与现有定义撞名（不创建同名重复）。
## 搜索模板与敌人的 art_id 约定为 prop.<模板ID>／enemy.<敌人ID>（计划 §3 资源 ID 示例）。
static func validate_registrations() -> Array:
	var problems: Array = []
	if AREAS.size() != 5:
		problems.append("五区数量应为 5，实际 %d" % AREAS.size())
	for area_id in AREAS:
		if str(AREAS[area_id].get("boss", "")) == "":
			problems.append("区域 %s 缺少区域强敌归属" % area_id)
		if str(AREAS[area_id].get("representative", "")) == "":
			problems.append("区域 %s 缺少代表搜索物" % area_id)
		elif not SEARCH_TEMPLATES.has(str(AREAS[area_id]["representative"])):
			problems.append("区域 %s 的代表搜索物未登记" % area_id)
		if not ENEMIES.has(str(AREAS[area_id].get("boss", ""))):
			problems.append("区域 %s 的强敌未登记" % area_id)

	var area_quota := {"trail": 10, "temple": 9, "tower": 8, "camp": 8, "wetland": 8}
	if SEARCH_TEMPLATES.size() != 43:
		problems.append("搜索模板应为 43 类，实际 %d" % SEARCH_TEMPLATES.size())
	for area_id in area_quota:
		if templates_for_area(area_id).size() != int(area_quota[area_id]):
			problems.append("区域 %s 模板数应为 %d，实际 %d" % [area_id, area_quota[area_id], templates_for_area(area_id).size()])
	for template_id in SEARCH_TEMPLATES:
		var record: Dictionary = SEARCH_TEMPLATES[template_id]
		if not AREAS.has(str(record["area"])):
			problems.append("模板 %s 指向未登记区域 %s" % [template_id, str(record["area"])])
		if not str(record.get("risk", "none")) in ["none", "guarded"]:
			problems.append("模板 %s 的 risk 字段非法" % template_id)

	if ENEMIES.size() != 23:
		problems.append("敌人应为 23 个，实际 %d" % ENEMIES.size())
	var boss_count := 0
	for enemy_id in ENEMIES:
		var record: Dictionary = ENEMIES[enemy_id]
		if int(record.get("batch", 0)) != 2 and int(record.get("batch", 0)) != 6:
			problems.append("敌人 %s 的 batch 字段非法" % enemy_id)
		if bool(record.get("boss", false)):
			boss_count += 1
			if not AREAS.has(str(record.get("area", ""))):
				problems.append("区域强敌 %s 缺少有效区域归属" % enemy_id)
		elif record.has("area"):
			problems.append("常规敌人 %s 不应带区域归属（区域遭遇在 P4/P6 登记）" % enemy_id)
	if boss_count != 5:
		problems.append("区域强敌应为 5 个，实际 %d" % boss_count)
	if enemies_for_batch(2).size() != 11 or enemies_for_batch(6).size() != 12:
		problems.append("批次数量应为 P2=11（9 常规+2 强敌）、P6=12（9 常规+3 强敌）")

	if ITEM_MAPPING.size() != 36:
		problems.append("物品映射应为 36 条，实际 %d" % ITEM_MAPPING.size())
	for index in range(1, 37):
		var design_no := "I%02d" % index
		if not ITEM_MAPPING.has(design_no):
			problems.append("缺少设计编号 %s 的物品映射" % design_no)
	var def_owner := {}
	for design_no in ITEM_MAPPING:
		var record: Dictionary = ITEM_MAPPING[design_no]
		var def_id := str(record["def_id"])
		if def_owner.has(def_id):
			problems.append("def_id %s 被 %s 与 %s 重复映射" % [def_id, str(def_owner[def_id]), design_no])
		def_owner[def_id] = design_no
		if bool(record.get("reuse", false)):
			if not ItemDefs.is_known_item(def_id):
				problems.append("映射 %s 声明复用但 ItemDefs 缺少 %s" % [design_no, def_id])
		elif not def_id.begins_with("forest_"):
			problems.append("新增物品 %s（%s）应使用 forest_ 前缀" % [design_no, def_id])
		elif ItemDefs.is_known_item(def_id):
			problems.append("新增物品 %s 与现有定义 %s 撞名" % [design_no, def_id])

	if NEW_CARDS.size() != 16:
		problems.append("新增牌应为 16 个，实际 %d" % NEW_CARDS.size())
	for card_id in NEW_CARDS:
		if not card_id.begins_with("forest_"):
			problems.append("新增牌 %s 应使用 forest_ 前缀" % card_id)
		elif CardDefs.CARDS.has(card_id):
			problems.append("新增牌 %s 已存在于 CardDefs（P1 前不得提前写入）" % card_id)
	if REUSED_CARDS.size() != 11:
		problems.append("复用牌应为 11 个，实际 %d" % REUSED_CARDS.size())
	for card_id in REUSED_CARDS:
		if not CardDefs.CARDS.has(card_id):
			problems.append("复用牌 %s 在 CardDefs 中不存在" % card_id)
	return problems
