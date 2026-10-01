# 2.5 农场衔接与长期成长：代码执行计划 v0.1

日期：2026-10-01。状态：未开始。适用工程：Godot 4.6.1（GL Compatibility）、Windows、现有 farm 工程。

导航：[整体开发计划](../Godot_第二大阶段_农场与合作洞窟_整体开发计划_v0.1.md)｜[2.5 详细设计](../design/Godot_阶段2.5_农场衔接与长期成长_详细设计_v0.1.md)｜[设计索引](../design/第二大阶段详细设计索引.md)｜[代码计划索引](第二大阶段代码执行计划索引.md)｜上游代码计划：[2.1](Godot_阶段2.1_规则基线与工程基础_代码执行计划_v0.1.md)｜[2.4](Godot_阶段2.4_单人洞窟与撤离闭环_代码执行计划_v0.1.md)

本文把 2.5 详细设计拆成可执行的 Godot 代码任务，并遵守 [2.1 代码计划](Godot_阶段2.1_规则基线与工程基础_代码执行计划_v0.1.md)附录 A 的全阶段工程约定与模块地图（结果字典、注入时间/随机数、测试命名 `tests/d25_*.gd`、模块地图 2.5 列：`crafting_defs.gd`＋`crafting_game.gd` 新增，农场既有文件与 UI 面板扩展）。设计内容（配方、价格、植物数值、界面行为）以详细设计为准，本文不重述数值，只引用 `D2.5-XX` 功能号。本阶段大量改动农场既有文件（`plant_defs.gd`／`farm_game.gd`／`market_defs.gd`），文件中现有字段名以当前代码为准引用。

## 1. 输入与前置

- 上游 2.1 交付物（文件级，本文直接依赖）：
  - `scripts/domain/expedition_baseline.gd`：容器尺寸与加入回合常量（本阶段扩容经其查询函数生效）；`scripts/domain/item_defs.gd`＋`card_defs.gd`：物品字段（含 `sellable`、保护资格、来源牌序列）与 `ItemDefs.is_basic` 基础装备标记。
  - `scripts/domain/inventory_game.gd`：`warehouse`（装备/材料库存）、`loadout`、`occupied_by_run`、`owner_of` 归属唯一、`grant_basic_kit` 补领。
  - `scripts/services/expedition_store.gd`：结算 ID 与 `applied_settlements` 去重；`scripts/domain/farm_game.gd`：`SAVE_VERSION`（2.1 后为 6）＋`expedition` 块。
  - `scripts/world/farm_world.gd` 的三个可点击占位之一：**制作台（"尚未开放"）——本阶段转正**。
- 上游 2.2/2.3 交付物：`combat_game.gd`、`deck_builder.gd`；`item_defs.gd` 的 12～16 种物品（铜片、纤维、药水、古旧摆件等材料与货物）与消耗品实体次数规则。
- 上游 2.4 交付物：`expedition_game.gd`（出发占用/撤离/死亡/结算事务）、结算面板与结算回写、`farm_game.gd` 的待领取区扩展、结算中的"带入返还 vs 新获得"分组数据（D2.5-01 的输入）。
- 设计功能范围：D2.5-01 回家收获大厅、D2.5-02 装备与材料仓库、D2.5-03 制作台（首批八配方）、D2.5-04 设施与容器成长、D2.5-05 稀有植物完整接入、D2.5-06 目标看板与一次性奖励、D2.5-07 商店与经济底线。
- 明确不在本阶段做：
  - 双人 2.6：救援包的合作使用、目标"一起回家"与"第一次合作胜利"的**事件源**（目标定义本阶段落地，显示为未开始）、物品分享（分享防套利只在 `ItemDefs` 标记上预留）。
  - 第二层内容 2.8：铁矿／微光晶石的实际获取来源、"击败守护者"事件源；因此"铁短剑""保险箱扩展"等以铁矿为成本的配方/升级**本阶段只定义与展示**，不可达成是预期行为。
  - 属性影响药效（设计 §6 明确另立规则）、携带堆叠（总计划 §4.2）、出发与结算本身（2.4 已交付）。
- 编码前必须落定（总计划 §14）：新植物正式名称与形象（"岩芽菜／rock_sprout"为暂名）；免费基础装备补领条件表（本计划 W1 落成配置，试玩后回填交付报告）。
- 功能号到工作包的映射（设计 → 拆解）：

| 功能号 | 内容 | 主要工作包 | 关键上游依赖 |
| --- | --- | --- | --- |
| D2.5-01 | 回家收获大厅 | W7 | 2.4 结算事务、`applied_settlements`、待领取区 |
| D2.5-02 | 装备与材料仓库 | W6、W8 | 2.1 `inventory_game`、2.3 物品池 |
| D2.5-03 | 制作台（八配方） | W1、W2、W8 | 2.1 制作台占位、`item_defs` |
| D2.5-04 | 设施与容器成长 | W1、W3 | 2.1 `expedition_baseline` 容器尺寸 |
| D2.5-05 | 稀有植物完整接入 | W5 | 2.4 结算带回记录、农场既有 `plant/breeding/market` 体系 |
| D2.5-06 | 目标看板与一次性奖励 | W1、W4、W8 | 2.4 结算事件源 |
| D2.5-07 | 商店与经济底线 | W1、W6、W9 | `MarketDefs` 折扣口径、`stage6_economy_sim` 传统 |

## 2. 新增与修改的工程结构

