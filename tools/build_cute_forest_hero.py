"""Rebuild the rounded farmer and six character-led card illustrations (native SVG)."""
from pathlib import Path
from build_forest_art import rect, path, poly, circle, ellipse, group

ROOT = Path(__file__).resolve().parents[1]
HERO = ROOT / "assets/characters"
CARDS = ROOT / "assets/art_studies/cute_adventurer_v03"
SKIN, CHEEK, INK = "#f0d6b2", "#dfa89b", "#506353"
GREEN, DARK_GREEN, HAT, WOOD = "#9cac7e", "#758b66", "#eddaa5", "#a27c59"


def sprout(x, y, scale=1):
    return group(path("M0 7V-7", stroke=DARK_GREEN, sw=3) + path("M0-2Q-19-1-14-13Q-2-16 0-2M1-4Q0-19 14-17Q19-5 1-4", GREEN), f"translate({x} {y}) scale({scale})")


def hero(pose="idle"):
    """200-unit art; boots stay at y=188, so existing contacts/animation pivots align."""
    s = rect(61, 118, 31, 43, WOOD, 10)  # Little travelling satchel.
    s += rect(76, 156, 20, 29, "#b29a76", 8) + rect(105, 156, 20, 29, "#b29a76", 8)
    s += rect(71, 169, 27, 19, WOOD, 8) + rect(104, 169, 27, 19, WOOD, 8)
    s += path("M80 173H91M113 173H124", stroke="#c5a77d", sw=3)
    s += path("M77 115Q100 107 125 117L135 158Q138 173 120 173H79Q64 173 67 159Z", GREEN)
    s += path("M117 121Q126 141 124 163H75Q74 174 86 174H121Q138 174 135 158L125 117Z", DARK_GREEN, opacity=".32")
    s += path("M81 121 76 153M120 121 124 153", stroke="#c3cd9a", sw=5)
    s += rect(85, 141, 30, 22, "#b2be8c", 7)
    s += circle(88, 140, 2.5, HAT) + circle(112, 140, 2.5, HAT)
    s += path("M75 119Q91 132 109 123L122 115", stroke="#ead7a4", sw=6)
    s += path("M104 124 116 132 109 140 101 127Z", "#d5ac6e")
    # Stubby sleeves and mitten hands. Each card has an actual small gesture.
    left = {"guard": "M76 129 63 119", "smoke": "M76 130 62 143"}.get(pose, "M76 129 61 145")
    right = {"shoot": "M125 130 143 119", "power_shot": "M124 130 144 137", "thrust": "M125 131 145 135", "bell": "M124 128 140 109", "guard": "M125 129 141 111", "smoke": "M124 128 140 114"}.get(pose, "M124 129 139 145")
    s += path(left, stroke=GREEN, sw=17) + path(right, stroke=GREEN, sw=17)
    left_hand = (63,119) if pose == "guard" else ((62,143) if pose == "smoke" else (61,145))
    right_hand = {"shoot": (143,119), "power_shot": (144,137), "thrust": (145,135), "bell": (140,109), "guard": (141,111), "smoke": (140,114)}.get(pose, (139,145))
    s += circle(*left_hand, 8, SKIN) + circle(*right_hand, 8, SKIN)
    # Big soft face, side curls, a small smile and barely-there rosy cheeks.
    s += ellipse(59, 89, 8, 12, SKIN) + ellipse(142, 89, 8, 12, SKIN)
    s += path("M59 72Q58 36 99 37Q141 35 143 74L139 98H62Z", "#927453")
    s += path("M62 66Q100 46 139 67L140 88Q140 119 101 122Q63 121 61 91Z", SKIN)
    s += path("M64 65Q76 52 89 57L80 76 73 69 67 78Z", "#927453")
    s += path("M131 64 139 67 139 86 132 78Z", "#927453")
    s += ellipse(77, 103, 8, 4.5, CHEEK, opacity=".65") + ellipse(124, 103, 8, 4.5, CHEEK, opacity=".65")
    if pose == "guard":
        s += path("M79 93Q84 86 89 93M112 93Q117 86 122 93", stroke=INK, sw=3.5)
    else:
        s += ellipse(85, 93, 3.5, 4.5, INK) + ellipse(117, 93, 3.5, 4.5, INK)
        s += circle(84, 91.5, 1, "#fff7e7") + circle(116, 91.5, 1, "#fff7e7")
    s += path("M96 106Q101 112 106 106", stroke="#a87761", sw=2.5)
    # Soft, slightly lopsided straw hat + sprout pin are the repeatable identity.
    s += path("M59 58 64 33Q65 24 78 24H118Q131 24 134 36L140 60Z", "#dfc68f")
    s += path("M69 34Q88 24 118 30L126 52H65Z", HAT)
    s += path("M62 49Q101 56 136 49L139 62H59Z", "#bd9769")
    s += path("M43 56Q100 45 151 56Q160 60 154 70Q129 82 96 76Q62 81 43 72Q33 65 43 56Z", HAT)
    s += path("M47 70Q85 78 122 72Q141 71 153 66", stroke="#d1b785", sw=3)
    s += sprout(128, 48, .62)
    return s


