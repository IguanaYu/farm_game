"""Rebuild the chapter's flat vector artwork. Standard library only; no raster inputs.

Artwork follows ExpeditionArt's 200-unit silhouettes and ExpeditionUI's palette.
Run from any directory: python tools/build_forest_art.py
"""
from pathlib import Path
import hashlib
import html
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/chapter_one"
INK, PAPER = "#302735", "#f1eadf"
SAGE, GOLD, WOOD, COPPER = "#b1c5a0", "#d8b866", "#927453", "#df947a"
STONE, BLUE, PURPLE = "#82858c", "#7999b0", "#a493b5"
SOURCE = (ROOT / "scripts/domain/chapter_one_defs.gd").read_text(encoding="utf-8")


def records(name):
    body = SOURCE.split(f"const {name} := {{", 1)[1].split("\n}", 1)[0]
    result = {}
    for key, fields in re.findall(r'"([a-zA-Z0-9_]+)": \{([^{}]+)\}', body):
        result[key] = dict(re.findall(r'"(\w+)": "([^"]+)"', fields))
    return result


def poly(points, fill, **attrs):
    return tag("polygon", points=points, fill=fill, **attrs)


def tag(element, **attrs):
    attrs = " ".join(f'{k.replace("_", "-")}="{html.escape(str(v), quote=True)}"' for k, v in attrs.items())
    return f"<{element} {attrs}/>"


def rect(x, y, w, h, fill, r=0, **kw):
    return tag("rect", x=x, y=y, width=w, height=h, rx=r, fill=fill, **kw)


def circle(x, y, radius, fill, **kw):
    return tag("circle", cx=x, cy=y, r=radius, fill=fill, **kw)


def ellipse(x, y, rx, ry, fill, **kw):
    return tag("ellipse", cx=x, cy=y, rx=rx, ry=ry, fill=fill, **kw)


def path(d, fill="none", stroke=None, sw=3, **kw):
    if stroke:
        kw.update(stroke=stroke, stroke_width=sw, stroke_linecap="round", stroke_linejoin="round")
    return tag("path", d=d, fill=fill, **kw)


def group(body, transform="", **kw):
    attrs = " ".join(f'{k.replace("_", "-")}="{v}"' for k, v in kw.items())
    return f'<g transform="{transform}" {attrs}>{body}</g>'


def eyes(x=100, y=69, gap=10, color=INK):
    return circle(x-gap, y, 3, color) + circle(x+gap, y, 3, color)


def shadow():
    return ellipse(100, 179, 65, 9, INK, opacity=".16")


def leaf(x, y, color=SAGE, scale=1):
    return group(path("M0 0 Q-25-30-13-43 Q13-35 0 0", color) + path("M0 0 Q25-22 29-37 Q7-34 0 0", color), f"translate({x} {y}) scale({scale})")


def mushroom(x, y, color=BLUE, scale=1):
    return group(rect(-4, -20, 8, 23, PAPER, 3) + path("M-23-18 Q-22-51 0-49 Q22-49 23-18Z", color) + circle(-10,-28,3,PAPER)+circle(9,-36,4,PAPER), f"translate({x} {y}) scale({scale})")


def bell(x=100, y=83, scale=1):
    return group(path("M-20 12-15-11Q-15-30 0-30Q15-30 15-11L20 12Z", GOLD) + rect(-23,10,46,6,COPPER,3)+circle(0,22,5,GOLD)+circle(0,-35,6,WOOD), f"translate({x} {y}) scale({scale})")


def bow():
    return path("M134 40Q190 100 134 160", stroke=WOOD, sw=9)+path("M134 40 150 100 134 160", stroke=PAPER, sw=2)+path("M110 100H178M167 94 179 100 167 106", stroke=COPPER, sw=4)


def shield():
    return poly("35,91 65,80 94,91 90,133 65,158 39,133", BLUE)+poly("65,87 86,96 82,129 65,146", "#9bb1bb")+path("M65 96V137M46 113H83", stroke=INK, sw=4)


def sword():
    return poly("138,119 157,40 168,31 173,48 151,124", COPPER)+poly("157,40 168,31 151,124 145,121", "#efba93")+path("M132 120 157 127M143 126 136 149", stroke=WOOD, sw=7)


