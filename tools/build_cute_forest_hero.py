"""Rebuild the rounded farmer and six character-led card illustrations (native SVG)."""
from pathlib import Path
from math import cos, sin, pi
from build_forest_art import rect, path, poly, circle, ellipse, group

ROOT = Path(__file__).resolve().parents[1]
HERO = ROOT / "assets/characters"
CARDS = ROOT / "assets/art_studies/cute_adventurer_v03"
SKIN, CHEEK, INK = "#efd1b9", "#dba39b", "#47463c"
GREEN, DARK_GREEN, HAT, WOOD = "#9cac7e", "#758b66", "#eddaa5", "#a27c59"
HAIR, HAIR_LIGHT, RIBBON, BLOUSE = "#443932", "#69564a", "#c59aa5", "#f0e7d5"


def sprout(x, y, scale=1):
    return group(path("M0 7V-7", stroke=DARK_GREEN, sw=3) + path("M0-2Q-19-1-14-13Q-2-16 0-2M1-4Q0-19 14-17Q19-5 1-4", GREEN), f"translate({x} {y}) scale({scale})")


def star(x, y, radius, color):
    points = []
    for i in range(10):
        angle = -pi / 2 + i * pi / 5
        r = radius if i % 2 == 0 else radius * .46
        points.append(f"{x + cos(angle)*r:.2f},{y + sin(angle)*r:.2f}")
    return poly(" ".join(points), color)


def gingham_hat():
    cap = "M53 64Q48 41 65 27Q94 14 126 28Q146 40 146 65Z"
    brim = "M36 58Q67 70 94 63Q128 52 157 61Q173 65 161 81Q144 94 123 82Q100 77 82 86Q53 95 34 80Q22 65 36 58Z"
    s = '<defs><clipPath id="gingham_clip">' + path(cap, "#fff") + path(brim, "#fff") + '</clipPath></defs>'
    checks = rect(22, 15, 151, 82, "#f0e8cc")
    for row in range(7):
        for col in range(13):
            color = "#c96165" if row % 2 == 0 and col % 2 == 0 else ("#dfa3a0" if row % 2 == 0 or col % 2 == 0 else "#f0e8cc")
            checks += rect(22 + col * 12, 15 + row * 12, 12, 12, color)
    s += group(checks, clip_path="url(#gingham_clip)")
    s += path("M36 58Q67 70 94 63Q128 52 157 61", stroke="#b7736e", sw=2)
    s += path("M132 48Q119 39 121 51Q123 58 133 53Q146 62 149 51Q151 40 135 48Z", "#3d4247")
    s += path("M134 53Q137 64 149 64L146 69Q134 66 130 55", "#3d4247")
    s += path("M53 83Q54 120 66 145M144 84Q148 125 135 153", stroke="#f0e8cc", sw=3)
    s += path("M54 100 56 108M60 123 62 131M145 101 145 109M142 133 139 141", stroke="#c96165", sw=3)
    return s


