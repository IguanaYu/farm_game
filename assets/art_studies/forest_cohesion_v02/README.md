# 古道整体风格校准样例 v02

2026-10-21，针对实机拼合后比例、背景空间及地台不协调的反馈。

以现有 `ExpeditionArt` 农夫的头身比、圆形五官、宽衣摆、短靴、低饱和绿与暖木色为基准。包含古道背景、哥布林弓手和铜剑三件独立 SVG；不覆盖 `assets/chapter_one/` 中已登记的正式插图。

变化：弓手的头部中心、身高和落脚点与农夫对齐；铜剑采用原有切击轮廓；树冠、树干和木头使用少量相近明暗面；路面从角色脚下开始；场景取消连续椭圆地台，改为两个轻薄接触阴影。原农夫、战斗卡框、按钮与战斗状态保留。

这是一张完整战斗画面的风格样例，尚未替换五区资源。独立的“攻击动画样稿”入口也使用这组三件插图，已收入 Windows 包；正式资源映射和玩法不变。

- 源码：`tools/build_forest_style_study.py`，运行 `python tools/build_forest_style_study.py` 再生成。
- 实机：`tests/capture_forest_style_study.gd`，需 Godot 导入后带渲染窗口运行。
- [同一战斗状态的原图](../../../screenshots/forest_style_study_v02/01_before.png)
- [校准后实机画面](../../../screenshots/forest_style_study_v02/02_unified_study.png)

验证输出：`FOREST_STYLE_STUDY_PASS: same combat state, original farmer and UI preserved`，无引擎／脚本错误。
