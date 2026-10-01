# 2.4 单人洞窟与撤离闭环：代码执行计划 v0.1

日期：2026-10-01。状态：**已完成（2026-10-01，交付报告见 [archive/Godot_阶段2.4_交付报告.md](../archive/Godot_阶段2.4_交付报告.md)）**。适用工程：Godot 4.6.1（GL Compatibility）、Windows、现有 farm 工程。

> 实施记录（2026-10-01）：按计划落地；装备仓库容量/待领取区移交 2.5，种子转换 2.5 接入。

导航：[整体开发计划](../Godot_第二大阶段_农场与合作洞窟_整体开发计划_v0.1.md)｜[2.4 详细设计](../design/Godot_阶段2.4_单人洞窟与撤离闭环_详细设计_v0.1.md)｜[设计索引](../design/第二大阶段详细设计索引.md)｜[代码计划索引](第二大阶段代码执行计划索引.md)｜上游计划：[2.1](Godot_阶段2.1_规则基线与工程基础_代码执行计划_v0.1.md)｜[2.2](Godot_阶段2.2_单人卡牌战斗原型_代码执行计划_v0.1.md)｜[2.3](Godot_阶段2.3_格子背包与物品卡牌_代码执行计划_v0.1.md)

本文把 2.4 详细设计拆成可执行的 Godot 代码任务，拆解依据为详细设计的功能号 D2.4-01～D2.4-07、总计划 §6（地图/节点/战利品）、§9.3（带入带出事务）、§9.4（恢复规则）、§10-2.4（交付与验收、试玩关口 A）与 §13（幂等从本阶段开始）。设计内容（地图排布、节点数值、事件结果、奖励池）以详细设计为准，本文不重述数值，只引用 `D2.4-XX` 功能号。工程分层、结果字典形状 `{ok, reason, …}`、注入随机数/时间、测试命名 `tests/d24_*.gd` 与模块出生地图，一律遵守 [2.1 计划附录 A](Godot_阶段2.1_规则基线与工程基础_代码执行计划_v0.1.md)，本文只引用、不另立约定。

## 1. 输入与前置

- 上游交付物（到文件级，以 2.1 附录 A2 模块地图为准；2.2/2.3 计划成文后如有出入以模块地图口径协调）：
  - 2.1：`scripts/domain/expedition_baseline.gd`（常量/几何/ID 约定）、`item_defs.gd`、`card_defs.gd`、`inventory_game.gd`（归属/占用/补领）、`scripts/services/expedition_store.gd`（ID 生成与读写空壳）、`scripts/ui/expedition_hub_panel.gd`、`loadout_panel.gd`（出发按钮 v0 置灰）、`farm_game.gd` v6（`expedition` 块：`active_run_ref`/`applied_settlements` 字段已预留恒空）、`farm_world.gd` 三个新入口。
  - 2.2：`scripts/domain/combat_game.gd`（回合引擎/裁定/意图/状态/日志/保存恢复入口）、`scenes/battle_screen.tscn`＋`scripts/ui/battle_screen.gd`。
  - 2.3：`inventory_game.gd` 扩展（拖放/旋转/自动整理/丢弃/消耗实体）、`scripts/domain/deck_builder.gd`（布局→牌组快照）、`item_defs.gd` 扩展 12～16 种物品、容器网格与物品详情 UI 组件（战备/搜刮面板内）。
- 本阶段功能号清单与工作包映射：

| 功能号 | 内容 | 主要工作包 |
| --- | --- | --- |
| D2.4-01 | 出发与局内概览（占用、顶部状态条、暂停菜单） | W5、W7 |
| D2.4-02 | 第一层地图（8 排、第 4/7 排撤离、连通、本局种子） | W1、W2、W7 |
| D2.4-03 | 节点行为（战斗/精英/宝箱采集/事件/休整） | W3 |
| D2.4-04 | 奖励结构（候选二选一、公共物资、裁定即固定） | W1、W4 |
| D2.4-05 | 搜刮与离开节点（拾取/丢弃/满包/完成确认） | W4、W7 |
| D2.4-06 | 撤离决策页面 | W3、W7 |
| D2.4-07 | 返还、死亡和满仓（保险箱保护、待领取区、回写农场） | W6、W8 |

- 明确不在本阶段：双人共同选路/分享/公共物资协商与倒地救援（2.6）；完整故障矩阵、重连凭据、未决结算重发（2.7，本阶段只做单人强退恢复与幂等）；第二层、层间、正式素材与教学（2.8）；装备/材料仓库管理界面、制作、设施升级（2.5，本阶段只加待领取区的最小领取入口）；地图分支随机生成（总计划 §6.2：闭环跑通后加入，本阶段用固定地图节点表）。

## 2. 新增与修改的工程结构

