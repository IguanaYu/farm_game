# 2.2 单人卡牌战斗原型：代码执行计划 v0.1

日期：2026-10-01。状态：未开始。适用工程：Godot 4.6.1（GL Compatibility）、Windows、现有 farm 工程。

导航：[整体开发计划](../Godot_第二大阶段_农场与合作洞窟_整体开发计划_v0.1.md)｜[2.2 详细设计](../design/Godot_阶段2.2_单人卡牌战斗原型_详细设计_v0.1.md)｜[设计索引](../design/第二大阶段详细设计索引.md)｜[代码计划索引](第二大阶段代码执行计划索引.md)｜[上游 2.1 代码计划](Godot_阶段2.1_规则基线与工程基础_代码执行计划_v0.1.md)

本文把 2.2 详细设计拆成可执行的 Godot 代码任务：功能范围逐条对应 `D2.2-01`～`D2.2-06`，交付与验收对应总计划 §10-2.2，规则验证对应总计划 §12.1"战斗"行。所有规则数值（生命、能量、牌效果、敌人行为、状态清除时点）以详细设计为准，本文只引用功能号与必要的结构、方法签名草案，不重述数值表。工程分层、结果字典 `{ok, reason, …}`、随机数注入、测试命名 `tests/d22_*` 与模块出生边界，全部遵守 [2.1 代码计划附录 A](Godot_阶段2.1_规则基线与工程基础_代码执行计划_v0.1.md)；本文只新建/扩展模块地图分配给 2.2 的模块，不发明地图外模块。

## 1. 输入与前置

- 上游 2.1 交付物（到文件级，2.2 直接引用）：
  - `scripts/domain/expedition_baseline.gd`：`MAX_HP=40`、`ENERGY_PER_TURN=3`、`DRAW_PER_TURN=5`、`HAND_LIMIT=10`、`JOIN_ROUND`、`PROTO_RULES_VERSION`——`combat_game.gd` 只引用不重复定义（红线 A3）。
  - `scripts/domain/card_defs.gd`（2.1-W2 骨架）：字段 `{id, name, cost, target, effect_kind, params, desc}` 已定，本阶段填充效果定义（地图 2.2 行"扩：牌效果定义"）。
  - `scripts/domain/item_defs.gd`：基础套装三件（旧短刀/木盾/行囊工具）与"占格数＝牌实例数"，本阶段把来源牌序列由占位骨架校正为正式牌 def id。
  - `scripts/domain/inventory_game.gd`：仅只读引用（演示战斗取基础套装构成）；2.2 不调用其任何写方法。
  - `scripts/ui/loadout_panel.gd`、`scripts/ui/farm_hud.gd`：modal 挂接体系，演示入口的接入点。
  - `scripts/services/expedition_store.gd`：ID 体系已定；2.2 不扩展（局快照读写 2.4、恢复路径 2.7）。
  - `scripts/domain/farm_game.gd`：v6 存档与 `expedition` 块；2.2 不改农场档。
- 设计功能号清单（本文 §4 逐一覆盖）：D2.2-01 战斗界面与牌的操作、D2.2-02 回合完整时序、D2.2-03 伤害格挡与状态、D2.2-04 首批牌效果、D2.2-05 敌人意图与遭遇、D2.2-06 结束行动胜负与日志。
- 明确不在本阶段（数据结构必须预留）：
  - 三容器延迟洗入与"布局→牌组"构建（2.3，`deck_builder.gd` 届时诞生）：本阶段牌实例已带 `join_round` 与 `source_instance_id/source_seq` 字段，回合引擎已有"回合开始加入到期牌"钩子，但演示配装全部 `join_round=1`。
  - 真实出发扣物、地图、撤离与结算（2.4）：演示战斗标注演示、不读不写库存；快照接口 `to_dict()/from_dict()` 先行。
  - 双人共同回合、倒地救援、同时出牌裁定（2.6）：`players` 做成按玩家键索引的字典（`"p1"`），2.6 增 `"p2"` 不改结构；敌人意图带 `target_key`。
  - 局档落盘与断线恢复（2.4/2.7）：2.2 只保证战斗状态可 JSON 序列化且恢复不变异，验收以测试钩子口径（§5）。
  - 战斗奖励资源（设计 §6：正式奖励未接入前不发可出售资源）、拖放整理（2.3）、表现打磨与音效（2.8）。