| 文件 | 动作 | 责任 | 预估规模 |
| --- | --- | --- | --- |
| `scripts/domain/crafting_defs.gd` | 新增 | 八配方表、五项设施升级表、八目标表（判定类型/参数/奖励/旧档补记规则）、金币成本不受折扣的标记、基础装备发放策略引用 | ~220 行 |
| `scripts/domain/crafting_game.gd` | 新增 | 制作事务（预览/扣料/产出/满仓）、设施升级事务、目标进度记录与一次性发奖、新植物种类解锁登记、制作类经济记录 | ~380 行 |
| `scripts/ui/crafting_panel.gd` | 新增 | 制作台面板（D2.5-03：类别/解锁态/材料拥有量/批量预览/批次指定；2.1 占位转正） | ~350 行 |
| `scripts/ui/gear_warehouse_panel.gd` | 新增 | 装备与材料仓库面板（D2.5-02：双区/筛选排序/锁定/出售/加入战备/比较） | ~380 行 |
| `scripts/ui/harvest_hall_panel.gd` | 新增 | 回家收获大厅（D2.5-01：摘要/分类/跳详情/待领取区分批领取） | ~300 行 |
| `scripts/ui/growth_board_panel.gd` | 新增 | 成长看板（D2.5-06：目标完成条件/进度/领奖状态、已解锁资源、下一目标） | ~180 行 |
| `scripts/domain/plant_defs.gd` | 修改 | `PLANTS` 新增 `rock_sprout` 条目（沿用现有字段：`display_name`/`grow_seconds`/`base_score`/`crop_count`/`seed_price`/`water_segments`/`encounter_count`/`harvest_exp`/`unlock_farming_level`/`unlock_shop_level`）；新植物是否可购的判定辅助 | +35 行 |
| `scripts/domain/market_defs.gd` | 修改 | 新植物市场参数（偏好倍率 1.0 即"无偏好客人"、公式沿用现有池的说明常量）；若设计澄清后需要，公式锁的放宽开关 | +15 行 |
| `scripts/domain/farm_game.gd` | 修改 | `SAVE_VERSION` 升 7＋v6→v7 迁移；`refresh_market` 的种类遍历由硬编码 `["cabbage","carrot"]` 改为"已解锁植物种类"；`seed_lock_reason`/`buy_seeds` 增加新植物门槛（首次收获前不可购）；`harvest` 结果补足目标事件所需字段；金币/台账入口保持兼容 | +120 行 |
| `scripts/domain/item_defs.gd` | 修改 | 补给类成品定义（白菜汤/绷带/岩芽药剂/救援包）；装备类成品补"可制作"用途标记与 `buy_price`（小药水/铜剑，D2.5-07）；`BASIC_KIT_GRANT_RULES` 补领条件集中配置；`sellable=false`＋不可作制作输入的防套利校验函数收口 | +80 行 |
| `scripts/domain/inventory_game.gd` | 修改 | `warehouse` 拆装备区/资源区（叠层 99、条目容量随战备仓储等级）；筛选/排序数据出口；条目锁定；出售事务（写金币与台账）；待领取区查询与分批领取；"加入战备"跳转数据 | +200 行 |
| `scripts/domain/expedition_baseline.gd` | 修改 | 容器尺寸改为"基线默认＋设施覆盖"查询（胸挂 3×4→4×4、背包 4×4→4×5、保险箱 1×2→2×2 经存档设施位生效，基线常量保留默认值） | +25 行 |
| `scripts/world/farm_world.gd` | 修改 | 制作台占位改为打开 `crafting_panel`；仓库建筑入口分流（作物/种子面板不动，新增装备与材料分区入口）；探险返回后的农场刷新接线点 | +40 行 |
| `scripts/ui/farm_hud.gd` | 修改 | 挂接四个新面板的 modal 打开/关闭（只挂接不内联） | +30 行 |
| `scripts/ui/loadout_panel.gd` | 修改 | 接收仓库面板"加入战备"跳转并高亮目标容器 | +30 行 |
| `tests/d25_*.gd` 7 份 | 新增 | 见 §5 | 共 ~500 行 |

## 3. 数据与存档

### 3.1 存档版本迁移

- `FarmGame.SAVE_VERSION` 6→7（若 2.4 落地时已升 7，则顺延为 8，迁移逻辑不变；见 §6 待澄清）。`_migrate_v6_to_v7`：
  - 原字段零改动搬运；追加 `crafting` 块（见 3.2）。
  - `expedition.inventory.warehouse` 由扁平实例表拆为 `{equipment: […], resource: […]}` 两区：按 `ItemDefs` 类别归区（武器/防具/工具→装备区；材料/补给/货物→资源区），实例 ID 与归属不变，拆分不改变 `owner_of` 语义（仍是 `warehouse`，区只是仓库内分区）。
  - `market.formulas` 不迁移新键：`refresh_market` 只为"已解锁种类"生成公式，旧档首次解锁岩芽菜后的下一个北京日才出现该键，客人抽取随机流不受影响（见 §6 风险）。
  - `crop_batches` 的批次锁定用 `.get("locked", false)` 读取，不迁移字段。
- 迁移失败返回 `false` 并提示恢复选项，不静默新建（沿用现有行为）。

### 3.2 `crafting` 块（本阶段声明后落码）

