# 2.6 双人合作与战利品分配：代码执行计划 v0.1

日期：2026-10-01。状态：未开始。适用工程：Godot 4.6.1（GL Compatibility）、Windows、现有 farm 工程。

导航：[整体开发计划](../Godot_第二大阶段_农场与合作洞窟_整体开发计划_v0.1.md)｜[2.6 详细设计](../design/Godot_阶段2.6_双人合作与战利品分配_详细设计_v0.1.md)｜[设计索引](../design/第二大阶段详细设计索引.md)｜[代码计划索引](第二大阶段代码执行计划索引.md)｜上游代码计划：[2.1](Godot_阶段2.1_规则基线与工程基础_代码执行计划_v0.1.md)｜[2.2](Godot_阶段2.2_单人卡牌战斗原型_代码执行计划_v0.1.md)｜[2.4](Godot_阶段2.4_单人洞窟与撤离闭环_代码执行计划_v0.1.md)

本文把 2.6 详细设计拆成可执行的 Godot 代码任务，同时依据总计划 §5.3/§5.4（双人规则、倒地失败复活）、§6.3（搜刮与分配）、§9.1～§9.4（房间、裁定同步、事务、断线表）、§10-2.6（交付验收与试玩关口 B）与 §14（互联网连接方式在 2.6 开始前确定）。设计内容（规则、数值、界面行为）以详细设计为准，本文不重述，只引用 `D2.6-XX` 功能号。工程约定、ID 体系与模块出生地图全部遵守 [2.1 计划附录 A](Godot_阶段2.1_规则基线与工程基础_代码执行计划_v0.1.md)：单人与联机共用同一规则入口，`session_host.gd`／`session_client.gd` 只搬运命令与快照、不实现第二套算法；动作 ID `act-<peer>-<seq>`；测试命名 `tests/d26_*.gd`；不新增 autoload，组合根保持 `farm_world.gd`，RPC 节点路径显式命名、双方一致。

## 1. 输入与前置

- 上游交付物（到文件级，2.6 直接依赖）：
  - `scripts/domain/expedition_baseline.gd`：常量与几何（2.1）；`PROTO_RULES_VERSION` 作为版本检查锚点之一。
  - `scripts/domain/item_defs.gd`／`card_defs.gd`：`ItemDefs.is_basic`（基础装备不可分享）、掩护／应急包扎等目标类型（2.1/2.2）；救援包物品与救援牌定义预期在 2.3 内容预算落地（见"待设计澄清"1）。
  - `scripts/domain/inventory_game.gd`：归属唯一、`set_run_occupied`／`clear_run_occupied`、合法放置与容器校验（2.1/2.3）。
  - `scripts/domain/combat_game.gd`：回合引擎、出牌验证、敌人意图（2.2，玩家状态自始为数组）；牌库构建与延迟加入（2.3 `deck_builder.gd`）。
  - `scripts/domain/expedition_game.gd`：地图、节点、撤离、死亡结算、出发占用事务（2.4）。
  - `scripts/services/expedition_store.gd`：局档／结算档读写与 ID 生成（2.4 起 `save_run/load_run/settlement` 已有业务）；2.6 按模块地图为"引用"，不修改。
  - `scripts/ui/battle_screen.gd`、`expedition_map_panel.gd` 等搜刮／撤离／结算面板（2.2/2.4）。
  - `scripts/domain/farm_game.gd`：`expedition` 块（`player_id`、`occupied_by_run`、`active_run_ref`、`applied_settlements`）；2.6 按模块地图为"引用"，不改 `SAVE_VERSION`。
  - 前置确认记录：互联网好友连接方式选型（总计划 §14，2.6 开始前确定；若届时未定，见 §6 风险）。
- 设计功能范围：D2.6-01 创建加入与邀请、D2.6-02 准备与出发、D2.6-03 共享战斗回合、D2.6-04 队友支援倒地救援、D2.6-05 敌人数量目标与人数变化、D2.6-06 共同选路事件休整、D2.6-07 个人奖励公共物资与争取、D2.6-08 分享完整交互、D2.6-09 共同撤离与主动离开（含设计索引细化：主机个人放弃、结束会话、全队放弃是三个不同操作，全队放弃需双方确认）。
- 明确不在本阶段：
  - 完整故障矩阵、重连、暂停恢复、主机崩溃后恢复、离线收结算 = 2.7。但**动作去重（同 `action_id` 重传回已有结果）与结算幂等应用（`applied_settlements`）的入口本阶段就要有**（总计划 §13"存档幂等从出发结算开始实施"；A3 红线）；掉线时只做"会话态提示＋占用保持"，不做恢复。
  - 第二层、精英／首领、正式素材与音效、新手教学 = 2.8；平衡模拟与导出 = 2.9。
  - 三人以上、个人带收益先撤离（D2.6-09 首版无此玩法）、语音、账号／云存档／匹配／主机迁移（总计划 §9.1）。

## 2. 新增与修改的工程结构

