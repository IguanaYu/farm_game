# 2.1 规则基线与工程基础：代码执行计划 v0.1

日期：2026-10-01。状态：未开始。适用工程：Godot 4.6.1（GL Compatibility）、Windows、现有 farm 工程。

导航：[整体开发计划](../Godot_第二大阶段_农场与合作洞窟_整体开发计划_v0.1.md)｜[2.1 详细设计](../design/Godot_阶段2.1_规则基线与工程基础_详细设计_v0.1.md)｜[设计索引](../design/第二大阶段详细设计索引.md)｜[代码计划索引](第二大阶段代码执行计划索引.md)

本文把 2.1 详细设计拆成可执行的 Godot 代码任务。设计内容（规则、数值、界面行为）以详细设计为准，本文不重述，只引用 `D2.1-XX` 功能号。本文末尾的**全阶段工程约定与模块地图**是 2.2～2.9 各代码计划的共同依据，后续计划只引用、不另立约定。

## 1. 输入与前置

- 前置：无（本阶段是第二大阶段的第一个子阶段）。
- 现有代码基础（组合方式见模块地图）：
  - `scripts/domain/farm_game.gd`：农场规则，`SAVE_VERSION = 5`，状态为单个 Dictionary，时间戳与随机数由调用方注入。
  - `scripts/services/save_store.gd`：静态类，主档／`.bak`／`.tmp` 三段式写入，路径可参数化。
  - `scripts/world/farm_world.gd`：主场景脚本（组合根），3D 拾取打开面板；`scripts/ui/farm_hud.gd`：全部 UI 代码构建。
  - 测试约定：`tests/*.gd` 为 `extends SceneTree` 脚本，用 `--headless --path . --script` 运行，随机种子固定注入。
- 设计功能范围：D2.1-01 农场新入口、D2.1-02 信息对象与归属、D2.1-03 战备首页、D2.1-04 准备检查、D2.1-05 基础装备底线、D2.1-06 生命周期与占用。
- 明确不在本阶段：真实出发与扣物、拖放／旋转／自动整理（2.3）、战斗（2.2）、地图与结算（2.4）、联机房间（2.6）。出发入口显示"洞窟功能准备中"，不做假出发（设计 §1）。

## 2. 新增与修改的工程结构

| 文件 | 动作 | 责任 | 预估规模 |
| --- | --- | --- | --- |
| `scripts/domain/expedition_baseline.gd` | 新增 | 规则基线常量（设计 §2 的表）＋共用枚举＋格子几何静态函数（占用矩形、合法放置判定） | ~120 行 |
| `scripts/domain/item_defs.gd` | 新增 | 物品定义表：基础套装、演示物品；字段含尺寸、类别、允许容器、保护资格、可售性、来源牌序列 | ~200 行 |
| `scripts/domain/card_defs.gd` | 新增 | 牌定义表：基础套装 8 张牌涉及的牌型骨架（效果体系统一在 2.2 落地，本阶段只定字段与展示信息） | ~80 行 |
| `scripts/domain/inventory_game.gd` | 新增 | 物品实例、归属状态机、基础装备发放／补领、占用标记、牌组预览（按加入回合分组） | ~300 行 |
| `scripts/services/expedition_store.gd` | 新增 | 局档／结算档的存取边界与 ID 生成（局 ID、动作 ID、结算 ID）；本阶段只落骨架与读写封装 | ~120 行 |
| `scripts/ui/expedition_hub_panel.gd` | 新增 | 洞窟入口概览面板（设计 §3 的状态表，本阶段实现"无活动局／未开放"两态） | ~180 行 |
| `scripts/ui/loadout_panel.gd` | 新增 | 战备首页 v0：三容器网格、物品详情、牌组预览、顶部统计、演示标识（设计 §5） | ~350 行 |
| `scripts/world/farm_world.gd` | 修改 | 场景新增洞窟入口、战备箱、制作台占位三个可点击对象，接进现有拾取分发 | +60 行 |
| `scripts/ui/farm_hud.gd` | 修改 | 挂接两个新面板的打开／关闭与遮罩管理（沿用现有 modal 模式） | +40 行 |
| `scripts/domain/farm_game.gd` | 修改 | `SAVE_VERSION` 5→6；`load_state` 增加 v5→v6 迁移；`new_game` 写入 `expedition` 初始块 | +90 行 |
| `tests/d21_defs_smoke.gd` 等 5 份 | 新增 | 见 §5 | 共 ~400 行 |