def humanoid(kind):
    goblin = "goblin" in kind
    skin = "#94aa79" if goblin else "#dfc4a0"
    robe = "priest" in kind or "wrapped" in kind or "walker" in kind
    body = PURPLE if "priest" in kind else "#75866a" if goblin else "#9d7461"
    if "wrapped" in kind:
        body, skin = "#b8b49e", "#cec7ad"
    if "walker" in kind:
        body, skin = "#6d8070", "#a8b29a"
    s = shadow()
    if "root_coffin" in kind:
        s += poly("40,159 40,48 56,22 121,22 140,48 140,160", "#655e64")
        s += path("M39 174Q15 116 49 59M133 172Q166 115 129 55M39 153 22 146M140 143 161 136", stroke=WOOD, sw=10)
    s += path("M79 141 73 173M117 141 126 173", stroke=WOOD, sw=16)
    s += poly("73,87 121,87 137,146 60,146", body)
    s += poly("100,89 121,89 137,146 100,146", "#302735", opacity=".12")
    s += path("M74 100 55 127M121 100 140 124", stroke=skin, sw=12)
    if goblin:
        s += poly("77,54 48,43 64,72 84,74 119,54 149,43 133,72 114,74",skin)
    s += circle(98,63,28,skin)
    s += eyes(98,65)
    s += path("M90 78H105", stroke=INK, sw=3)
    s += rect(65,134,68,8,WOOD)+rect(92,131,13,14,GOLD,2)
    if "archer" in kind:
        s += rect(55,70,17,59,WOOD,3)+path("M58 73 50 40M65 70 61 34",stroke=PAPER,sw=3)+poly("74,41 83,24 113,29 124,46", "#697f60")+bow()
    elif "shield" in kind:
        s += sword()+shield()
    elif "spearman" in kind:
        s += path("M151 174V40",stroke=WOOD,sw=7)+poly("140,46 152,13 164,46 153,57",STONE)+path("M146 56H158M146 62H158",stroke=PAPER,sw=3)
    elif "herbalist" in kind:
        s += rect(40,82,30,48,WOOD,6)+leaf(53,93,SAGE,.7)+leaf(62,92,"#899b75",.5)+ellipse(144,127,17,20,SAGE)+circle(139,119,4,"#d1dfb8")
    elif "crossbow" in kind:
        s += path("M120 150 151 90",stroke=WOOD,sw=12)+path("M116 95Q150 75 178 108M116 95 150 111 178 108",stroke=PAPER,sw=4)
    elif "trapper" in kind:
        s += ellipse(145,126,25,34,WOOD)+path("M124 109 162 146M121 124 153 154M134 98 168 132M126 144 161 105M135 156 170 119",stroke=PAPER,sw=2)
    elif "axeman" in kind or "captain" in kind:
        s += path("M139 163 153 48",stroke=WOOD,sw=9)+poly("151,51 181,50 185,76 151,83",STONE)+poly("181,50 185,76 175,78 172,52",PAPER)
        if "captain" in kind:
            s += poly("63,45 77,24 126,28 137,48",INK)+poly("113,33 139,14 134,40",COPPER)+poly("73,92 87,90 91,126 61,126", "#715b43")+bell(47,137,.48)
    elif "priest" in kind:
        s += poly("68,54 98,22 127,54 113,50 98,37 81,55",body)+path("M151 167V57",stroke=WOOD,sw=7)+bell(151,66,.65)
        s += poly("87,99 108,99 116,145 79,145",GOLD)+circle(98,112,5,PAPER)
        if "root_coffin" in kind:
            s += path("M72 37 53 18M121 37 137 15M58 22 46 24M133 23 149 25",stroke=WOOD,sw=7)
    elif "wrapped" in kind:
        for y in [45,55,79,96,110,124]:
            s += path(f"M75 {y} 122 {y+5}",stroke=PAPER,sw=4)
        s += rect(80,60,40,13,INK,3)+eyes(100,67,10,GOLD)+shield()
    elif "walker" in kind:
        s += mushroom(77,45,PURPLE,.65)+mushroom(122,64,SAGE,.8)+mushroom(137,129,BLUE,.48)
    return s