| 文件 | 动作 | 责任 | 预估规模 |
| --- | --- | --- | --- |
| `scripts/services/session_host.gd` | 新增 | 房间状态机（版本检查/人数上限/准备/移除与退出）、出发事务编排、主机权威循环（动作验证、递增序号、去重、过期版本拒绝）、快照广播、结算单下发与确认表（A2 模块地图 2.6 行） | ~380 行 |
| `scripts/services/session_client.gd` | 新增 | 连接与加入、命令封装（`act-<peer>-<seq>`、等待反馈与重发）、快照应用、快捷信号收发、结算拉取与回执、本机会话凭据存取 | ~300 行 |
| `scripts/domain/combat_game.gd` | 扩展 | 双人共同回合（提交/裁定顺序/目标死亡拒绝/结束与取消）、倒地与救援、意图目标指派与重选、快捷信号事件（D2.6-03/04/05） | +260 行 |
| `scripts/domain/expedition_game.gd` | 扩展 | 共同选路/事件付款/休整、公共物资原子领取、分享三步裁定、共同撤离、个人放弃/全队放弃/结束会话语义、按人数取敌人配置（D2.6-05/06/07/09） | +240 行 |
| `scripts/domain/inventory_game.gd` | 扩展 | 分享锁定/解锁、`can_share` 校验、公共区暂存容器（D2.6-07/08；A2 行"扩：分享/公共区"） | +80 行 |
| `scripts/domain/combat_game.gd` 内部敌人定义表（2.2 计划 §2 已决定不设独立 `enemy_defs.gd`） | 修改 | 人数缩放字段：`hp_scale_by_headcount`、`attack_override_by_headcount`、`extra_spawn_2p`、`target_rule`（D2.6-05） | +40 行 |
| `scripts/ui/room_panel.gd` | 新增 | 房间页（创建/加入/成员卡/邀请信息/连接方式说明/准备/出发确认/移除与退出），挂 `farm_hud` modal 体系 | ~320 行 |
| `scripts/ui/battle_screen.gd` | 扩展 | 队友面板、只读手牌查看、等待中的牌标记、结束/取消结束、倒地与救援 UI、快捷信号条（A2 行"扩：双人面板/信号"） | +180 行 |
| `scripts/ui/expedition_map_panel.gd` 等搜刮/撤离/结算面板 | 扩展 | 双人协商与并排展示、分享流程、公共区实时刷新、共同撤离、放弃与全队放弃确认（A2 行"扩：协商/信号"） | +220 行 |
| `scripts/world/farm_world.gd` | 修改 | 组合根新增显式命名子节点 `SessionHost`／`SessionClient`（双方一致）、"好友组队"入口接线 | +30 行 |
| `scripts/ui/farm_hud.gd` | 修改 | 挂接 `room_panel` 的 modal 打开/关闭（沿用现有模式，不内联） | +15 行 |
| `tests/d26_*.gd` 8 份＋`tests/capture_d26_*.gd` 3 份 | 新增 | 见 §5 | 共 ~800 行 |

## 3. 数据与存档

### 3.1 主机局档结构扩展（经 `ExpeditionStore` 既有 `save_run` 透传，不改该文件）

在 2.4 局档（`user://expeditions/run_<run_id>.json`）之上扩展以下字段（新字段为快照字典的透传成员，遵守 A1-5"先声明再落码"）：

```text
run: {
  … 2.4 已有（地图种子、节点状态、每人生命/物品/补给、牌组快照 …）
  rules_version: String        # 出发时的 PROTO_RULES_VERSION，版本检查用
  net_proto_version: int       # 网络协议版本，随消息结构变更递增
  members: {                   # peer_id -> 成员记录
    member_id: "p-…"           # 即个人档 player_id，不用昵称认人（总计划 §9.4）
    name, role: "host"|"client", peer_id
    session_secret_digest      # 加入时主机分发的会话凭据摘要；完整凭据双方各存一份
    loadout_digest, ready, depart_saved: bool
    forfeited, extracted: bool, settlement_id, settlement_confirmed: bool
  }
  state_version: int           # 每接受一个动作 +1；广播与动作校验依据（总计划 §9.2）
  action_log: [ {action_id, seq, actor_member, kind, payload_digest,
                 base_state_version, result_version, result_digest} ]
  pending_settlements: { member_id: settlement_id }   # 未回执确认的结算，保留待重发
  session_status: "open"|"running"|"paused_session"|"closed"   # 结束会话=paused_session
}
```

### 3.2 客户端个人档的占用与结算确认（不改 `farm_game.gd`，字段全部为 2.1 已声明）

- 占用：带入即 `inventory.occupied_by_run = run_id`（2.1 字段、2.4 事务），结束解除；客户端全程只通过本人 `FarmGame`/`SaveStore` 读写自己的农场档。
- 结算确认：`applied_settlements` 去重登记（2.4 起用）；收到重复结算单只回执、不重复应用（总计划 §9.3）。
- 新增客户端本局凭据文件 `user://expeditions/session_<run_id>.json`（session 层自有，不动农场档）：`{run_id, member_id, session_secret, host_addr, joined_at}`；2.7 在此基础上扩重连。

### 3.3 网络消息协议草案表

传输：ENet（`ENetMultiplayerPeer`）＋ Godot 高层 MultiplayerAPI。主机即 peer 1；`SessionHost`／`SessionClient` 节点在双方进程同路径存在，未激活一侧静默。命令统一走 `cl_action` 的 `kind` 分派，不为每个玩法单开 RPC。

| 消息（方法名） | 方向 | 载荷要点 | 声明与可靠性 |
| --- | --- | --- | --- |
| `cl_hello` | 客户端→主机 | `{net_proto_version, rules_version, player_id, name, loadout_digest}` | `@rpc("any_peer","call_remote","reliable")` |
| `sv_join_result` | 主机→客户端 | `{ok, reason?, member_id, session_secret, room_view}`；reason 含 `version_mismatch`／`room_full`（第三人看到人数限制，D2.6-01） | `@rpc("authority","call_remote","reliable")` |
| `sv_room_update` | 主机→客户端 | 成员卡数组（昵称/连接状态/配装摘要/首回合牌数/补给/保护区容量/准备/保存确认；不含对方农场金币与仓库） | authority, reliable |
| `cl_set_ready` | 客户端→主机 | `{ready, loadout_digest, rules_version}`（准备对应当前配装与版本，D2.6-02） | any_peer, reliable |
| `sv_depart_begin` | 主机→客户端 | `{run_id}`（出发事务开始，双方本地写占用并保存） | authority, reliable |
| `cl_depart_saved` | 客户端→主机 | `{run_id, loadout_digest}`（保存成功确认；失败端发 `cl_depart_failed`，全队留在房间并提示是谁） | any_peer, reliable |
| `sv_run_start`／`sv_depart_abort` | 主机→客户端 | 初始局快照 ／ `{who}`（双方各自回滚 `clear_run_occupied`，不进局） | authority, reliable |
| `cl_action` | 客户端→主机 | `{action_id:"act-<peer>-<seq>", run_id, base_state_version, kind, payload}` | any_peer, reliable |
| `sv_action_result` | 主机→广播 | `{action_id, seq, actor, ok, reason, events:[…], state_version}`；拒绝时仅发给提交者且 `state_version` 不变 | authority, reliable |
| `sv_snapshot` | 主机→广播 | 全量快照 `{state_version, scene, members(含双方手牌), enemies, intents, inventories, public_zone, decisions}`；战斗开始/回合切换/节点切换/结算时发；依 D2.6-03 双方手牌互相可只读查看，故随快照下发 | authority, reliable |
| `cl_request_snapshot` | 客户端→主机 | `{have_version}`（版本缺口补发） | any_peer, reliable |
| `cl_signal`／`sv_signal` | 客户端→主机→转发 | `{signal_id}`（我来挡/先集火/我能救你/准备结束，`SessionHost.COOP_SIGNALS` 常量）；低频，统一可靠通道保证显示有序 | any_peer／authority, reliable |
| `sv_settlement` | 主机→对应成员 | `{settlement_id, sheet}`（结算单数据；主机不写客户端农场档，§10-2.6 验收） | authority, reliable |
| `cl_settlement_applied` | 客户端→主机 | `{settlement_id}`（本人档单次保存应用后回执） | any_peer, reliable |
| `sv_kick`／`cl_leave` | 双向 | `{reason}`（仅限未出发成员，D2.6-01） | reliable |