## 2. 新增与修改的工程结构

| 文件 | 动作 | 责任 | 预估规模 |
| --- | --- | --- | --- |
| `scripts/domain/combat_game.gd` | 新增 | 回合引擎、出牌裁定、敌人定义表与意图、状态、战斗日志、快照（模块地图 2.2 行全部职责） | ~600 行 |
| `scripts/domain/card_defs.gd` | 扩展 | 12 张牌效果模板＋效果原语词表＋详情文案＋基础套装 8 张构成（D2.2-04） | +150 行 |
| `scripts/domain/item_defs.gd` | 扩展 | 基础套装三件 `cards` 序列校正为正式牌 def id，占格＝张数校验不变 | +15 行 |
| `scenes/battle_screen.tscn` | 新增 | 战斗整屏场景：根 Control＋脚本引用，子树代码构建（A1-3、A1-4 风格） | ~10 行 |
| `scripts/ui/battle_screen.gd` | 新增 | 战斗 UI：事件播放、选牌与目标、牌堆查看、日志、胜负画面（D2.2-01/06 画面） | ~500 行 |
| `scripts/ui/loadout_panel.gd` | 修改 | 顶部加"演示战斗"按钮与遭遇选择（演示标识、不动库存），最小挂接 | +40 行 |
| `scripts/domain/expedition_baseline.gd`、`inventory_game.gd` | 引用 | 常量只读；库存只读。零改动（表中列出以示边界） | 0 |
| `tests/d22_rules_smoke.gd`、`d22_worked_example.gd`、`d22_serialize_smoke.gd`、`capture_d22_battle.gd` | 新增 | 见 §5 | 共 ~400 行 |

说明：模块地图未给 `loadout_panel.gd` 设 2.2 行，也未设 `enemy_defs.gd`——前者按本计划任务要求做"演示入口"最小挂接（不改其既有职责），后者将敌人定义表落为 `combat_game.gd` 内部常量（意图本就属于 2.2 的"敌人意图"职责），均不产生地图外新模块。

## 3. 数据与存档

- 个人档与局档存盘格式：**无变化**。`FarmGame.SAVE_VERSION` 仍为 6，不写 `expedition` 新字段，不写 `user://expeditions/`。演示战斗纯内存，退出即弃。
- 战斗状态字典（`CombatGame` 内部状态，`snapshot()/restore()` 的载荷）形状草案——为 2.3（牌库构建/延迟洗入）、2.4（局快照）、2.6（双人）、2.7（恢复）预留：

```text
battle := {
  rules_version: String,            # expedition_baseline.PROTO_RULES_VERSION
  rng_seed: int, rng_state: int,    # 注入随机源的种子与推进态（洗牌/抽牌确定性，总计划 §9.2）
  round: int, phase: String,        # "player" / "enemy" / "finished"
  next_card_uid: int,               # 牌实例发号器（战斗内唯一）
  players: {                        # 按玩家键索引；2.6 直接加 "p2"
    "p1": {
      hp: int, max_hp: int, block: int, energy: int, energy_max: int,
      statuses: { vulnerable: int, weak: int, poison: int },   # 剩余回合 / 中毒层数
      hand: [uid…], draw_pile: [uid…], discard_pile: [uid…], removed: [uid…],
      pending: [uid…],              # 等待裁定标记（防重复提交，D2.2-01）
      ended: bool                   # 本回合已结束行动
    }
  },
  cards: { uid: { def_id, source_instance_id, source_seq, join_round } },  # 2.3 牌库构建直接复用
  consumed_sources: { instance_id: true },  # 饮药/包扎：战斗内耗尽标记，关联牌全部失效（总计划 §4.3）
  enemies: [ {
    enemy_id: int, def_id: String, hp: int, max_hp: int, block: int,
    statuses: { vulnerable: int, weak: int, poison: int },
    behavior_index: int,            # 行为循环步，只在意图执行后推进
    intent: Dictionary,             # 本回合已预生成意图；恢复不重掷（D2.2-05）
    alive: bool
  } ],
  log: [ { round: int, actor: String, kind: String, text: String } ],
  outcome: String                   # "" / "victory" / "defeat"
}
```