def hero(pose="idle", appearance="gingham"):
    """Photo-inspired geometric heroine. Boots/pivots still match the original 200-unit rig."""
    # Shoulder-length dark hair with loose curled ends, rather than tied braids.
    s = path("M55 82Q51 48 72 38Q101 23 128 39Q148 48 148 81L145 112Q144 126 151 137Q146 155 132 150L123 133H78Q65 155 52 143Q61 128 55 112Z", HAIR)
    s += path("M58 107Q67 120 61 133Q58 140 64 141M140 108Q132 122 141 136Q145 141 138 145", stroke=HAIR_LIGHT, sw=4)
    if appearance == "gingham":
        s += path("M57 104Q48 117 54 133Q43 150 55 160Q66 167 78 153L76 127ZM141 101Q154 116 147 134Q162 152 146 163Q132 169 125 152L128 125Z", HAIR)
        s += path("M57 128Q64 139 56 150Q57 156 65 155M141 127Q134 137 143 147Q151 152 143 158", stroke=HAIR_LIGHT, sw=4)
    s += rect(61, 122, 31, 39, WOOD, 10)  # Little travelling satchel.
    s += rect(77, 157, 18, 28, BLOUSE, 8) + rect(107, 157, 18, 28, BLOUSE, 8)
    s += rect(71, 169, 27, 19, WOOD, 8) + rect(104, 169, 27, 19, WOOD, 8)
    s += path("M80 173H91M113 173H124", stroke="#c5a77d", sw=3)
    s += path("M79 117Q101 110 123 117L135 158Q139 169 132 173Q100 179 67 173Q61 169 66 158Z", GREEN)
    s += path("M119 127 126 164Q100 171 68 165L67 173Q100 179 132 173Q139 169 135 158L123 117Z", DARK_GREEN, opacity=".26")
    # Cream cardigan, modest sage inner dress, and a tiny gold pendant from the reference.
    s += path("M79 117Q86 112 94 117L100 130 94 156Q85 162 69 156L74 127Z", BLOUSE)
    s += path("M106 117Q116 112 123 118L130 129 133 156Q119 162 105 156L100 130Z", BLOUSE)
    s += path("M92 120 99 130 106 121M102 134V155", stroke="#d9ceb8", sw=2)
    s += path("M89 120Q93 134 101 136Q110 131 114 120", stroke="#c5a76f", sw=1.5)
    s += ellipse(101, 137, 2.6, 3.6, "#d1ae68")
    s += circle(108, 145, 1.6, "#c4bba6") + circle(108, 152, 1.6, "#c4bba6")
    s += rect(78, 145, 12, 9, "#e4dbc7", 3)
    s += sprout(99, 166, .25)
    if appearance == "gingham":
        # Grey-blue polo and dark collar/cuffs echo the second reference.
        s += path("M78 118Q99 110 124 118L133 154Q139 170 126 172H76Q63 171 67 156Z", "#aebfc4")
        s += path("M86 117 98 126 92 134 82 121ZM114 117 102 126 108 135 122 121Z", "#43525a")
        s += path("M99 127V153", stroke="#8b9fa6", sw=2)
        s += circle(103, 139, 1.6, BLOUSE) + circle(103, 149, 1.6, BLOUSE)
        s += path("M79 123 115 162", stroke="#e5e6d1", sw=7)
        s += path("M80 124 84 128M88 132 92 136M96 140 100 144M104 148 108 152M112 156 115 160", stroke="#718ca0", sw=4)
    # Stubby sleeves and mitten hands. Each card has an actual small gesture.
    left = {"guard": "M76 129 63 119", "smoke": "M76 130 62 143"}.get(pose, "M76 129 61 145")
    right = {"shoot": "M125 130 143 119", "power_shot": "M124 130 144 137", "thrust": "M125 131 145 135", "bell": "M124 128 140 109", "guard": "M125 129 141 111", "smoke": "M124 128 140 114"}.get(pose, "M124 129 139 145")
    sleeve = "#aebfc4" if appearance == "gingham" else BLOUSE
    s += path(left, stroke=sleeve, sw=17) + path(right, stroke=sleeve, sw=17)
    left_hand = (63,119) if pose == "guard" else ((62,143) if pose == "smoke" else (61,145))
    right_hand = {"shoot": (143,119), "power_shot": (144,137), "thrust": (145,135), "bell": (140,109), "guard": (141,111), "smoke": (140,114)}.get(pose, (139,145))
    s += circle(*left_hand, 8, SKIN) + circle(*right_hand, 8, SKIN)
    # Rounded cheeks and open eyes; spaced fine bangs are kept separate from the brows.
    s += ellipse(59, 89, 8, 12, SKIN) + ellipse(142, 89, 8, 12, SKIN)
    s += path("M61 67Q100 42 139 67L140 88Q140 119 101 123Q63 121 61 91Z", SKIN)
    s += path("M59 76Q55 48 79 40Q108 28 131 45Q144 56 142 78L134 73Q123 58 111 58Q101 53 93 58Q75 58 67 79Z", HAIR)
    s += path("M87 49Q82 69 78 81M97 49Q91 69 94 81M104 49Q102 66 103 78M111 51Q117 68 114 80M123 55Q125 72 130 82", stroke=HAIR, sw=4)
    s += path("M62 74Q69 69 69 83V103Q69 116 61 121Q56 111 60 100Z", HAIR)
    s += path("M135 72Q143 75 142 91L140 108Q135 119 129 118Q136 101 131 88Z", HAIR)
    s += path("M73 52Q82 43 94 44M115 46Q127 50 132 61", stroke=HAIR_LIGHT, sw=3)
    s += ellipse(77, 105, 8, 4, CHEEK, opacity=".55") + ellipse(124, 105, 8, 4, CHEEK, opacity=".55")
    s += path("M79 85Q85 83 91 85M111 85Q117 83 123 85", stroke="#6c5549", sw=2)
    if pose == "guard":
        s += path("M79 93Q84 86 89 93M112 93Q117 86 122 93", stroke=INK, sw=3.5)
    else:
        s += ellipse(85, 94, 4.8, 5.6, "#fff8e9") + ellipse(117, 94, 4.8, 5.6, "#fff8e9")
        s += ellipse(85, 94.3, 3.4, 4.5, "#776249") + ellipse(117, 94.3, 3.4, 4.5, "#776249")
        s += ellipse(85, 94.6, 1.9, 3, INK) + ellipse(117, 94.6, 1.9, 3, INK)
        s += circle(84, 92, 1.2, "#fffaf0") + circle(116, 92, 1.2, "#fffaf0")
    s += path("M92 109Q101 114 110 109", stroke="#ac786f", sw=2.5)
    # The photo's pastel star headwear becomes a small adventure-friendly star circlet.
    if appearance == "star":
        s += path("M59 56Q99 21 142 53", stroke="#b49ba9", sw=5)
        s += star(67, 45, 10, "#d6a4b4") + star(98, 31, 12, "#eee4c9") + star(130, 42, 10, "#c7b6d5")
        s += star(83, 35, 5, "#d4c6dd") + star(115, 35, 5, "#e3b6bd")
    else:
        s += group(gingham_hat(), "translate(0 -8)")
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


def card(pose, appearance="gingham"):
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
    s += group(hero(pose, appearance) + prop(pose), "translate(50 0) scale(.96)")
    if pose == "bell":
        s += path("M220 64Q235 71 228 86M234 57Q255 70 245 92", stroke="#ceb276", sw=3)
    return s


def write(folder, name, body, width, height, raster_scale=1):
    folder.mkdir(parents=True, exist_ok=True)
    source = f'<svg xmlns="http://www.w3.org/2000/svg" width="{width*raster_scale}" height="{height*raster_scale}" viewBox="0 0 {width} {height}">{body}</svg>\n'
    (folder / (name + ".svg")).write_text(source, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    write(HERO, "farmer_cute", hero(), 200, 200, raster_scale=2)
    write(HERO, "farmer_star", hero(appearance="star"), 200, 200, raster_scale=2)
    for key, pose in POSES.items():
        write(CARDS, key, card(pose), 320, 200)
        write(CARDS / "star", key, card(pose, "star"), 320, 200)
    print("CUTE_FOREST_HERO: 2 looks, each with 1 hero + 6 action card SVGs")