```text
crafting: {
  unlocked_recipes: [String]      # 已解锁配方 id（八配方之外预留给后续阶段）
  goals: {                        # 目标记录：完成条件/进度/领奖状态（总计划 §7.3）
    <goal_id>: {
      progress: Dictionary        # 计数型进度，如 {copper_brought: 6}
      done_at: int                # 0=未完成；完成时刻
      claimed_at: int             # 0=未领奖；奖励只发一次
    }
  }
  facilities: {                   # 设施等级/一次性扩展（D2.5-04；失败不退级=只增不减）
    storage_level: 1              # 战备仓储 1/2/3 → 两区各 40/80/160 条目
    pack_extended: false          # 背包 4×4→4×5
    chest_extended: false         # 胸挂 3×4→4×4
    safe_extended: false          # 保险箱 1×2→2×2，最多一次
  }
  plant_unlocks: {                # 新植物解锁登记（D2.5-05）
    rock_sprout: {kind_unlocked_at: int, first_harvest_at: int}   # 0=未发生
  }
  craft_log: [{t, recipe, count}] # 制作记录（目标判定与经济分析用，截断上限 200 条）
}
```

- 单一写者：`state["crafting"]` 只由 `CraftingGame` 写；`FarmGame.seed_lock_reason`/`buy_seeds`/`refresh_market` 对 `plant_unlocks` **只读**（跨块只读访问，写一律经 `CraftingGame`，保证解锁与购种门槛不出现双写）。
- 目标"发现类按带回记录判定"：判定输入是 2.4 结算结果中的"新增战利品"清单（含保险箱保住的种子，设计 §6），不是农场库存；旧档已有的库存物品不补记带回类目标，仅 `legacy_rule != "none"` 的教学/收获类目标允许补记（明示规则落在 `CraftingDefs.GOALS` 每条 `legacy_rule` 字段）。
- 台账沿用 `FarmGame._record_ledger` 的字段形状 `{t, day, reason, amount}`，新增 reason：`craft_<recipe>_x<n>`（负）、`facility_<id>`（负）、`sell_item_<def>`（正）。`inventory_game.gd` 的出售事务与 `crafting_game.gd` 的制作/升级事务是 `FarmGame` 之外仅有的两个金币写入口，台账形状由测试断言一致。

### 3.3 物品与条目结构

- 资源区叠层条目：实例保留 `instance_id` 与归属（A3 红线"同一实例单一归属"不变），同 `def_id`＋同品质实例归入同一**叠层**，叠层 `count ≤ 99`，条目数计容量；带入洞窟时从叠层按实体单位逐实例取出（2.3 的"携带不堆叠"口径不变）。装备区逐件一条目。
- 新植物进入现有定义表的方式（全部沿用现有字段，不新增植物侧字段）：
  - `PlantDefs.PLANTS["rock_sprout"]`：60 分钟档（`grow_seconds`）、`base_score` 600、`crop_count` 5、`water_segments` 1、`encounter_count` 2、`harvest_exp` 60、商店基础种子 `seed_price` 30；`unlock_farming_level`/`unlock_shop_level` 填 1（真正的门槛是 `plant_unlocks`，见 W5）。
  - 后代种子 2～3 粒：现有 `_roll_round` 的 `seed_count = randi_range(2, 3)` 已是植物无关实现，不改。
  - 遭遇：复用 `ENCOUNTER_TIERS`/`ENCOUNTER_TEXTS` 与 `encounter_count`，无需新表。
  - 词条：`BreedingDefs.EFFECTS` 六词条为属性无关实现，岩芽菜直接适用（设计明确"不另做战斗词条种子"）。
  - 市场：`refresh_market` 遍历" cabbage、carrot 之后追加已解锁种类"，公式类型/系数沿用 `SINGLE_COEFFICIENTS` 等现有池；偏好倍率 1.0 由"没有任何 `GUESTS.preferred_kind == rock_sprout`"自然成立，不改 `quote`。
  - 基础种子无词条：`_new_seed(kind)` 默认 `traits = []`，购种路径即无词条基础种子。

### 3.4 兼容与测试档

- 未知版本仍拒绝加载并提示（现有行为）；v7 档直接加载不触发迁移分支；`version == 8`（若 2.4 已占 7 则为 9）拒绝——该断言进 `tests/d25_plant_smoke.gd` 的迁移部分。
- 测试档一律自定义路径注入（`user://d25_*.json`），不碰真实 `farm_save_v1.json`（A1-6）；`craft_log` 截断上限 200 条，与 `ledger` 的 400 条同思路，防存档无限膨胀。
- 本阶段不改 `SaveStore` 三段式写法；制作/升级/出售/领奖四个事务的存档保存点都在组合根（`farm_world.gd`）事务返回后立即触发，与 2.4 结算应用的保存节奏一致。

## 4. 工作包拆解

W1→W9 为建议实施顺序：W2/W3/W4 依赖 W1；W5 依赖 W4（解锁登记）；W6 可与 W2~W5 并行；W7 依赖 W6；W8 依赖 W2~W7；W9 收尾。

### W1 配方、设施、目标与发放策略定义表（D2.5-03/04/06/07）

