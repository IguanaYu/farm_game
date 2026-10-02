# 泛用联机框架 分层设计 v0.1

日期：2026-10-02
状态：设计稿（未实施）。当前农场联机实现见《Godot_联机中继_互联网房间_方案与执行计划_v0.1.md》（已落地）。
定位：一套可跨项目复用的联机内核，支撑后续多类游戏的多人模式。

## 1. 目标与非目标

**目标**
- 一套代码支撑三类典型玩法：
  - **回合制/慢节奏**（打牌、当前的合作洞窟）：意图→裁定→全量快照；
  - **实时合作**（胡闹厨房式）：10~20Hz 连续模拟，掉线暂停可接受；
  - **实时平台/对抗**（马里奥式）：低延迟要求，需要插值/预测。
- 2~8 人房间（不再写死双人）；观战位可选。
- 部署形态可切换：玩家主机权威（现状，零服务器成本）／云端专用服（headless 跑裁定）。
- 已落地资产最大化复用：中继服务器本来就游戏无关；房号/心跳/重连去重/两段式出发事务全部保留。

**非目标（明确不做）**
- 账号系统、好友关系、大规模匹配、反作弊、跨 region 加速。
- 回滚网络（GGPO 式）的完整实现——接口预留，另立项目再议（见 §6 风险）。
- 万人同服 MMO/持久世界。

## 2. 核心判断：三类游戏的差异在哪一层

先说结论：**传输和会话两层对所有游戏是同一套；真正随玩法变化的是"同步模型"这一层；游戏规则永远留在游戏侧。**

| 玩法 | 上行（客机→主机） | 下行（主机→客机） | 频率 | 对延迟 | 掉线策略 |
|---|---|---|---|---|---|
| 打牌/合作洞窟 | 意图（幂等，带 id） | 全量快照 | 每动作 1 次 | 不敏感（秒级也行） | 暂停等待重连（现有） |
| 胡闹厨房式 | 每 tick 输入 | 每 tick 状态增量 | 10~20Hz | 宽容（100~200ms 可玩） | 暂停等待重连 |
| 马里奥式 | 每 tick 输入 | 状态增量 + 本机预测 | 20~30Hz | 敏感（>80ms 手感差） | 本机预测兜住，暂停重连 |

由此得出分层：下层共用，只有 L2 按"同步模型"插拔。

## 3. 分层架构

```
L3  游戏适配层（每个游戏自己写，框架只定义接口）
    GameRules: 校验/执行意图、序列化/应用状态、tick 模拟、掉线策略
        ▲
L2  同步模型层（框架提供，三选一插拔）
    IntentSnapshot（现有）｜TickDelta（实时类）｜Lockstep（预留接口）
        ▲
L1  会话层（框架提供，游戏无关）
    房间/房号、成员表（N 人）、就绪、两段式开局、心跳、重连、版本协商
        ▲
L0  传输层（现有 session_transport 抽象，扩展）
    ENet 直连｜TCP 中继｜WebSocket（新增）｜（预留 UDP 中继）
```

每层只依赖下一层的接口；换传输不动会话，换同步模型不动传输。

## 4. 各层详细设计

### L0 传输层

现有 `SessionTransport` 基类保留，扩展两点：

1. **消息属性**：`send(peer_id, envelope, channel)`，channel 0=可靠有序（默认，现有行为）、channel 1=不可靠最新（实时增量用，丢了不重发）。ENet 原生支持；TCP 中继上 channel 1 退化为可靠（行为正确、延迟特性见 §6）。
2. **新实现 `WebSocketTransport`**：Web 导出与更广兼容；中继服务器已按"转发任意 JSON"设计，加二进制帧即可承载。

**中继服务器 v2**（`relay_server.py` 演进，向后兼容）：
- `create_room` 增加 `game`（游戏标识）、`max_members`（默认 2）、`meta`（房间名等）；
- 成员槽从写死 {1,2} 改为动态 1..N；`peer_down`/`relay` 信封不变；
- 房间内成员间消息仍按行转发，服务端永不理解游戏协议（这一原则不变）。

### L1 会话层（从 SessionHost 剥离）

新类 `SessionCore`（主机侧）/`SessionMember`（客机侧），承接现在 SessionHost/SessionClient 里**与游戏无关**的部分：

- 房间生命周期：`lobby → departing（两段式开局事务）→ playing → over`；
- 成员表：`player_id`（稳定身份，重连去重键）、`seat`（1..N）、`online`、`ready`；
- 心跳与超时（800ms ping / 2.5s 判离线，现有参数）；掉线后**是否暂停推进**由游戏的掉线策略决定（打牌/厨房=暂停；马里奥=本机继续预测，主机用最后已知输入）；
- 重连：同 player_id 新连接接回原座位 + 补发快照（现有逻辑泛化到 N 人）；
- 版本协商：`rules_version` 不一致拒绝（现有）。

现 SessionHost 里的"动作裁定 + 快照广播"（`_on_action`/`_execute_action`/`host_action`）移出会话层，归入 L2。

### L2 同步模型层

统一接口（示意）：

```gdscript
class_name SyncModel
func submit_intent(member_seat: int, intent: Dictionary) -> void      # 客机上行入口
func host_submit(intent: Dictionary) -> Dictionary                    # 主机本地意图直通
func poll(now_ms: int) -> void                                        # 泵：裁定/模拟/下发
```