- 意图字典形状：`{kind: "attack"/"block"/"attack_status", value: int, hits: int, status: {kind, turns}, target_key: String}`；多段攻击 `hits>1`（UI 显示"3×2"）。
- 事件列表形状（规则层每个命令随结果返回，UI 只播放、网络层只搬运，A1-1/A1-2）：
  `{kind: "turn_begin"|"cards_join"|"draw"|"shuffle"|"card_played"|"attack"|"block_gain"|"heal"|"status_change"|"discard"|"remove_card"|"intent_reveal"|"enemy_act"|"round_end"|"victory"|"defeat", …载荷}`。事件描述已发生的裁定结果，禁止由表现层回放修改状态。
- 序列化要求：状态内只允许 int/String/bool/Array/Dictionary（JSON 原生类型），`to_dict()` 原样导出、`from_dict()` 校验后整体替换；同种子＋同命令序列必得同状态。

## 4. 工作包拆解

顺序 W1→W10 即建议实施顺序；W2←W1、W3←W2、W4/W5←W3、W6←W4、W7←W4~W6、W8←W4~W6（可用桩事件并行）、W9←W8、W10 收尾。

### W1 牌效果定义与基础套装校正（D2.2-04；总计划 §10-2.2 内容预算落点）

- 目标：12 种牌效果模板与基础套装 8 张构成在定义表落成，满足预算"8～12 种牌效果模板"上限口径。
- 文件：`card_defs.gd`（扩展）、`item_defs.gd`（扩展）。
- 实现要点：
  - 效果原语词表 7 个：`attack`／`block`／`draw`／`heal`／`apply_status`／`consume_source_item`／`remove_self_from_battle`；另注册 `gain_energy` 原语但 2.2 无牌使用（设计 §4"临时能量"即时效果，字段预留，见 §6 待澄清）。
  - 12 张牌逐张对应设计 §5 表（牌名/费用/目标/初始效果/去向）：切击、重击、架盾、掩护、稳住、调整呼吸、观察、破绽、毒刺、饮药、笨重货物、应急包扎；去向枚举 `discard`/`remove`/`remove_linked`（饮药、应急包扎按来源物品关联移除）。
  - `item_defs.gd`：旧短刀→2×切击；木盾→2×架盾＋掩护＋稳住；行囊工具→调整呼吸＋观察；占格＝张数断言沿用 `d21_defs_smoke` 口径。
  - 签名草案：

```gdscript
class_name CardDefs
static func get_card(def_id: String) -> Dictionary          # 取牌定义；未知 id 返回空字典
static func target_side(def_id: String) -> String           # "enemy" / "self" / "ally_or_self"（掩护单人目标=自己）
static func card_detail(def_id: String) -> String           # D2.2-01：完整说明（"给予自己或队友 6 格挡"，不以"保护"替代）
static func basic_kit_cards() -> Array[Dictionary]          # 免费基础套装 8 张实例骨架：{def_id, source_def_id, source_seq, join_round:1}
static func effect_primitives() -> Array[String]            # 原语词表（含预留 gain_energy），供校验与文档对账
```

- 验证：`tests/d22_rules_smoke.gd` 定义段——12 张字段齐全、目标类型合法、基础套装 8 张与设计 §5 逐张一致、消耗类牌带 `consume_source_item` 原语。
- 依赖：2.1-W2。

### W2 战斗状态结构与快照（D2.2-02/05 结构面；总计划 §9.2 确定性）

- 目标：`combat_game.gd` 落状态字典、注入随机源、可序列化快照，后续工作包只在其上叠规则。
- 文件：`combat_game.gd`（新增，本包只落骨架与序列化）。
- 实现要点：
  - `class_name CombatGame extends RefCounted`，不访问场景树与文件（A1-1）；随机源沿用 `set_debug_random_seed` 风格注入；所有公开方法返回 `{ok, reason, …}`。
  - 状态形状按 §3；牌实例、玩家键索引、意图、RNG 推进态全部入状态，保证"同种子＋同命令序列＝同状态"。
  - 签名草案：