- 依赖：无（纯新增定义，可与任何工作包并行启动）。
- 文件：`crafting_defs.gd`、`item_defs.gd`（扩展）。
- 要点：
  - `RECIPES`：八个配方逐项对应设计 §4 表——`{product, product_count, coin_cost, inputs: [{source, id, count}], unlock: {kind, goal_or_event}, category, desc}`；`source` 区分 `item`（装备/材料实例）与 `crop`（作物批次，按 `kind` 消耗数量）；`coin_cost` 带"不受商店折扣"标记（D2.5-03 末段）。救援包定义 `single_entity_use` 与"自用转换预览"文案字段，实际双人用途等 2.6。
  - `FACILITY_UPGRADES`：五项（战备仓储 1→2/2→3、背包、胸挂、保险箱），含成本（金币＋材料 def 与数量）、效果描述键、一次性标记。
  - `GOALS`：八个目标 `{condition_kind, params, reward, legacy_rule}`；`condition_kind` ∈ `settlement_event / craft_event / farm_event / coop_event(2.6) / boss_event(2.8)`；`legacy_rule` ∈ `none / tutorial_backfill`（带回类一律 `none`，设计 §7）。
  - 免费基础装备收口（总计划 §14"2.5 结束"项）：`item_defs.gd` 新增 `const BASIC_KIT_GRANT_RULES`（首次全赠；补领=部件缺失且该部件不在活动局占用；每种限一件——沿用 `grant_basic_kit` 现行行为，只是把条件从代码移进配置）；防套利三处统一读 `ItemDefs.is_basic(def_id)`：出售（W6）、制作输入校验（W2）、分享（2.6 预留标记）。
  - `item_defs.gd` 补 `buy_price`（小药水 8、铜剑 70，D2.5-07）与不变式校验函数：`discounted_total(buy_price, MAX_SHOP_LEVEL) >= sell_value`（折扣后最便宜购买不低于出售收入）。
- 验证：`tests/d25_crafting_smoke.gd` 第一部分——八配方字段齐全且材料/成品 `def_id` 都存在于 `ItemDefs`；配方解锁引用的目标 id 存在；价格不变式对全部带 `buy_price` 定义成立；救援包/铁短剑标记为"事件源未开放"。

### W2 制作事务（D2.5-03；总计划 §7.2）

- 依赖：W1（配方表与防套利标记）。
- 文件：`crafting_game.gd`。
- 接口草案：

```gdscript
class_name CraftingGame extends RefCounted
func bind(state: Dictionary) -> void                 # 绑定整个 game.state：只写 state["crafting"]，
                                                     # 制作/升级事务内事务性写 coins/ledger/crop_batches/inventory
func recipe_status(recipe_id: String) -> Dictionary  # 解锁态、拥有/需要量、可制作次数、缺口清单（材料不足可看来源）
func preview_craft(recipe_id: String, count: int, batch_plan: Dictionary) -> Dictionary
    # 无副作用：整批总花费与成品数、输出占仓、预计进待领取区的件数（设计 §4"事先说明"）
func craft(recipe_id: String, count: int, batch_plan: Dictionary, now: int) -> Dictionary
    # 一次事务：校验（解锁/材料/金币/非 basic 输入/占用过滤）→ 扣材料与金币 → 产成品入仓或待领取区
func cancel_hint(recipe_id: String) -> Dictionary    # 取消=预览阶段退出，无任何扣费路径
```

- 实现要点：
  - 防重复：制作**无持久化中间态**——`craft` 在单次调用内完成"扣料＋产成品"，成功即落存档点，不存在"已开始未完成"的存档状态，因此重启不可能重复制作；连续点击由 UI 在事务返回前禁用按钮（W8）＋事务本身重校验材料（第二次调用因材料不足被拒，`reason` 可读）。
  - 取消不扣费：确认页之前所有操作走 `preview_craft`（纯读）；确认后成功不因关闭面板退料（设计 §4）。
  - 满仓：`preview_craft` 先算输出空间，放不下的件数明示进待领取区；待领取区也满（或成品为不可入待领取的类型）则在扣费前拒绝（总计划 §7.2"满仓产物进待领取区或在扣费前拒绝"）。
  - 作物材料：`batch_plan` 允许手动指定批次，默认策略"低 `per_crop_score` 且未锁定批次优先"；扣的是批次 `count`（同 `sell_batch_to` 的减量口径），剩余批次属性原样、不同批次不合并；材料够但批次全锁定时返回需手动选择的 `reason`，不静默消耗（设计 §10）。
  - 活动局占用：`occupied_by_run` 非空时，位于 `loadout` 的材料不计入拥有量；待领取区物品不计入可用数量（设计 §10、2.4 §8）。
  - 金币不足不自动变卖任何资产（设计 §4），只给缺口与"跳转集市"事件号。
  - 制作不掷随机数，`now` 仅用于台账与解锁时间戳（结果确定，便于测试与 2.6/2.7 重放）。
- 验证：`tests/d25_crafting_smoke.gd` 第二部分——固定状态制作铜短剑：材料/金币扣减与成品入库在同一次调用后一致；重复调用第二次被拒且状态不变；`preview` 前后存档逐字节相等；满仓路径产出进待领取区、扣费前拒绝路径不扣金币；作物批次按低分优先消耗且锁定批次不被静默消耗；basic 物品作输入被拒。

### W3 设施升级事务与容量生效（D2.5-04）

- 依赖：W1；与 W2 共用占用过滤与台账写入（同文件内实现）。
- 文件：`crafting_game.gd`、`expedition_baseline.gd`、`inventory_game.gd`（读容量）。
- 接口草案：