**a) IntentSnapshot（现有模型，直接迁移）**
- 客机发意图（幂等 id，`action_log` 去重）；主机校验执行；结果 + 全量快照广播。
- 适用：回合制。当前合作洞窟即此，迁移后行为不变。

**b) TickDelta（新增，实时类主力）**
- 主机（或专用服）以固定 tick 模拟（推荐 15~20Hz，物理跑自己的更高帧率）；
- 上行：每 tick 一条输入包 `{tick, seat, input}`（不可靠通道，≤64B；主机缺输入时沿用上一 tick）；
- 下行：每 tick 状态**增量**（实体脏标记 + 字段掩码，二进制），每 N tick（如 20）夹一条全量关键帧兜底；客户端两 tick 插值显示；
- **本机预测（可选开关）**：只预测自己操控的实体——本地立即响应，主机权威帧到达后软校正（误差大瞬移，小则 100~200ms 内平滑收敛）。马里奥式必开，厨房式可不开。
- 带宽账（支撑设计的依据）：8 实体游戏，增量 ≈ 8×24B ≈ 200B/tick，20Hz → 4KB/s/人下行；输入上行 64B×20Hz ≈ 1.3KB/s。对比 JSON 全量快照 2KB×20Hz=40KB/s/人——所以实时类必须二进制增量，不打牌的全量 JSON 不动。

**c) Lockstep（预留，不实现）**
- 确定性模拟 + 输入延迟/回滚。接口位留出（SyncModel 第三个实现），当前不排期，理由见 §6。

### L3 游戏适配层（每个游戏实现的小接口）

```gdscript
# 游戏侧要提供的（全部围绕"状态字典 + 意图字典"，与现 ExpeditionGame 同构）：
func net_validate(seat: int, kind: String, args: Dictionary) -> String   # ""=合法
func net_execute(seat: int, kind: String, args: Dictionary) -> Dictionary
func net_state_full() -> Dictionary            # 全量快照（打牌用）
func net_state_delta(since_tick: int) -> PackedByteArray   # 增量（实时用）
func net_apply_full(state: Dictionary) -> void # 客机侧
func net_tick(delta: float) -> void            # 实时类主机侧模拟
func net_offline_policy() -> int               # PAUSE / PREDICT
```

当前 `ExpeditionGame` + `SessionHost._execute_action` 的 match 分支就是事实上的 `net_validate/net_execute`——迁移即搬移，不重写规则。

## 5. 三类游戏落在框架上的样子

**打牌（现在的农场合作洞窟）**：IntentSnapshot + 现中继。迁移完成后行为与今天完全一致，d26/d27/d34 三个测试保证不回归。

**胡闹厨房式（2~4 人）**：TickDelta（不开预测，或只预测自己角色移动）+ 主机权威 + 掉线暂停（复用现有暂停语义）。厨房类玩法本身对 100~200ms 延迟宽容，TCP 中继即可。

**马里奥式（2~4 人）**：TickDelta + 本机预测必开；优先局域网 ENet 直连（最低延迟），中继做跨网兜底——预测能把中继多出的半程 RTT 大部分藏在本机响应里，藏不住的部分表现为对手位置略滞后，平台跳跃自己手感不受影响。

## 6. 风险与诚实标注

- **TCP 中继与实时游戏**：中继路径比直连多约半个 RTT，且 TCP 队头阻塞在丢包时会卡增量流。厨房式可接受；马里奥式"自己手感靠预测保住、他人略滞后"可接受；真要电竞级手感需要 UDP 中继/回滚——本期不做，接口留了位置 [B]。
- **回滚（Lockstep）工作量**：要求模拟完全确定性（浮点、随机数、迭代序都要锁），投入是另起一个项目的量级，不适合顺手做 [A]。
- **主机权威 + 主机退出**：现有设计=主机存档恢复+重连接回；厨房/马里奥若频繁掉线体验差，届时上专用服模式（headless Godot 跑 SessionCore+SyncModel，中继服务器只当转发），这是比主机迁移（host migration）便宜得多的路线——迁移不在本设计内 [A]。
- **JSON 全量快照不适合实时类**：带宽账见 §4-b，实时类必须走二进制增量，这是 TickDelta 存在的理由。

## 7. 目录与迁移路径

目标目录（独立于任何游戏，可直接拷给下一个项目）：

```
addons/netkit/
  envelope.gd            # 消息信封 {seq, channel, kind, body, id}（向后兼容现格式）
  transport/             # session_transport / enet / relay / websocket
  session/               # session_core / session_member / room_state
  sync/                  # intent_snapshot / tick_delta / (lockstep 预留)
```

分阶段落地（每步农场照跑、测试护住）：

| 阶段 | 内容 | 验收 |
|---|---|---|
| A | 抽 SessionCore/SessionMember，SessionHost/Client 变薄壳；行为零变化 | d26/d27/d34 全绿 |
| B | 信封 v2（channel/seq）+ 中继 v2（N 成员/game 标识）+ WebSocketTransport | 中继兼容旧客户端回归 |
| C | TickDelta + 二进制增量 + 一个 20Hz 小样例场景（两个方块互推） | 样例在中继+直连两模式下 60s 压测不卡不漂 |
| D | 专用服模式：headless Godot 跑 SessionCore（农场先受益） | 主机退房局不断 |
| E（可选） | UDP 中继 / Lockstep 另立项 | — |

当前农场不需要等框架完成：现有实现继续用，阶段 A~B 是纯重构不改变行为，C 起新游戏直接用 netkit。