def enemy_art(key):
    k = key.removeprefix("forest_")
    if any(t in k for t in ["goblin", "bandit", "priest", "wrapped", "walker"]):
        return humanoid(k)
    s = shadow()
    if "slime" in k:
        c, light = ("#899b75", "#c0d4a3") if "green" in k else ("#be7965", "#e4ac81") if "red" in k else ("#7999b0", "#b3d4db")
        s += path("M35 155Q28 116 57 99Q65 49 105 62Q136 57 149 104Q174 118 163 156Q100 184 35 155",c)
        s += path("M45 135Q42 111 67 108Q76 72 103 75",stroke=light,sw=10)+eyes(104,132,16)
        if "green" in k:
            s += leaf(104,80,SAGE,.7)
        elif "red" in k:
            s += path("M99 110Q72 94 96 64L100 79 112 60Q136 99 111 110Z", GOLD)
        else:
            s += path("M105 69V108M90 78 120 99M120 78 90 99M100 74 105 81 111 74M100 104 105 97 111 104",stroke=PAPER,sw=3)
    elif "wolf" in k:
        c = "#8c8e94" if "alpha" in k else "#8b8c7c"
        s += poly("38,133 20,102 50,115 79,94 126,101 153,81 173,109 164,137 142,145 127,170 114,168 118,139 81,138 68,171 54,171 58,134",c)
        s += poly("132,88 128,52 148,66 163,55 173,89 185,112 165,123 143,112",c)
        s += poly("145,87 157,105 181,108 170,119 153,112", "#c6c4ad")+circle(157,86,3,INK)+circle(181,109,4,INK)
        if "alpha" in k:
            s += poly("85,100 104,74 116,92 127,77 133,113 118,143 105,130 98,146 86,124", "#c1c0ad")+path("M146 79 151 88",stroke=COPPER,sw=3)
    elif "bat" in k:
        s += poly("85,87 31,49 16,113 39,103 53,135 70,111 89,128",PURPLE)+poly("115,87 169,49 184,113 161,103 147,135 130,111 111,128",PURPLE)
        s += path("M31 49 53 116 85 96M169 49 147 116 115 96",stroke="#776781",sw=4)+ellipse(100,113,25,38,"#655b72")+poly("76,94 78,60 95,78 108,78 122,60 126,94", "#8d7c9f")+eyes(100,95,10,PAPER)
    elif "spider" in k:
        for side in [-1,1]:
            for i in range(4):
                x1,y1,x2,y2=100+side*25,90+i*10,100+side*(55+i*5),63+i*26
                s += path(f"M{x1} {y1} {x2} {y2} {x2+side*17} {y2+24}",stroke=WOOD,sw=7)
        s += ellipse(100,94,35,39,"#7e8969")+circle(100,132,24,"#9ba27c")+eyes(100,132,8)+leaf(100,85,SAGE,.5)
    elif "wisp" in k:
        s += circle(100,98,65,PURPLE,opacity=".08")+path("M65 131Q47 110 65 83L82 59 100 37 120 66Q155 88 134 124L145 142 114 137 97 155 86 135Z", "#a493b5")+bell(100,101,.8)+eyes(100,87,11,PAPER)
    elif "guard" in k or "keeper" in k:
        s += path("M76 144 68 172M123 144 135 172",stroke=WOOD,sw=20)
        s += poly("63,77 132,77 145,145 55,145",WOOD)+poly("75,83 120,83 131,133 63,133","#78866c")
        s += path("M62 88 42 122M137 88 157 123",stroke=WOOD,sw=22)+rect(72,34,53,48,"#a7b08b",8)+eyes(99,58,11)
        for y in [94,112,130]:
            s += path(f"M68 {y}H128",stroke="#bba477",sw=4)
        if "keeper" in k:
            s += bell(100,59,1.05)+rect(151,82,17,91,STONE,4)+poly("138,89 159,64 181,89",STONE)+path("M143 92H176",stroke=PAPER,sw=5)
        else:
            s += path("M145 169V58",stroke=WOOD,sw=9)+poly("135,53 157,53 168,76 123,76",STONE)
    elif "matriarch" in k:
        s += path("M38 162Q29 106 59 89L132 87Q174 100 167 161Z","#7c9389")
        for x,y,c,scale in [(64,105,BLUE,1),(124,90,PURPLE,1.2),(98,77,SAGE,1.2),(146,120,BLUE,.7)]:
            s += mushroom(x,y,c,scale)
        s += eyes(103,135,16,PAPER)+path("M52 148Q99 173 156 148",stroke=SAGE,sw=5)
        for x,y in [(29,75),(173,99),(46,47),(156,52)]:
            s += circle(x,y,4,SAGE,opacity=".7")
    else:
        raise ValueError(f"Missing enemy {key}")
    return s


def chest(lock=False, color=WOOD):
    return poly("39,73 144,73 163,91 163,158 39,158",color)+poly("39,73 58,55 145,55 163,73 144,90 39,90", "#b99a72")+poly("144,90 163,73 163,158 144,158", "#725c4b")+path("M40 99H144M59 78V155M126 78V155",stroke=GOLD,sw=5)+(rect(83,91,22,25,GOLD,3)+circle(94,100,4,INK) if lock else path("M72 120H116",stroke="#bba477",sw=3))