## 3. 数据与存档

### 3.1 存档版本迁移（对应总计划 §9.5）

- `FarmGame.SAVE_VERSION` 升为 6。`load_state` 读到 `version == 5` 时执行 `_migrate_v5_to_v6(source)`：原字段原样保留，追加 `expedition` 块后按 6 版加载；未知版本仍拒绝并提示（现有行为）。
- `expedition` 块初始结构（本阶段落地的字段）：

```text
expedition: {
  player_id: String            # 首次生成并终身稳定，"p-" + 时间戳 + 随机段
  next_instance_id: int        # 物品实例 ID 发号器，从 1000 起
  inventory: {                 # InventoryGame 维护
    warehouse: [Instance…]     # 装备/材料库存（带物品回家的家，2.5 扩展）
    loadout: {chest: [Instance…], pack: […], safe: […]}   # 战备容器，Instance 含 container/cell/rotated
    occupied_by_run: String    # 活动局 ID 或空；非空时 loadout 全量视为占用
  }
  loadouts: [ {name, items: [{def_id, container, cell, rotated}…]} ]   # 配装预设=要求清单，不拥有实例
  active_run_ref: String       # 活动局引用，2.4 起使用，本阶段恒空
  applied_settlements: [String]# 已应用结算 ID 去重表，2.4 起使用，本阶段恒空
}
```

- Instance 结构（`InventoryGame` 内部约定，测试据此断言）：`{instance_id, def_id, quality, container, cell:[x,y], rotated, demo:false, source}`。`demo:true` 的实例只在内存，任何保存前统一剔除。
- 物品实例 ID 全存档唯一；局 ID／动作 ID／结算 ID 由 `ExpeditionStore` 生成（`run-…`／`act-…`／`settle-…` 前缀），格式一次定死，后续阶段不改。
- 局档路径预留 `user://expeditions/run_<run_id>.json`，结算路径 `user://expeditions/settlement_<settlement_id>.json`；本阶段只实现 `ExpeditionStore.save_run/load_run` 的空壳与 ID 生成，不写业务。

### 3.2 农场档与探险档分离

- 农场档继续是 `user://farm_save_v1.json`（不换文件名），只增加 `expedition` 块；`SaveStore` 不改，`ExpeditionStore` 复用其三段式写法但独立实现（避免 SaveStore 承担两职责）。
- 测试档继续用自定义路径注入（`user://d21_*.json`），不动真实存档。

## 4. 工作包拆解

每个工作包独立可验证；W1→W9 顺序即建议实施顺序，W4 依赖 W2/W3，W6 依赖 W5，其余可小范围并行。

### W1 规则基线常量与 ID 体系

- 文件：`expedition_baseline.gd`、`expedition_store.gd`（ID 部分）。
- 要点：
  - 基线常量逐项对应设计 §2：`MAX_HP=40`、`ENERGY_PER_TURN=3`、`DRAW_PER_TURN=5`、`HAND_LIMIT=10`、容器尺寸 `CHEST 3×4 / PACK 4×4 / SAFE 1×2`、加入回合 `JOIN_ROUND = {chest:1, pack:2, safe:3}`、`PROTO_RULES_VERSION = "d2-baseline-v0.1"`（写入存档与交付报告，作为规则版本锚点）。
  - 几何静态函数：`cells_of(size, cell, rotated) -> Array[Vector2i]`、`can_place(container_cells, occupied_cells, item) -> bool`。2.1 的战备用"点击物品→自动找首个合法位"，背包整理器（自动摆放搜索）留给 2.3。
  - ID 生成：`InventoryGame.next_instance_id()`（存档内递增）；`ExpeditionStore.new_run_id()/new_action_id(peer)/new_settlement_id()`（时间戳＋随机段，格式常量化）。
