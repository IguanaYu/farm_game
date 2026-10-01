# 2.3 格子背包与物品卡牌：代码执行计划 v0.1

日期：2026-10-01。状态：未开始。适用工程：Godot 4.6.1（GL Compatibility）、Windows、现有 farm 工程。
导航：[整体开发计划](../Godot_第二大阶段_农场与合作洞窟_整体开发计划_v0.1.md)｜[2.3 详细设计](../design/Godot_阶段2.3_格子背包与物品卡牌_详细设计_v0.1.md)｜[设计索引](../design/第二大阶段详细设计索引.md)｜[代码计划索引](第二大阶段代码执行计划索引.md)｜[上游 2.1 代码计划](Godot_阶段2.1_规则基线与工程基础_代码执行计划_v0.1.md)｜[上游 2.2 代码计划](Godot_阶段2.2_单人卡牌战斗原型_代码执行计划_v0.1.md)

本文把 2.3 详细设计拆成可执行的 Godot 代码任务，拆解依据为该设计的 D2.3-01～D2.3-07，以及总计划 §4（物品、空间与卡牌）、§10-2.3（交付与验收）、§12.1（必须覆盖的规则验证）、§11（工程划分）。物品数值、容器容量、牌构成等一切设计内容以详细设计为准，本文不重述数值，只引用 `D2.3-XX` 功能号与设计节号。工程约定（规则层 `RefCounted` 纯逻辑、结果字典 `{ok, reason, …}`、注入随机数与时间、测试命名 `tests/d23_*.gd`、提交粒度=工作包）全部遵守导航"上游 2.1 代码计划"的附录 A；本文只新建/扩展模块地图（附录 A2）分配给 2.3 的模块，两处边界处理在 §2 说明。

## 1. 输入与前置

上游 2.1 交付物（到文件级，只引用不重定义）：

- `scripts/domain/expedition_baseline.gd`：容器尺寸（胸挂 3×4／背包 4×4／保险箱 1×2）、`JOIN_ROUND={chest:1, pack:2, safe:3}`、格子几何 `cells_of/can_place`、`PROTO_RULES_VERSION`。
- `scripts/domain/item_defs.gd`／`card_defs.gd`：定义字段（占格、类别、允许容器、保护资格、来源牌序列 `cards`、`basic_kit`、`demo`）；基础套装三件；`demo` 实例保存前剔除机制。
- `scripts/domain/inventory_game.gd`：`bind/add_instance/move_to_loadout/move_to_warehouse/find_first_fit/owner_of/deck_preview/strip_demo_instances/set_run_occupied`，Instance 结构 `{instance_id, def_id, quality, container, cell, rotated, demo, source}`。
- `scripts/domain/farm_game.gd`：`SAVE_VERSION=6`、v5→v6 迁移、`expedition` 块（含 `loadouts` 预设结构、`next_instance_id` 发号器）。
- `scripts/ui/loadout_panel.gd`：三容器网格渲染（已按 `rotated` 预留）、点击式自动找位放置、物品详情、牌组预览、`LoadoutCheck.evaluate` 纯函数。
- `scripts/ui/expedition_hub_panel.gd`、`scripts/world/farm_world.gd`、`scripts/ui/farm_hud.gd`：入口与 modal 挂接方式。
- `scripts/services/expedition_store.gd`：ID 体系（本阶段仅沿用 `InventoryGame.next_instance_id()`，无新增 ID 种类）。

上游 2.2 交付物（到文件级；具体命名以 2.2 代码计划与交付为准，差异列 §6 对齐项）：

- `scripts/domain/combat_game.gd`：回合时序（步骤 2"加入该回合到期的物品牌"的 2.2 占位实现）、牌实例携带来源物品字段的预留结构、D2.2-04 十二种牌效果模板（含饮药／应急包扎"消耗来源、移除关联牌"与笨重货物"本场移除"语义）、跨场生命延续、战斗日志与胜负画面。
- `scenes/battle_screen.tscn`＋`scripts/ui/battle_screen.gd`：手牌／抽弃牌堆／移除区查看、牌详情（名称／费用／效果／来源物品）、可重复挑战的开发入口。

本阶段功能号清单（逐个覆盖，设计 §2～§8）：

| 功能号 | 内容 | 落点 |
| --- | --- | --- |
| D2.3-01 | 三种容器与保险箱白名单 | W1、W2 |
| D2.3-02 | 格子交互（拖放／旋转／自动整理／提示回退） | W2、W3、W6 |
| D2.3-03 | 基础物品池 15 种 | W1 |
| D2.3-04 | 牌组生成与分回合加入 | W4、W5、W6 |
| D2.3-05 | 补给消耗与货物负担 | W2、W5、W7 |
| D2.3-06 | 搜刮页面（最小奖励流子集） | W7 |
| D2.3-07 | 物品比较与配装方案 | W6、W8 |

明确不做（占位与后移）：