```gdscript
func facility_status() -> Dictionary                       # 各项当前级/成本/已满标记/预览效果（新布局与实际效用）
func upgrade_facility(id: String, now: int) -> Dictionary   # 校验金币+材料（占用过滤同 W2）→ 扣费 → 写 facilities，只增不减
static func effective_container_size(container: String, facilities: Dictionary) -> Vector2i
    # 落 expedition_baseline.gd：默认基线尺寸 + 扩容覆盖；战斗/牌组/整理统一改查此函数（A3 红线的登记见 §6）
```

- 要点：升级永久保留（失败不退级＝事务成功才落档，无回滚路径）；容器不是物品、不产牌、扩容不赠装备（设计 §5）；保险箱扩展影响经济最大，等级位单独可查以支撑经济模拟观察。
- 验证：`tests/d25_crafting_smoke.gd` 第三部分——战备仓储 1→2 后两区条目容量 40→80；背包扩容后 `effective_container_size("pack")` 为 4×5 且 `deck_preview` 分组不变；重复升级同项被拒；材料不足时金币不扣。

### W4 目标成长与一次性奖励（D2.5-06；总计划 §7.3）

- 依赖：W1；事件源字段以 2.4 结算结果的实际形状为准（开工前对照 2.4 交付代码核对一次）。
- 文件：`crafting_game.gd`。
- 接口草案：

```gdscript
func goals_snapshot() -> Dictionary                  # 每目标：完成条件文案、进度、完成时刻、领奖状态、奖励预览
func record_event(event: Dictionary, now: int) -> Dictionary
    # 事件源（由组合根 farm_world 转发）：2.4 结算结果（撤离/死亡/新增战利品/保险箱保住物）、
    # W2 制作成功、farm 收获（kind）、2.6/2.8 预留事件类型
func claim_goal_reward(goal_id: String, now: int) -> Dictionary   # 只发一次：claimed_at>0 时拒绝
func plant_kind_unlocked(kind: String) -> bool       # 供 FarmGame 只读（含保险箱带回种子的解锁，设计 §6）
```

- 要点：完成与领奖分轨（看板两列显示）；发现类按结算"新增战利品"判定，保险箱保住的岩芽菜种子计为带回、可解锁种类，但不计"第一次安全回家"（死亡结算）也不冒充"共同撤离"；制作类按 `craft_log` 判定；旧档补记仅 `legacy_rule == "tutorial_backfill"` 的目标在 `bind` 后首次 `record_event` 前扫描一次存档状态完成，带回类永不以库存补记（设计 §7）；`一起回家`/`击败守护者` 本阶段显示条件但无事件源（§1）。
- 验证：`tests/d25_goals_smoke.gd`——八个目标的判定/进度/领奖各一条正反用例；同一结算重复 `record_event`（含 `applied_settlements` 重放场景）不重复推进；旧档已有铜片库存不完成"发现铜片"；领奖两次被拒；保险箱种子解锁种类但不触发安全回家目标。

### W5 稀有植物完整接入农场（D2.5-05；总计划 §7.1）

- 依赖：W4（`plant_unlocks` 登记入口）；正式名称与素材须在本工作包开工前落定（§1、§6 待澄清 1）。
- 文件：`plant_defs.gd`、`farm_game.gd`、`market_defs.gd`、`farm_world.gd`/`farm_hud.gd`（文案与素材）。
- 要点：
  - 定义条目按 §3.3 落地（只加 `PLANTS` 一条＋辅助函数，不动既有两键与随机流）。
  - 解锁链：结算带回第一粒种子（含保险箱）→ `plant_unlocks.kind_unlocked_at` → `refresh_market` 开始为该种类生成公式、配方/仓库/出售界面可见该种类；第一次真实收获 → `first_harvest_at` → `seed_lock_reason` 放行、商店出现无词条基础种子（`buy_seeds` 走 `_new_seed` 默认空词条）。
  - `farm_game.gd` 改动点：`refresh_market` 的 `for kind in ["cabbage","carrot"]` 改为 `["cabbage","carrot"] + 已解锁额外种类`（顺序固定，保证旧两键的公式随机流逐日不变）；`seed_lock_reason` 增查 `plant_unlocks`（未解锁种类返回"尚未带回这种种子"）；`harvest` 返回值已含 `kind`/批次字段，组合根据此转发 `record_event`。
  - 新植物"配齐"清单式核对（总计划 §7.1"不能只加入一个可以获得但无法播种的种子"，缺一项不得合并该工作包）：
    1. 基础生长配置：`PLANTS["rock_sprout"]` 十字段全部就位（§3.3 列出的现有字段名，一个不少、一个不造）。
    2. 词条适用性：`BreedingDefs.EFFECTS` 六词条（水分/纤维/色泽的保底与倾向）对岩芽菜生效，`TRAIT_LIMIT` 现行口径不变。
    3. 遭遇：`encounter_count` 2 条正向遭遇，档位与文案沿用 `ENCOUNTER_TIERS`/`ENCOUNTER_TEXTS`（或经设计确认另配专属文案）。
    4. 经验：收获经验进 `farming_exp` 与 `plant_exp["rock_sprout"]` 双轨，等级加分沿用 `LEVEL_BONUS_PER_LEVEL` 播种快照。
    5. 市场报价：解锁后每日生成公式（沿用现有系数池）、默认出售 1.2 倍、金克拉 `sale_multiplier_bonus` +0.2、单客偏好 1.0。
    6. 育种：`set_breeder_template`/`breeder_settle`/`collect_breeder` 对该种类按现行规则可复制，后代种子进原种子区。
    7. 仓库与种子区：稀有种子保留词条与原叠放口径，不在资源区复制；`seed_slots` 计数包含新种类。
    8. 模型/图标/文案：成熟模型、生长分段表现、种子图标、教学提示齐全；资产登记进 `assets/stage1_manifest.json` 同套盘点。
    9. 用途闭环：岩芽药剂配方（第一茬解锁）与"卖高分菜还是消耗作药"的比价关系可被玩家看到（W8 制作台/仓库显示）。
  - 探险期间农场时间接线点：现有 `farm_game` 全部以注入 `now` 计算（`is_ready`/`mature_plot_ids`/`watering_status`/`refresh_market`），农场无需"离线结算"代码；接线点只有一处——2.4 回到农场场景时组合根用挂钟 `now` 调 `refresh_market(now)` 并刷新 HUD（2.1-W7 已固化"农场时间只由真实挂钟驱动"）。本阶段补回归证明（见 W9 测试）。