- 验证：`tests/d21_defs_smoke.gd`——基线常量与设计 §2 逐项相等；矩形旋转 90° 后占格正确；ID 连续且不重复。

### W2 物品与牌定义表（D2.1-02、D2.1-05）

- 文件：`item_defs.gd`、`card_defs.gd`。
- 要点：
  - 定义字段按设计 §4：名称、类别（武器/防具/工具饰品/补给/材料/稀有种子/货物）、品质、占格、可放容器、来源牌序列（列表长度=占格数，允许重复，即"占 N 格给 N 张牌"）、售价值、保护资格、`basic_kit` 标记、`demo` 标记。
  - 基础套装三件（设计 §7）：旧短刀 1×2 两张攻击牌、木盾 2×2 四张防御牌、行囊工具 1×2 两张辅助牌；合计 8 格／8 张。牌的名称与效果数值引用 2.2 设计 §的牌表（本阶段先按 2.1 设计 §7 的骨架占位，2.2 校正）。
  - 演示物品 2～3 件（含一件大尺寸货物），`demo:true`，只出现在战备预览，不进存档。
  - `card_defs.gd` 字段：`{id, name, cost, target, effect_kind, params, desc}`；`effect_kind` 本阶段只注册不实现。
  - 基础装备约束落在定义上：`sellable=false`、不可作制作输入、不可分享（2.3/2.5 的相应系统读取该标记，本阶段先写进字段与校验函数 `ItemDefs.is_basic(def_id)`）。
- 验证：`tests/d21_defs_smoke.gd` 续——基础套装占格数=牌实例数=8；所有定义的 `cards.size() == w*h`；demo 物品与正式物品 `def_id` 不冲突。

### W3 物品归属与库存规则（D2.1-02、D2.1-05、D2.1-06）

- 文件：`inventory_game.gd`。
- 接口草案：

```gdscript
class_name InventoryGame extends RefCounted
func bind(state: Dictionary) -> void            # 绑定 game.state["expedition"]["inventory"]，原地读写
func grant_basic_kit() -> Dictionary            # 首次全赠；之后只补缺失部件；{ok, granted:[def_id], already_had:[def_id]}
func basic_kit_missing() -> Array               # 当前缺哪些基础部件（活动局中的也计入拥有，设计 §7）
func add_instance(def_id, source, quality := 1, demo := false) -> Dictionary
func move_to_loadout(instance_id: int, container: String) -> Dictionary   # 自动找位；失败给 reason（满/非法容器/演示物）
func move_to_warehouse(instance_id: int) -> Dictionary
func find_first_fit(container: String, size: Vector2i, rotated := false) -> Variant
func owner_of(instance_id: int) -> String       # warehouse/chest/pack/safe/none——归属唯一（设计 §4）
func set_run_occupied(run_id: String) -> Dictionary   # 写 occupied_by_run；重复调用拒绝
func clear_run_occupied(run_id: String) -> Dictionary # 校验 run_id 一致才清除
func is_run_occupied() -> bool
func deck_preview() -> Dictionary               # {join_round_1:[牌实例…], …, totals:{…}}，按容器→加入回合分组
func strip_demo_instances() -> void             # 保存前调用
```