def item_art(key):
    k=key.removeprefix("forest_")
    s=shadow()
    if k == "bone_dagger":
        return s+poly("74,123 112,55 130,38 135,69 91,135",PAPER)+poly("112,55 130,38 91,135 84,129","#c9c3a8")+path("M66 121 97 141M80 134 65 157",stroke=WOOD,sw=9)+path("M68 147 79 153",stroke=SAGE,sw=4)
    if k == "copper_shortsword":
        return s+group(sword(), "translate(-35 5) scale(1.15)")
    if k in ["goblin_bow", "hunting_crossbow"]:
        s += group(bow(), "translate(-45 0)")
        if "crossbow" in k:
            s += path("M65 158 117 74",stroke=WOOD,sw=14)+path("M54 101 136 123",stroke=STONE,sw=7)
    elif k=="reinforced_shield":
        s += group(shield(), "translate(-5 -25) scale(1.4)")
    elif k=="logging_axe":
        s += path("M65 162 116 46",stroke=WOOD,sw=14)+poly("103,51 155,52 166,91 113,100",STONE)+poly("150,52 166,91 151,94 139,51",PAPER)
    elif k=="resin_armor":
        s += poly("69,42 52,72 26,91 48,115 65,98 57,163 142,163 135,98 152,115 176,91 145,72 130,42 116,62 85,62", "#a79261")+poly("99,65 127,54 130,84 121,151 101,151", GOLD)+path("M70 104H130M68 126H128",stroke=WOOD,sw=5)
    elif k=="bat_mantle":
        s += poly("74,45 126,45 169,159 138,143 116,169 100,145 80,169 59,145 28,161",PURPLE)+poly("100,63 126,45 169,159 138,143 116,169 100,145", "#7b6b8b")+circle(100,64,9,GOLD)
    elif k in ["ritual_bellstaff","runic_wand"]:
        s += path("M72 170 116 43",stroke=WOOD,sw=10)
        s += bell(119,55,.9) if "bell" in k else poly("100,49 122,21 142,48 118,75",PURPLE)+path("M97 91 115 97M91 109 109 115",stroke=GOLD,sw=4)
    elif k=="feather_charm":
        s += path("M79 37Q145 52 123 109L72 152Q42 106 79 37Z",PAPER)+path("M72 152 101 65M76 130 109 120M82 110 115 99M88 90 117 79",stroke=WOOD,sw=3)+circle(74,157,12,GOLD)
    elif k=="hunting_horn":
        s += path("M54 51Q85 153 144 140L159 112Q92 141 76 44Z",GOLD)+ellipse(66,48,17,11,PAPER)+path("M144 140 159 112",stroke=WOOD,sw=7)
    elif "gel" in k or k in ["resin_chunk", "rot_spore_sac", "sting_sac"]:
        c = SAGE if k=="green_gel" else BLUE if "frost" in k else COPPER if "fire" in k else GOLD if "resin" in k or "sting" in k else PURPLE
        s += path("M71 53 126 53 126 78Q174 132 143 158Q99 178 58 154Q30 127 72 78Z",c)+path("M64 126Q58 104 82 88",stroke=PAPER,sw=6)+rect(68,49,62,11,WOOD,4)
        if "fire" in k:
            s += path("M93 148Q70 125 94 101L99 113 112 96Q135 131 111 148Z",GOLD)
        elif "frost" in k:
            s += path("M100 98V146M80 110 120 135M120 110 80 135",stroke=PAPER,sw=4)
        elif "rot" in k:
            s += mushroom(101,146,SAGE,.6)
        elif "sting" in k:
            s += path("M85 112 116 148M91 104 122 140M77 120 108 156",stroke=INK,sw=3)
        elif k=="green_gel":
            s += leaf(104,144,"#71885e",.65)
    elif k=="honey_chunk":
        s += poly("40,91 66,54 135,50 163,89 143,151 59,159",GOLD)
        for x,y in [(76,85),(119,81),(98,120),(140,117),(57,119)]:
            s += poly(f"{x-14},{y} {x-7},{y-12} {x+7},{y-12} {x+14},{y} {x+7},{y+12} {x-7},{y+12}","#b28a4e")
    elif k=="healing_moss":
        s += ellipse(101,145,64,20,"#71885e")+leaf(75,147,SAGE,1.1)+leaf(118,142,"#99b686",1.2)+path("M82 121H118M100 104V139",stroke=PAPER,sw=7)
    elif k=="resin_torch":
        s += path("M78 173 114 75",stroke=WOOD,sw=15)+path("M93 91 116 99M96 80 119 88",stroke=GOLD,sw=9)+path("M114 81Q80 66 111 22L116 42 134 30Q156 67 128 86Z",COPPER)+path("M116 79Q101 62 124 46L130 67Z",GOLD)
    elif k=="old_lantern":
        s += path("M73 69V47Q100 11 128 47V69",stroke=WOOD,sw=7)+rect(57,67,87,94,WOOD,8)+rect(67,78,67,69,GOLD,5)+path("M100 81V146M67 112H132",stroke=WOOD,sw=5)+rect(53,155,95,11,STONE,4)
    elif k=="rope_net":
        s += ellipse(101,117,60,49,WOOD)
        for n in range(6):
            x=45+n*19
            s += path(f"M{x} 83 {min(159,x+40)} 150M{x} 151 {min(159,x+40)} 83",stroke=PAPER,sw=2)
        s += path("M57 85Q100 28 146 84",stroke=WOOD,sw=7)
    elif k in ["silverleaf_seed", "glowcap_spawn"]:
        s += path("M64 66 135 66 151 160 48 160Z",WOOD)+rect(61,58,77,14,"#bba477",4)+rect(68,90,63,55,PAPER,7)
        s += leaf(100,139,SAGE,.8) if "silver" in k else mushroom(100,141,BLUE,.75)
    elif k=="clean_linen":
        s += poly("48,61 148,61 159,142 58,157 38,129",PAPER)+poly("48,61 76,71 82,143 58,157 38,129","#c6c0ad")+path("M72 84 141 77M77 103 145 96M80 124 148 117",stroke="#b0ad9f",sw=3)
    elif k=="copper_scrap":
        s += poly("37,89 74,61 122,74 112,122 59,136",COPPER)+poly("103,102 152,76 172,121 139,160 93,145","#b58165")+path("M67 82 94 90M119 121 145 108",stroke=GOLD,sw=5)
    elif k=="hide_roll":
        s += path("M51 65 128 49 157 71 159 144 80 165 50 143Z",WOOD)+ellipse(71,88,27,33,"#bba477")+ellipse(71,88,13,17,WOOD)+path("M115 68 129 149",stroke=PAPER,sw=8)
    elif k=="antique_silver":
        s += path("M54 58H146L135 112Q126 132 106 134V150H135V163H65V150H94V134Q70 130 64 111Z","#b8c0bd")+path("M58 73Q19 64 38 105L68 113M141 73Q182 64 163 105L134 113",stroke="#b8c0bd",sw=8)+path("M76 75H125",stroke=PAPER,sw=5)
    elif k=="glow_crystal":
        s += poly("51,136 64,58 98,27 132,58 152,131 100,172",PURPLE)+poly("98,27 101,135 64,58","#d5c7df")+poly("101,135 152,131 100,172","#857493")
    elif k=="prayer_carving":
        s += poly("65,166 70,79 87,46 113,46 132,79 140,166",WOOD)+circle(100,63,23,"#bba477")+eyes(100,63,8)+path("M82 110 100 127 120 108M100 127V151",stroke=GOLD,sw=5)
    elif k=="warden_badge":
        s += poly("65,33 100,46 136,33 120,90 78,90",COPPER)+circle(100,122,43,GOLD)+circle(100,122,32,"#75866a")+leaf(100,143,SAGE,.65)
    elif k=="bell_ring":
        s += path("M72 56A53 53 0 1 1 49 109",stroke=GOLD,sw=17)+poly("59,49 79,53 72,74",COPPER)+path("M116 60Q148 71 145 104",stroke=PAPER,sw=4)
    elif k=="bat_wing":
        s += poly("40,149 37,55 88,77 157,49 165,144 136,125 113,153 92,126 65,143",PURPLE)+path("M37 55 92 126 157 49M88 77 113 153",stroke="#6c5e77",sw=5)
    elif k=="fiber_clump":
        for n in range(5):
            s += path(f"M{55+n*16} 64Q{115+n*5} 110 {57+n*16} 153",stroke=PAPER,sw=9)
        s += path("M52 98 143 118",stroke=WOOD,sw=9)
    elif k=="salvaged_spear":
        s += path("M56 172 126 49",stroke=WOOD,sw=10)+poly("111,55 145,20 145,61 125,75",STONE)+path("M112 76 130 86M108 85 126 95",stroke=PAPER,sw=5)
    else:
        raise ValueError(f"Missing item {key}")
    return s