```gdscript
func _init(seed_value: int) -> void                 # 注入战斗随机源（初始洗牌、洗弃牌）；意图生成不耗随机数
func set_debug_random_seed(value: int) -> void      # 测试注入，风格与 FarmGame 一致
func start_battle(setup: Dictionary) -> Dictionary  # {enemies:[def_id…], players:{p1:{deck:[牌实例], hp, max_hp}}}；洗入抽牌堆并开局
func to_dict() -> Dictionary                        # 完整快照，仅 JSON 原生类型
func restore(snap: Dictionary) -> bool              # 校验并整体替换状态；不重掷 RNG、不重生成意图
```

- 验证：`tests/d22_serialize_smoke.gd`——开局→出牌数张→`to_dict`→`JSON.stringify/parse` 往返→`restore`→手牌顺序、抽/弃牌堆、敌人意图逐项相等；恢复后继续运行与不序列化连续运行结果一致。
- 依赖：W1。

### W3 回合引擎与时序（D2.2-02）

- 目标：一整个回合循环可被纯命令驱动跑通，时序逐条对应设计 §3 步骤 1～8。
- 文件：`combat_game.gd`。
- 实现要点：
  - 第 1 回合无旧格挡可清；能量重置不跨回合；抽 5、手牌上限截断（只抽空位数，提示不烧牌）；没有牌也可结束回合。
  - "加入该回合到期的物品牌"钩子落地：回合开始把 `join_round == round` 的牌洗入抽牌堆；2.2 数据全部 `join_round=1`，延迟洗入留给 2.3 喂真实数据。
  - 抽牌堆空洗弃牌堆继续；两堆皆空只抽实存数量；移除区牌不参与（设计 §9 边界）。
  - 敌方阶段：逐敌"清自身旧格挡→结算自身中毒→死亡跳过→执行意图"，随后玩家结算自身中毒、状态递减与清理、胜负判断；最后一个敌人死亡立即判胜，不多跑一轮敌方行动。
  - 状态递减时点严格按设计 §4 表（易伤/虚弱在受影响单位完成自身行动阶段后减 1；中毒行动前结算并减层）。
  - 签名草案：

```gdscript
func begin_player_turn() -> Dictionary                        # 清玩家旧格挡→加入到期牌→能量重置→回合开始效果→抽 5→预生成敌人意图
func draw_cards(pkey: String, count: int) -> Dictionary       # 返回 {ok, drawn, events}；含洗弃与上限截断事件
func end_player_turn(pkey: String) -> Dictionary              # 非保留手牌入弃牌堆；单人全部结束后进入敌方阶段
func run_enemy_phase() -> Dictionary                          # 逐敌结算与意图执行、玩家持续伤害、胜负判断；返回 {ok, events}
func check_outcome() -> String                                # "" / "victory" / "defeat"
```

- 验证：`tests/d22_rules_smoke.gd` 时序段——格挡清除时点（玩家回合开始清玩家格挡、敌人自身行动开始清敌人格挡）、能量重置、空堆洗弃、上限截断、无牌结束回合、最后敌人死亡即胜（§12.1 战斗行：能量、抽弃牌、胜负边界）。
- 依赖：W2。

### W4 出牌裁定与效果结算（D2.2-03；D2.2-01 的预览与防重复）

- 目标：一次出牌请求从验证到落状态的完整裁定，含伤害公式、状态乘率、去向与消耗连锁。
- 文件：`combat_game.gd`。
- 实现要点：
  - 合法请求接受后才移出手牌并扣能量；选牌本身不耗能量；正在等待裁定的牌加 `pending` 标记，重复请求拒绝（设计 §9"牌已移出又被点击"）。
  - 伤害：基础值×易伤×虚弱，先乘后一次取整、不小于 0，先扣格挡再扣生命；持续伤害绕格挡；治疗不超上限、满血目标预览显示恢复 0 但允许确认（设计 §9）。
  - 效果中敌人全部死亡：完成本张牌不可拆子效果后立即判胜（设计 §3 末段）。
  - 去向：`discard`／`remove`（本场移除）／`remove_linked`（`consumed_sources` 置位，该来源物品在手/抽/弃中的其余关联牌全部失效移除，总计划 §4.3；战斗内口径，实体扣除 2.3 接 InventoryGame）。
  - 签名草案：