- 规则要点：同一实例任何时刻只有一个归属位置——所有移动都是先验证目标合法、写新位置、再清旧位置的单事务（在函数内完成，无中间暴露）；`owner_of` 是测试断言归属唯一性的入口。基础部件每种限一件：`add_instance` 对 `basic_kit` 定义查重（含 loadout 与占用中）。
- 验证：`tests/d21_inventory_smoke.gd`——发放→装入胸挂→`owner_of` 变化；把木盾移到背包后 `deck_preview()` 第 1 回合张数从 8 降为 4（对应设计 §9 场景）；满容器拒绝且 `reason` 可读；重复补领不增发；`set_run_occupied` 后再次 `set_run_occupied` 被拒；`strip_demo_instances` 后演示物消失而正式物保留。

### W4 旧档迁移（总计划 §9.5、验收第一条）

- 文件：`farm_game.gd`。
- 要点：
  - `new_game` 直接产出 v6 结构（含 `expedition` 块与 `player_id`）。
  - `_migrate_v5_to_v6`：v5 原字段零改动搬运，追加默认 `expedition` 块；金币、种子（含词条）、十块地拥有状态、成长经验、市场锁定、育种机进度逐字段保留。
  - 迁移失败（结构异常）返回 `false`，调用方提示恢复选项，不静默新建农场。
- 风险：现有回归测试断言 `state["version"] == 5`（`tests/stage1_smoke.gd` 等）——本工作包同步把这些断言改为 6 并在交付报告记录；"原八项回归保持通过"按行为口径验收，不是字面断言不变。
- 验证：`tests/d21_migration_smoke.gd`——构造 v5 样例档（含育种机中批次、词条种子、锁定市场）迁移后逐项相等；v6 档直接加载不触发迁移分支；version 7 拒绝加载。

### W5 农场场景入口（D2.1-01）

- 文件：`farm_world.gd`、`expedition_hub_panel.gd`、`farm_hud.gd`。
- 要点：
  - 场景加三个可点击占位：洞窟入口（农场边缘，不遮挡地块/商店/仓库的拾取区）、战备箱（入口旁）、制作台（带"尚未开放"说明）。模型优先复用现有 glb（如 `deco_*`／`facility_*`）或临时 `BoxMesh`＋纯色材质，登记进 `assets/stage1_manifest.json` 的同一套盘点方式；正式素材 2.8 替换。
  - 洞窟入口打开 `expedition_hub_panel`（概览）：最高到达层数（本阶段 0/未解锁）、当前目标文案、单人出发（置灰＋"洞窟功能准备中"）、好友组队（置灰）、战备配置（打开战备）、操作说明；首次打开显示"建议先配好装备"引导段，可关闭。状态表（设计 §3）本阶段实现"无活动局"与"新功能未开发"两行，其余状态 2.4/2.6 接入时补。
  - 战备箱直接打开战备面板；制作台弹"尚未开放"。关闭任何面板回到同一农场视角（沿用 farm_hud 现有 modal 关闭路径）。
- 验证：`tests/capture_d21_hub.gd` 截图概览与关闭后农场视角进 `screenshots/`；手工确认新增入口不影响原有点击（跑一遍 `tests/world_picking_smoke.gd` 思路的既有用例）。

### W6 战备首页 v0（D2.1-03、D2.1-04）

- 文件：`loadout_panel.gd`。
- 要点（按设计 §5 布局）：
  - 左：仓库列表＋类别筛选；中：三容器网格（底格＋已放物品块，尺寸按格渲染）；右：物品详情（名称/类别/品质/占格/可放容器/来源牌/售价值/保护资格/归属）＋牌组预览（按加入回合分组、重复牌叠卡可展开）；下：预设位（本阶段只读展示默认配置）、清空配置、返回。
  - 顶部统计条：生命上限、已用格数、首回合牌数、后续加入牌数、携带可售价值（基础装备显示"基础装备，不计可售价值"）、失败保护价值。
  - 放置交互本阶段为点击式：选中物品→点容器→`InventoryGame.move_to_loadout` 自动找位；非法给出面板内原因提示。拖放/旋转/自动整理在 2.3 升级，本阶段网格渲染已按 `rotated` 支持（数据结构预留）。
  - 演示物品带"演示"角标，仅可放入预览、不写存档；面板打开时由 `InventoryGame` 临时注入，关闭即弃。
  - 准备检查（D2.1-04）实现为纯函数 `LoadoutCheck.evaluate(inventory) -> {hard_blocks:[…], advises:[…]}`：硬阻止=未解决活动局/归属非法/布局重叠/首回合牌库为空；建议项=无攻击牌、无重复防御手段。UI 在"出发"按钮旁展示检查结果；真实出发 2.4 接线。