`cl_action.kind` 清单与主机分派入口（`payload` 只带参数，裁定全部在主机侧规则层完成）：

| kind | payload 要点 | 分派到 |
| --- | --- | --- |
| `play_card`／`cancel_end` | `{card_uid, target_uid}`（救援即救援牌＋倒地队友目标） | `CombatGame.request_play_card`／`request_cancel_end` |
| `end_turn` | `{}` | `CombatGame.request_end_turn` |
| `propose_node`／`confirm_node` | `{node_id}` | `ExpeditionGame.propose_node`／`confirm_node` |
| `loot_done`／`loot_undo`、`rest_choice`、`event_choice` | `{node_id?}`／`{choice}`／`{event_id, option_id}` | `ExpeditionGame.mark_loot_done` 等 |
| `pick_reward`／`claim_public`／`want_flag` | `{candidate_id}`／`{public_item_id, container, cell}`／`{public_item_id, flag}` | `ExpeditionGame` W5 入口 |
| `share_propose`／`share_accept`／`share_cancel` | `{instance_id}`／`{proposal_id, container, cell}`／`{proposal_id, reason}` | `ExpeditionGame` W6 入口 |
| `confirm_extract`／`forfeit`／`forfeit_all_vote`／`forfeit_all_confirm` | `{}` | `ExpeditionGame` W7 入口 |

- 通道约定：全部消息走可靠通道（回合制无高频消息，可靠有序最简单且与去重/快照版本语义一致）；快捷信号与状态同用默认 channel，若实测出现队头阻塞再为信号单独分配 ENet channel（仅改传输参数，不改语义）。
- 节点约定：`SessionHost`／`SessionClient` 由组合根 `farm_world.gd` 创建并显式命名，两侧进程路径一致；客户端调用形如 `session_host_node.rpc_id(1, "cl_action", msg)`（主机恒为 peer 1），主机广播形如 `sv_snapshot.rpc(snap)`（authority 模式仅主机可发）；`multiplayer.is_server()` 区分角色，未激活一侧节点不参与逻辑。

## 4. 工作包拆解

W1→W13 顺序即建议实施顺序：W1~W7 是规则层（headless 可全量验证，单人回归不受影响）；W8~W9 网络层；W10~W12 UI 与结算流；W13 实测与交付。W3 依赖 W2，W5 依赖 W4，W9 依赖 W2~W7 与 W8，W12 依赖 W9。

### W1 敌人定义表的人数缩放（D2.6-05 数据面）

- 文件：`combat_game.gd`（敌人定义表为该文件内部常量，见 2.2 计划 §2 说明）、`expedition_game.gd`（人数来源）。
- 要点：每条敌人定义增加 `hp_scale_by_headcount := {2: 1.6}`（普通敌人生命×1.6 向上取整，**不做全数值翻倍**，总计划 §5.3）、`attack_override_by_headcount := {}`（默认攻击不变，个别条目显式覆盖）、`extra_spawn_2p: String`（特殊双人组合追加一名低生命敌人的 def_id，且不与生命放大叠加）、`target_rule: "fixed"|"alternate"|"aoe"`（意图目标的可理解规则，不许按"谁没格挡"暗选）。

```gdscript
static func scaled_entry(def_id: String, headcount: int) -> Dictionary
## 返回 {hp, attack, extra_spawn}；hp = ceil(base_hp * scale)，缩放系数全部来自表字段
func active_headcount() -> int    # expedition_game：未放弃且仍在局的成员数；某人放弃后"下一场"按它取配置
```

- 验证：`tests/d26_scaling_smoke.gd`——初值断言 {小泥团 18→29、洞穴蝠 14→23、碎石蟹 26→42}，攻击不变；单人 headcount=1 取原值；`extra_spawn_2p` 组合不叠加生命放大；放弃一人后新一场 headcount 回落。
- 依赖：2.2 敌人表、2.4 `expedition_game.gd`。

### W2 combat_game 双人共同回合（D2.6-03、总计划 §5.3）

- 文件：`combat_game.gd`。
- 要点：玩家状态自 2.2 即数组（2.2 设计开篇"规则从一开始允许后续队友加入"），本包把"出牌人"参数化并落主机验证分支：逐请求验证 actor 归属（不许操作队友的牌）、存活未倒地、未结束行动、能量与手牌、目标合法（目标已死 → 掟子拒绝：牌留在手、能量不扣、不自动换目标）。出牌按主机**实际接受顺序**逐个生效，无强制先后；"同时"到达即先后裁定。结束行动可取消，条件是敌方阶段未开始；全部可行动玩家都结束才进敌方阶段；倒地者不计入。最后一名敌人死亡：完成当前有效牌效果即转搜刮，未裁定请求取消且不消耗，不多打一轮敌方阶段。