| 文件 | 动作 | 责任 | 预估规模 |
| --- | --- | --- | --- |
| `scripts/domain/expedition_defs.gd` | 新增 | 第一层固定地图节点表与静态连通性校验、节点类型/风险/资源倾向、事件表（设计 §4 三事件）、休整选项表、撤离排常量、奖励池（引用 `item_defs.gd` 的 def_id，不含第二层铁矿） | ~220 行 |
| `scripts/domain/expedition_game.gd` | 新增 | 局规则：绑定局快照、出发校验与初始快照构建、节点裁定（首次裁定后固定）、节点处理器分发表、战斗接线（组合 CombatGame/DeckBuilder）、搜刮/丢弃/补给、休整/事件、撤离/死亡/放弃与结算记录构造 | ~450 行 |
| `scripts/services/expedition_store.gd` | 修改 | 扩展：`save_run/load_run`（主档＋`.bak` 三段式）、`save_settlement/load_settlement`、`user://expeditions/` 目录初始化与孤儿结算档判定 | +90 行 |
| `scripts/domain/farm_game.gd` | 修改 | 扩展：`apply_expedition_settlement`（单事务幂等应用）、`claim_pending_expedition_items`、`expedition_pending_summary`；`load_state` 为 2.4 新字段补缺省 | +120 行 |
| `scripts/domain/expedition_baseline.gd` | 修改 | 扩展常量：`WAREHOUSE_ITEM_CAP`（装备/材料仓库容量初值，2.5 挂设施升级）、结算/撤离相关共用常量 | +12 行 |
| `scripts/domain/plant_defs.gd` | 修改 | 扩展岩芽菜（`rock_sprout`）最小完整植物配置：生长、词条适用、遭遇、经验、市场报价、图标占位（总计划 §7.1 红线：可获得必须可播种；正式素材 2.8 替换） | +45 行 |
| `scenes/expedition_screen.tscn`＋`scripts/ui/expedition_screen.gd` | 新增 | 整屏洞窟场景（`farm_world` 全屏子节点，不切换场景树、不新增 autoload）：顶部状态条、开局概览卡、子面板容器、暂停菜单、关闭窗口→暂停 | ~280 行 |
| `scripts/ui/expedition_map_panel.gd` | 新增 | 8 排分支地图：已揭示节点类型/连线/当前位置/可进入相邻节点/风险与可撤离标记 | ~200 行 |
| `scripts/ui/expedition_loot_panel.gd` | 新增 | 节点内搜刮与整理：奖励候选卡（价格/牌数/保护资格/配方用途）、公共区、三容器网格（复用 2.3 组件）、补给使用、完成搜刮确认 | ~260 行 |
| `scripts/ui/expedition_evac_panel.gd` | 新增 | 撤离决策页：收获分组（带入旧装备 vs 新增战利品）、保护区、生命/补给/下段风险，三按钮（回家/深入/返回整理） | ~170 行 |
| `scripts/ui/expedition_result_panel.gd` | 新增 | 回家结算面板：返还/获得/消耗/损失/金币变化分组数量变化、待领取提示、重复打开只回执 | ~190 行 |
| `scripts/ui/loadout_panel.gd` | 修改 | "出发"按钮接真实出发事务（替换 2.1 置灰），检查结果随事务返回刷新 | +35 行 |
| `scripts/ui/expedition_hub_panel.gd` | 修改 | 状态表接入"活动局"行（继续本局/主动放弃入口）、最高到达层数、待领取区领取入口 | +55 行 |
| `scripts/world/farm_world.gd` | 修改 | 组合根编排：出发事务、结算应用、启动恢复检测、实例化/移除 `expedition_screen`、关闭窗口走暂停 | +80 行 |
| `tests/d24_*.gd` 5 份＋`tests/capture_d24_*.gd` 2 份 | 新增 | 见 §5 | 共 ~750 行 |

不修改：`farm_hud.gd`（新面板一律独立文件，A1-3）、`combat_game.gd`/`battle_screen`/`inventory_game.gd`/`deck_builder.gd`（按模块地图仅引用；局内 carry 布局由 `InventoryGame` 绑定同形合成块实现，不改其代码）、`save_store.gd`。

## 3. 数据与存档

### 3.1 局档 `user://expeditions/run_<run_id>.json`（结构草案）

```jsonc
{
  "schema": "expedition_run_v1",
  "run_id": "run-<时间戳>-<随机段>",          // ExpeditionStore.new_run_id()，格式沿 2.1-W1
  "rules_version": "d2-baseline-v0.1",
  "player_id": "p-…",
  "created_at": 1760000000,
  "map_id": "layer1_fixed_v1",                 // 固定图；分支模板生成在 2.8 前后加入
  "rng_seed": 1234567,                         // 本局随机种子，出发时生成并保存（总计划 §6.1）
  "rng_rolls_used": 12,                        // 已推进步数；恢复时重建 rng 用
  "status": "active",                          // active | extracted | layer_clear | dead | abandoned
  "settlement_id": "",                         // finish() 时写入
  "layer": 1, "hp": 33, "max_hp": 40,
  "path": ["n0", "n1a"],                       // 已走节点序列，不回头
  "current_node": "n1a",
  "revealed": ["n0", "n1a"],                   // 已揭示节点集合；v0.1 固定图开局全揭示，字段为模板变化预留
  "nodes": {                                   // 每节点裁定记录：首次裁定时生成后固定，恢复不重生成
    "n1a": {
      "resolved": true,                        // 节点只能完成一次
      "encounter": "mud_bat_pair",             // 战斗敌人组合 id / 事件 id / null
      "battle_seed": 99123,                    // hash(rng_seed, node_id)，战斗意图与裁定恢复用
      "personal_pool": [ {"def_id": "copper_scrap", "quality": 1}, {"def_id": "small_potion", "quality": 1} ],
      "public_drop": {"def_id": "fiber_bundle"},// 可选公共物资，单人也能领取
      "picked_personal": -1,                   // 已选候选下标；选中后另一件消失
      "public_claimed": false,
      "event_state": null,                     // {"option_id": "dig", "outcome": {…}}，一次性
      "rest_choice": "",                       // rest8 | check_gear，确认后不可切换
      "dropped": []                            // 节点公共区（丢弃物，离开前可捡回，离开放弃）
    }
  },
  "carry": {                                   // 局内携带镜像；布局事务经 InventoryGame 绑定合成块单源处理
    "loadout": {"chest": [], "pack": [], "safe": []},   // 元素见下行 Instance
    "next_local_id": 5,                        // 局内新物 ID 发号（run 命名空间，结算时换发农场实例 ID）
    "consumed": [],                            // 已消耗实例（结算时不重复列为损失，设计 §9）
    "buffs": {}                                // 如休整"检查装备"：{"extra_draw_first_turn": 1}
  },
  "log": []                                    // 动作日志 {t, act, node, detail}，结算与排障用
}
```