- 验证：`tests/capture_d21_loadout.gd` 截图（空配装→放入基础套装→木盾挪背包三张图）；`tests/d21_inventory_smoke.gd` 补 `LoadoutCheck` 断言（空胸挂→硬阻止含"首回合牌库为空"）。

### W7 生命周期挂钩与占用可见（D2.1-06）

- 文件：`inventory_game.gd`（已在 W3 提供 API）、`farm_hud.gd`、`farm_game.gd`。
- 要点：
  - `expedition.occupied_by_run` 非空时，仓库/战备中的占用物品在 UI 显示"正在探险"角标；本阶段没有真实活动局，用一个仅测试可调用的入口在冒烟里驱动（`set_run_occupied`），UI 角标逻辑同时落地。
  - 农场时间规则确认：进入探险（未来）不快进农场时间——本阶段在 `farm_game.gd` 注释与测试里固化"农场时间推进只由真实挂钟驱动"的现有行为，不引入探险内时间源。
  - 出发占用/解除的完整事务在 2.4 实现，本阶段保证状态字段与角标就绪。
- 验证：`tests/d21_inventory_smoke.gd` 续——占用后 `add_instance(basic)` 对占用中部件仍计为"已拥有"（设计 §7"活动局中的也计入拥有"）。

### W8 网络技术试验（总计划 §10-2.1 交付项）

- 文件：`tests/d21_net_probe.gd`、交付报告章节。
- 要点：本机 ENet 双端最小验证：`SceneTree.create_multiplayer_peer` 思路不适用 headless 单进程，改为在一个进程内建 `ENetMultiplayerPeer` host＋一个 client peer 通过 `127.0.0.1` 连接，验证连接建立、一条自定义消息往返、断开信号；记录 Godot 4.6 ENet 在 Windows 的端口/防火墙观察。结论写入交付报告"初步网络技术试验记录"章节：直连可行性、互联网可达性待 2.6 前确认（总计划 §14 表）。
- 验证：探针脚本输出连接成功/往返计数；报告成文。

### W9 回归、文档与交付

- 跑全量：现有 `stage1~6` 全部 smoke（含 W4 改断言后的版本检查）＋ `world_picking_smoke` ＋ 本阶段 5 份新测试。
- 实机验收对应设计 §10 通过条件：旧档（真实 v5 备份副本）加载资产一致；新入口可找到；战备可进出；三容器/物品牌/失败保护能被试玩者复述。
- 交付物：`docs/archive/Godot_阶段2.1_交付报告.md`（含规则基线表实际采用值、迁移记录、网络试验记录、演示与正式物品边界说明）；更新总计划 §10-2.1 状态与 `docs/README.md`、根 `README.md`。

## 5. 测试与验收汇总

| 测试 | 覆盖 | 对应总计划 §12.1 |
| --- | --- | --- |
| `tests/d21_defs_smoke.gd` | 基线常量、几何、定义表一致性 | （基础） |
| `tests/d21_inventory_smoke.gd` | 归属唯一、占格=牌数、补领、占用、`LoadoutCheck` | 库存-占用 |
| `tests/d21_migration_smoke.gd` | v5→v6 迁移、旧资产保留、未知版本拒绝 | 存档-v5 迁移 |
| `tests/d21_net_probe.gd` | ENet 本机连通 | 联机-连接 |
| `tests/capture_d21_hub.gd`、`tests/capture_d21_loadout.gd` | 概览/战备界面截图 | 实机记录 |

