# 第二批十张森林情境卡

2026-10-24，使用内置 image_gen，一张一个提示词生成，沿用已确认的草帽双辫小姑娘和第一批的森林卡风格。原图保留在本目录，`manifest.json` 保存每张的完整提示词、身份／风格参考图、原始输出路径与一句话情境。

通过 `tools/build_card_story_expansion_assets.gd` 将原图等比例缩为 `assets/chapter_one/cards/<id>.png`（640×400）。缩放只适配运行尺寸，不改变构图；旧 SVG 保留作历史资源。共享登记表为全部十六张情境卡使用 PNG。

名称与实际规则读取 `ForestStoryExpansionCombat.ADDITIONS`。具体牌表、来源规划、数值理由、场景描述和未实现范围见 `docs/design/Farm_森林情境卡第二批_规则与画面_2026-10-24.md`。

- `screenshots/card_story_v06/01_ten_new_cards.png`：十张新卡、当前费用与效果。
- `02_thumbnail_and_grayscale.png`：128×80 彩色／灰度，64×40 压力图。
- `03_all_sixteen_cards.png`：两批十六张总览。
- `gameplay/`：两组牌的 1280×800、1024×640 真实手牌及净化／中毒结算。

入口：首页 → 森林预览 → 新卡试玩（10 张），设置 → 换组。

本次新卡具备独立可运行定义。灼烧与独立寒冷尚未实现，火系使用直接伤害，冰囊使用攻击后虚弱；这些限制与当前卡牌说明一致。一次补给在本场移除，不扣农场库存。玩家对缩图、趣味和攻防识别的反馈仍是后续打磨依据。