- 局内 Instance：`{local_id, def_id, quality, container, cell:[x,y], rotated, from_farm, farm_instance_id}`。带入物 `from_farm=true` 并保留 `farm_instance_id`（返还=释放占用，不重复发放）；局内新物 `farm_instance_id=0`，结算时由农场 `next_instance_id` 换发。
- 写入时机：出发时建档；此后每个改变状态的动作（裁定、拾取、丢弃、事件选择、休整、战斗每步裁定、撤离/放弃确认）立即写盘（tmp→bak→替换）。这保证任意时点 kill 进程都可恢复到最近动作后状态。
- 战斗期间：把 2.2 `CombatGame` 的保存/恢复快照嵌入局档 `nodes[node]["battle_state"]` 一并落盘，恢复时原样重建手牌、回合与意图（2.2 设计 §9 边界）。
- 局档生命周期与目录约定：`user://expeditions/` 下 `run_<id>.json`（＋`.bak`/`.tmp`）与 `settlement_<id>.json` 并存；局档进入终态后原文件保留（状态字段为准），不做移动/删除——2.7 再引入归档清理。ID 前缀与格式严格沿用 2.1-W1（`run-…`／`act-…`／`settle-…`），跨阶段不改。

### 3.2 结算档 `user://expeditions/settlement_<settlement_id>.json`（结构草案）

```jsonc
{
  "schema": "expedition_settlement_v1",
  "settlement_id": "settle-<时间戳>-<随机段>",
  "run_id": "run-…", "player_id": "p-…", "created_at": 1760001234,
  "kind": "extract",                            // extract | layer_clear | death | abandoned
  "hp_left": 33,
  "coins_delta": 0,                             // v0.1 恒 0：货物回家仍是货物，出售才变金币（设计 §7）；字段为 2.5/2.8 事件金币预留
  "returned_brought": [ {"farm_instance_id": 1001, "def_id": "old_short_blade"} ],
  "gained": [ {"def_id": "copper_scrap", "quality": 1, "seed": null},
              {"def_id": "rock_sprout_seed", "quality": 1, "seed": {"kind": "rock_sprout", "traits": ["耐旱"]}} ],
  "consumed": [ {"farm_instance_id": 1005, "def_id": "small_potion"} ],
  "lost": [],                                   // 死亡/放弃：全部未保护存活携带（带入＋新得）；正常撤离为空
  "protected_kept": [],                         // 保险箱白名单保留（死亡/放弃时）
  "stats": {"nodes": 5, "battles_won": 3, "evac_row": 4}
}
```

### 3.3 农场档 `expedition` 块：本阶段启用的字段与新增字段

- `SAVE_VERSION` 保持 6（2.1 已升）。`active_run_ref`、`applied_settlements` 从本阶段起真实使用；新增 `pending_items`（待领取区）与 `stats`，`load_state` 读到缺失时补缺省，向后兼容 2.1～2.3 产出的 v6 档：

```jsonc
expedition: {
  /* …2.1 v6 既有字段原样（player_id/inventory/loadouts 等）… */
  "active_run_ref": "run-…",        // 非空＝存在活动局或未应用的终局
  "applied_settlements": ["settle-…"],  // 已应用结算 ID 去重表（总计划 §13：幂等从 2.4 开始）
  "pending_items": [],              // 待领取区 Instance（farm 命名空间，仓库满时的获得物）
  "stats": {"max_layer_reached": 0} // hub 面板"最高到达层数"
}
```

- 待领取区语义（设计 §7）：仓库满也能完成撤离，放不下的获得物进 `pending_items`；其中物品不可直接装入战备，须先 `claim_pending_expedition_items` 领取入仓库（容量内、风格同既有 `claim_pending`）；种子满则走农场既有 `state["pending"]["seeds"]`。容器本身不是物品实例，任何损失清册都不含容器（设计索引基线细化）。

## 4. 工作包拆解

W1→W9 为建议实施顺序；W2 完成后 W3/W4/W5 可并行，W7 依赖 W3/W4，W8 依赖 W5/W6，W9 收尾。

### W1 第一层固定地图与定义表（D2.4-02、D2.4-03、D2.4-04）

- 目标：`expedition_defs.gd` 落全第一层"苔石浅洞"内容定义，全部表驱动（总计划 §6.2：先固定图，分支生成标注"闭环跑通后加入"）。
- 文件：`expedition_defs.gd`（新增）。
- 实现要点：
  - 地图数据结构：`LAYER1 := {map_id, name, rows: 9, nodes: {node_id: {row, type, risk, hint, evac}}, edges: {node_id: [node_id…]}}`。0 排起点、8 排守门战与层末出口；每排 1～3 个候选；边只连相邻排、不回头。撤离排常量 `EVAC_ROWS := [4, 7]`：第 4 排全部节点 `type="rest_evac", evac=true`（免费小休整＋撤离，设计 §3），第 7 排 `type="evac", evac=true`（只撤离/继续，不恢复）。
  - `static func validate_layer1() -> Dictionary`：静态校验——图无环且边严格前进一排；除第 8 排外每节点有出边、除第 0 排外每节点有入边（无断路）；枚举全部起点→第 8 排路径，每条都经过第 4 排与第 7 排的撤离节点、且至少含一个非战斗资源节点（宝箱/采集/事件）；第 4/7 排节点 `evac` 全真、其余全假。
  - 事件表 `EVENTS`：设计 §4 三事件（狭窄裂隙／荒废药箱／洞壁幼芽），每项 `{event_id, options: [{option_id, cost_hp, gated_on_hp, outcomes: [{weight 或固定, grants/loss}]}]}`；概率与文案只在表里写一份（总计划 §6.2）。生命代价选项带 `hp_floor: 1`（设计：不能扣至 0），生命不足时选项禁用。
  - 休整选项表 `REST_OPTIONS := ["rest8", "check_gear"]`（恢复 8 生命／下一场首回合多抽 1 张）。
  - 奖励池 `REWARD_POOLS`：按节点类型分池（shallow_battle/shallow_chest/elite/gate），元素为 `{def_id, weight, quality}`；浅层以铜片、纤维、小补给、普通装备为主，少量岩芽菜种子（词条来源固定为候选池，不掉满配四词条），古旧摆件制造带货选择；第二层专有铁矿不进任何浅层池（设计 §5）。稀有种子条目带 `{seed_kind, trait_pool_id}`。