手工验收按 §4-W9。测试运行命令沿用根 README 的 PowerShell 形式（`--headless --path … --script res://tests/…`）。

## 6. 风险与回退

- 存档版本升级动到所有回归断言：W4 单独成提交，失败可回退该提交而不影响 W1~W3 纯新增代码。
- `farm_hud.gd` 已 1500 行，新面板一律独立文件，只挂接不内联，避免继续膨胀（总计划 §10-2.1 开发重点）。
- 演示物品泄漏进存档是最可能的一致性事故：`strip_demo_instances` 在 `farm_game.gd` 保存入口统一调用并加测试断言。
- 3D 占位模型遮挡原拾取区：入口位置做成数据常量（世界坐标＋尺寸），试玩调整不改正文逻辑。

## 7. 交付物清单

- 代码：§2 表列出的 7 个新文件与 3 处修改。
- 测试：§5 的 7 份脚本。
- 文档：交付报告（archive）、本计划状态更新、总计划/README 状态更新。
- 数据示例：`item_defs.gd` 内基础套装与演示物品即"数据示例"交付项（总计划 §10-2.1）。

---

## 附：全阶段工程约定与模块地图（2.2～2.9 共用）

**本附录是九份代码计划的共同约定，后续阶段引用本文，不另行定义。**

### A1 分层与风格

1. 规则层（`scripts/domain/`）全部 `class_name … extends RefCounted`：不访问场景树、不直接读写文件；时间与随机数由调用方注入（沿用 `farm_game.gd` 的 `now: int` 参数与 `set_debug_random_seed` 风格）。规则方法返回结果字典，统一形状 `{ok: bool, reason: String, …}`；状态变更随事件列表返回给 UI/网络层（总计划 §11"规则层接收命令"）。
2. 单人与联机共用同一规则入口：网络层（`scripts/services/`）只搬运命令与快照，不实现第二套算法（总计划 §11、§9.2）。
3. UI 一律代码构建（现状风格）；整屏模式（战斗、地图）建独立 `.tscn`＋脚本，农场侧面板挂在 `farm_hud` 的 modal 体系。新 UI 脚本独立文件，不在 `farm_hud.gd` 内加长。
4. 定义表集中在 `scripts/domain/*_defs.gd` 常量；运行时可变状态放对应 `*_game.gd` 的状态字典。禁止把规则数值写散在 UI。
5. 存档：个人档 `farm_save_v1.json`（`SAVE_VERSION` 管理＋迁移）；局档/结算 `user://expeditions/`。写入一律三段式（tmp→bak→替换）。所有新档字段先在本文档式的阶段计划里声明再落码。
6. 测试命名 `tests/d2<N>_<主题>_<种类>.gd`（N=子阶段号；种类 smoke/worked/sim/probe/capture）；`extends SceneTree`＋`_initialize()`＋`_check()` 模式；随机种子与时间注入；截图脚本产出进 `screenshots/`。禁止依赖真实 `user://` 玩家档。
7. 提交粒度＝工作包；每阶段完成写 `docs/archive/Godot_阶段2.<N>_交付报告.md`，并更新总计划 §10 对应小节状态。
8. 不新增 autoload；组合根保持 `farm_world.gd`。RPC 场景里节点命名显式、双方一致（总计划 §11 末段）。
9. ID 体系（2.1-W1 定义）：物品实例 ID（存档内递增 int）、局 ID `run-…`、动作 ID `act-<peer>-<seq>`、结算 ID `settle-…`；格式跨阶段不改。

### A2 模块出生地图（谁在哪个阶段诞生/扩展）