- 真实搜刮节点、掉落表、公共物资与双人分栏在 2.4（`expedition_game.gd`／`ui/expedition_map_panel.gd` 等，模块地图 2.4 列）；2.3 的"拾取"用战斗后最小奖励流验证：奖励候选为固定演示清单（占位方式见 W7），领取事务为真实实现。
- 撤离／死亡／回家结算在 2.4；2.3 的"带入／使用／返还"只在战后奖励条展示，不生成结算档、不写 `applied_settlements`。
- 战备容量升级（总计划 §4.2）、制作、仓库筛选与材料回家叠放优化在 2.5；携带堆叠保持禁止（总计划 §4.2），仓库结构维持 2.1 现状。
- 任务系统边界（设计 §10"任务要求货物已丢弃"）随 2.5 任务目标落地。
- 战斗中布局锁定由"战斗场景不暴露任何整理入口＋牌组快照锁定"保证；真实出发占用锁（`occupied_by_run` 事务）在 2.4。
- 复杂拼图形状与复杂交换手势不做（设计 §3、总计划 §4.2，原型先矩形）。

## 2. 新增与修改的工程结构

| 文件 | 动作 | 责任 | 预估规模 |
| --- | --- | --- | --- |
| `scripts/domain/item_defs.gd` | 扩展 | 物品池 15 种条目（设计 §4 表）：类别细分、保险箱白名单标记、消耗品 `uses`；定义一致性自检 | +130 行 |
| `scripts/domain/inventory_game.gd` | 扩展 | 精确放置／旋转校验与失败原因、非战斗丢弃、堆叠禁则、消耗品实体（剩余次数／扣除／耗尽移除）、自动整理与空间诊断、预设保存与应用事务、待领取数据 | +260 行 |
| `scripts/domain/deck_builder.gd` | 新增 | 容器布局→按加入回合分组的牌实例快照；战斗开始构建一次、构建后锁定 | ~110 行 |
| `scripts/domain/combat_game.gd` | 扩展 | 绑定牌组快照、三容器延迟洗入与"每物品只加入一次"去重、牌效果经来源实例 ID 回查 InventoryGame、关联牌清理、战后补给统计 | +150 行 |
| `scripts/ui/battle_screen.gd`＋`scenes/battle_screen.tscn` | 扩展 | 牌↔物品互查、来源徽标、战后最小奖励条与补给报告、"再战一场（重建牌组）"入口 | +180 行 |
| `scripts/ui/loadout_panel.gd` | 扩展 | 格子拖放／旋转／放置预览（绿红＋文字原因）、自动整理入口、满包连续空间提示、保险箱清空警告、物品比较视图、配装预设 UI、待领取侧栏 | +320 行 |
| `tests/d23_*.gd` 等 7 份 | 新增 | 见 §5 | 共 ~520 行 |

模块地图边界说明（对照 2.1 附录 A2 的 2.3 列）：地图分配给 2.3 的动作是 `deck_builder.gd` 新增，`inventory_game.gd`、`item_defs.gd`（与 `card_defs.gd` 同行）、`combat_game.gd`、`battle_screen.tscn/battle_screen.gd` 扩展，上表与之逐行对应。两处补充：① 格子交互与预设的 UI 落在 2.1 已建的 `loadout_panel.gd` 内扩展——该文件未列入模块地图、也未分配给其他阶段的动作，扩展它优于新建第二套网格 UI；② D2.3-06 搜刮正式面板按地图属 2.4，本阶段不新建面板文件，最小奖励流由 `battle_screen`（奖励条）＋`loadout_panel`（待领取侧栏）承载。牌效果全部复用 2.2 的 12 种模板，预计 `card_defs.gd` 无需改动；若 2.2 交付缺模板，按地图同行"扩"口径补齐（§6 对齐项）。`farm_game.gd`、`farm_world.gd`、`farm_hud.gd` 本阶段零改动。

## 3. 数据与存档

### 3.1 布局数据结构（Instance 结构不变，语义扩展）

- Instance 沿用 2.1 结构；`cell:[x,y]` 与 `rotated` 从"自动找位写入"升级为精确放置的真实坐标（设计 §3）。旋转只互换宽高，占格数与来源牌数不变（设计 §10 第 1 行），定义层 `cards.size()==w*h` 红线不动（2.1 附录 A3）。
- 归属唯一事务不变：一切布局变更（放置／旋转／丢弃／整理／预设应用）都经 InventoryGame 单事务完成（先验证、写新位、再清旧位，函数内无中间暴露）；UI 拖动过程不写状态，"拿起物品断线→按已确认布局恢复"天然成立（设计 §10 第 4 行）。
- 堆叠禁则：三个携带容器内任何物品一律不堆叠（总计划 §4.2）；材料拾取时每个单位生成独立实例逐件发号。仓库仍按 2.1 现状（每实例一条），回家叠放优化在 2.5。

### 3.2 消耗品实体与剩余次数

- Instance 新增可选字段 `uses_remaining: int`，仅消耗品使用；读取侧对缺失字段按 `ItemDefs.default_uses(def_id)` 回填（小药水／绷带=1）。"占 2 格提供两张饮药的同一瓶药仍只有一次使用"（设计 §5）由定义 `uses` 与多张来源牌共同表达，W5 有专项测试。
- `consume_use` 扣减剩余次数；归零时实体从容器移除（位置变空，战斗中不给整理机会，战后空格才可拾取——设计 §5）。战斗内关联牌清理由 combat_game 按来源 ID 执行（W5）；存档侧只看结果——耗尽实体已不存在。
- 战后统计 `battle_supply_report()`（带入／使用／返还按 def_id 计数）由 combat_game 内存状态生成，展示在奖励条；不写 farm 档。