- 验证：`tests/d24_map_smoke.gd`——`validate_layer1()` 通过；逐排节点数、第 4/7 排撤离标记与设计 §3 表一致；全部池内 `def_id` 在 `ItemDefs` 存在；浅层池不含铁矿；事件表三事件的选项/代价与设计 §4 逐项相符。
- 依赖：无（`item_defs.gd` 的 def_id 由 2.1/2.3 交付，先定常量名即可并行）。

### W2 局快照、裁定固定与局档读写（D2.4-02、D2.4-04）

- 目标：`ExpeditionGame` 核心状态机与 `ExpeditionStore` 局档读写，实现"本局随机种子生成并保存、节点奖励首次裁定时生成后固定、恢复不重生成"。
- 文件：`expedition_game.gd`（新增核心部分）、`expedition_store.gd`（扩展）。
- 签名草案：

```gdscript
class_name ExpeditionGame extends RefCounted
func bind(run: Dictionary) -> void                    # 绑定局快照，原地读写
func inject_rng(rng: RandomNumberGenerator) -> void   # 测试注入；产线按 rng_seed + rng_rolls_used 重建
func snapshot() -> Dictionary                         # 完整局快照，供 save_run
static func departure_check(inventory: InventoryGame, expedition: Dictionary) -> Dictionary
                                                     # 硬阻止复用 2.1 LoadoutCheck＋无活动局校验
static func build_initial_run(run_id: String, player_id: String, seed_value: int, carry_mirror: Dictionary, now: int) -> Dictionary
func enter_node(node_id: String) -> Dictionary        # 只许相邻排前进；首次进入触发 _adjudicate 并落盘
func node_view(node_id: String) -> Dictionary         # 面板数据（类型/风险/倾向/连线/已裁定内容）
```

- 实现要点：
  - `_adjudicate(node_id)`：若 `run["nodes"]` 已有该节点记录则直接返回（关闭恢复、反复看详情都不重抽，设计 §5）；否则按节点类型用注入 rng 裁定敌人组合／候选二选一／公共物资／事件 id，连同 `rng_rolls_used` 写入节点记录；`battle_seed = hash(rng_seed, node_id)`。每个动作后由组合根调用 `ExpeditionStore.save_run`。
  - 局内 carry 布局：`InventoryGame.bind` 绑定合成块 `{warehouse: [], loadout: carry.loadout, next_instance_id: carry.next_local_id}`，放置/整理/丢弃规则单源（A3 红线），不改 `inventory_game.gd`。
  - `expedition_store.gd`：`save_run(run) -> bool`／`load_run(run_id) -> Dictionary`（主档失败读 `.bak`，三段式同 `SaveStore` 写法）；`ensure_dir()` 建 `user://expeditions/`。
- 验证：`tests/d24_run_smoke.gd`——同一种子两次构建的裁定结果逐项相等；`enter_node` 后重开（重新 bind＋load_run）不改变已裁定内容；跳排/回头被拒且给 reason；`rng_rolls_used` 随裁定推进；局档主档损坏时 `.bak` 可恢复。
- 依赖：W1。

### W3 节点处理器分发表与战斗/事件/休整接线（D2.4-03、D2.4-06）

- 目标：六类节点统一经分发表进入处理器；战斗节点组合 2.2/2.3 交付，宝箱/事件/休整改为表驱动裁定。
- 文件：`expedition_game.gd`（扩展）。
- 签名草案：

```gdscript
# 分发表（常量字典，类型→处理器方法名）：
# _HANDLERS := {battle: "_on_battle", elite: "_on_battle", gate: "_on_battle",
#               treasure: "_on_treasure", event: "_on_event", rest_evac: "_on_rest",
#               evac: "_on_evac", start: "_on_start"}
func begin_battle() -> Dictionary                   # DeckBuilder 由 carry 布局建牌组；CombatGame 带 run hp、battle_seed 与 buffs
func on_battle_finished(result: Dictionary) -> Dictionary   # 胜利→开启搜刮（状态清除、生命延续）；失败→待死亡结算
func choose_event_option(option_id: String) -> Dictionary   # 一次性；加权结果裁定即写入 event_state 固定
func choose_rest_option(option_id: String) -> Dictionary    # 二选一；确认后不可切换刷两份（设计 §4）
func use_supply(local_id: int) -> Dictionary                # 非战斗仅恢复类补给；消耗实体、效果同战斗、不产出牌能量
func request_extract() -> Dictionary                       # 当前节点可撤离且已完成时进入 finish("extract"/"layer_clear")
func request_abandon() -> Dictionary                       # 暂停菜单二次确认后调用；损失规则同死亡
```