- 验证：`tests/d25_plant_smoke.gd`——解锁前购种被拒／公式不生成；带回种子后次日公式出现且 cabbage/carrot 同日公式与旧代码口径一致（固定种子对照）；播种→浇水（1 时段）→ 60 分钟成熟→收获 5 作物＋2~3 后代种子＋经验 60；后代种子可进育种机；`quote` 对岩芽菜单客倍率 1.0、金克拉批次 +0.2；跨北京日刷新（`MarketDefs.day_index` 口径）；"出发时在生长、返回时已成熟"用注入 t0/t1 两时点断言。

### W6 装备与材料仓库与防套利收口（D2.5-02；总计划 §7.2）

- 依赖：2.3 物品池与消耗品实体规则就绪；与本阶段 W2~W5 可并行。
- 文件：`inventory_game.gd`（主要）、`item_defs.gd`（W1 已扩）。
- 接口草案：

```gdscript
func warehouse_zones() -> Dictionary     # {equipment: {entries, capacity}, resource: {…}}，容量读 facilities.storage_level
func warehouse_view(filter: String, sort: String) -> Array
    # filter: all/weapon/armor/tool/supply/material/goods（材料支持"可制作"标记，读 CraftingGame.recipe_status）
func set_entry_locked(instance_id: int, locked: bool) -> Dictionary
func sell_from_warehouse(def_id: String, quality: int, count: int, now: int) -> Dictionary
    # 事务：校验（可售/未锁定/非 basic/非预设占用/非活动局占用）→ 移除实例 → coins += 固定售价值×数 → 台账
func sell_batch_preview(filters: Dictionary) -> Array   # 批量出售预览清单（排除稀有种子、预设装备、锁定物）
func pending_summary() -> Dictionary    # 待领取区：物品、来源局、未入仓原因
func claim_pending(limit: int) -> Dictionary   # 批量领取只拿放得下的部分，余量留待领取区
```

- 要点：装备区逐件、资源区叠层 99（§3.3）；作物区/种子区完全不动，稀有种子不复制进资源区；固定售价值用 `ItemDefs` 字段，不进白菜/胡萝卜每日客人公式；基础装备与活动局占用物不可出售（`is_basic` 收口）；"保护和活动局占用有明显标签"由视图数据给出标记位。
- 验证：`tests/d25_warehouse_smoke.gd`——两区容量 40 与叠层 99 边界；`owner_of` 在归区/领取/出售后仍唯一；basic 物品出售被拒；锁定条目批量出售预览不包含；出售后金币与台账形状与 `FarmGame` 一致；带词条稀有种子只出现在种子区。

### W7 回家收获大厅与待领取区（D2.5-01）

- 依赖：W6（待领取区数据出口）、2.4 结算面板与结算档。
- 文件：`harvest_hall_panel.gd`（UI）、`inventory_game.gd`（W6 已给数据出口）、`farm_world.gd`（入口接线）。
- 要点：探险结算应用后先弹摘要（2.4 结算面板的后续屏），分类为装备/材料/补给/货物/种子，带入返还与新增获得分组；每件可跳详情与用途（"铜片：可制作铜短剑，还缺 1 份"——读 `recipe_status` 缺口）；入口按钮"整理入仓/查看制作/查看种子/关闭"；已完成结算的摘要可从记录重看、不再提供第二次领取（读 `applied_settlements` 对应结算档）；待领取区显示未入仓原因与来源局，批量领取分批（W6 `claim_pending`），"完成结算"按钮不因满仓锁死。
- 验证：`tests/d25_pending_smoke.gd`——满仓结算后待领取区正确承接；分批领取后余量保留；对已应用结算重开大厅不产生新领取；种子类待领取进原种子区。

### W8 三个面板落地与场景接线（D2.5-02/03/06）

- 依赖：W2~W7 全部规则出口就绪后接线。
- 文件：`crafting_panel.gd`、`gear_warehouse_panel.gd`、`growth_board_panel.gd`、`farm_world.gd`、`farm_hud.gd`、`loadout_panel.gd`。
- 要点：
  - 制作台：`farm_world` 的制作台占位从"尚未开放"改为打开 `crafting_panel`（2.1 占位转正）；面板按设计 §4：类别页签、未解锁配方显示成品与获取途径但无制作按钮、选择配方列成品/数量/占仓/生成牌/金币/材料拥有量、材料不足看来源、金币不足发"跳转集市"事件；批量制作用 W2 的整批预览；制作事务期间禁用按钮（防连点）；金币成本旁标"不受商店折扣"，购买商品旁标折扣后价格（防误解，D2.5-03 末段）。
  - 仓库面板：双区＋筛选（全部/武器/防具/工具/补给/材料/货物）＋排序（最近获得/名称/价值/用途）；逐件与指定数量出售带卖价与预设影响提示；收藏/锁定；批量出售先预览清单再确认；"加入战备"跳 `loadout_panel` 并高亮，"比较"并排两件装备详情。
  - 成长看板：目标列表（完成条件/进度/领奖按钮）、已到达层数（读 2.4 记录）、已解锁配方/植物/设施汇总、下一目标建议；2.6/2.8 事件源的目标显示"合作玩法未开放/深层未开放"。
  - 全部代码构建、独立文件，挂 `farm_hud` modal 体系（A1-3）。
