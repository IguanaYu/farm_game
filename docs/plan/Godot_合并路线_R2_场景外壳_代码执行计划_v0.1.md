# 合并路线 R2：常驻场景外壳 代码执行计划 v0.1

编写日期：2026-10-03。状态：**已定稿，开始实施**。

依据：[合并路线图](Godot_合并路线图_联网与多场景_v0.1.md) R2 行；[多场景与空间交互设计稿 v0.4](../design/Farm_多场景与空间交互_设计稿_v0.4.md) §10（Godot 落地结构）。

## 1. 目标与非目标

**出口**（路线图 R2 原文）：

> 往返切换十次零重建、零额外收益；离线+线上双模式回归全过。

**非目标：**
- 不新增商店/洞口/拜访场景的实际内容（R3/R4/R7）；本轮只立骨架与一个占位切换目标。
- 不动 farm_hud 的面板布局（CommonHUD 的"地点/金币/连接"常显区在 R3 随视觉轮落地）。
- 不改任何玩法规则与联网协议。

## 2. 架构（设计稿 §10 的落地形态）

```text
main.tscn（FarmWorld 节点，即事实上的 WorldShell——常驻根）
 ├─ GameContext（scripts/world/game_context.gd，RefCounted）   ← 本轮抽取
 │   ├─ mode（OFFLINE_NEW / OFFLINE_LOAD / ONLINE，读 GameFlow）
 │   ├─ game: FarmGame（离线读档/新档；线上=bridge.game）
 │   ├─ online: OnlineFarmBridge（线上装配/登录/恢复，原 _boot_online）
 │   ├─ now()（离线系统时间 / 线上服务器锚点，原 _now）
 │   ├─ save()（离线原子落盘；线上 no-op 提示，原 _save 家族）
 │   └─ tick()（离线 market 跨日+育种结算；线上跳过——服务器已做，原 _on_clock_tick 前半）
 ├─ SceneRouter（scripts/world/scene_router.gd）               ← 本轮新增
 │   ├─ locations 注册表（location_id → 展示节点 + 进入/离开钩子）
 │   ├─ switch_to(id, intent)：返回栈 + 0.2~0.35s 淡入过渡（设计稿 §3）
 │   └─ R2 注册：farm（自身根）+ shop_stub（占位间，证明切换与返回）
 └─ FarmScene 视图（farm_world.gd 瘦身后保留：3D 构建/地块刷新/HUD 装配/输入分发）
```

**关键决策：**

1. **farm_world 原位长成 WorldShell，不改 main.tscn 根节点**：d33 等测试直接访问 `world.game/hud/_refresh_all/_on_*_requested`，根节点换成新类型会全部破坏。设计稿要求的是"常驻根 + 切换不重建规则对象"——由 farm_world 承担该职责在结构上等价；更名/拆分推迟到 R3 视觉轮（届时引入真正的 SceneHost 子节点挂多场景）。
2. **GameContext 先行**：这是"切换十次零重建"的本体——把 `game/online/now/save/tick` 从 farm_world 的 `_ready` 路径抽到独立对象，farm_world 持有 `context` 并保留同名薄转发（`_now()/_save()/game` 直接引用 context 成员），测试面零变化。
3. **SceneRouter 以"地点=节点可见性+钩子"实现**：R2 不 instantiate/销毁场景；切换=隐藏当前地点节点+展示目标节点+镜头/回调。占位 shop_stub 是 FarmWorld 下一个隐藏 Node3D 小间（一面墙+门），点击商店建筑经 router.switch_to("shop") 进入，ESC/门返回 farm。R3 把 shop_stub 换成真正的商店内景时，router 接口不变。
4. **零额外收益的验收口径**：切换前后 `context.game` 为**同一实例**（`==` 比较）；`tutorial_step/market.day/coins/next_id` 逐项不变；离线 tick 的 `refresh_market/breeder_settle` 在切换期间至多按时间推进一次（不因切换重复触发——tick 计时器常驻 context，与场景无关）。

## 3. 实施步骤

| 步 | 内容 | 提交点 |
| --- | --- | --- |
| R2-a | `game_context.gd`：搬 mode/game/online/now/save/tick（离线分支全量 + 线上装配）；farm_world 持有 context 并保留同名转发；`_boot_online/_online_bootstrap` 拆为 context 装配 + farm_world 视图反应 | 全量回归绿（零行为变化） |
| R2-b | `scene_router.gd` + shop_stub 地点 + 商店建筑点击改走 router + ESC 返回；过渡用 ColorRect 淡入淡出（约 0.25s，不阻塞输入队列） | d47 绿 |
| R2-c | d47：`tests/d47_world_shell_switch_smoke.gd`——离线：farm↔shop 往返 10 次，断言 game 同实例/tutorial/market/coins 不变、tick 计时不重置；线上：context 装配后 game 即 bridge.game、now() 为服务器锚点（复用 d46 子进程服务器模式，轻量两断言） | d47 绿 + 全量回归绿 |

## 4. 风险

| 风险 | 对策 |
| --- | --- |
| farm_world 1316 行抽取漏引用（_save/_now 有 100+ 调用点） | 保留同名薄转发方法，调用点零改动；抽取以"搬走创建逻辑、留转发壳"为纪律 |
| 线上 bootstrap 时序（welcome→视图构建）被拆散 | context 发 `bootstrapped` 信号，farm_world 原方法体作为反应器原样接上；d42~d46 回归兜底 |
| 切换过渡阻塞导致测试卡死 | 过渡纯表现（CanvasLayer alpha 动画），切换本体同步完成；headless 下跳过动画 |

## 5. 维护

完成后更新本文件状态与[合并路线图](Godot_合并路线图_联网与多场景_v0.1.md) §0；偏差记录在本文件末尾。