def bell(x, y, scale=1):
    s = path("M0-29V25", stroke=WOOD, sw=6)
    s += circle(0, -28, 4, "#d2b56d")
    s += path("M-8-20Q-8-30 0-30Q8-30 8-20L12-7H-12Z", "#e1c87b")
    s += path("M-10-8H10", stroke="#b79452", sw=3) + circle(0,-3,3,WOOD)
    return group(s, f"translate({x} {y}) scale({scale})")


def prop(pose):
    if pose == "shoot":
        return path("M150 89Q181 120 151 151", stroke=WOOD, sw=5) + path("M150 89 155 120 151 151", stroke="#ecdfbf", sw=2) + path("M140 120H184M177 116 185 120 177 124", stroke="#be9166", sw=3)
    if pose == "power_shot":
        return path("M130 142 165 118M146 112 166 138", stroke=WOOD, sw=7) + path("M138 113Q175 109 177 146M138 113 177 146", stroke="#b99b71", sw=4) + path("M143 139 176 111", stroke="#d6b675", sw=3)
    if pose == "thrust":
        return path("M127 146 186 102", stroke=WOOD, sw=6) + poly("176,107 186,89 194,101 183,112", "#9baea7") + path("M180 108 187 96", stroke="#d9e0cd", sw=2) + path("M170 116 176 122", stroke=HAT, sw=3)
    if pose in ("bell", "guard"):
        return bell(146, 111)
    if pose == "smoke":
        return path("M145 140 157 96", stroke=WOOD, sw=7) + path("M149 98Q140 82 155 65Q153 79 165 78Q177 98 149 98Z", "#d9a176") + path("M151 92Q148 84 157 77Q166 91 158 96Z", "#f0d58f")
    return ""


POSES = {"forest_shoot": "shoot", "forest_thrust": "thrust", "forest_power_shot": "power_shot", "forest_bell_strike": "bell", "forest_guard_bell": "guard", "forest_smoke_screen": "smoke"}


def card(pose):
    s = rect(0, 0, 320, 200, "#e9e4d4", 15)
    s += ellipse(159, 111, 112, 79, "#d9dfc7")
    s += path("M27 171Q107 154 168 166Q242 151 299 173V200H24Z", "#d1d9be", opacity=".65")
    s += sprout(53, 165, .5) + sprout(275, 169, .4)
    if pose == "smoke":
        for x,y,r in [(221,56,19),(248,71,25),(230,96,20)]:
            s += circle(x,y,r,"#b8b9b6",opacity=".7")
    if pose == "guard":
        s += path("M213 83 235 93 231 119Q223 135 212 139Q195 133 191 119L188 93Z", "#a7c4c3")
        s += path("M211 95V121M200 107H222", stroke="#e8edd9", sw=4)
        s += path("M65 71V83M59 77H71M248 44V58M241 51H255", stroke="#d9b974", sw=3)
    if pose in ("shoot", "power_shot", "thrust"):
        s += path("M207 62Q242 46 277 59M223 76Q255 68 282 77", stroke="#b6c4a9", sw=3)
    s += ellipse(153, 181, 55, 7, "#5b7057", opacity=".16")
    s += group(hero(pose) + prop(pose), "translate(50 0) scale(.96)")
    if pose == "bell":
        s += path("M220 64Q235 71 228 86M234 57Q255 70 245 92", stroke="#ceb276", sw=3)
    return s


def write(folder, name, body, width, height):
    folder.mkdir(parents=True, exist_ok=True)
    source = f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">{body}</svg>\n'
    (folder / (name + ".svg")).write_text(source, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    write(HERO, "farmer_cute", hero(), 200, 200)
    for key, pose in POSES.items():
        write(CARDS, key, card(pose), 320, 200)
    print("CUTE_FOREST_HERO: 1 hero + 6 action card SVGs")
