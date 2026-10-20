# 苔冠森林 · 插图实机画面

2026-10-20，Godot 4.6.1，OpenGL Compatibility，1280×800。以下均为实际引擎渲染，源资源为 `assets/chapter_one/` 中的简洁几何风 SVG。

- [林间古道](area_trail.png)
- [苔封神殿](area_temple.png)
- [空铃废塔](area_tower.png)
- [废弃伐木营地](area_camp.png)
- [荧沼湿地](area_wetland.png)
- [23 种敌人总览](enemies_overview.png)
- [预览页敌人区](enemy_section.png)
- [36 件物品](item_section.png)
- [16 张来源牌插图](card_section.png)

入口：主菜单打开「测试功能」→「森林预览」。页面可滚动查看全部插图。当前仍是开发图鉴，正式森林出发开关保持关闭。

截图脚本：`tests/capture_forest_art.gd`。验证：`forest_art_smoke.gd`、既有 `forest_defs_smoke.gd`、123 件 SVG XML 解析均通过。布局检查覆盖 1024×640 最小窗口，检查背景不遮挡搜索物；截图在独立测试存档目录运行。