```gdscript
func can_play(pkey: String, card_uid: int, target: Dictionary) -> Dictionary       # {ok, reason}：能量/归属/目标合法/pending 检查
func preview_play(pkey: String, card_uid: int, target: Dictionary) -> Dictionary   # 纯函数：格挡/生命/状态变化预估，不落状态（D2.2-01 预览）
func play_card(pkey: String, card_uid: int, target: Dictionary) -> Dictionary      # 裁定并落状态；{ok, reason, events, log_entries}
```

- 验证：`tests/d22_rules_smoke.gd` 裁定段——能量不足拒绝不扣；目标已死拒绝且牌与费用保留；重复点击同一牌不重复扣（总计划 §10-2.2 验收"费用不足和目标死亡不误扣"）；取整边界（⌊6×1.5⌋＝9、虚弱 ×0.75 只取整一次）；饮药后关联牌全部失效。
- 依赖：W3。

### W5 敌人定义、意图与遭遇（D2.2-05）

- 目标：3 种敌人行为循环、意图预生成与三处遭遇可配置、可恢复。
- 文件：`combat_game.gd`（敌人定义表为本文件内部常量——地图未设 `enemy_defs.gd`，见 §2 说明）。
- 实现要点：
  - 内容条目逐项对应设计 §6 表：小泥团（18：攻击 5→获得 4 格挡→攻击 7）、洞穴蝠（14：攻击 3×2→攻击 4 并施加 1 回合虚弱）、碎石蟹（26：获得 6 格挡→攻击 9）——总计划"3 种普通敌人行为"预算落点。
  - 遭遇表：教学场＝单小泥团；普通验证场＝泥团＋蝠；防御验证场＝碎石蟹；演示入口可重复挑战，不发资源。
  - 意图在 `begin_player_turn` 末预生成存入敌人状态；一经确定不因查看/退出恢复而变；`make_intent` 为纯函数（由 `behavior_index` 决定，不耗随机数）；`behavior_index` 只在意图执行后推进；单人 `target_key` 恒 `"p1"`，原目标倒地的替代规则留 2.6（§6 待澄清）。
  - 签名草案：

```gdscript
const ENEMY_DEFS := { … }                                                   # 3 种敌人：{name, hp, loop:[步…]}（设计 §6）
const ENCOUNTERS := { … }                                                   # tutorial / normal / defense 三处遭遇
static func make_intent(def_id: String, behavior_index: int) -> Dictionary  # 纯函数：loop 步 → {kind, value, hits, status, target_key}
```

- 验证：`tests/d22_rules_smoke.gd` 敌人段——循环推进、多段攻击 `hits=2`、虚弱施加、死亡跳过行动；`d22_serialize_smoke.gd`——恢复后意图与 `behavior_index` 不变。
- 依赖：W3。

### W6 战斗日志与胜负结算（D2.2-06）

- 目标：日志按序完整可核对，胜负画面数据一次产出。
- 文件：`combat_game.gd`。
- 实现要点：
  - 日志逐条 `{round, actor, kind, text}`：谁用哪张来源牌、费用、目标、实际伤害、格挡吸收、治疗、状态触发、敌人行动、胜负；伤害条目按设计 §7 例句口径（"切击：原始 6，易伤后 9，格挡抵消 4，生命 -5"）；日志只追加不改写。
  - 胜利 `summary := {rounds, remaining_hp, consumed:[{def_id, count}]}`（本场消耗＝已移除牌与已消耗来源，口径在交付报告记录）；失败 summary 只报结果，携带损失画面 2.4 接入；胜利不回满血。
  - 签名草案：

```gdscript
func battle_summary() -> Dictionary     # 胜负既定后聚合回合数/剩余生命/本场消耗；未结束时 {ok:false}
func log_tail(count: int) -> Array      # 最近 count 条（UI 默认少量、可展开全文）
```