### 3.3 存档字段增改与兼容

- `SAVE_VERSION` 不因本阶段升级（仍在 v6 的 `expedition` 块内新增可选字段，读取回填默认）；若 2.2 交付时已调整版本策略，跟随其实际版本号并在交付报告记录（§6 对齐项）。
- `expedition.loadouts` 从"只读默认配置"启用为可写多套预设，结构沿用 2.1：`{name, items:[{def_id, container, cell, rotated}…]}`，仍为"要求清单、不拥有实例"（设计 §8、总计划 §3.1）。
- 待领取区（W7）不落档：未领取奖励只是 def_id 列表，成功放置才经 `pick_up` 生成实例写档；关闭游戏即视为放弃，奖励条在离开前给出确认（设计 §6）。
- 战斗牌组快照、joined 标记、跨场延续生命均为内存态（2.3 无局档，重开游戏回到满血基准）；2.4 起 `expedition_store` 落局快照时再序列化。

### 3.4 存读档断言口径（总计划 §10-2.3 验收末条）

`tests/d23_save_smoke.gd` 断言：保存→读取后，三容器逐实例 `{def_id, container, cell, rotated, uses_remaining}` 与保存前全等、`owner_of` 全等、`next_instance_id` 不回退、`demo` 实例与待领取区不入档；另用"手工去掉 `uses_remaining` 的构造档"验证回填。

## 4. 工作包拆解

W1→W9 为建议实施顺序，每包独立提交。依赖：W2←W1，W3←W2，W4←W1/W2，W5←W4，W6←W2/W3，W7←W5/W2，W8←W2/W6，W9←全部；W1 与 W4 的纯函数部分可先行。

### W1 物品池定义（D2.3-01 白名单、D2.3-03）

- 目标：物品池 15 种全部落成 `item_defs.gd` 条目，覆盖武器／防具／工具／补给／材料／种子／货物，含两种"值钱但拖累战斗"的负担（总计划 §10-2.3 内容预算；总量 15、新增 12，两种口径都落在 12～16 内）。
- 文件：`scripts/domain/item_defs.gd`（`card_defs.gd` 仅在 2.2 缺模板时补）。
- 条目清单（暂名→`def_id`，逐行对应设计 §4 表；基础套装三件为 2.1 已建，本包只核对来源牌序列与 2.2 牌表一致）：

| def_id（暂名） | 尺寸／格 | 来源牌 | 售价 | 保险箱 | 类别 |
| --- | --- | --- | --- | --- | --- |
| `old_shortsword`（旧短刀，basic_kit） | 1×2／2 | 切击×2 | 不可售 | 否 | 武器 |
| `wooden_shield`（木盾，basic_kit） | 2×2／4 | 架盾×2、掩护、稳住 | 不可售 | 否 | 防具 |
| `kit_tools`（行囊工具，basic_kit） | 1×2／2 | 调整呼吸、观察 | 不可售 | 否 | 工具 |
| `copper_shortsword`（铜短剑） | 1×3／3 | 切击×2、重击 | 40 | 否 | 武器 |
| `reinforced_shield`（加固盾） | 2×2／4 | 架盾×2、掩护、稳住 | 50 | 否 | 防具 |
| `leather_bracer`（皮护腕） | 1×2／2 | 稳住、架盾 | 25 | 否 | 防具 |
| `scout_whistle`（侦察哨） | 1×2／2 | 观察、调整呼吸 | 30 | 否 | 工具 |
| `small_potion`（小药水，uses=1） | 1×1／1 | 饮药 | 6 | 否 | 补给 |
| `bandage`（绷带，uses=1） | 1×1／1 | 应急包扎 | 5 | 否 | 补给 |
| `copper_scrap`（铜片） | 1×1／1 | 笨重货物 | 8 | 可 | 材料 |
| `fiber_bundle`（纤维团） | 1×1／1 | 笨重货物 | 6 | 否 | 材料 |
| `iron_ore`（铁矿） | 1×2／2 | 笨重货物×2 | 18 | 可 | 材料 |
| `sprout_seed`（岩芽菜种子） | 1×1／1 | 笨重货物 | 按种子回收规则 | 可 | 种子 |
| `antique_ornament`（古旧摆件） | 2×2／4 | 笨重货物×4 | 90 | 否 | 货物 |
| `glimmer_crystal`（微光晶石） | 1×2／2 | 稳住、观察 | 60 | 否 | 材料 |

- 实现要点（签名草案）：

```gdscript
# ItemDefs 追加（2.1 已建类）
static func get_def(def_id: String) -> Dictionary
static func default_uses(def_id: String) -> int          # 消耗品默认次数，非消耗品 0
static func is_safe_allowed(def_id: String) -> bool      # 保险箱白名单（设计 §2）
static func validate_pool() -> Array[String]             # 自检：cards.size()==w*h、类别齐全、demo 不冲突
```