- 实现要点：
  - 战斗：`begin_battle` 用 `DeckBuilder`（2.3）从 carry 三容器构建牌组快照，`CombatGame` 按浅层组合记录初始化；生命延续、格挡与战斗状态清零（设计 §3、2.2 规则）；休整 `check_gear` 的 `extra_draw_first_turn` 在本场第 1 回合消耗。精英节点进入前 UI 显示"高风险，偏向装备与稀有资源"（风险级别来自节点表，不伪装）。第 8 排守门战胜利＝完成第一层，`finish("layer_clear")`，本阶段不再向下。
  - 事件：`choose_event_option` 校验生命门槛（不足禁用）、`hp_floor=1`（代价不致死）、结果（含 60%/40% 加权）一次性写入 `event_state`；事件不自动扣农场钱包、不引入随身金币（设计 §4）。
  - 休整：第 4 排先二选一（取消允许、确认后锁定），之后开放撤离/继续；第 7 排无休整选项。
  - 撤离：`request_extract` 在撤离节点开放；"继续深入"即普通 `enter_node` 前进——当前撤离点随之关闭，不能远程回到上一撤离点（设计 §6）。
- 验证：`tests/d24_nodes_smoke.gd` 前半——固定种子下敌人组合与意图可复算；生命跨场延续、战后不回满；事件致命选项被 `hp_floor` 拦截、生命不足禁用；60/40 加权在固定种子下结果确定且恢复不变；休整二选一后另一项不可再选；buff 在下一场第 1 回合生效一次。
- 依赖：W2、上游 2.2/2.3 交付。

### W4 奖励领取与搜刮规则（D2.4-04、D2.4-05）

- 目标：奖励候选二选一、公共物资、丢弃/捡回、满包留置、完成搜刮确认的规则闭环。
- 文件：`expedition_game.gd`（扩展）。
- 签名草案：

```gdscript
func claim_personal(candidate_index: int) -> Dictionary   # 二选一；选中后另一件从候选消失
func claim_public() -> Dictionary                         # 公共物资领取，不占个人选择次数（设计 §5）
func drop_item(local_id: int) -> Dictionary               # 丢入当前节点公共区；受保护物移出保险箱即失保护并明示
func pick_from_common(local_id: int) -> Dictionary        # 离开当前节点前可捡回
func finish_node() -> Dictionary                          # 完成搜刮：未领取/未捡回物品放弃，节点 resolved，返回摘要
func carry_summary() -> Dictionary                        # 顶部状态条与撤离页数据：补给数/可售携带价值/保护内容/未保护价值
```

- 实现要点：拾取走 `InventoryGame` 放置校验（放不下给出"还差连续空间"类 reason，复用 2.3 文案），满包时新物品留在奖励区，禁止自动按价格取舍、不自动清基础武器（设计 §5）；战斗胜利一刻不等于已获得奖励，"带回"条件只在回家结算满足（设计 §5）；节点 `resolved` 后其公共区与未领取奖励全部放弃（离开放弃、不可回头）。
- 验证：`tests/d24_nodes_smoke.gd` 后半——二选一后另一候选不可再领；公共物资领取不改 `picked_personal`；满包领取被拒且奖励保留；丢弃→捡回→离开后丢弃物消失；`finish_node` 返回未领取摘要；丢弃基础武器不触发自动补发。
- 依赖：W2（与 W3 并行；战斗奖励入口接 W3 的胜利回调）。

### W5 出发事务与出发接线（D2.4-01、总计划 §9.3）

- 目标：战备面板"出发"按钮接真实流程（替换 2.1 置灰）；出发事务步骤落成明确序列，中途失败按记录恢复。
- 文件：`farm_world.gd`（编排）、`farm_game.gd`（占用写入侧复用 2.1 API）、`loadout_panel.gd`、`expedition_hub_panel.gd`（修改）。
- 出发事务步骤序列（编排函数 `_start_run()`，规则/校验在 domain、落盘在 services，满足 A1 分层）：
  1. 校验：`ExpeditionGame.departure_check` 无硬阻止（含 2.1 `LoadoutCheck`：首回合牌库非空、无活动局、布局合法）；`rules_version` 一致。
  2. `run_id = ExpeditionStore.new_run_id()`（生成局 ID）。
  3. 写占用：`InventoryGame.set_run_occupied(run_id)` → `expedition.active_run_ref = run_id` → `SaveStore.save_state` 单次落盘（带入清单即占用快照；带入物不搬离农场容器，只镜像进局档，容器布局与配装预设不消耗，设计 §2）。
  4. 本机确认参与者资料：`player_id`、`rules_version`、带入清单校验和写入快照头部（此步在 2.6 为主机确认，位置不变，总计划 §9.3）。
  5. 生成本局随机种子（注入或挂钟）并 `build_initial_run` 构建初始快照（生命 40/40、起点、全图揭示、carry 镜像）。
  6. `ExpeditionStore.save_run` 写局初始快照（tmp→bak→替换）。
  7. 步骤 4～6 任一失败：回滚第 3 步（`clear_run_occupied(run_id)` → `active_run_ref=""` → 再落盘），返回 `{ok:false, reason}`，停留在战备界面；出发前失败不扣任何物品。
  8. 成功：实例化 `expedition_screen` 进入洞窟，展示开局概览卡（层名/建议风险/当前目标/已带物品/保护区，设计 §2）。
  - 恢复语义：任何时点发现"占用已写、局档不存在"→ 判定出发未正式开始，按第 7 步同款回滚恢复到出发前（不猜删物品）；"占用已写、局档存在"→ 恢复同一局（暂停恢复，不返还带入装备，设计 §2 与设计索引基线细化）。