- 验证：`tests/d22_worked_example.gd` 打印逐回合日志，与设计 §8 算例逐行人工核对。
- 依赖：W4。

### W7 固定种子算例（总计划 §10-2.2 交付"固定种子算例"；延续 `stage2_worked_example.gd` 传统）

- 目标：一份可手工核对、可回归的逐回合断言算例。
- 文件：`tests/d22_worked_example.gd`（新增，`extends SceneTree`，`_initialize()`＋`_check()`，固定种子注入）。
- 实现要点：
  - 固定配装＝基础套装 8 张（`CardDefs.basic_kit_cards()`）＋固定种子：教学场（单小泥团）逐回合出牌断言。
  - 必覆盖设计 §8 两个算例：基础攻防（切击×2：18→12→6；架盾＋稳住：格挡 9；泥团攻击 5：格挡 9→4、生命仍 40；下回合开始残余 4 清 0）；易伤算例（破绽先中：格挡 6→2 并施加易伤；切击 ⌊6×1.5⌋＝9、扣 2 格挡生命 −7，不追溯已发生伤害）。
  - 时序边界各至少一条断言：能量类（3 能量用尽后 0 费仍可出、超费拒绝）；格挡类（清除时点、敌人新格挡覆盖下次玩家行动）；状态类（易伤/虚弱递减回合、中毒绕格挡且减层）。
  - 输出格式沿用 stage2 传统：打印可手算的明细行＋末行 `D22_WORKED_PASS`。
- 验证：脚本 PASS；日志文本与设计 §8 一致。
- 依赖：W4、W5、W6。

### W8 战斗界面（D2.2-01；D2.2-06 画面）

- 目标：与规则层解耦的整屏战斗 UI，规则层输出事件列表、UI 按事件播放。
- 文件：`scenes/battle_screen.tscn`（新增）、`scripts/ui/battle_screen.gd`（新增）。
- 节点组织（tscn 只含根节点＋脚本，子树代码构建，沿用工程现有 UI 风格）：

```text
BattleScreen (Control, 全屏 anchors_preset=full_rect)
├─ Background (ColorRect)
├─ EnemyArea (HBoxContainer, 顶部)：EnemyPanel×N —— 意图标签(含"3×2"分段)、生命条、格挡、状态图标+剩余数
├─ PlayerPanel (左下)：生命/格挡/能量/状态
├─ HandArea (底部 PanelContainer+HBoxContainer)：CardWidget×N —— 名称、能量费、效果数字、目标图标、来源物品、等待遮罩
├─ ActionBar (底部右侧)：能量球、结束行动按钮(突出显示剩余能量)、抽牌堆/弃牌堆/移除区/延后加入 四个查看入口
├─ LogPanel (右侧)：最近数条 + 展开全文
├─ TargetHint (居中提示)：预览文本/拒绝原因（不被遮罩压暗）
└─ ResultOverlay (CenterContainer)：胜利(回合数/剩余生命/本场消耗)与失败画面、返回按钮
```

- 信号与解耦草案：

```gdscript
class_name BattleScreen extends Control
signal battle_finished(outcome: String, summary: Dictionary)   # 规则层 outcome 驱动；农场侧据此收尾
signal exit_requested                                          # 请求退出（演示路径直接关闭覆盖层）
func setup(setup: Dictionary) -> void                          # 注入 {encounter_id, player_setup}；内部 new CombatGame(种子)
func _apply_events(events: Array) -> void                      # 事件队列逐条播放（await 节奏），期间锁输入防二次提交
func _refresh() -> void                                        # 按当前状态全量重绘（进入/兜底，与事件播放同一渲染函数）
```

- 实现要点：
  - UI 不计算规则：预览调 `preview_play`、合法性调 `can_play`、出牌调 `play_card`、回合调 `end_player_turn/run_enemy_phase`；动画队列只播放事件结果，不得造成第二次伤害（总计划 §5.1）。
  - 交互流（D2.2-01）：点击牌→高亮合法目标→点目标确认；Esc/右键取消；拖放走同一流程；等待裁定牌显示标记并禁连点；目标已不合法时显示原因、牌与能量保留；敌方阶段开始后结束按钮禁用且不可反悔。
  - 能量剩余且有可出牌时结束行动给轻量提示，不强行禁止（D2.2-06）；未加入牌（延后加入入口）只显示"将于第 N 回合加入"，不混入可抽列表（设计 §9）。
  - 结束行动能量提示、意图与状态说明、卡牌详情（`card_detail`）悬停/点击可查。