- "值钱但拖累"两件＝`antique_ornament`（90 售价／4 张负担牌）与 `iron_ore`（18／2 张负担牌）；`glimmer_crystal`（60／稳住＋观察）作"贵且能打"对照，三者并存避免单一价值排名（总计划 §6.3）。
- 验证：`tests/d23_defs_smoke.gd`——15 种逐项与设计 §4 表一致；每件 `cards.size()==w*h`；白名单恰为｛铜片、铁矿、种子｝；类别覆盖齐全；两件拖累货物与一件"贵且能打"对照各就位。
- 依赖：无。

### W2 布局规则核心：精确放置／旋转／丢弃／消耗品实体（D2.3-01、D2.3-02 规则、D2.3-05 实体）

- 目标：把 2.1 的"自动找位"升级为完整格子规则层；全部操作返回可读失败原因，供 W6 的 UI 事件逐项映射。
- 文件：`scripts/domain/inventory_game.gd`。
- 实现要点（签名草案；沿用 `bind`／结果字典／注入随机）：

```gdscript
func validate_place(instance_id: int, container: String, cell: Vector2i, rotated: bool) -> Dictionary
    # {ok, cells, reason, blockers}；reason∈{out_of_bounds, overlap, not_safe_whitelisted, no_instance, run_locked}
func place_instance(instance_id: int, container: String, cell: Vector2i, rotated: bool) -> Dictionary
    # 单事务放置；失败原状返回（设计 §3"Esc／非法位置放手回原处"的规则侧依据）
func rotate_instance(instance_id: int) -> Dictionary          # 原地旋转＝place 到同 cell 换朝向
func discard_instance(instance_id: int, confirm_lose_protection: bool) -> Dictionary
    # 非战斗丢弃：移出归属；保险箱内物品必须显式确认失去保护（设计 §10 第 3 行）
func consume_use(instance_id: int) -> Dictionary              # {ok, remaining, exhausted}；非消耗品拒绝
func pick_up(def_id: String, container: String, cell: Vector2i, rotated: bool, source: String) -> Dictionary
    # 奖励领取事务＝发号＋放置合一；失败不产生实例、不消耗号段（"满包不吞物"）
```

- 要点：`add_instance` 初始化 `uses_remaining`、归零即移除实例；重叠／越界判定复用 `expedition_baseline.can_place`，但 reason 细分为 UI 可直显的文字键；重叠时 `blockers` 列出被压实例，支撑"不自动挤走旧物品"（设计 §3）。
- 验证：`tests/d23_inventory_worked.gd`——越界／重叠／保险箱白名单三类拒绝各有 reason 与 blockers；旋转后 `deck_preview()` 张数不变；丢弃保险箱内种子未确认被拒、确认后失去保护；药水 `consume_use` 一次后实例消失、二次调用拒绝；`pick_up` 满包失败不消耗 `next_instance_id`。
- 依赖：W1。

### W3 自动整理与空间诊断（D2.3-02）

- 目标：自动整理只重排同一容器内部、可旋转、保留容器归属与保险箱保护选择（总计划 §4.2）；无法求解时整体回退（设计 §3、§10 第 5 行）。
- 文件：`scripts/domain/inventory_game.gd`。
- 实现要点（签名草案）：

```gdscript
func auto_organize(container: String, seed: int) -> Dictionary
    # {ok, moves:[{instance_id, cell, rotated}…]}；确定性（注入随机）；先在临时布局求解，
    # 全部可放才提交，否则原布局逐字节回退，绝无半整理状态
func free_space_report(container: String) -> Dictionary
    # {free_cells: int, largest_free_rect: Vector2i, can_fit_shapes: Array[Vector2i]}
    # 满包提示数据源："剩 4 格但分散成四角，2×2 放不下"（设计 §3，空闲格数与可放形状分别提示）
```

- 算法边界：容器 ≤16 格、单品 ≤4 格，首版用"面积降序＋左上角首个合法位＋两种朝向"的确定性贪心，不求最优解；解不出即回退。整理结果不覆盖已存预设（设计 §8，W8 再校验）。
- 验证：`d23_inventory_worked.gd` 续——可解布局整理后每件物品容器归属不变、总占用不变；不可解样例（3×4 胸挂内木盾＋加固盾＋古旧摆件三件 2×2，12 格无解排布）返回 `ok=false` 且布局逐实例回退；同 seed 两次结果一致。
- 依赖：W2。

### W4 牌组构建器（D2.3-04）

- 目标：容器布局→按加入回合分组的牌实例快照；战斗开始时构建一次、战斗中锁定（总计划 §4.3）。
- 文件：`scripts/domain/deck_builder.gd`（新增，`class_name DeckBuilder extends RefCounted`，纯逻辑）。
- 实现要点（签名草案）：

