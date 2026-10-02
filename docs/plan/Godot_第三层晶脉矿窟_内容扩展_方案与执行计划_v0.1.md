# 第三层「晶脉矿窟」内容扩展：方案与执行计划 v0.1

编写日期：2026-10-02。状态：**已实施，d28/d40 覆盖，待实机验收**（实施记录见 §8）。
定位：玩法内容扩展轮（用户选定方向），一条完整成长线：**新层 → 新材料 → 新配方装备 → 变强 → 打穿新首领 → 新稀有植物**。数值依据：沿用 L1→L2 既有梯度外推（敌人 HP 均值约 +40%、材料价值 ×2.2、武器 +1/+2 伤害），全部为试玩初值。

## 1. 目标与非目标

**目标**：铁根矿窟守门战胜利后同局进入第三层「晶脉矿窟」；打穿第三层首领「晶暴君」才算整局 gate_clear 结算。新增：新材料辉晶簇、三阶武器辉晶刃与防具辉晶盾（带回辉晶簇解锁配方）、4 种新敌人＋新首领、2 个新深层事件、稀有植物星瓣花（4 小时档，种价 110，商店 4 级解锁）。

**非目标**：不做选层出发 UI（仍从第一层进入）、不改双人规则与平衡框架、不加新卡牌机制（只加数值档模板）、不动存档结构版本（v7 不变，新内容全是定义表数据）。

## 2. 数值设计表

### 2.1 层与地图（沿用 9 排固定图、第 4 排休整/第 7 排撤离/第 8 排守门的全局约束）

| 层 | depth | 名字 | 特征 |
| --- | --- | --- | --- |
| moss_stone_shallow | 1 | 苔石浅洞 | 不变 |
| iron_root_deeps | 2 | 铁根矿窟（第二层） | 不变（守门后不再结算，改为衔接第三层） |
| crystal_vein_deeps | 3 | 晶脉矿窟（第三层） | 更险：第 3 排战斗在前宝箱在后、第 6 排精英；遭遇用 deep3_pair/deep3_hard |

`LAYER_ORDER := [moss, iron, crystal]`；`next_layer()` 决定守门衔接，末层守门 → gate_clear 结算。

### 2.2 敌人（HP 梯度：L2 普通 20~32 → L3 普通 28~42；首领 60→90）

| id | 名字 | HP | 意图循环 |
| --- | --- | --- | --- |
| vein_crawler | 晶脉爬虫 | 28 | 攻6×2 → 攻9 → 架盾6 |
| void_moth | 暗渊蛾 | 32 | 攻5(易伤1) → 攻7×2 → 攻10 |
| prism_golem | 棱镜魔像 | 42 | 架盾10 → 攻12 → 攻12(虚弱1) |
| crystal_tyrant | 晶暴君（首领） | 90 | 攻7×2 → 架盾12 → 攻16 → 攻6(中毒3层) |

遭遇：`deep3_pair`（爬虫＋蛾）、`deep3_hard`（魔像＋爬虫）、`layer3_elite`（魔像＋蛾）、`layer3_guardian`（晶暴君）。精英/守门按 `node.depth` 泛化为 `layer%d_elite/guardian`。

### 2.3 物品与卡牌（cards 数＝占格数约束；价值梯度 copper 8→iron 18→radiant 40）

| id | 名字 | 类别 | 占格 | 品质 | 价值 | 牌 |
| --- | --- | --- | --- | --- | --- | --- |
| radiant_cluster | 辉晶簇 | material | 1×2 | 2 | 40（可保险箱） | 笨重货物×2 |
| crystal_blade | 辉晶刃 | weapon | 1×3 | 2 | 170 | 晶刃斩(8)×2＋裂石一击(17) |
| crystal_aegis | 辉晶盾 | armor | 2×2 | 2 | 100 | 架盾×2/掩护/稳住（同构高品质） |
| star_bloom_seed | 星瓣花种子 | rare_seed | 1×1 | 1 | 8（不可售） | 笨重货物 |

新卡模板：`slash8` 晶刃斩（1 费 8 伤）、`heavy_strike17` 裂石一击（2 费 17 伤）。铜(6/13)→铁(7/15)→辉晶(8/17)，每阶 +1/+2。

### 2.4 奖励池（结构复刻 L2：个人/公共/精英/采集/宝箱/守门）

- 战斗个人：辉晶簇、铁矿、微光晶石、小药水、辉晶簇（新材料双权重）
- 公共：辉晶簇、铁矿、绷带
- 精英：**辉晶刃**、微光晶石、古旧摆件、救援包
- 采集：辉晶簇×2＋铁矿；宝箱：辉晶刃、微光晶石、辉晶簇、古旧摆件
- 守门固定：**星瓣花种子＋辉晶刃**（对应 L2 的萤果种子＋铁短剑）

### 2.5 制作与目标（零新判定分支：配方解锁走既有 stat 口径）

