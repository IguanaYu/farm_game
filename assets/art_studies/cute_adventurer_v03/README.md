# 草帽小姑娘 · 主角与动作卡样稿

保留草帽、绿色衣服和暖木色靴子，主角设定为可爱的小姑娘。棕色双辫、草帽丝带、米色衬衣和绿色背带裙配合大头短身、圆脸、微笑与淡脸颊；叶芽别针、围裙刺绣和小挎包在各张卡中重复出现。

六张卡由同一份主角 SVG 构造生成，姿势、道具和辅助符号分别对应射击、突刺、强射、敲击、守护铃、烟幕。卡面无费用/文字，仍由真实战斗 UI 绘制。

- 主角：`assets/characters/farmer_cute.svg`，由共用 `ExpeditionArt` 的 farmer 主题使用，覆盖现有 2D 战斗/探索/搜刮肖像。
- 卡牌：本目录六张 SVG，仅“攻击动画样稿”使用这组角色卡面；六张卡的规则与费用保持已有样稿定义。
- 构造源：`python tools/build_cute_forest_hero.py`；主角与卡牌共享同一个 `hero(pose)`。
- 实机截图：`screenshots/cute_forest_girl/`；上一版保留于 `screenshots/cute_forest_hero/`。
- 捕获与视觉接线检查：`tests/capture_cute_forest_hero.gd`。

足底仍在 200 单位画布的 y=188，保持现有落地阴影与攻击轴点。原有整片前冲、箭矢、受击和减少动态效果设置继续工作。