- 实现要点：`loadout_panel` 出发按钮调用编排入口并展示失败原因；`expedition_hub_panel` 状态表接入"活动局"行（继续本局入口）。农场时间不受出发影响（现实时间驱动，2.1 已固化）。
- 验证：`tests/d24_run_smoke.gd` 续——注入 `save_run` 失败模拟第 6 步中断：占用被回滚、物品仍在原容器、可立即再次出发；成功路径后 `occupied_by_run==run_id` 且农场档已落盘。
- 依赖：W2（W3/W4 可并行推进）。

### W6 结算事务与农场回写（D2.4-07、总计划 §9.3、§13）

- 目标：撤离/死亡/放弃/层末四类终局生成唯一结算并在个人档单次保存中幂等应用；仓库满也能完成撤离。
- 文件：`expedition_game.gd`（`finish`）、`farm_game.gd`（应用）、`expedition_store.gd`（结算档）、`plant_defs.gd`（岩芽菜）、`expedition_baseline.gd`（容量常量）。
- 签名草案：

```gdscript
# expedition_game.gd
func finish(kind: String) -> Dictionary   # 生成唯一结算 ID；按 carry 生成分组结算记录（§3.2 结构）

# farm_game.gd
func apply_expedition_settlement(settlement: Dictionary, now: int) -> Dictionary
                                         # 幂等：查 applied_settlements → 释放占用 → 返还/获得/种子/金币入账 → 登记；纯内存事务
func claim_pending_expedition_items() -> Dictionary   # 待领取区→仓库（容量内），重复领取不产生新物品
func expedition_pending_summary() -> Dictionary       # 待领取数量/最高价值
```

- 结算事务步骤序列（编排函数 `_apply_settlement(settlement)`）：
  1. 局终确认（撤离面板/战斗死亡/放弃二次确认）后 `finish(kind)` 生成 `settlement_id` 并按 §3.2 分组：返还＝仍存活 `from_farm` 实例；获得＝存活新物（种子带 `{kind, traits}`）；消耗＝`consumed`（死亡时不再列为掉落，设计 §9）；损失＝死亡/放弃时的全部未保护存活实例；保护＝保险箱内白名单实例。装备返还按"释放占用"、新物按"获得"分组，不重复给带入装备（设计 §7）。
  2. 先写 `settlement_<id>.json`（三段式），再把局档 `status` 置终态＋`settlement_id` 落盘。局档状态是"局是否终局"的唯一权威；有结算档而局档仍 active 的孤儿结算档按废档忽略、不应用。
  3. 个人档单次保存中应用：`apply_expedition_settlement` 在同一内存事务内完成——去重检查 → `clear_run_occupied`＋`active_run_ref=""`（返还物留在原容器位）→ 获得物按 `WAREHOUSE_ITEM_CAP` 入仓库、溢出进 `pending_items` → 种子按现有种子体系入 `state["seeds"]`（满则入既有 `state["pending"]["seeds"]`，用现有 `_new_seed(kind, traits)`/`next_id`）→ `coins_delta` 入账并写既有 `ledger`（reason 前缀 `expedition:<kind>`）→ `stats.max_layer_reached` 更新 → 登记 `applied_settlements` → 随后单次 `SaveStore.save_state`。
  4. 重复确认只回执：同一 `settlement_id` 再次提交（再次打开结算面板、重启后重放）→ 返回 `{ok:true, applied:false, reason:"already_applied"}`，不重发任何物品、不重复释放占用（幂等从本阶段开始，不等 2.7，总计划 §13）。
  5. 第 2 步成功而第 3 步中途崩溃：启动恢复发现 `active_run_ref` 非空且局档终态 → 自动按结算档补应用一次（幂等保证不重发）；局档写失败则局停留在终局前状态允许重试，不进入半应用。
- 实现要点：死亡/放弃只损失未保护携带（带入＋新得），保险箱白名单物保留、农场未带入资产/容器容量/解锁不受影响；失败后 hub/战备提示可 `grant_basic_kit` 补领缺失基础装备（2.1 API，活动局占用期间也计为拥有）。岩芽菜最小完整配置进 `plant_defs.gd`（待澄清项见 §6）。
- 验证：`tests/d24_settle_smoke.gd`——设计 §9 算例全量复演（正常撤离/死亡两分支逐项断言）；死亡时保险箱种子保留、带入三件与战利品进 `lost`、消耗药不重复列；满仓撤离成功且溢出全部进 `pending_items`、领取后可再入战备；同结算 ID 二次应用只回执；结算后 `occupied_by_run` 清空、可立即再出发。
- 依赖：W2、W4（W5 完成后可端到端）。

### W7 洞窟整屏 UI（D2.4-01、02、05、06）