```gdscript
func start_battle(players: Array, enemy_def_ids: Array, ctx: Dictionary) -> Dictionary
func request_play_card(actor_member_id: String, card_uid: int, target_uid: String, base_state_version: int) -> Dictionary
## 主机分支裁定入口；单人局同入口（A1-2 共用规则入口）
func request_end_turn(actor_member_id: String, base_state_version: int) -> Dictionary
func request_cancel_end(actor_member_id: String) -> Dictionary    # 敌方阶段已开始则拒绝（总计划 §5.3）
func try_advance_enemy_phase(now: int) -> Dictionary    # 全员（可行动者）结束才推进；倒地者豁免
func state_digest() -> String    # 确定性摘要，重放一致性断言用（总计划 §9.2）
```

- 验证：`tests/d26_combat_coop_smoke.gd`（headless 直调主机分支）——同一帧先后提交两张打同一敌人：后到者目标已死返回 `{ok:false, reason:"target_dead"}` 且手牌与能量逐字段不变；提交队友的 `card_uid` 拒绝 `reason:"not_your_card"`；A 结束→B 取消自己的结束→仍可出牌；双结束进入敌方阶段后 `cancel_end` 拒绝；最后敌人死亡瞬间在途请求返回 `reason:"battle_over"` 不消耗；同一动作序列重放两次 `state_digest()` 相同。
- 依赖：2.2/2.3 战斗与牌库。

### W3 倒地、救援与意图目标（D2.6-04、D2.6-05）

- 文件：`combat_game.gd`、`card_defs.gd`（救援牌效果模板，见澄清 1）。
- 要点：生命归零 → `knock_down`：格挡清零、牌与能量保留但一切 `request_*` 拒绝 `reason:"downed"`，可观战发求救信号，不自动掉装备。掩护＝自己或存活队友格挡；应急包扎治疗存活友方；普通治疗对倒地目标拒绝。救援牌（耗 1 能量、消耗一次实体）把倒地队友恢复到 8 生命，**每人每场最多一次**；被救起立即可在当前玩家回合行动，保留未花能量与手牌，若尚未经历本回合开始则补本回合资源、不重复抽牌。救援牌只能玩家阶段使用；敌人阶段倒地需存活者撑到下一玩家回合；双方倒地立即失败。战斗胜利时倒地者恢复 4 生命再一起搜刮。意图目标：单体按 `target_rule`（固定/交替）指派并在意图中显示；群攻显示每人伤害；原目标倒地时**行动前**重选存活者并立即更新意图、写入日志；救援不重抽本回合意图；某人放弃后本场已生成生命与意图不回退。

```gdscript
const DOWNED_REVIVE_HP := 8
const POST_WIN_REVIVE_HP := 4
func request_revive(actor_member_id: String, card_uid: int, target_member_id: String) -> Dictionary
## 即救援牌的 play_card 目标类型"倒地友方"；每人每场一次：member.revived_this_battle
func knock_down(member_id: String) -> Dictionary
func assign_intent_targets() -> void            # 依 target_rule 与当前存活成员
func on_intent_target_downed(enemy_uid: int) -> void   # 行动前重选＋日志记录
```

- 验证：`tests/d26_downed_rescue_smoke.gd`——倒地后出牌拒绝且能量/手牌保留；普通治疗对倒地目标拒绝、救援牌成功且 8 生命；二次救援拒绝 `reason:"already_revived"`；救援后能量与手牌保留、未经历回合开始者补资源不重复抽牌；双方倒地立即判负并按 2.4 失败结算走保护区规则；胜利后倒地者 4 生命；敌人行动前目标倒地 → 意图换人且日志有记录、救援后意图不变。
- 依赖：W2。

### W4 共同选路、事件与休整（D2.6-06）

- 文件：`expedition_game.gd`。
- 要点：每人可标记一个推荐节点（可改）；两人确认**同一个有效节点**才进入；分歧保持决策状态、无倒计时；主机不因身份自动覆盖队友。离开搜刮需双方分别完成整理，已完成者可撤回直到节点真正切换；队友拿物不影响已完成者布局，公共区变化实时可见。事件分个人选项（荒废药箱各选各的）与全队选项：需付款物的事件展示付款人与结果归属，**付款人本人确认后才执行**，不默认扣主机材料、不投票扣别人生命。休整各人独立二选一，全队完成后回地图；某人满血不迫使另一人放弃恢复。

```gdscript
func propose_node(member_id: String, node_id: String) -> Dictionary
func confirm_node(member_id: String, node_id: String) -> Dictionary   # 双方同一有效节点才 enter_node
func mark_loot_done(member_id: String) -> Dictionary / func undo_loot_done(member_id: String) -> Dictionary
func choose_event_option(member_id: String, event_id: String, option_id: String) -> Dictionary
func rest_choice(member_id: String, choice: String) -> Dictionary
```

- 验证：`tests/d26_map_coop_smoke.gd`——两人确认不同节点不进入、确认同节点进入一次；付款事件未获付款人确认不扣物、确认后只扣付款人并给归属者；休整各自独立、全队完成回地图；整理完成后对方领取公共物不改变已完成者状态、撤回有效至节点切换。
- 依赖：2.4 地图与事件。

### W5 个人奖励、公共物资与争取（D2.6-07、总计划 §6.3）

- 文件：`expedition_game.gd`、`inventory_game.gd`（公共区暂存容器）。
- 要点：普通战胜利每人两个候选选一件（默认仅本人可领），未选候选在选定后直接放弃，**不允许先分享已选物再回来领另一候选**。公共区 1~2 件高价值候选，任一人可领；主机原子裁定：物品仍在公共区 && 玩家可操作 && 容器位置合法 → 一次事务移入个人容器；两人同时请求只有先接受者成功，另一人得 `{ok:false, reason:"claimed_by:<成员>"}`，不扣空间、不产生复制物（总计划 §6.3）。"我想要／让给你"只是沟通信号（`want_flag`），不入所有权判定。