- `crystal_blade`：45 币＋辉晶簇×3＋铁矿×2；解锁＝带回辉晶簇 ≥1（`stat brought_total`）
- `crystal_aegis`：30 币＋辉晶簇×2＋纤维×2；解锁同上
- `beat_guardian` 目标改名"击穿晶脉矿窟"，条件不变（gate_clears≥1，现在含义=打穿三层），奖励加 **星瓣花种子×1**

### 2.6 植物（档位链 60 分钟→120 分钟→240 分钟）

`star_bloom` 星瓣花：grow 14400s、base_score 2600、crop_count 4、seed_price 110、water_segments 2、encounter_count 2、harvest_exp 260、unlock 种地 2 级＋**商店 4 级**（顶格）。链路：守门/事件种子 → `seed_item_to_plant` → 播种解锁 → 市场 cave_kind 公式。

### 2.7 事件（DEEP_EVENTS 4→6）

- `resonant_vein` 晶脉共振：搬开晶壳（失 6 生命，辉晶簇×2）／离开
- `star_plant` 深渊花圃：取种（星瓣花种子）／敲晶（微光晶石）／不动

### 2.8 版本

`ExpeditionBaseline.PROTO_RULES_VERSION`：d2-baseline-v0.1 → **v0.2**（内容变更；合作握手按版本拒绝不匹配客户端）。

## 3. 代码接入点（改逻辑处仅 4 个文件）

1. `expedition_defs.gd`：LAYERS 加 crystal＋全层加 depth；LAYER_ORDER/next_layer；L3 池；battle_pools 改表驱动；新增 gate_rewards(layer_id)；DEEP_EVENTS＋2；events_for_node/encounter_for 泛化 depth
2. `expedition_game.gd`：`_resolve_node` 置 node.depth（保留 deep 兼容）；守门奖励按层取；`leave_node` 层衔接改 LAYER_ORDER 通用链；衔接日志用层名格式化
3. `farm_game.gd`：seed_item_to_plant 加星瓣花；市场 cave_kind 列表加 star_bloom
4. `expedition_baseline.gd`：规则版本号升级
5. 纯数据：`combat_game.gd`（敌/遭遇）、`card_defs.gd`（2 模板）、`item_defs.gd`（4 物品）、`crafting_defs.gd`（2 配方＋目标改名）、`plant_defs.gd`（star_bloom）

## 4. 测试计划

- 更新 `d28_content_smoke.gd`：内容预算 24 物品/19 卡/9 敌/6 深事件；第二层守门 → **衔接第三层**（原 gate_clear 断言移到第三层守门后）；新增第三层预算断言
- 更新 `d21_defs_smoke.gd:50`：卡模板 17→19
- 新增 `d40_crystal_layer_smoke.gd`：三层链路（进第三层→节点按 L3 池裁定含辉晶簇→守门晶暴君→gate_clear）；辉晶刃配方解锁与制作；星瓣花种子→种植→市场→收获全链；晶暴君 90 血与首意图
- 全量回归 + 证据 `docs/testing/crystal_layer_d40/`

## 5. 风险与回退

- 第三层难度靠数值外推，未经真人试玩；可能偏难（守门 90 血 vs 玩家 40 HP＋辉晶刃）——留待试玩调参，不改机制。
- 旧进行中的局档（rules_version v0.1）在升级后仍按原 layer 链跑：第二层守门会进第三层（地图重建不依赖旧档内容），行为可接受；合作双方必须同版本。
- 回退：revert 单次提交即可；无存档迁移。

## 6. 后续接口（本轮不做）

选层出发（expedition_hub UI）、第四层与新卡机制、辉晶系消耗品、星瓣花专属词条线。

## 7. 工作量

定义表 6 文件＋逻辑 4 文件＋测试 3 件，预估 1 轮会话完成。

## 8. 实施记录（2026-10-02）

- 按本计划完成：定义表 6 文件（expedition_defs/combat_game/card_defs/item_defs/crafting_defs/plant_defs）＋逻辑 4 文件（expedition_game 层衔接通用化与 depth 泛化、farm_game 种子与市场、expedition_baseline 版本 v0.2）＋UI 一处（farm_hud `CROP_ICONS` 补 star_bloom 占位图标——探索报告未列入，d36 回归暴露后补）。
- 测试：d28 更新（预算 24 物品/19 卡/9 敌/9 事件、通关断言移到第三层、晶暴君 90 血）、d21/d23 预算断言更新、新增 d40 全链（定义/敌人/配方/目标/星瓣花种植共 26 断言）。
- 全量回归 46 项全过（`REGRESSION_ALL_PASS`）；证据 `docs/testing/crystal_layer_d40/`。
- 实施偏差：无设计变更；唯一的计划外改动是 farm_hud 图标表（同款占位图复用，符合既有萤果/岩芽做法）。
- 实机验收待用户：第三层实际难度（数值外推未试玩）、商店第 4 级升级后购买星瓣花种子、地图页第三层名字与事件文案显示。