- 目标：地图、搜刮、撤离决策、暂停菜单四组界面与顶部状态条，实机可玩。
- 文件：`expedition_screen.tscn`＋`expedition_screen.gd`、`expedition_map_panel.gd`、`expedition_loot_panel.gd`、`expedition_evac_panel.gd`（新增）。
- 实现要点：
  - `expedition_screen` 由 `farm_world` 实例化为全屏子节点（不换场景树、不加 autoload，农场在洞窟期间继续按现实时间成长，总计划 §7.1）；顶部持续显示生命、补给数量、可售携带价值、已保护物品、当前层数（`carry_summary` 数据源）。开局概览卡一次（恢复局不重复弹）。
  - 地图面板：自下向上 8 排渲染，显示已揭示节点类型/风险/资源倾向/连线/当前位置，精英风险醒目；只允许相邻排节点进入；第 4/7 排撤离标记按 `evac` 字段。具体敌人组合/事件选项/掉落不提前显示（进入节点才见，设计 §2）。
  - 搜刮面板：复用 2.3 容器网格与物品详情组件；奖励卡显示价格、牌数、保护资格与配方用途；丢弃进当前节点公共区可捡回；"完成搜刮"弹未拿物资摘要（数量＋最高价值候选）确认后关闭节点；补给使用入口在此与休整页（设计 §4）。满包提示直接进入整理。
  - 撤离面板：主区域"现在已获得什么"（新增可售价值/材料/种子/可保留装备/保护区内容/未保护携带价值，带入旧装备与新增战利品分组）；旁栏生命/补给/下段风险与资源倾向（不给准确胜率）；按钮"带着这些回家／继续深入／返回整理"（设计 §6）。
  - 暂停菜单：继续、查看牌组、查看物品、返回农场并暂停、主动放弃；放弃单独展示失去物品清单、确认后才结算，不放在普通关闭位置（设计 §2）。窗口关闭（`NOTIFICATION_WM_CLOSE_REQUEST`＋`set_auto_accept_quit(false)`）＝保存局快照并按暂停处理，绝不视为放弃（设计索引基线细化：退出造成暂停恢复、主动放弃才触发损失）。
  - 战斗时在 `expedition_screen` 内打开 2.2/2.3 的 `battle_screen.tscn` 子场景，胜利回搜刮、失败进死亡结算。
- 验证：`tests/capture_d24_map.gd`——开局地图、搜刮、撤离决策三张截图进 `screenshots/`；手工跑 `world_picking_smoke` 思路确认农场入口不受影响。
- 依赖：W3、W4。

### W8 结算面板、恢复入口与待领取 UI（D2.4-07、总计划 §9.4）

- 目标：回家结算面板、启动恢复检测与待领取区领取入口闭环。
- 文件：`expedition_result_panel.gd`（新增）、`expedition_hub_panel.gd`、`farm_world.gd`（修改）。
- 实现要点：
  - 结算面板：分别列返还（释放占用）/获得/消耗/损失/金币变化的数量变化清单（带入装备不显示为新增），满仓时提示待领取区；关闭后回农场视角。重复打开只回执已应用状态。
  - 启动恢复检测（`farm_world._ready` 组合根，决策表）：

| 启动时观测 | 处理 |
| --- | --- |
| `active_run_ref` 为空 | 正常进农场 |
| 非空、局档不存在/主备皆损坏 | 判定出发未正式开始：按 W5 第 7 步回滚占用并提示；主备皆损坏保留占用并提示（完整矩阵 2.7） |
| 非空、局档 `status=active` | hub 面板"恢复本局"（重进 `expedition_screen` 原样重建地图与奖励）或"主动放弃"（走死亡规则结算） |
| 非空、局档终态、结算未应用 | 自动补应用结算一次（幂等），进结算面板 |

  - 待领取区入口在 hub 面板（数量/最高价值摘要＋领取按钮），仓库界面本阶段不做（2.5）。
- 验证：`tests/capture_d24_result.gd`——撤离与死亡两张结算面板截图；手工：实机强退后重启走一遍恢复路径。
- 依赖：W5、W6。

### W9 强退恢复模拟、回归、试玩关口 A 与交付

- 目标：验证"出发与结算之间任意时点 kill 进程→重开恢复同一地图与奖励"，收尾交付。
- 文件：`tests/d24_recovery_sim.gd`、`docs/archive/Godot_阶段2.4_交付报告.md`。
- 实现要点：
  - 恢复模拟（脚本模拟强退：每个检查点写完快照后直接冷加载，不走正常退出路径）：检查点取——出发落盘后、首次裁定后、拾取后、事件选择后、战斗中途（含 `battle_state`）、撤离确认后（结算档已写、农场未应用）。每点：新进程内全新实例从磁盘重读农场档＋局档，断言地图节点、已裁定奖励、`picked_personal`、生命、公共区、手牌与意图逐项一致；"结算档已写、农场未应用"点断言启动补应用恰好一次且不重发。
  - 回归：跑 2.1～2.3 全部 `tests/d2*_*.gd` 与第一大阶段 `stage1~6`、`world_picking_smoke`；本阶段 7 份新测试。
  - 实机验收对照总计划 §10-2.4 六条：提前撤离得合法收益；死亡只保留白名单物；重复回家不重复发装备；关闭重启恢复同一地图与奖励；满仓可安全结束本局；出发与结算之间任意强退可恢复。
  - 交付报告：实际采用值（地图表、事件、奖励池、容量常量）、恢复检查点结果、试玩关口 A 三种玩法记录、已知问题；更新总计划 §10-2.4 状态与 `docs/README.md`、根 `README.md`、代码计划索引。
- 依赖：全部。

## 5. 测试与验收汇总

| 测试 | 覆盖 | 对应总计划 §12.1 |
| --- | --- | --- |
| `tests/d24_map_smoke.gd` | 固定图连通性、第 4/7 排撤离、每路线含非战斗资源、奖励池合法且不含铁矿、事件表 | 探索-地图连通 |
| `tests/d24_run_smoke.gd` | 出发事务成功/中断回滚、占用、种子固定、裁定不重抽、节点只能完成一次、局档 .bak | 存档-活动局恢复；探索-奖励固定 |
| `tests/d24_nodes_smoke.gd` | 战斗接线与生命延续、事件规则与加权、休整二选一、奖励二选一/公共物资/满包/丢弃捡回 | 探索-节点只能完成一次；战斗-延续 |
| `tests/d24_settle_smoke.gd` | 设计 §9 算例、保险箱保护、满仓撤离、种子入种子体系、幂等回执、占用释放 | 库存-带入返还/新获得/满仓；存档-重复结算 |
| `tests/d24_recovery_sim.gd` | 六个检查点冷恢复一致性、结算补应用恰好一次 | 存档-活动局恢复、写入失败 |
| `tests/capture_d24_map.gd`、`tests/capture_d24_result.gd` | 地图/搜刮/撤离、撤离/死亡结算截图 | 实机记录 |