```gdscript
func pick_personal_reward(member_id: String, candidate_id: String) -> Dictionary
func claim_public_item(member_id: String, public_item_id: String, container: String, cell: Vector2i) -> Dictionary
func set_want_flag(member_id: String, public_item_id: String, flag: String) -> Dictionary
```

- 验证：`tests/d26_map_coop_smoke.gd` 续——同帧两成员 `claim_public_item` 同一件：恰一人 `ok`、另一人 `reason="claimed_by:…"` 且无空间扣减、公共区数量不出现双份；选定个人奖励后另一候选消失，先分享再领取被拒；丢弃物进公共区可被对方领取（沿用 2.4 丢弃规则）。
- 依赖：W4。

### W6 分享三步流程（D2.6-08、A3 红线）

- 文件：`expedition_game.gd`（裁定）、`inventory_game.gd`（锁定与校验）。
- 要点：三步＝①发送者从物品详情发起提议（带尺寸、价值、来源牌摘要），物品仍属发送者但**临时锁定**（锁定期间丢弃/使用/出售/再次分享全部拒绝）；②接收者选容器与位置确认（可先放弃自己的物品腾空间，全程本人选择）；③主机一次事务转移所有权。接收者拒绝、满包、任一方取消或掉线 → 提议取消、解锁、原物品留在发送者；禁止"双方都持有/都失去"的中间态（事务经 InventoryGame，禁止旁路直改字典）。不可挤掉对方保险箱内容、普通材料不能强制进保护区（复用 2.1/2.3 容器合法校验）；基础装备不可分享（`is_basic`）；任务用品/已锁定装备分享前给提示不阻止（见澄清 5）；允许单向赠送。

```gdscript
# inventory_game.gd
func lock_instance(instance_id: int, purpose: String) -> Dictionary / func unlock_instance(instance_id: int, purpose: String) -> Dictionary
func can_share(instance_id: int) -> Dictionary      # {ok|advise[]}；基础装备拒绝
# expedition_game.gd
func propose_share(from_member: String, instance_id: int) -> Dictionary
func accept_share(to_member: String, proposal_id: String, container: String, cell: Vector2i) -> Dictionary
func commit_share(proposal_id: String) -> Dictionary
func cancel_share(proposal_id: String, by_member: String, reason: String) -> Dictionary
```

- 验证：`tests/d26_map_coop_smoke.gd` 续——锁定期间发送者丢弃/使用被拒；接收者满包接受失败且物品解锁留发送者；成功路径后 `owner_of` 唯一指向接收者；双方各自 `owner_of` 断言不出现双重持有；基础装备分享拒绝；普通材料进保护区拒绝。
- 依赖：W5。

### W7 共同撤离与主动离开（D2.6-09、设计索引基线细化）

- 文件：`expedition_game.gd`。
- 要点：撤离页并排展示每人生命、补给、携带新收益、未保护价值与保护区；两人各确认撤离才生成结算回各自农场，一人想深入则停留协商，系统不代决。首版无"个人带收益先撤离"。个人主动放弃按失败损失结算回家，剩余者继续，双方损失归各自清单；放弃者离场后本场敌人不回退、下一场按剩余人数配置（W1/W3 已覆盖）。**三个不同操作**：主机作为玩家的个人放弃（`forfeit`，可回农场但会话维持到队友本局结束）；结束会话（`end_session`，局档存 `paused_session`、不判全队失败，客户端保持占用与凭据显示"等待原主机恢复"，恢复本身 2.7）；全队放弃（需双方各自确认，两位成员确认后统一结算）。

```gdscript
func extract_sheet(member_id: String) -> Dictionary    # 撤离页并排卡数据
func confirm_extract(member_id: String) -> Dictionary  # 双方确认 → 冻结操作 → 逐人生成结算单
func member_forfeit(member_id: String) -> Dictionary
func forfeit_all_vote(member_id: String) -> Dictionary / func forfeit_all_confirm(member_id: String) -> Dictionary
func end_session() -> Dictionary    # 仅主机可调；局档标记 paused_session 并保存
```

- 验证：`tests/d26_map_coop_smoke.gd` 续——单方确认撤离不结算；双方确认后各自结算单正确、结算互相独立；个人放弃后剩余者可继续进入下一节点且下一场 headcount=1；全队放弃单方确认不生效；`end_session` 后局档 `paused_session` 且客户端占用未解除。
- 依赖：W4~W6、2.4 结算事务。

### W8 session_host：房间、版本检查与出发事务（D2.6-01、D2.6-02、总计划 §9.1/§9.3）

- 文件：`session_host.gd`、`farm_world.gd`（节点挂载）。
- 要点：`farm_world.gd`（组合根）创建子节点 `SessionHost`（本脚本，`extends Node`）与 `SessionClient`，路径双方一致；不新增 autoload。建房：`ENetMultiplayerPeer.create_server(port, 2)` 后 `multiplayer.multiplayer_peer = peer`，监听 `peer_connected/peer_disconnected`。加入握手：`cl_hello` 校验 `net_proto_version` 与 `rules_version`（不符 → `sv_join_result{ok:false, reason:"version_mismatch", …}`）、人数上限（第三人 `room_full`）；通过则绑定 peer↔member（凭据按 §3.1 分发与记录）。准备：`cl_set_ready` 记录并广播 `sv_room_update`；本地配装/补给/目标变化 → 客户端自动撤回本人准备并提示双方。出发事务按总计划 §9.3 顺序：主机生成 `run_id` → `sv_depart_begin` → **各端本地**写带入清单与 `set_run_occupied` 并保存 → 客户端回 `cl_depart_saved` → 主机收齐双方确认（主机自己也完成本地占用）→ 组装初始快照（地图种子为主机 RNG）`save_run` → `sv_run_start`；任一端失败 → `sv_depart_abort{who}` 双方本地 `clear_run_occupied` 回滚，留在房间提示是谁未完成，其他人不先进入（D2.6-02）。进入局后无客户端侧"再开一局"入口。

