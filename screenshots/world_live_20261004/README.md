# 世界/探险/战斗真实输入链路证据（d55，2026-10-04）

测试脚本：`tests/d55_world_live_input_smoke.gd`（SceneTree 直驱 + 真实输入注入，参考
`capture_scene_alignment.gd` 与 `capture_expedition_redesign.gd` 的功能面，与其互补：截图套件带窗口跑，
本脚本同链路纳入 headless 回归）。运行：带窗口（本目录截图）＋ headless（回归）。

## 证据分类口径

- `live_*`：**真实输入驱动**后的状态。3D 物体 = 相机投影到屏幕坐标再注入鼠标 move/press/release（真实视口拾取）；
  2D 按钮 = 控件矩形中心注入（带窗口时先断言 hover 命中、无遮挡）；拖放 = 引擎拖放流程；
  按键 = 合成 press/release 走完整输入链。
- `fixture_*`：**直开面板/直备状态**（演示口径，与线上演示快照的 fixture 约定一致）。

## 截图清单

| 文件 | 类别 | 驱动方式 | 验证内容 |
| --- | --- | --- | --- |
| fixture_01_farm_home.png | fixture | 无输入（种两块催熟） | 农场初始 |
| live_02_expansion_by_plot_click.png | live | 真实点击未开垦地块 | 弹出扩地弹窗 |
| live_03_seed_picker_by_plot_click.png | live | 真实点击已开垦空地块 | 弹出选种弹窗 |
| live_04_shop_by_building_click.png | live | 真实点击杂货铺小屋 | 点门换场景：进商店 |
| live_05_guest_trade_by_click.png | live | 真实点击客商 | 打开交易弹窗并选中该客商 |
| live_06_camp_by_stairs_click.png | live | 真实点击山道楼梯 | 点门换场景：进洞窟营地 |
| live_07_loadout_after_drag.png | live | 真实点击战备台 + 真实拖放 | 配装面板打开；装备落到指定格 [1,2] |
| fixture_08_hub_ready.png | fixture | 直开出发台+直备装备 | 空配装出发禁用 → 装备上身解禁 |
| fixture_09_route.png | fixture | 直开地图 | 探险路线初始 |
| live_10_encounter_by_confirm_click.png | live | 真实点路线 + 真实点"向这里前进" | 选中下一节点并走领域层移动 |
| fixture_11_settlement.png | fixture | 直开结算 | 撤离结算（真实 ESC 无法提前关闭） |
| fixture_12_battle_round1.png | fixture | 直开战斗 | 战斗首回合 |
| live_13_strike_by_target_click.png | live | 真实点卡 + 真实点目标 | 挥砍选中；破挡 4 后敌人生命 -2 |

## 断言结果（2026-10-04）

- **带窗口**：30 项 ok / 0 FAIL，`D55_WORLD_LIVE_PASS`，退出码 0；13 张截图。
- **headless（回归口径）**：30 项 ok / 0 FAIL，退出码 0；3D 视口拾取在 headless 同样生效
  （地块/杂货铺/客商/楼梯/战备台真实点击全部命中）。
- 数值对账：真实点击"确认卖出"后金币增量 == 客商报价；挥砍伤害 = 基础 6 − 敌人格挡 4 = 生命 -2。

## 报错检查（两份日志）

- 运行期：**0 条 SCRIPT ERROR、0 条 ERROR**（`screenshots/d55_windowed_run.log`、`d55_headless_run.log`）。
- 退出期：本脚本在世界与面板全部 `queue_free()` 后退出，无 d53/d54 那类资源缓存提示，**无需回归白名单**。

## 与既有测试的关系

- d49 的 3D 点击是"回调直呼"（其注释：真实视口拾取由 capture_scene_alignment 验证）——d55 把真实拾取纳入回归。
- d44 的真实拖放在战利品面板；d55 补配装格拖放，并沿用其 headless 拖放口径
  （motion 走 `root.push_input`；dummy 显示服务不跟踪指针，headless 释放用同一 `_can_drop_data/_drop_data` 回调验证载荷）。
- capture_scene_alignment / capture_expedition_redesign 仍负责窗口截图与更全的布局检查；d55 取其核心交互链。