def prop_art(key):
    s=shadow()
    if "hollow_log" in key or "stump" in key or "fallen_hive" in key:
        s += poly("35,95 146,76 168,95 156,150 51,165",WOOD)+ellipse(51,129,26,37,"#bba477")+ellipse(51,129,16,25,"#514b45")+path("M82 102 132 93M89 147 146 137",stroke="#bba477",sw=4)+leaf(112,102,SAGE,.6)
        if "stump" in key:
            s += rect(72,64,66,67,WOOD,7)+ellipse(105,64,33,12,"#bba477")+path("M87 62H120",stroke=WOOD,sw=3)
        if "fallen_hive" in key:
            s += group(prop_art("trail_beehive").replace(shadow(),""),"translate(62 62) scale(.52)")
        if "stash" in key:
            s += group(chest(True),"translate(72 78) scale(.5)")
    elif "bird_nest" in key:
        s += ellipse(100,134,64,29,WOOD)
        for y in [124,136,148]:
            s += path(f"M47 {y}Q99 {y+21} 152 {y}",stroke="#bba477",sw=5)
        s += ellipse(80,114,12,18,PAPER)+ellipse(105,109,13,19,"#b9c9c2")+ellipse(127,118,11,16,PAPER)
    elif "beehive" in key:
        s += path("M100 25V48",stroke=WOOD,sw=8)
        for y,rx in [(64,28),(79,39),(95,46),(111,46),(127,38),(140,26)]:
            s += ellipse(100,y,rx,12,GOLD if y%2 else "#b89a5d")
        s += ellipse(118,111,10,12,WOOD)+ellipse(154,85,10,5,GOLD)+path("M149 81 149 89M157 81 157 89",stroke=INK,sw=2)
    elif "remains" in key:
        s += circle(87,96,26,PAPER)+eyes(87,95,10)+path("M87 123 116 151M109 130 82 153M117 146 145 134",stroke=PAPER,sw=8)+poly("111,80 135,56 157,99 134,110",WOOD)
    elif "camp" in key and "hunter" in key:
        s += poly("29,143 80,49 130,143",SAGE)+poly("80,49 153,142 130,143", "#718064")+poly("67,142 83,92 105,142",INK)+path("M124 164 163 151M127 151 159 166",stroke=WOOD,sw=7)+path("M137 150 135 132 147 140 152 122 161 150",COPPER)
    elif "herb" in key and not "casket" in key:
        s += ellipse(100,155,65,15,"#667d63")
        for x,y,c in [(63,148,SAGE),(99,153,"#899b75"),(139,143,SAGE)]:
            s += leaf(x,y,c,1)
        if "roots" in key:
            s += path("M45 162 83 150M165 164 127 148",stroke=WOOD,sw=8)
    elif "sarcophagus" in key or "shrine" in key or "niche" in key:
        s += poly("56,165 50,54 77,29 126,29 151,54 145,165",STONE)+poly("61,151 62,60 82,42 122,42 138,60 134,151","#a5a79d")+path("M76 79H125M85 126H116M100 65V141",stroke="#697775",sw=5)
        if "priest" in key:
            s += bell(101,95,.5)+path("M49 154Q21 128 49 95M147 150Q174 115 144 80",stroke=WOOD,sw=7)
        if "shrine" in key:
            s += poly("32,58 100,14 169,58",STONE)+rect(79,74,43,57,INK,4)+circle(101,97,13,GOLD)
        if "ember" in key:
            s += path("M83 133Q64 112 87 86L96 101 111 77Q139 118 116 134Z",COPPER)
    elif "cistern" in key or "pool" in key or "gel_nest" in key:
        s += ellipse(100,134,73,33,STONE)+ellipse(100,126,63,25,BLUE if "cistern" in key else SAGE)+ellipse(102,123,36,12,"#a7c3bd",opacity=".6")+leaf(42,126,SAGE,.5)
        if "gel_nest" in key:
            s += circle(100,119,30,COPPER)+circle(88,111,7,"#e5b18b")
    elif "glowcap" in key:
        s += ellipse(100,165,67,11,"#657f73")+mushroom(65,158,BLUE,.9)+mushroom(111,151,SAGE,1.2)+mushroom(146,169,PURPLE,.7)
    elif "raft" in key:
        for n in range(5):
            s += group(rect(30,75+n*16,133,17,WOOD,8),"rotate(-12 100 120)")
        s += path("M65 72 88 159M122 62 145 144",stroke=PAPER,sw=5)+path("M44 39 147 170",stroke="#bba477",sw=7)+poly("31,28 55,24 76,57 62,65",WOOD)
    elif "web_bundle" in key:
        s += ellipse(101,115,43,53,"#b7c1b5")
        for n in range(5):
            s += path(f"M{70+n*14} 68Q{114+n*4} 109 {73+n*14} 161",stroke=PAPER,sw=3)
        s += path("M48 47 153 169M34 113 172 99M83 33 110 182",stroke=PAPER,sw=2)
    elif "bag" in key:
        s += path("M76 57 126 57 117 84Q163 126 148 161H51Q36 124 84 84Z",WOOD)+path("M74 83H126",stroke=PAPER,sw=7)+rect(82,115,37,29,"#bba477",5)
        if "fungal" in key:
            s += mushroom(133,137,BLUE,.7)+mushroom(70,100,SAGE,.5)
        elif "wolf" in key:
            s += path("M90 124 100 136 112 123",stroke=PAPER,sw=4)
    elif "rack" in key:
        s += path("M47 168V52M153 168V52M36 65H164",stroke=WOOD,sw=10)
        if "weapon" in key:
            s += group(item_art("forest_logging_axe").replace(shadow(),""),"translate(32 51) scale(.6)")+path("M125 150V56",stroke=PAPER,sw=5)
        else:
            s += poly("67,67 132,67 122,100 137,145 111,141 100,155 84,138 61,146 76,100", "#bba477")
    elif "book_cabinet" in key:
        s += rect(43,37,114,126,WOOD,5)+rect(51,45,98,107,INK,2)
        for x,c in [(59,SAGE),(81,COPPER),(105,BLUE),(125,PURPLE)]:
            s += rect(x,57,14,37,c,2)+rect(x,112,14,31,c,2)
        s += path("M49 101H151",stroke=WOOD,sw=7)
    else:
        s += chest(any(t in key for t in ["lock", "sealed", "captain", "caravan", "offering"]), STONE if "guard" in key else WOOD)
        if "root" in key:
            s += path("M38 154Q20 116 54 94M145 163Q173 122 148 87",stroke="#718064",sw=8)
        if "medicine" in key:
            s += path("M78 126H117M98 106V145",stroke=PAPER,sw=7)
        if "herb_casket" in key:
            s += leaf(100,138,SAGE,.6)
        if "bell" in key:
            s += bell(100,122,.5)
        if "lamp" in key:
            s += circle(100,127,16,GOLD)+path("M100 108V144",stroke=WOOD,sw=4)
        if "repair" in key:
            s += path("M81 142 111 109M101 108 118 125",stroke=PAPER,sw=6)
        if "sealed" in key:
            s += poly("98,103 113,123 98,143 83,123",PURPLE)
        if "caravan" in key:
            s += circle(100,130,17,COPPER)+path("M94 117 107 143M88 131H111",stroke=PAPER,sw=3)
    return s