```gdscript
class_name SessionHost extends Node
const MAX_PLAYERS := 2
func open_room(port: int, profile: Dictionary) -> Dictionary
func set_ready_self(ready: bool) -> Dictionary / func kick_unstarted(peer_id: int) -> Dictionary
func start_departure() -> Dictionary    # 上述事务编排；状态机 room→departing→running
@rpc("any_peer", "call_remote", "reliable") func cl_hello(msg: Dictionary) -> void
@rpc("any_peer", "call_remote", "reliable") func cl_set_ready(msg: Dictionary) -> void
@rpc("any_peer", "call_remote", "reliable") func cl_depart_saved(msg: Dictionary) -> void
@rpc("authority", "call_remote", "reliable") func sv_room_update(room_view: Dictionary) -> void
@rpc("authority", "call_remote", "reliable") func sv_run_start(initial_snapshot: Dictionary) -> void
```

- 任何 `any_peer` RPC 入口先 `multiplayer.get_remote_sender_id()` 取真实发送者并比对成员绑定，不信任载荷内自报身份（总计划 §9.2）。
- 验证：`tests/d26_session_smoke.gd`（headless 直调，不经网络）——版本不符拒绝、第三人 `room_full`、改配装撤回准备并广播、出发事务全序（占用→双方确认→快照→开始）、单端保存失败全队回滚且占用清空、未收齐确认不 `sv_run_start`；`kick_unstarted`/`cl_leave` 只对未出发成员有效。
- 依赖：W1~W7 规则层、2.4 占用事务。

### W9 session_host/session_client：主机权威循环、动作序列与快照广播（总计划 §9.2；D2.6-03~08 联机面）

- 文件：`session_host.gd`（续）、`session_client.gd`。
- 要点：主机权威循环处理 `cl_action`，逐步为：
  1. `action_id` 已在确认表 → 直接回发缓存结果（**动作去重**，重复消息不再扣费/领取，总计划 §13）；
  2. 校验 `run_id` 匹配、`multiplayer.get_remote_sender_id()` 与成员绑定一致、`base_state_version == state_version`（过期 → `{ok:false, reason:"stale_version", current_version}`，客户端转拉快照）；
  3. 按 `kind` 分派到 W2~W7 的 `request_*`/裁定入口（唯一规则入口，网络层不写第二套判定）；
  4. 接受 → `state_version += 1`、写 `action_log`（递增 `seq`）、广播 `sv_action_result`（附表现事件列表，动画只展示结果）；
  5. 拒绝 → 只回提交者，`state_version` 不变。
  快照广播时机：战斗开始、回合/阶段切换、节点切换、结算生成；客户端版本落后主动 `cl_request_snapshot`。随机数全部由主机端 RNG 生成并随局档存种子与推进状态；客户端不产生任何裁定。客户端 `submit(kind, payload)` 生成 `act-<peer>-<seq>`、进 `pending_actions`（UI"等待反馈"来源），可靠通道下超时重发同一 `action_id`（去重保证安全）。快捷信号经主机转发（§3.3），仅表现层。"同一帧两人同时请求"即两条消息按到达先后过此循环，天然产生唯一权威顺序，无并列裁定分支。

```gdscript
# session_host.gd
@rpc("any_peer", "call_remote", "reliable") func cl_action(msg: Dictionary) -> void
@rpc("authority", "call_remote", "reliable") func sv_action_result(result: Dictionary) -> void
@rpc("authority", "call_remote", "reliable") func sv_snapshot(snap: Dictionary) -> void
func confirmed_action(action_id: String) -> Variant     # 去重命中返回缓存结果
# session_client.gd
class_name SessionClient extends Node
func join_by_addr(addr_port: String, profile: Dictionary) -> Dictionary   # create_client + connected_to_server/connection_failed 信号
func submit(kind: String, payload: Dictionary) -> Dictionary             # 组装 action_id 并记录 pending
func apply_snapshot(snap: Dictionary) -> void                            # 重建 UI 视图；版本缺口则 cl_request_snapshot
```

- 验证：`tests/d26_session_smoke.gd` 续（直调两侧对象）——同一 `action_id` 提交两次结果相同且能量只扣一次；`base_state_version` 落后拒绝并说明；身份不匹配（peer 冒用他人 member）拒绝；`tests/d26_net_probe.gd`（真实 ENet，见 §5 双实例/双进程方案）——hello→加入→set_ready→出发→`play_card` 往返→快照到达→断开信号。
- 依赖：W2~W8。

### W10 房间 UI 与联机入口（D2.6-01、D2.6-02）

- 文件：`room_panel.gd`、`farm_hud.gd`、`farm_world.gd`。
- 要点：农场"好友组队"（2.1 置灰入口）打开房间页：创建页（本次层数范围、可见昵称、当前配装摘要、主机可复制邀请信息）与加入页（按实际连接方式加入，先版本检查）。邀请界面写清当前连接方式（局域网／直连／已接入的平台或中继名），**无可用房间服务时不显示房间码**；邀请信息内容＝连接方式＋地址＋规则版本。成员卡按 D2.6-01 字段渲染（含携带可售价值，不含对方农场金币与仓库），只读对方战备。准备/取消、主机移除未出发成员、加入者退出未出发房间（不损失装备）均经 W8 消息。出发确认页：带入清单＋保护区＋各人保存确认状态（等待标记），某人保存失败显示是谁。全程按钮防重复提交、等待状态常显（总计划 §8.1）。
- 验证：`tests/capture_d26_room.gd` 截图（建房、双人准备、出发确认三态）进 `screenshots/`；手工：改配装后双方都看到准备被撤回提示。
- 依赖：W8。

### W11 战斗双人面板、快捷信号与地图协商 UI（D2.6-03/04/06/07/09 界面）