```gdscript
static func build(inventory: InventoryGame, seed: int) -> Dictionary
    # 输入：InventoryGame 三容器全部在位实例的布局投影
    # 输出：{rounds: {1:[CardInstance…], 2:[…], 3:[…]}, totals:{per_round, per_item}, layout_fingerprint}
    # CardInstance: {card_id, source_instance_id, source_slot, def_id, join_round}
    # rounds 键＝容器 JOIN_ROUND（胸挂 1／背包 2／保险箱 3）；构建即深拷贝，之后不再回查 InventoryGame
static func audit(snapshot: Dictionary, inventory: InventoryGame) -> Dictionary
    # 测试口径：每件物品牌数=占格数；不存在/耗尽/demo/被活动局占用的实体不生成；三容器无遗漏无多算
```

- 要点：第 1 组在战斗初始化时直接洗入抽牌堆（沿用 2.2 流程），第 2／3 组整组移交 combat_game 回合开始时合并（W5）；`layout_fingerprint`（实例 ID＋容器＋cell＋rotated 的有序摘要）用于"下一场是否重建"的对比与断言。牌组预览（2.1 `deck_preview`，战备 UI 用）与快照同源同值，测试加一致性断言，避免两套算法漂移。
- 验证：`tests/d23_deck_smoke.gd`——设计 §9 场景：胸挂基础 8 张→`rounds[1]=8`；背包放铜剑＋摆件＋药水→`rounds[2]=3+4+1`；保险箱放种子→`rounds[3]=1`；卸下短刀改在胸挂放铜剑→`rounds[1]=9`；丢弃摆件后重建其 4 张不再出现；构建后修改 InventoryGame 布局，已建快照内容不变（锁定）；`audit` 与 `deck_preview` 张数一致。
- 依赖：W1、W2。

### W5 战斗接入：延迟洗入／消耗品回查／连续两场（D2.3-04、D2.3-05）

- 目标：combat_game 消费 DeckBuilder 快照——三容器第 1／2／3 回合加入且每件物品只加入一次；牌效果解析经来源物品实例 ID 回查 InventoryGame；两场战斗生命延续、格挡与手牌重建。
- 文件：`scripts/domain/combat_game.gd`（2.2 已建；本包独立成提交，便于 2.2 回归定位）。
- 实现要点（签名草案；引用 2.2 预留的来源字段与效果钩子，命名差异见 §6）：

```gdscript
func start_battle(snapshot: Dictionary, carry_hp: int, rng_seed: int) -> Dictionary
    # 绑定快照（深拷贝锁定）、按 2.2 时序开局；carry_hp 缺省＝基线满血（首场按出发状态）
func _join_round_cards(round: int) -> void
    # 回合开始步骤 2（2.2 设计 §3）：该轮组合并进"此时剩余抽牌堆"后整体重洗；
    # 弃牌堆与手牌不参与合并（设计 §5"不让已打出的牌提前重抽"）；
    # 按 source_instance_id 记 joined 集合——回合推进／重开面板／重复调用都不再次加入
func resolve_source_consume(card_instance: Dictionary, inventory: InventoryGame) -> Dictionary
    # 牌效果解析钩子（饮药／应急包扎，2.2 预留）：inventory.consume_use(source_instance_id)
    # → exhausted=true 时把手牌／抽牌堆／弃牌堆中该来源的全部关联牌移除（总计划 §4.3、设计 §5）
func remove_card_this_battle(card_instance: Dictionary) -> Dictionary
    # 笨重货物"花 1 能量本场移除"：只移除牌、实体不动——UI 文案必须写"本场移除这张牌，物品仍在背包"
func battle_supply_report() -> Dictionary
    # {brought:{def_id:n}, used:{…}, returned:{…}}——支撑"带入 2 瓶，使用 1 瓶，返还 1 瓶"
```

- 要点：`resolve_source_consume` 是 combat_game 与 InventoryGame 的唯一耦合点（InventoryGame 以参数注入，规则层不引全局、不读场景树）；实体已不存在（被非战斗丢弃等）时拒绝打出该牌并返回 reason，已发生的伤害／治疗不回滚（设计 §5）。第二场由入口重新 `DeckBuilder.build`＋`start_battle(carry_hp=上场结束生命)`——上场已移除的货物牌随重建回来、已耗尽的药水不再生成（设计 §5）；格挡、手牌、抽弃牌、回合数按 2.2 基线全部重建，普通状态不跨场。
- 验证：`tests/d23_combat_worked.gd`（固定种子）——①第 1 回合抽牌只可能来自 `rounds[1]`；②第 2 回合开始后抽牌堆张数=此前剩余抽牌堆＋`rounds[2]` 且顺序重洗（集合相等）；③同一物品跨回合只加入一次；④`rounds[2]` 为空时第 2 回合抽牌堆不变；⑤构造测试用 1×2／两张饮药／uses=1 的 demo 定义：打出一张后另一张不可再用且从三区移除（设计 §5"一个药水多个牌位"）；⑥笨重货物本场移除后 InventoryGame 中实体仍在；⑦两场串联：第一场结束生命＝第二场初始生命、格挡为 0、起手重抽 5 张；⑧2.2 全部既有测试保持通过。
- 依赖：W4（及上游 2.2 交付）。

### W6 战备格子交互 UI（D2.3-02、D2.3-07 比较、D2.3-04 首回合提示）