def tree(x,y,scale=1,color="#586b59",conifer=False):
    canopy = poly("0,-180 -60,-92 -36,-97 -77,-42 -43,-51 -83,-2 80,-2 43,-52 73,-41 32,-100 58,-92",color) if conifer else circle(-35,-107,43,color)+circle(12,-145,56,color)+circle(53,-91,44,color)+circle(-7,-80,58,color)
    return group(rect(-9,-104,18,114,WOOD)+canopy, f"translate({x} {y}) scale({scale})")


def background_art(area):
    pal={"trail":("#aeb99d","#718367","#52664e","#bca783"),"temple":("#a4ada3","#7f9082","#5e7463","#969891"),"tower":("#a39bac","#7e788f","#5f5b74","#96909b"),"camp":("#bfad94","#8c8c72","#66735e","#a18b71"),"wetland":("#8faeaa","#668c85","#496e68","#6f9990")}[area]
    sky,far,mid,ground=pal
    s=rect(0,0,1280,640,sky)+circle(930,113,48,PAPER,opacity=".45")
    s+=poly("0,288 160,194 280,263 441,148 612,247 793,164 970,267 1130,153 1280,261 1280,550 0,550",far)
    for i,x in enumerate(range(0,1320,110)):
        s+=tree(x,367+(i%3)*16,1.1,mid,area=="tower")
    s+=poly("0,374 192,355 380,382 602,337 817,372 1070,350 1280,382 1280,640 0,640",ground)
    if area=="trail":
        s+=poly("521,356 650,356 1020,640 273,640 485,485 608,431", "#d2bc94")
        for i in range(7):
            x,y=530+i*23,405+i*23
            s+=poly(f"{x},{y} {x+59},{y-8} {x+76},{y+5} {x+13},{y+14}","#af9d80")
        s+=group(prop_art("trail_hollow_log"),"translate(76 327) scale(1.25)")
        s+=group(prop_art("trail_wagon_lockbox"),"translate(940 333) scale(1.05)")
        s+=path("M985 422V338H1133V427M989 364H1133",stroke=WOOD,sw=16)+circle(1010,433,33,WOOD)+circle(1130,433,33,WOOD)+circle(1010,433,18,ground)+circle(1130,433,18,ground)
    elif area=="temple":
        s+=poly("378,384 410,182 595,129 831,184 865,387",STONE)+poly("365,199 616,102 879,199", "#b7b6a7")+rect(545,226,146,173,"#4f5d58",60)
        for x in [418,767]:
            s+=rect(x,208,48,185,"#b7b6a7",4)+rect(x-9,203,67,20,PAPER,3)+rect(x-11,380,71,19,"#b7b6a7",3)
        s+=path("M426 387Q463 331 434 273M804 388Q757 329 793 261",stroke="#718064",sw=15)
        s+=poly("476,399 757,399 797,423 444,423", "#b7b6a7")+poly("445,426 797,426 829,452 413,452", "#a2a493")
        s+=group(prop_art("temple_side_sarcophagus"),"translate(99 337) scale(1.2)")+group(prop_art("temple_cistern"),"translate(948 380) scale(1.25)")
    elif area=="tower":
        s+=poly("536,395 551,128 578,71 699,71 727,131 742,395","#787582")+rect(567,171,143,159,"#a19aa5",5)
        s+=poly("510,146 630,38 765,146", "#625969")+poly("533,256 639,202 744,256", "#625969")
        s+=rect(595,165,80,66,"#4c485a",24)+bell(635,208,1.0)+rect(601,315,68,85,"#4c485a",30)
        s+=path("M556 388 590 344 570 305M703 291 682 274",stroke="#5d596d",sw=7)
        s+=group(prop_art("tower_book_cabinet"),"translate(150 348) scale(1.1)")+group(prop_art("tower_bell_cache"),"translate(937 375) scale(1.1)")
    elif area=="camp":
        s+=rect(390,263,448,155,WOOD,5)+poly("354,278 491,157 875,278", "#75634f")+rect(537,309,104,109,"#4b4942",3)
        for x in [419,459,701,748,796]:
            s+=path(f"M{x} 292V408",stroke="#b39774",sw=7)
        s+=path("M430 454 813 454",stroke=WOOD,sw=7)+group(prop_art("camp_weapon_rack"),"translate(107 336) scale(1.2)")
        s+=group(prop_art("camp_hunting_rack"),"translate(947 333) scale(1.1)")
        s+=ellipse(688,514,89,24,"#716c61")+path("M637 525 733 501M646 499 729 526",stroke=WOOD,sw=14)+path("M653 501Q634 469 671 433L682 464 707 423Q752 474 721 503Z",COPPER)+path("M674 503Q659 484 691 460L700 479 714 474 710 503Z",GOLD)
    else:
        s+=path("M667 355Q449 405 684 463Q844 515 529 640H1043Q1136 548 943 476Q728 416 812 356Z","#92b4ae")
        s+=path("M636 413H762M720 494H867M588 588H795",stroke="#c3d2c2",sw=5)
        s+=group(prop_art("wetland_abandoned_raft"),"translate(875 353) scale(1.4)")
        for x,y,c,scale in [(204,487,BLUE,1.7),(276,518,SAGE,2.3),(1080,543,PURPLE,2.0),(1155,483,BLUE,1.5)]:
            s+=mushroom(x,y,c,scale)
        for x,y in [(310,391),(940,320),(392,465),(1062,410),(199,350)]:
            s+=circle(x,y,4,SAGE)+circle(x,y,12,SAGE,opacity=".08")
    for x,y,sc in [(30,575,2.4),(1247,564,2.7)]:
        s+=tree(x,y,sc, "#435747" if area!="tower" else "#4a465e",area=="tower")
    s+=poly("0,584 138,563 272,608 365,590 489,640 0,640",mid)+poly("925,640 1039,574 1163,595 1280,565 1280,640",mid)
    for i in range(12):
        x=60+i*103
        s+=leaf(x,593+(i%3)*13,SAGE,.4)
    return s