- 运行方式沿用根 README 的 PowerShell 形式（`--headless --path . --script res://tests/…`），随机种子与时间注入，测试档用 `user://d24_*.json` 自定义路径，禁止碰真实玩家档（A1-6）。
- 实机验收（真实窗口，总计划 §12.3）：§4-W9 六条逐项；另做一次真实 kill 进程复测（任务管理器结束进程后重启）对应恢复路径，与脚本模拟互为印证。界面检查按总计划 §8.1：地图/搜刮/撤离/结算四屏在当前窗口尺寸与 1080p 下可操作，满背包与长物品名（如"古旧摆件"详情卡）不溢出；撤离"继续深入"等关键操作有图标配文字，不裸用颜色区分风险。
- 试玩关口 A（三种玩法，总计划 §10-2.4、设计 §10），每条记录：单局时长、每个撤离点的决定与理由、生命曲线、搜刮取舍（至少一次"腾空间"决定）、结果与带回/损失清单、净收益：
  1. 轻装短途：只带基础装备与一瓶药，目标第 4 排撤离；
  2. 带货深入：带古旧摆件等贵重货走第 7 排乃至守门战，记录中途是否想丢货；
  3. 满载撤离：接近满包后在最近撤离点回收，含一次满包留置与待领取区领取。
  通过标准：玩家能清楚指出至少一次"因为收获而改变是否继续"的决定（设计 §10）；若试玩者不关心搜到什么或何时撤离，优先调整物品与战斗，不扩层数（总计划 §10-2.4）。记录归档进交付报告。

## 6. 风险与回退

- 局档写入频率高（每动作一写）：单局 JSON 小、三段式开销可接受；若实测掉帧，把落盘改为动作后延迟合帧写，但撤离/结算/放弃确认必须同步写完再继续——此调整须写进交付报告。
- 跨文件原子性残余窗口（结算档已写、农场未应用时崩溃）：以启动补应用＋`applied_settlements` 幂等覆盖（W6 第 5 步、W8 决策表）；完整故障矩阵与未决结算重发属 2.7，本阶段不宣称覆盖。
- 2.3 组件复用不确定（其计划与本文并行编写）：本文按 2.1 附录 A2 模块地图口径引用容器网格/详情组件；若 2.3 未抽出可复用控件，W7 先做最小抽取（移动到独立控件文件），不复制第二套网格逻辑。
- 岩芽菜最小配置与 2.5"完整可种新植物"的边界、市场报价与词条池初值可能返工：配置集中在 `plant_defs.gd` 单处，改动不扩散。
- 数值风险（八排长度、两次撤离频率、休整恢复 8、二选一候选，设计 §10 未验证事项）：全部集中在 `expedition_defs.gd` 表内，试玩调整不改代码结构；调整须保持地图连通、奖励固定、结算清晰三约束。
- 回退粒度：每工作包一提交（A1-7）；W5/W6 涉及 `farm_game.gd`/档结构，单独提交可整体回退而不影响 W1~W4 纯新增规则代码；W7/W8 纯 UI 可独立回退（回退后 2.1 的置灰入口恢复原状）。
- 待设计澄清项：
  1. 岩芽菜在 2.4 即会掉落并可播种：其最小完整配置（词条池是否先复用现有通用池、市场报价锚点）需设计确认，v0.1 暂用现有词条池与白菜锚点同级报价。
  2. 守门战胜利按 `layer_clear`＝成功撤离＋守门奖励处理；是否给"首通第一层"额外奖励，设计未给数值，v0.1 不加，留 2.8。
  3. 第 4 排休整二选一是否可跳过（直接撤离而不选休息/检查装备）：v0.1 按"先完成二选一才出现撤离/继续按钮"实现（设计 §3"免费进行一次小休整并选择撤离"的读法），待确认。
  4. `WAREHOUSE_ITEM_CAP` 初值（v0.1 取 60）及其与 2.5 设施升级的衔接，需在 2.5 设计确认后回填 `expedition_baseline.gd`。
  5. "返回农场并暂停"期间农场可玩范围（v0.1 允许正常种地/卖菜，占用物品除外），设计未明说，待确认。
  6. 撤离页"下一段风险与资源倾向"的文案粒度（按节点类型还是按排），v0.1 按节点表的 `risk/hint` 字段直出。

## 7. 交付物清单

- 代码：§2 表中 8 个新文件（`expedition_defs.gd`、`expedition_game.gd`、`expedition_screen.tscn`＋脚本、4 个面板脚本）与 7 处修改（`expedition_store.gd`、`farm_game.gd`、`expedition_baseline.gd`、`plant_defs.gd`、`loadout_panel.gd`、`expedition_hub_panel.gd`、`farm_world.gd`）。
- 测试：§5 的 7 份脚本（5 规则/模拟＋2 截图）。
- 数据示例：`expedition_defs.gd` 内固定地图表、事件表、休整选项、奖励池即"节点与战利品数据示例"交付项（总计划 §6）；`plant_defs.gd` 岩芽菜条目。
- 文档：`docs/archive/Godot_阶段2.4_交付报告.md`（实际采用值、恢复检查点记录、试玩关口 A 三种玩法记录）；更新总计划 §10-2.4 状态、代码计划索引、`docs/README.md` 与根 `README.md`。
- 截图：`screenshots/` 内地图、搜刮、撤离、结算四类实机记录。
