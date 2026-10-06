# 菜单真实输入链路证据（d54，2026-10-04）

测试脚本：`tests/d54_menu_live_input_smoke.gd`（SceneTree 直驱 + 真实输入注入）
运行方式：带窗口跑（本目录截图）＋ headless 跑（入回归，自动跳过截图）。

## 证据分类口径

- `live_*`：**真实输入驱动**后的状态。鼠标 = warp_mouse + MouseMotion + press/release 注入（root.push_input），
  点击前先断言 `gui_get_hovered_control` 命中目标按钮（同时证明无遮挡）；键盘 = 合成 ESC press/release 走完整输入链。
- `fixture_*`：**未经输入**的初始/直开状态（与线上演示快照的 fixture 口径一致）。

## 截图清单

| 文件 | 类别 | 驱动方式 | 验证内容 |
| --- | --- | --- | --- |
| fixture_01_main_menu_home.png | fixture | 无输入（初始状态） | 主菜单首页；继续按钮可用（有种子里 999 金） |
| live_02_settings_opened_by_click.png | live | 真实点击"设置" | 设置页可见 |
| live_03_new_game_confirm_by_click.png | live | 真实点击"开始新游戏" | 有档时弹出覆盖确认页 |
| live_04_pause_opened_by_esc.png | live | 真实 ESC 输入 | 游戏内弹出暂停菜单 |
| live_05_pause_settings_by_click.png | live | 真实点击"设置"（暂停内） | 暂停设置子页可见 |
| live_06_back_to_main_menu.png | live | 真实点击"回到主菜单" | 场景切回主菜单；**与 fixture_01 逐字节一致**（MD5 相同） |

## 断言结果（带窗口运行，2026-10-04）

29 项 ok / 0 项 FAIL，`D54_MENU_LIVE_PASS`，退出码 0。覆盖链路：

1. 主菜单：设置（点击开 → 真实 ESC 回）→ 新游戏覆盖确认（点击开 → 点"返回"关）→ 继续游戏（点击 → 切进农场、读档金币 999、GameFlow 复位）。
2. 游戏内暂停：ESC 弹出 → 点"继续"关闭 → ESC 再弹 → 点开设置子页 → 点"返回"回暂停主视图 → 点"回到主菜单"切回主菜单场景（继续按钮可用）。
3. 退出：真实点击"退出游戏"按钮 → 进程退出码 0（点击后未观察到"进程未退出"失败）。
4. 11 个按钮全部通过 hover 命中断言（无遮挡）与"中心点在窗口内"断言。

## 报错检查（windowed / headless 两份日志）

- 运行期：**0 条 SCRIPT ERROR、0 条未预期 ERROR**（日志：`screenshots/d54_windowed_run.log`、`screenshots/d54_headless_run.log`）。
- 退出期：仅 1~2 条引擎资源缓存提示 `ERROR: N resources still in use at exit`（d53 同款已知项，
  headless 下多 1 条音频流），已在 `tests/run_regression.ps1` 与 `run_regression.sh` 白名单同步放行（各 2 条上限）。
- 首次运行曾失败：`.godot` 类缓存/导入缓存过期（新加 SVG 精灵未导入、LifeUI/SceneArt 类名未注册），
  `--headless --import` 重建后消除——与游戏代码无关，属工作副本缓存陈旧。

## headless 差异说明

headless 无窗口（`root.size` 为 0）且无 hover 状态：截图、hover 命中、窗口内三类**视觉证据断言**自动跳过；
点击注入与全部结果断言照常执行（headless 25 项 ok 全过、退出码 0）。