- 目标：loadout_panel 从点击式升级为完整格子交互；UI 事件全部映射到 W2/W3 校验函数，UI 不自算合法性、不旁路直改字典（2.1 附录 A3）。
- 文件：`scripts/ui/loadout_panel.gd`（格单元用内部类承载，不新建脚本文件）。
- 实现要点——UI 事件到规则函数的映射（Godot 4.6 Control 拖放三件套）：

| UI 事件（Godot 载体） | 调用 | 行为 |
| --- | --- | --- |
| 开始拖动（格单元 `Control._get_drag_data`，返回 `{instance_id, grab_cell_offset}`） | 不调规则层 | `set_drag_preview` 拖动虚影；原位半透明虚影；拖动中禁止关闭面板（设计 §3"不会拿着物品退出面板后消失"） |
| 拖动经过（容器网格 `_can_drop_data`） | `validate_place(instance_id, container, cell, drag_rotated)` | 整个占格区域高亮：合法绿＋"可放置"文字，非法红＋原因（越界／与"木盾"重叠／保险箱白名单外） |
| 松手（`_drop_data`） | `place_instance(...)` | 成功落位；失败回原位（规则层本就未变更） |
| R 键／右键／屏幕旋转按钮（`_unhandled_key_input`／`gui_input`） | 翻转 `drag_rotated` 后重跑 `validate_place`；选中态原地调 `rotate_instance` | 矩形宽高互换，占格与牌数不变 |
| Esc（`_unhandled_key_input`） | 不调规则层 | 取消拖动／取消选中，物品留原处 |
| 点击物品→点格子（2.1 交互保留） | 同 `validate_place/place_instance` | 与拖放共用同一套校验与提示 |
| "自动整理"按钮 | `auto_organize(container, seed)` | 展示移动结果；失败提示"已恢复原布局" |
| 满包提示 | `free_space_report(container)` | "剩 N 格，但缺 2×2 连续空间"，附"去整理"按钮（设计 §3） |
| "清空保险箱"按钮 | 逐件 `move_to_warehouse` | 先列出将失去保护的物品，确认后执行（设计 §3） |

- 网格控件组织：每容器一个 `GridContainer`（`columns=容器宽`），格单元为内部类 `CellWidget extends Control`（实现拖放三件套＋悬浮详情）；物品块为覆盖在占用格上的 `PanelContainer`（按格定位、尺寸=占格×格边长），保证预览渲染的是整个占格区域。全部控件只做事件转发与展示。
- 顶部统计追加"负担牌张数"（笨重货物类牌计数），与"携带可售价值"并排，落实"贵重货物的经济价值与拖累程度都可预览"（设计 §5）。
- 比较视图（D2.3-07）：详情区"与其他物品比较"弹出双栏，逐行展示占格、每张牌、加入时点、是否可保护；替换场景给差异行（如"新增重击／多占 1 格"），禁止"战力 +12"式单一评分（设计 §8）。
- `LoadoutCheck.evaluate` 扩展：advices 增加"首回合牌数少于 5，实际抽不满"；硬阻止沿用 2.1 的"首回合牌库为空阻止出发"（D2.3-04）。
- 验证：`tests/capture_d23_loadout.gd`——拖放进行中、非法红提示、旋转前后、满包连续空间提示、自动整理前后共五张截图进 `screenshots/`；交互行为按 §5 实机步骤人工核对。
- 依赖：W2、W3。

### W7 战后最小奖励流与牌物互查（D2.3-06 最小子集、D2.3-05 报告、D2.3-04 下一场生效）

- 目标：第一场→奖励→整理→第二场的可玩串联（总计划 §10-2.3 交付），奖励流为"演示清单＋真实事务"。
- 文件：`scripts/ui/battle_screen.gd`＋`scenes/battle_screen.tscn`、`scripts/ui/loadout_panel.gd`（待领取侧栏）。再战入口沿用 2.2 的开发入口位置（若其落在 `expedition_hub_panel.gd`，仅改按钮文案为"再战一场（按最新布局重建）"，不新增文件）。
- 实现要点：
  - 奖励条（胜利画面追加）：常量 `DEMO_REWARD_POOL`——固定候选＝设计 §9 的古旧摆件、铜短剑、岩芽菜种子，UI 标注"演示奖励"；每张奖励卡显示名称、尺寸、牌数、价值、用途、保护资格（设计 §6"查看不是领取"）。下方展示 `battle_supply_report()` 文案。
  - 占位说明（演示→真实的过渡）：候选清单、数量与生成时机为硬编码演示；领取的选位校验、写入、放弃确认为真实实现；2.4 把清单来源替换为 `item_defs` 的节点奖励表引用（模块地图 2.4 列），奖励卡与领取流程结构不变。
  - 待领取区（loadout_panel 左侧临时侧栏，由奖励条"去整理"打开）：pending 列表只存 def_id，不入档；"尝试放入背包"＝两种朝向 `find_first_fit(pack)`，只找合法空位、不替玩家丢装备、不自动占保险箱；受保护候选（种子）单列"放入保险箱"＝`find_first_fit(safe)`，无位提示调整（设计 §6）；手动领取走拖放／点击＋`pick_up`，取消或放不下仍留在待领取区。关闭侧栏时若有未领取项，确认弹窗列数量与最高价值候选（设计 §6）。
  - "再战一场"：`DeckBuilder.build`＋`start_battle(carry_hp)`（W5）；两场之间可关闭战斗场景回农场整理再进，延续生命由入口持有；重开游戏回满血基准（§3.3 边界）。
  - 牌↔物品互查（模块地图 2.3 列"battle_screen 扩：牌与物品互查"）：牌面来源徽标（物品名＋序号，重复牌可展开看来源与份数，设计 §5）；点牌弹物品详情（占格、所在容器、加入时点、剩余次数）；实体耗尽时手牌／牌堆中关联牌即时移除并有说明（总计划 §4.3）。战备侧物品详情的来源牌列表补"加入时点"标注（2.1 已有结构上加显示）。