CARD_SOURCES={"shoot":"goblin_bow","thrust":"salvaged_spear","power_shot":"hunting_crossbow","bell_strike":"ritual_bellstaff","rest_bell":"ritual_bellstaff","guard_bell":"ritual_bellstaff","glow_bolt":"runic_wand","apply_gel":"green_gel","throw_fire_sac":"fire_gel_sac","throw_frost_sac":"frost_gel_sac","eat_honey":"honey_chunk","scatter_stings":"sting_sac","torch_strike":"resin_torch","smoke_screen":"old_lantern","throw_net":"rope_net","throw_spores":"rot_spore_sac"}


def card_art(key):
    k=key.removeprefix("forest_")
    s=rect(0,0,320,200,"#e4dfcf",12)+circle(159,97,78,"#d6dac9")
    if k=="smoke_screen":
        s+=circle(205,68,30,"#b8b6ba")+circle(235,91,36,"#b8b6ba")+circle(199,118,28,"#b8b6ba")
    if "throw" in k or k in ["shoot","power_shot","scatter_stings","glow_bolt"]:
        s+=path("M41 132Q110 39 267 63M54 152Q137 71 271 89",stroke="#b8bdad",sw=5)
    s+=group(item_art("forest_"+CARD_SOURCES[k]),"translate(60 0)")
    if k=="guard_bell":
        s+=group(shield(),"translate(175 15) scale(.65)")
    elif k=="rest_bell":
        s+=path("M218 48V83M201 65H235",stroke=SAGE,sw=7)
    elif k=="glow_bolt":
        s+=poly("240,54 255,75 240,96 225,75",PURPLE)+path("M255 75H283",stroke=PURPLE,sw=5)
    elif k=="power_shot":
        s+=path("M238 99H286M272 87 286 99 272 111",stroke=COPPER,sw=6)
    return s