- 验证：`tests/capture_d22_battle.gd`（战斗中、意图展示、胜负画面三张截图进 `screenshots/`）＋手工按总计划 §10-2.2"不看开发文档完成一场战斗"。
- 依赖：W4～W6（界面骨架可用桩事件先行并行）。

### W9 演示战斗入口与返回（进入战斗的临时入口；正式闭环 2.4）

- 目标：从 2.1 战备面板可反复进入演示战斗，全程不动库存与存档。
- 文件：`scripts/ui/loadout_panel.gd`（修改，最小挂接）、`battle_screen.gd`（返回路径）。
- 实现要点：
  - 战备面板顶部加"演示战斗"按钮（带"演示·不影响库存"标识）→遭遇选择小面板（教学/普通/防御三场）→以固定基础套装配装（全部 `join_round=1`）实例化战斗场景；出发生命取 `MAX_HP` 满血。
  - 场景组织：`battle_screen.tscn` 以全屏 Control 覆盖层加入当前场景树（`get_tree().root.add_child`），不用 `change_scene`——农场场景与内存状态不丢，退出即 `queue_free` 回战备面板；组合根仍是 `farm_world.gd`，不新增 autoload（A1-8）。
  - 演示路径禁止调用 `InventoryGame` 写方法与一切保存入口；正式出发（扣物/占用/地图/结算）2.4 接线，按钮旁文案注明"正式出发将在后续版本开放"。
- 验证：手工进出三场；`capture_d22_battle.gd` 补入口截图；退出后战备/库存与进入前逐项一致（对照 `deck_preview()`）。
- 依赖：W8。

### W10 回归、文档与交付

- 跑全量：既有 `stage1~6`、`world_picking_smoke`、2.1 全部 `d21_*` 与本阶段 4 份测试。
- 实机验收按 §5 步骤执行并记录试玩观察（设计 §10：普通场 3～6 回合、8 张牌重复感、货物移除是否无脑优选、易伤时序可解释性）。
- 交付物：`docs/archive/Godot_阶段2.2_交付报告.md`（牌效果与敌人实际采用值、固定种子算例输出、试玩记录、发现的问题）；更新本计划状态、总计划 §10-2.2 状态与 `docs/README.md`、根 `README.md` 测试命令。

## 5. 测试与验收汇总

| 测试 | 覆盖点 | 对应总计划 §12.1 |
| --- | --- | --- |
| `tests/d22_rules_smoke.gd` | 12 牌定义、基础套装 8 张、能量/目标/重复提交裁定、伤害取整与乘率、格挡清除时点、抽弃洗边界、手牌上限、敌人循环与意图字段、胜负边界 | 战斗行：能量、抽弃牌、持续状态、胜负边界 |
| `tests/d22_worked_example.gd` | 固定配装＋固定种子逐回合断言：设计 §8 两算例、能量/格挡/状态三类时序边界、逐回合日志 | 战斗行：能量、持续状态；§10-2.2 交付"固定种子算例" |
| `tests/d22_serialize_smoke.gd` | `to_dict/from_dict` JSON 往返：手牌顺序、抽/弃牌堆、敌人意图与行为序号不变；恢复后续跑与连续跑一致 | 存档行：活动局恢复的前置钩子；§10-2.2 验收"保存恢复不改变手牌或敌人意图" |
| `tests/capture_d22_battle.gd` | 战斗界面、意图展示、胜负画面、演示入口截图 | 实机记录（§12.3 前置） |

实机验收步骤（对应总计划 §10-2.2 验收与设计 §10"设计验证关口"）：

