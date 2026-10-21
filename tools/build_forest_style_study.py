"""One-scene style study anchored to the existing farmer, separate from shipped art."""
from pathlib import Path
from build_forest_art import rect, path, poly, circle, ellipse, group

OUT = Path(__file__).resolve().parents[1] / "assets/art_studies/forest_cohesion_v02"


def grove(x, y, scale=1, bark="#766b57", crown="#667a61"):
    # Broad rounded masses with a single shadow plane, rather than repeated circles.
    canopy = path("M-97-121Q-126-159-92-182Q-99-224-52-223Q-31-262 8-237Q50-251 67-214Q111-209 107-169Q135-138 98-112Q48-93 6-109Q-54-84-97-121Z", crown)
    canopy += path("M-92-143Q-49-118-11-140Q20-112 68-133Q95-127 107-158Q133-136 98-112Q48-93 6-109Q-54-84-97-121Z", "#435e50", opacity=".30")
    trunk = path("M-23 0-15-147-36-173-28-181-2-156 20-193 30-185 9-139 23 0Z", bark)
    trunk += path("M0 0-2-156 9-139 23 0Z", "#594f43", opacity=".26")
    return group(trunk + canopy, f"translate({x} {y}) scale({scale})")


def backdrop():
    s = rect(0, 0, 1280, 800, "#a5ad9c")
    s += path("M0 166Q108 108 218 158Q349 86 468 148Q590 91 710 139Q876 89 984 146Q1124 99 1280 145V360H0Z", "#8d9c86")
    for x, y, scale in [(118,270,.75),(279,251,.64),(424,250,.72),(626,241,.69),(797,255,.75),(973,256,.64),(1160,270,.85)]:
        s += grove(x,y,scale,"#8a816b","#788b70")
    s += path("M0 263Q245 232 478 260Q747 225 998 261Q1147 246 1280 266V800H0Z", "#889276")
    # Ground is deliberately under the actors' feet at y≈295, rather than below the UI.
    s += path("M568 252Q621 262 686 252Q738 302 911 345Q979 397 1138 452L1280 800H0L145 461Q306 373 425 338Q526 304 568 252Z", "#b9ab8a")
    s += path("M568 252Q595 271 635 290Q531 336 447 372Q305 420 145 461L0 800H116L246 498Q373 431 511 391Q624 356 720 324Q663 279 686 252Z", "#afa183")
    for x,y,scale in [(418,297,.32),(905,320,.39),(311,368,.58),(1025,408,.65)]:
        s += group(poly("-25,3 -13,-10 17,-9 30,5 9,11 -18,10", "#898c7b") + poly("-25,3 -13,-10 17,-9 7,2", "#a8aa94"),f"translate({x} {y}) scale({scale})")
    for x,y in [(300,310),(352,330),(986,347),(1014,360),(198,421),(1103,470)]:
        s += path(f"M{x} {y}q-11-19-18-19q1 16 18 19q9-18 17-20q0 17-17 20", "#778c67")
    # A small log is grounded on the same plane, with the farmer's warm wood palette.
    s += ellipse(160,395,84,14,"#576653",opacity=".20")
    s += path("M98 329Q151 311 218 324L227 377Q169 392 106 383Z", "#927453")
    s += path("M98 329Q151 311 218 324L219 340Q155 331 102 344Z", "#b69a70")
    s += ellipse(106,356,22,29,"#c5ad80") + ellipse(107,357,13,20,"#675e49")
    s += path("M145 349 198 342M149 374 209 366",stroke="#b69a70",sw=4)
    s += grove(38,435,1.8,"#766b57","#526d57")
    s += grove(1244,426,1.85,"#766b57","#4d6654")
    s += path("M0 477Q96 440 168 473Q202 474 246 510L160 800H0Z", "#6b805f")
    s += path("M1102 481Q1197 443 1280 471V800H1181Z", "#68795e")
    return s


def archer():
    # Match farmer: head near y=90, broad tunic, short block legs, rounded arms.
    skin, cloth, wood = "#a7b68b", "#7f916b", "#927453"
    s = poly("76,157 95,157 95,189 79,189",wood) + poly("108,157 127,157 124,189 108,189",wood)
    s += poly("72,111 128,111 141,168 117,171 103,149 85,171 61,166",cloth)
    s += poly("109,115 128,111 141,168 117,171 103,149", "#6d805d")
    s += path("M74 119 60 142M129 119 140 135",stroke=skin,sw=13)
    s += poly("73,74 52,66 63,94 78,98 127,74 148,66 137,94 122,98",skin)
    s += circle(101,88,31,skin)
    s += circle(91,94,3,"#485a50") + circle(113,94,3,"#485a50")
    s += path("M72 73Q72 48 93 46Q115 43 126 69Z", "#75835f")
    s += path("M78 69Q100 58 125 72",stroke="#b1c5a0",sw=5)
    s += path("M143 93Q171 132 144 169",stroke=wood,sw=7)
    s += path("M143 93 151 134 144 169",stroke="#d7c8a6",sw=2)
    s += path("M130 134H174M165 130 174 134 165 138",stroke="#ad8163",sw=3)
    return s


def copper_sword():
    s = poly("72,130 133,45 150,30 150,56 91,143", "#d29c67")
    s += poly("72,130 133,45 150,30 87,139", "#efba93")
    s += path("M59 119 103 152",stroke="#ad8163",sw=10)
    s += path("M80 140 57 169",stroke="#927453",sw=12) + circle(55,171,7,"#d8b887")
    return s


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    for key,body,w,h in [("trail",backdrop(),1280,800),("goblin_archer",archer(),200,200),("copper_sword",copper_sword(),200,200)]:
        svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{body}</svg>\n'
        (OUT/(key+".svg")).write_text(svg,encoding="utf-8",newline="\n")
    print("FOREST_STYLE_STUDY_BUILT: 3 SVGs")


if __name__ == "__main__":
    main()