| 模块（`scripts/` 下） | 2.1 | 2.2 | 2.3 | 2.4 | 2.5 | 2.6 | 2.7 | 2.8 | 2.9 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `domain/expedition_baseline.gd` | **新增**：常量/几何/ID 约定 | 引用 | 引用 | 引用 | 引用 | 引用 | 引用 | 引用 | 引用 |
| `domain/item_defs.gd` `card_defs.gd` | **新增**：字段+基础套装 | 扩：牌效果定义 | 扩：12~16 种物品 | 扩：节点奖励表引用 | 扩：配方用材料 | 引用 | 引用 | 扩：第二层内容池 | 冻结 |
| `domain/inventory_game.gd` | **新增**：归属/占用/预览 | 引用 | **扩展**：拖放/旋转/自动整理/丢弃/堆叠禁则/消耗品实体 | 引用 | 扩：仓库筛选/移入战备 | 扩：分享/公共区 | 引用 | 引用 | 回归 |
| `domain/combat_game.gd` | — | **新增**：回合引擎/出牌裁定/敌人意图/状态/日志 | 扩：牌库构建（布局→牌）、三容器延迟洗入 | 引用 | 引用 | **扩展**：双人共同回合/倒地救援/信号 | 扩：动作去重入口 | 扩：精英/首领行为 | 回归 |
| `scenes/battle_screen.tscn` `ui/battle_screen.gd` | — | **新增** | 扩：牌与物品互查 | 引用 | — | 扩：双人面板/信号 | 引用 | 扩：表现层打磨 | 回归 |
| `domain/deck_builder.gd` | — | — | **新增**：布局→牌组快照（战斗开始时构建） | 引用 | 引用 | 引用 | 引用 | 引用 | 回归 |
| `domain/expedition_game.gd` | — | — | — | **新增**：地图/节点/撤离/死亡/出发占用/结算事务 | 引用 | **扩展**：共同选路/公共物资/分享裁定 | 扩：暂停恢复语义 | 扩：第二层/层间 | 回归 |
| `ui/expedition_map_panel.gd` 等 | — | — | — | **新增**：地图/搜刮/撤离/结算面板 | 引用 | 扩：协商/信号 | 引用 | 打磨 | 回归 |
| `domain/expedition_defs.gd` | — | — | — | **新增**：第一层固定地图/事件/休整/奖励池表 | 引用 | 引用 | 引用 | **扩展**：第二层生成参数/深层事件/教学路线 | 回归 |
| `domain/crafting_defs.gd` `crafting_game.gd` | — | — | — | — | **新增**：配方/制作事务/设施升级/目标成长 | 引用 | 引用 | 引用 | 回归 |
| `services/expedition_store.gd` | **新增**：骨架/ID | 引用 | 引用 | **扩展**：局快照/结算读写 | 引用 | 引用 | **扩展**：幂等清单/恢复路径 | 引用 | 回归 |
| `services/session_host.gd` `session_client.gd` | — | — | — | — | — | **新增**：房间/主机裁定/动作序列/快照广播 | **扩展**：重连凭据/暂停恢复/未决结算 | 引用 | 真机验证 |
| 农场既有 `farm_game.gd`/`plant_defs.gd` 等 | 扩：v6 迁移 | — | — | 扩：结算回写/待领取区 | **扩展**：新植物/作物用途 | 引用 | 引用 | 引用 | 全量回归 |

### A3 跨阶段一致性红线

- 占格数＝牌实例数、三容器 1/2/3 回合加入、保险箱白名单保护：任何调整先改 `expedition_baseline.gd` 与 2.1 设计，再同步受影响阶段（设计索引"阅读与使用约定"）。
- 同一物品同一时刻只有一个归属（`InventoryGame.owner_of` 断言口径），2.4 出发占用、2.6 分享、2.7 恢复都必须经 `InventoryGame`/`ExpeditionGame` 事务，禁止旁路直改字典。
- 结算只应用一次（`applied_settlements` 去重），从 2.4 第一次写结算起生效，不等 2.7（总计划 §13）。