- 验证：`tests/capture_d25_panels.gd` 截图（制作台已解锁/未解锁两态、仓库双区、看板）进 `screenshots/`；`tests/world_picking_smoke.gd` 思路确认新增入口不影响原拾取。

### W9 经济模拟、全量回归与交付（D2.5-07；总计划 §7.4、§10-2.5）

- 依赖：W1~W8 全部；经济模拟依赖 2.4 的 `expedition_game` 可脚本化驱动。
- 文件：`tests/d25_economy_sim.gd`、交付报告。
- 要点：
  - 延续 `tests/stage6_economy_sim.gd` 传统：`extends SceneTree`、固定随机种子、受控时间推进、打印锚点对照、`quit(0)`。模拟三种出发方式（总计划 §7.4）：基础装备（免费套装＋至多 1 瓶药水）、普通（铜短剑＋皮护腕＋2 补给）、高成本（铁剑＋加固盾＋更多补给——材料经 2.4 奖励表注入，铁矿路径以假设值标注）；脚本化决策策略（第 4 排撤离／第 7 排撤离／打穿）各跑 N 局，输出每策略：携带成本（可售价值口径）、消耗补给、带回价值、丢弃、死亡损失、净收益、解锁进度（推进到哪个配方/设施）。
  - 锚点核对：早期 1～3 次普通撤离可推进一个基础制作目标（总计划 §12.2）；制作不套利（设计 §9 算例：铜剑总成本视角 44 ≥ 售 40）；低成本局失败后仍可再出发（净损失不摧毁再出发能力）。
  - 全量回归：农场既有回归（stage1～stage6 全部测试＋`world_picking_smoke`，即总计划"原八项回归"口径）＋ d21~d24 各阶段测试＋本阶段 7 份。
  - 实机验收按 §5 清单执行并记入交付报告；未做的检查写"未验证"。
  - 交付物：`docs/archive/Godot_阶段2.5_交付报告.md`（含经济模拟报告章节、实际采用数值与调整原因、容器扩容在基线的登记说明、免费基础装备条件结论——总计划 §14 两项在本阶段收口）；更新总计划 §10-2.5 状态与 `docs/README.md`、根 `README.md`。
- 验证：模拟脚本输出完整、锚点结论成文；全量测试零失败。

## 5. 测试与验收汇总

| 测试 | 覆盖 | 对应总计划 §12.1 |
| --- | --- | --- |
| `tests/d25_crafting_smoke.gd` | 定义表一致性、制作事务（扣料/防重/取消/满仓/批次/占用）、设施升级与容量生效 | 库存-制作扣料 |
| `tests/d25_goals_smoke.gd` | 目标判定/进度/一次性领奖、旧档补记边界、防转手、保险箱种子解锁 | 存档-重复结算 |
| `tests/d25_plant_smoke.gd` | 新植物全链（解锁→购种→种植→照料→收获→育种→市场）、跨北京日、离线成熟 | 农场-新植物照料与育种、跨日刷新 |
| `tests/d25_warehouse_smoke.gd` | 双区容量/叠层/筛选数据/锁定/出售与防套利、归属唯一保持 | 库存-满仓、出发占用 |
| `tests/d25_pending_smoke.gd` | 待领取区分批领取、重开结算不重领、满仓不锁结算 | 库存-满仓 |
| `tests/d25_economy_sim.gd` | 三种出发方式成本收益模拟与锚点（§4-W9） | （经济模拟） |
| `tests/capture_d25_panels.gd` | 制作台/仓库/看板截图 | 实机记录 |

- 运行命令沿用根 README 的 PowerShell 形式（`--headless --path . --script res://tests/d25_*.gd`）；随机种子与时间注入，禁止碰真实 `user://` 玩家档（A1-6）。

### 实机验收清单（总计划 §10-2.5、§12.3）

| 验收项 | 通过标准 | 对应 |
| --- | --- | --- |
| 三条成长链 | 带回材料制作装备、带回种子种出新植物、出售货物再准备出发，各完整走通一遍 | §10-2.5 交付 |
| 新植物闭环 | 新种子可购买／获取、播种、照料、育种、出售，全链无断点 | §10-2.5 验收 |
| 制作与领奖不重复扣发 | 连点、重启、重开面板均不重复制作／重复领奖；取消不扣费 | §10-2.5 验收 |
| 失败后低成本再出发 | 死亡结算后补领基础装备即可再次出发，无需长时间种菜 | §10-2.5 验收、§12.2 |
| 探险期间农场时间 | 出发时在生长的作物在探险 60 分钟后回家已成熟；跨北京日回家市场刷新 | §12.1 农场项 |
| 无重复套利路径 | "放弃后刷免费装""重复领奖""重开结算重领""制作卖出循环获利"逐一试并失败 | §10-2.5 验收、§12.2 |
| 旧档兼容 | 真实 v6 备份副本加载后原资产一致，仓库双区拆分后装备/材料各就各位 | §9.5 |