def save_svg(category,key,title,body,w=200,h=200):
    folder=OUT/category
    folder.mkdir(parents=True,exist_ok=True)
    filename=folder/(key+".svg")
    text=f'<svg xmlns="http://www.w3.org/2000/svg" width="{1280 if category=="backgrounds" else 320 if category=="cards" else 256}" height="{640 if category=="backgrounds" else 200 if category=="cards" else 256}" viewBox="0 0 {w} {h}"><title>{html.escape(title)}</title>{body}</svg>\n'
    filename.write_text(text,encoding="utf-8",newline="\n")
    return {"id":key,"name":title,"kind":category,"path":"res://"+filename.relative_to(ROOT).as_posix(),"sha256":hashlib.sha256(text.encode()).hexdigest()}


def main():
    entries=[]
    names={"trail":"林间古道","temple":"苔封神殿","tower":"空铃废塔","camp":"废弃伐木营地","wetland":"荧沼湿地"}
    for key,name in names.items():
        entries.append(save_svg("backgrounds",key,name,background_art(key),1280,640))
    for key,data in records("ENEMIES").items():
        entries.append(save_svg("enemies",key,data["name"],enemy_art(key)))
    for key,data in records("SEARCH_TEMPLATES").items():
        entries.append(save_svg("props",key,data["name"],prop_art(key)))
    for data in records("ITEM_MAPPING").values():
        entries.append(save_svg("items",data["def_id"],data["name"],item_art(data["def_id"])))
    for key,data in records("NEW_CARDS").items():
        entries.append(save_svg("cards",key,data["name"],card_art(key),320,200))
    (OUT/"manifest.json").write_text(json.dumps({"style":"flat_geometry_v1","generator":"tools/build_forest_art.py","assets":entries},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"Built {len(entries)} SVG assets in {OUT}")


if __name__=="__main__":
    main()