1. 农场→战备→演示战斗→教学场，不看开发文档完成一场战斗。
2. 故意在能量不足、目标刚死亡时出牌，确认牌与费用不被误扣。
3. 连续出牌打到抽牌堆耗尽，确认洗弃牌堆继续、移除区不回流。
4. 任选一次攻击，对照界面状态与日志核对伤害明细（原始值、倍率、格挡吸收、生命变化）。
5. 战斗中途关闭窗口重进：2.2 演示战斗为全新一局（无局档），"保存恢复不变异"由 `d22_serialize_smoke` 在规则层钩子保证（2.4/2.7 才有玩家可见恢复）。
6. 试玩并记录：普通验证场回合数是否落在 3～6；能量、意图、格挡清除、抽弃牌能否被试玩者复述；不同牌序是否产生不同存活结果。

## 6. 风险与回退

- `combat_game.gd` 单文件承担引擎＋敌人定义＋日志（模块地图约束），预计 ~600 行：内部按"常量/状态/时序/裁定/敌人/日志"分节注释；2.3/2.6 扩展逼近 800 行时，再提模块地图调整申请，不自行拆新文件。
- 表现层重复触发是卡牌战斗最典型事故：事件列表为只读裁定结果，UI 播放期间锁输入；出牌与结束行动按钮在等待/敌方阶段禁用；`pending` 标记在规则层再拦一道。
- 演示入口误写库存为最大一致性风险：演示路径禁用一切 `InventoryGame` 写方法与保存入口（W9 代码评审点＋手工验收第 6 步前的库存对照）。
- 随机数不可复现会毁掉固定种子算例：所有洗牌/抽牌只经注入 RNG；意图生成是纯函数不耗随机数，避免恢复后意图漂移。
- 回退：W1～W7 为纯新增或定义表扩展，W8/W9 挂接面小；提交粒度＝工作包（A1-7），任一包失败可单独回退，不影响 2.1 已交付物。

待设计澄清（发现出入列此，不自行改设计）：

1. "临时能量"效果模板（设计 §4 状态表）在 12 张牌中无使用者：总计划"8～12 种牌效果模板"预算是否将其计入？本计划按"注册 `gain_energy` 原语、不发牌"处理。
2. 敌人意图"原目标倒地按明确替代目标规则处理"（设计 §6）单人不会触发：替代规则需在 2.6 详细设计中明确，2.2 只在意图结构里保留 `target_key`。
3. "各场战斗生命延续，首场按出发状态"（设计 §2）：跨场生命结算是 2.3/2.4 的事，2.2 演示固定满血 40；"出发状态"届时取生命上限还是战备面板当前值，待 2.3/2.4 设计时确认（结构上 hp 已由 `start_battle` 入参注入，两侧都能接）。
4. 总计划 §10-2.2 验收"保存恢复不改变手牌或敌人意图"与 2.2 无局档、无恢复 UI 的矛盾：本计划落为规则层 `snapshot/restore` 测试钩子（`d22_serialize_smoke`）；玩家可见的"中断后续跑同一场"是否要求 2.2 演示战斗提供内存内版本，待确认（默认不做）。
5. 设计 §3 步骤 2"按 2.3 规则洗入"到期牌：2.2 仅首回合牌，本计划把 `join_round>1` 的洗入时点实现为"回合开始、抽牌之前"；若 2.3 详细设计另有细化时点再校正。

## 7. 交付物清单

- 代码：`scripts/domain/combat_game.gd`、`scenes/battle_screen.tscn`、`scripts/ui/battle_screen.gd`（新增）；`scripts/domain/card_defs.gd`、`scripts/domain/item_defs.gd`（扩展）；`scripts/ui/loadout_panel.gd`（最小挂接）。
- 测试：`d22_rules_smoke.gd`、`d22_worked_example.gd`、`d22_serialize_smoke.gd`、`capture_d22_battle.gd` 共 4 份。
- 文档：`docs/archive/Godot_阶段2.2_交付报告.md`；本计划与总计划 §10-2.2 状态更新；`docs/README.md`、根 `README.md` 测试命令补充。
- 截图：`screenshots/` 下战斗界面、意图展示、胜负画面、演示入口。
- 数据示例：`card_defs.gd` 12 张牌效果模板与 `combat_game.gd` 3 种敌人定义即总计划 §10-2.2 内容预算的实际落点（实际采用值与修改原因记入交付报告）。