- 文件：`battle_screen.gd`、`expedition_map_panel.gd` 等搜刮/撤离/结算面板。
- 要点（战斗）：队友面板（生命/格挡/能量/手牌数/结束状态/倒地标记），点击只读查看其手牌与来源（不覆盖自己出牌区）；正在提交的牌等待标记、禁止连点重复提交；结束按钮高亮剩余能量＋可取消状态；救援牌打出时高亮倒地队友；倒地玩家视角＝可观战＋求救信号；快捷信号条（`SessionHost.COOP_SIGNALS`，图标配文字，总计划 §8.1）。要点（地图/搜刮/撤离）：推荐节点标记与双方确认状态；事件付款人确认弹层（展示付款人与归属）；休整双栏独立选择；搜刮页双栏（个人候选＋公共区、想要/让给你、领取与分享流、完成整理/撤回、公共区实时刷新）；撤离页并排卡（W7 `extract_sheet`）与共同确认；暂停菜单扩"个人放弃（损失清单确认）/全队放弃（双确认）"，不放在易误点位置（2.4 设计 §2）。动画只展示裁定结果，不阻塞合法操作。
- 验证：`tests/capture_d26_coop_battle.gd`、`tests/capture_d26_extract.gd` 截图；手工核对 1080p 与当前窗口尺寸下双人满面板可用。
- 依赖：W2~W7、W9、W10。

### W12 跨端结算流（总计划 §9.3；§10-2.6 验收"主机不代替客户端写农场档"）

- 文件：`session_host.gd`（续）、`session_client.gd`（续）。
- 要点：撤离/死亡/全队放弃后 `expedition_game` 逐成员生成结算单（`settle-…`，2.4 已有生成与落盘）；主机经 `sv_settlement` 只发**数据**给对应成员并登记 `pending_settlements`；客户端收到 → 展示 → **本人档单次保存应用**（复用 2.4 幂等入口：`applied_settlements` 命中即跳过）→ `cl_settlement_applied` 回执 → 主机标记 `settlement_confirmed`；未回执保留并重发（完整离线重试归 2.7）。主机自身结算在本地同路径应用。客户端保持占用直到本人结算应用完成才 `clear_run_occupied`。主机进程内不存在任何指向客户端农场档路径的写调用。
- 验证：`tests/d26_settlement_smoke.gd`（进程内同时驱动两侧）——同一结算单下发两次只应用一次、回执幂等；主机确认表状态正确；客户端先应用后回执、回执前占用未解除；主机侧仅写自身档（断言结算应用只发生在各端本地 `FarmGame`/`SaveStore` 调用点）。
- 依赖：W7、W9。

### W13 本机双实例、两台设备、互联网实测与试玩关口 B

- 执行序：①先跑 §5 全部 headless 与截图脚本；②本机双实例完整双人局（连接、出发事务、共同战斗、公共区争夺、分享、共同撤离、双方结算逐一走查）；③按 §14 选型实测互联网连接方式并记录配置/防火墙/可达性；④两台设备不同网络再跑一次完整局；⑤组织试玩关口 B 局并填写记录表；⑥全量回归＋交付报告与状态更新。
- 逐项核对总计划 §10-2.6 验收：玩家不能操作队友牌或物品；同时出牌和同时拾取只按权威顺序结算；分享取消不丢物；双方看到相同敌人与节点；结算分别回正确个人档、主机不代替客户端写农场文件。
- 依赖：W1~W12 全部。

## 5. 测试与验收汇总

| 测试 | 覆盖 | 对应总计划 §12.1 |
| --- | --- | --- |
| `tests/d26_scaling_smoke.gd` | 人数缩放数值、extra_spawn 不叠加、headcount 回落 | 战斗-人数配置 |
| `tests/d26_combat_coop_smoke.gd` | 同时出牌裁定、目标死亡拒绝不扣、结束/取消、胜利转搜刮、重放一致 | 战斗-同时出牌/同时击杀 |
| `tests/d26_downed_rescue_smoke.gd` | 倒地限制、救援一次、双倒失败、战后恢复、意图重选 | 战斗-倒地救援/胜负边界 |
| `tests/d26_map_coop_smoke.gd` | 共同选路、付款确认、休整、公共物资原子领取、分享三步、撤离/放弃区分 | 库存-分享与取消、探索-节点一次、联机-同时领取 |
| `tests/d26_session_smoke.gd` | 版本/人数/准备/出发事务、动作去重、过期动作、身份校验 | 联机-版本不同/重复过期动作/身份错误 |
| `tests/d26_net_probe.gd` | 真实 ENet 双端 hello/动作/快照/断开 | 联机-连接 |
| `tests/d26_settlement_smoke.gd` | 跨端结算幂等、回执、占用解除时序、主机不写对方档 | 存档-重复结算、联机-离线收结算（入口） |
| `tests/capture_d26_room.gd` 等 3 份 | 房间/双人战斗/撤离截图 | 实机记录 |

- 本机 headless 方案：规则与裁定断言（`d26_*_smoke`）不经网络，直调主机分支函数，确定性最强；网络面 `d26_net_probe.gd` 沿用 2.1 `d21_net_probe.gd` 已验证的"一个进程内 host＋client 两个 `ENetMultiplayerPeer` 经 127.0.0.1 互通"。RPC 层验证给出两个方案，W9 开工时先做小验证后定一：
  - 方案①（首选）**双进程**：测试脚本用 `OS.create_process` 再起一个 `godot --headless --path . --script res://tests/d26_net_probe_peer.gd -- 角色参数` 子进程当对端；两侧各持独立 SceneTree 与真实 `multiplayer`，RPC 路径天然一致；子进程把加入/动作/快照结果写入约定 JSON 结果文件或以退出码回传，父进程 `await process_frame` 轮询 `OS.is_process_running(pid)`，带超时判定失败。
  - 方案②（待验证）单进程双 `SceneMultiplayer`：`SceneMultiplayer.new()` ×2 分别 `set_multiplayer` 到两棵**同构**子树，各挂 ENet host/client peer，同一帧循环内推进；引擎支持按子树自定义 MultiplayerAPI 实例，但单进程双端的边缘行为（路径解析、poll 时机）**待验证**，见 §6。
  - 两方案都要求测试侧节点结构与生产同构（`SessionHost`/`SessionClient` 显式命名、两侧一致），否则 RPC 寻址失真（A1-8）。