### 经济模拟报告要求（延续 `stage6_economy_sim` 传统）

- 脚本固定随机种子、受控时间推进，打印各策略表格后 `quit(0)`；报告章节进交付报告，包含：三种出发方式（基础／普通／高成本）× 三种决策策略（第 4 排撤／第 7 排撤／打穿）的携带成本、消耗、带回价值、死亡损失、净收益与解锁进度；锚点结论（1～3 次普通撤离推进一个基础制作目标、铜剑总成本 44 ≥ 售 40、低成本失败局可再出发）；高成本档涉及铁矿的部分标注"素材依赖 2.8，数值为假设口径"。
- 试玩记录口径按总计划 §12.2：新手首局、低成本局、普通装备局、高成本局、失败后恢复局各至少一局，记录单局时长、带回价值与配方解锁所需局数。

## 6. 风险与回退

- **农场回归八项必须保持通过**是本阶段最大风险：`refresh_market`/`seed_lock_reason`/`buy_seeds` 直接改在阶段 4/6 测试覆盖的热路径上。对策：种类遍历保持"cabbage、carrot 在前、新种类仅解锁后追加"，公式随机流按种类独立（`formula_rng.seed` 含 `kind.hash()`），`stage4_market_smoke`/`stage6_economy_sim` 期望不变；W5 单独成提交，失败可回退而不影响 W1~W4。
- 存档 v7 迁移动 `warehouse` 结构：迁移与拆区单独成提交；拆区只按定义类别分组、不动实例 ID 与归属，`d21_inventory_smoke` 的 `owner_of` 断言必须原样通过。
- 制作事务跨农场块与探险块：任何"扣料成功但产成品失败"的中间态都是事故；事务内先全量校验、后一次性写入，`preview` 纯读；保存点紧随事务返回（组合根），并在 `d25_crafting_smoke` 用"预览前后存档相等"断言。
- 免费基础装备套利：出售（W6）、制作输入（W2）、批量出售预览三处都必须过 `ItemDefs.is_basic`；新增任何未来物品处理路径（2.6 分享）也读同一标记，禁止在 UI 层各写一份判断。
- `farm_hud.gd` 膨胀：四个新面板全部独立文件，只挂接（A1-3）。
- 经济风险：旧农场白菜收入可能让金币成本失效（设计 §10）；本阶段只观察、把深层材料承担解锁条件，不在本阶段内无限调价——结论写入交付报告，整体调整留给 2.9（总计划 §14 末行）。
- 回退顺序：W9（测试/文档）→ W8（UI）→ W7/W6（仓库与大厅）→ W5（农场接入）→ W2~W4（crafting 域）→ W1（定义表）；`crafting_defs/crafting_game` 为纯新增文件，可整体摘除。
- 待设计澄清（编码前/中需设计侧确认，均不阻塞 W1/W2 开工）：
  1. 新植物正式名称与形象（总计划 §14 要求 2.5 开始前定；暂名"岩芽菜/rock_sprout"不得带进交付）。
  2. 新植物公式锁定：现规则 `request_lock_formula` 只允许锁"已锁客人偏好植物"，而无客人偏好岩芽菜，与设计 §6"商店 3 级后可按原锁定规则锁新植物公式"冲突——需澄清是增加偏好客人、放宽锁定条件，还是本阶段不提供新植物公式锁。
  3. 小药水/铜剑的购买入口归属（原集市面板扩展 vs 仓库/制作面板内补给购买区）与上架清单范围。
  4. 作物批次锁定标记的 UI 入口位置（数据层已定 `.get("locked", false)` 免迁移）。
  5. 待领取区物品的字段名以 2.4 代码计划落地为准（本文暂记 `inventory.pending`，W6/W7 开工前对齐）。
  6. `SAVE_VERSION` 最终号取决于 2.4 是否已占用 7（本文按 6→7 编写，若冲突顺延）。
  7. 救援包"单人自用转换"的恢复数值预览（设计 §4 允许转换，比例待定；2.6 前必须有，否则该物品半边死牌）。
  8. "纯教程目标旧档补记"的具体名单（本文按 `legacy_rule` 逐条明示，试玩后确认边界）。

## 7. 交付物清单

- 代码：§2 表列出的 6 个新文件（`crafting_defs.gd`、`crafting_game.gd`、`crafting_panel.gd`、`gear_warehouse_panel.gd`、`harvest_hall_panel.gd`、`growth_board_panel.gd`）与 9 处既有文件修改（`plant_defs.gd`、`market_defs.gd`、`farm_game.gd`、`item_defs.gd`、`inventory_game.gd`、`expedition_baseline.gd`、`farm_world.gd`、`farm_hud.gd`、`loadout_panel.gd`）。
- 测试：§5 的 7 份 `tests/d25_*.gd` 脚本与截图产物。
- 文档：`docs/archive/Godot_阶段2.5_交付报告.md`（含经济模拟报告、实际采用数值、基线登记说明、免费基础装备条件结论）；本计划状态更新；总计划 §10-2.5 与两个 README 状态更新。
- 数据示例：`crafting_defs.gd` 内八配方/五设施/八目标即"6～8 个配方、3 类设施升级、6 个以上目标"的内容交付（总计划 §10-2.5 建议内容预算）。