- 验证：`tests/capture_d23_battle_loot.gd`——胜利画面、奖励卡详情、待领取放置、牌来源互查弹层截图；规则行为已由 `d23_combat_worked.gd` ⑦ 与 `d23_deck_smoke.gd` 覆盖。
- 依赖：W5、W2。

### W8 配装预设 v1（D2.3-07）

- 目标：预设的保存与应用事务（总计划 §3.1"保存一套配置和按配置补齐已有物品"），不自动购买、不拿被活动局占用的物品。
- 文件：`scripts/domain/inventory_game.gd`（事务）、`scripts/ui/loadout_panel.gd`（保存／应用／缺失清单 UI）。
- 实现要点（签名草案）：

```gdscript
func save_loadout_preset(name: String) -> Dictionary     # 当前三容器布局→要求清单（def_id+位置），同名覆盖需确认
func plan_apply_preset(preset: Dictionary) -> Dictionary
    # {matched, missing:[def_id…], conflicts, preview_layout}——匹配自有实例（仓库＋现布局），
    # 排除活动局占用与 demo；缺件列清单，不做替代（设计 §8"不能悄悄用稀有武器替代普通剑"）
func apply_preset(plan: Dictionary, allow_partial: bool) -> Dictionary
    # 逐件 place 事务执行；缺件时 allow_partial=false 拒绝，true 必须先经 plan 预览确认
```

- 要点：应用前必须展示最终布局预览并确认；自动整理后的布局不覆盖已存预设，除非玩家主动保存（设计 §8）。
- 验证：`d23_inventory_worked.gd` 续——保存→清空→应用完整还原逐位一致；缺一件时完整模式拒绝、部分模式预览后应用且缺失清单准确；占用中的实例不参与匹配。
- 依赖：W2、W6。

### W9 存读档、回归与交付

- 目标：总计划 §10-2.3 验收全条目＋全阶段回归。
- 文件：`tests/d23_save_smoke.gd`、交付报告。
- 要点：存读档断言按 §3.4；跑 2.1／2.2 全部测试与既有 `stage1~6`、`world_picking` 回归；实机验收按 §5 步骤执行并截图归档；交付报告 `docs/archive/Godot_阶段2.3_交付报告.md` 记录物品池实际条目与设计 §4 的差异、自动整理算法与回退记录、演示奖励流占位说明、§6 澄清项结论；更新总计划 §10-2.3 状态、`docs/README.md`、根 `README.md` 与代码计划索引。
- 依赖：W1～W8。

## 5. 测试与验收汇总

| 测试 | 覆盖 | 对应总计划 §12.1 |
| --- | --- | --- |
| `tests/d23_defs_smoke.gd` | 物品池 15 种、占格=牌数、白名单、类别覆盖、值钱拖累两件＋贵且能打对照 | 背包（定义口径） |
| `tests/d23_inventory_worked.gd` | 精确放置／越界／重叠／非法容器／旋转／丢弃／堆叠禁则／消耗品实体／自动整理与回退／空间诊断／预设 | 背包、库存-满包 |
| `tests/d23_deck_smoke.gd` | 分回合分组、构建后锁定、下一场重建、删除物品后不再生成 | 战斗-延迟加入（构建侧） |
| `tests/d23_combat_worked.gd` | 1／2／3 回合洗入与去重、消耗回查与关联牌清理、货物本场移除、两场连续（生命持续、格挡／手牌重建） | 战斗-延迟加入、库存-带入返还 |
| `tests/d23_save_smoke.gd` | 布局与归属存读档断言、消耗品次数回填、demo／待领取不入档 | 存档 |
| `tests/capture_d23_loadout.gd` | 拖放／旋转／满包／整理截图 | 实机记录 |
| `tests/capture_d23_battle_loot.gd` | 来源互查、奖励条、待领取截图 | 实机记录 |

测试运行方式沿用 2.1 附录 A1-6（`--headless --path . --script res://tests/…`，种子与时间注入，截图进 `screenshots/`）。

实机验收步骤（总计划 §12.3，真实窗口完成，不以规则测试替代）：