- 本机双实例（UI 层）：两份编辑器进程分别作主机/客户端经 127.0.0.1 互联，走完房间→准备→出发→一节点战斗→搜刮→共同撤离→各自结算；`user://` 隔离见 §6（副本工程保底）；双实例用不同显示窗口位置便于同屏观察，截图各存 `screenshots/`。
- 两台设备实测要求（总计划 §12.3）：不同硬件、不同网络环境（至少一次非同一局域网）完成一次双人完整探险；记录机型、连接方式、版本号、时长与故障。
- 互联网连接方式实测（总计划 §9.1）：**至少一种实测可达的好友连接方式**（端口直连/平台组队/中继按 §14 选型）；若最终仅局域网可达，交付报告中明确标记"联机交付未完成"，不写"互联网可玩"。
- 试玩关口 B 记录要求（总计划 §10-2.6、设计 §12）：双人完整局建议不少于 5 局（含 1 局故意双倒失败、1 局满包分享、1 局公共区争夺、1 局路线分歧、1 局共同撤离）；逐局记录等待时间分解（等待队友出牌/选路协商/搜刮整理/撤离协商）、路线分歧次数与结果、公共物资分配方式与体验、救援/掩护/分享救命物资是否出现且"有实际意义"、撤离决定动因；同时攻击同目标、同时拾取、满包分享、意见分歧四类边界逐项勾验。记录表进交付报告。
- 命令与既有约定：`--headless --path . --script res://tests/…`；随机种子与时间注入；测试档 `user://d26_*` 注入路径，禁止依赖真实玩家档；全量回归含 stage1~6、d21~d25 与全部 d26。

## 6. 风险与回退

- 待设计澄清项：
  1. 救援包物品与"救援牌"定义归属：D2.6-04 要求救援包（普通恢复牌＋救援牌共享一次使用），但 2.2 牌表无救援牌；按模块地图 2.6 对 `card_defs/item_defs` 为"引用"，应确认其已纳入 2.3 的 12~16 种物品预算；若未纳入，需先更新附录 A 模块地图与 2.3 计划再由 2.6 补定义。
  2. `extra_spawn_2p` 的启用组合与低生命敌人数值（D2.6-05"特殊双人组合"未列名单）：2.6 先留配置位并只做一个示例组合，数值待试玩。
  3. 单体攻击 `target_rule` 逐敌人的具体指派（哪只固定打谁、交替顺序）：影响意图可理解性，需设计逐条确认初值。
  4. "结束会话"后双方的界面状态与文案（客户端"等待原主机恢复"期间可做什么）：设计只给规则未给界面；2.6 先做最小提示，恢复操作 2.7。
  5. "任务用品分享前给提示"（D2.6-08）：任务系统 2.5 落地，若"任务用品"标记字段未在 2.5 定义，2.6 先按无任务用品处理（提示位留空不阻断）。
- 互联网连接方案未定的影响（总计划 §14）：W10 邀请信息与连接方式文案、W13 实测口径都依赖选型；未定则先交付 IP 直连路径并按 §9.1 标记联机交付未完成，`session_client.join_by_addr` 接口不变、后补平台/中继实现不牵动规则层。
- 单进程双 `SceneMultiplayer` 行为待验证：若②方案不可行，回退①双进程方案；两者都失败则网络断言只保留直调式（`d26_session_smoke`）＋两台设备实测，并在交付报告记为未验证项。
- 双实例 `user://` 隔离：同一工程名两实例共享 `user://`。可行方案 a：工程目录副本＋改 `project.godot` 的项目名或 `application/config/use_custom_user_dir`＋自定义目录名（确定可行）；方案 b：引擎命令行参数直接覆盖用户目录（是否存在该参数**待验证**，不得当作定论）。实测用 a 保底。
- 合作等待手感（总计划 §13 优先风险）：快捷信号、等待标记、意图提示先行；若试玩显示"高手替新手看牌完全指挥"，按设计 §12 收起默认队友手牌（改 UI 常量即可回退）。
- 快照体积与频率：全量快照仅在关键时点发送，常规动作只广播增量事件；若双人局实测快照过大（手牌＋双容器＋地图），先压缩为按场景裁剪的快照分片，不改消息语义；快照结构变更必须递增 `net_proto_version`。
- 主机个人放弃后的会话维持：主机以玩家身份放弃后仍需保持进程承载裁定直至队友本局结束（D2.6-09）；若主机此时结束会话，按 `paused_session` 处理且客户端保持未决态，不自动返还装备（总计划 §9.3）。
- UI 体量风险：`battle_screen`/地图面板改动集中且截图逐关口验证；`room_panel` 独立文件防 `farm_hud` 膨胀（A1-3）。
- 回退粒度：每个工作包独立提交；W8/W9（网络）失败可整体回退而保留 W1~W7 的规则层与全部单人回归；W10~W12 依赖网络层但可灰版（本地双人直调）先行。

## 7. 交付物清单

- 代码：§2 表的 2 个新服务脚本、1 个新 UI 面板、6 处扩展与 2 处挂接修改。
- 测试：§5 的 8 份 `d26_*` 脚本与 3 份截图脚本。
- 文档：`docs/archive/Godot_阶段2.6_交付报告.md`（含：实测连接方式与可达性记录、两台设备配置表、本机双实例方案结论、试玩关口 B 记录表、等待时间分解数据、规则版本与网络协议版本实际采用值、待验证项清单）；更新总计划 §10-2.6 状态、`docs/README.md`、根 `README.md` 与代码计划索引。
- 实测记录：互联网连接方式实测证据（配置、防火墙/端口观察、服务依赖）；仅局域网可达时明确标记"联机交付未完成"。