1. 新档或 v5 迁移档进战备：基础套装在胸挂、首回合牌数 8；把木盾拖到背包（虚影＋绿色预览），首回合牌数变 4、后续加入 4。
2. 非法操作逐项：拖出界、拖到占用格、纤维团拖进保险箱——红色高亮＋文字原因；Esc 与非法松手都回原位。
3. 铜短剑 R 旋转（1×3↔3×1）；填满背包只留 4 个分散空格后放摆件——提示"缺 2×2 连续空间"；自动整理成功后可放入；三件 2×2 塞胸挂的不可解场景提示"已恢复原布局"。
4. 进入第一场（2.2 入口）：起手 5 张全部来自胸挂；胜利进入奖励条。
5. 奖励条：补给报告正确；"去整理"→待领取区领三件（种子入保险箱、铜剑入背包、摆件入背包）；留一件不领→关闭确认弹窗显示数量与最高价值候选。
6. 再战一场：首回合仍基础 8 张；第 2 回合加入铜剑 3＋摆件 4（带药水则＋1）；第 3 回合加入种子 1（设计 §9 算例）；生命延续、格挡清零、手牌重抽。
7. 带小药水出战并使用：实体从背包消失、饮药牌从各区清除、战后报告"带入 1 瓶，使用 1 瓶，返还 0 瓶"。
8. 存档退出重开：三容器布局、归属、保险箱内容、消耗品次数与重开前一致；待领取区为空。
9. 试玩通过条件（设计 §10）：试玩者能解释"这件贵东西为什么会拖累我"与"盾放胸挂更可靠"，并独立完成一次拾取、旋转、整理和查看来源牌。

## 6. 风险与回退

- 与上游 2.2 的结构对齐是最前置风险：本计划的 `start_battle`、牌来源字段与效果钩子引用 2.2 预留结构，2.2 代码计划若调整命名或入口，W5 先改适配层再动时序；W5 独立提交，可单独回退而不影响 W1～W4、W6～W8。
- combat_game 时序改动可能破坏 2.2 行为：W5 合并当轮跑 2.2 全部测试，任何差异先修再进。
- `loadout_panel.gd` 规模膨胀（2.1 预估 350 行，本阶段 +320）：格单元／物品块／比较弹层一律内部类或私有函数，不在 `farm_hud.gd` 加一行；若单文件仍超预期，交付报告说明拆分建议，本阶段不拆文件。
- 自动整理是小型装箱问题（NP）：限定确定性贪心＋两朝向＋小容器；任何失败路径都必须整体回退（设计 §10），禁止出现"整理一半丢结果"。
- 演示奖励被误当真实掉落：常量 `DEMO_` 前缀＋UI"演示奖励"标识＋交付报告明示 2.4 替换点。
- `uses_remaining` 与旧 v6 档兼容：读取侧统一回填默认值，`d23_save_smoke.gd` 用构造旧档断言。
- 牌组预览（战备）与牌组快照（战斗）双源漂移：W4 的一致性断言兜底；规则仍以快照为准。

待设计澄清（不阻塞 W1～W4 开工，须在对应节点前定）：

1. "至少两种值钱但拖累战斗的货物"口径：本计划计 `antique_ornament`（90／4 张负担）与 `iron_ore`（18／2 张负担，材料类）；若试玩认为材料类不算"货物"，需在 2.4 前补第二件纯高价值拖累货物（总计划 §10-2.3、§6.3）。
2. `reinforced_shield` 与 `wooden_shield` 牌构成完全相同、仅售价不同（设计 §4），与"不能只换皮并提高价格"存在张力——初版照表落地，试玩后调牌数字或构成。
3. `sprout_seed`"回家按种子回收规则"的回收价与新植物配置未定义（2.5 范围）；2.3 只落定义、保护资格与负担牌。
4. `bandage` 的合法目标"存活友方"（D2.2-04）在单人局是否含自己：2.3 设计 §4 写"一次单人／队友恢复"，按含自己实现，需回写 2.2 目标定义并在 2.2 计划评审确认。
5. 自动整理的排布目标（紧凑左上／按类别聚簇）设计未指定，初版取紧凑左上，试玩后定（设计 §3）。
6. 两场之间关闭战斗场景再进入时的生命延续载体：本计划按"再战入口在内存持有 carry_hp、重开游戏回满血"处理；若 2.4 局档提前需要跨会话延续，再引入局内状态持久化（与 2.4 计划对齐）。

## 7. 交付物清单

- 代码：新增 `scripts/domain/deck_builder.gd`；扩展 `scripts/domain/item_defs.gd`、`scripts/domain/inventory_game.gd`、`scripts/domain/combat_game.gd`、`scripts/ui/battle_screen.gd`＋`scenes/battle_screen.tscn`、`scripts/ui/loadout_panel.gd`（§2 表）。
- 测试：§5 的 7 份脚本与 `screenshots/` 截图。
- 文档：`docs/archive/Godot_阶段2.3_交付报告.md`（物品池采用值、自动整理与回退记录、演示奖励流占位说明、澄清项结论）；本计划状态更新；总计划 §10-2.3 状态、`docs/README.md`、根 `README.md`、代码计划索引更新。
- 可玩交付：从战备进入战斗 → 搜到物品 → 整理 → 第二场的完整流程（总计划 §10-2.3"交付"原文口径）。
