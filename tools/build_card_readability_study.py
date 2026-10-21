"""Three function-first forest card studies, plus two composition thumbnails per card."""
from pathlib import Path
from build_forest_art import rect, path, poly, circle, ellipse, group
from build_cute_forest_hero import HAT, HAIR, RIBBON, BLOUSE

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/art_studies/card_readability_v04"


def glint(x, y, radius=15, color="#fff2c5"):
    return poly(f"{x},{y-radius} {x+4},{y-4} {x+radius},{y} {x+4},{y+4} {x},{y+radius} {x-4},{y+4} {x-radius},{y} {x-4},{y-4}", color)


def straw_hat():
    # Same plain straw hat, pink bow and sprout as the user-approved braided girl.
    s = path("M59 58 64 33Q65 24 78 24H118Q131 24 134 36L140 60Z", "#dfc68f")
    s += path("M69 34Q88 24 118 30L126 52H65Z", HAT)
    s += path("M62 49Q101 56 136 49L139 62H59Z", RIBBON)
    s += path("M43 56Q100 45 151 56Q160 60 154 70Q129 82 96 76Q62 81 43 72Q33 65 43 56Z", HAT)
    s += path("M51 65Q36 53 37 68Q39 77 51 70Q59 80 64 69Q65 58 51 65Z", RIBBON)
    s += path("M48 70 43 88 51 85 55 72", RIBBON)
    s += path("M128 53V44M128 48Q117 49 119 40Q128 39 128 48M129 46Q130 37 138 38Q140 45 129 46", "#9cac7e", stroke="#758b66", sw=2)
    return s


def arrow():
    # Exactly one projectile. Large head, readable shaft and split feather silhouette.
    s = path("M239 229 522 129", stroke="#59473b", sw=14)
    s += path("M239 226 520 126", stroke="#cfa675", sw=6)
    s += poly("507,117 587,98 535,154 520,137 509,143", "#fbebbc")
    s += poly("520,137 587,98 535,154", "#d4ad78")
    s += poly("236,218 202,197 211,226 239,239 260,227", "#b67c63")
    s += poly("239,238 220,269 250,261 266,233 262,222", "#e4bb91")
    s += path("M227 214 246 228M235 253 254 233", stroke="#f1d5b0", sw=3)
    return s


def shooting():
    s = rect(0, 0, 640, 400, "#e7cfaa", 18)
    s += path("M159 400 401 0H640V232L357 400Z", "#f5e4bd")
    s += path("M0 34Q58 56 81 111Q22 112 0 92ZM489 400Q526 348 584 343Q578 391 559 400Z", "#c4b88a")
    # A full close bow, with a small cropped hand instead of a standing heroine.
    s += path("M97 39Q222 178 139 362", stroke="#694e39", sw=28)
    s += path("M94 36Q206 174 136 359", stroke="#b58a58", sw=18)
    s += path("M95 40Q194 169 138 354", stroke="#e4bd7d", sw=5)
    s += path("M97 39 118 221 139 362", stroke="#70634b", sw=5)
    s += path("M102 48 117 216M121 231 138 354", stroke="#fff0c9", sw=2)
    s += path("M140 191 160 200M136 207 157 216M132 224 154 232M128 240 151 247", stroke="#775940", sw=7)
    # A large quiet trail behind the single arrow makes release direction survive reduction.
    s += path("M210 187Q314 138 438 122M214 258Q364 216 494 155", stroke="#d1aa75", sw=8)
    s += path("M270 176 345 153M294 242 389 204", stroke="#fff0ce", sw=5)
    s += arrow()
    s += path("M-12 345 64 274Q92 253 113 272L129 295 45 408H0Z", "#c3b68c")
    s += path("M-8 363 67 291Q87 278 101 293L31 400H0Z", BLOUSE)
    s += path("M83 274Q75 254 91 246L121 235Q139 232 145 247L149 272Q150 288 135 298L116 301Z", "#efd1b9")
    s += path("M111 245Q133 242 135 254M115 258Q136 254 139 266M119 274 138 270", stroke="#cfaa90", sw=4)
    s += path("M117 309Q129 321 143 306Q144 321 129 329Q121 320 117 309Z", "#83916a")
    s += glint(594, 88, 10)
    return s


def bell():
    s = path("M0-54Q-15-56-14-69Q-13-82 0-82Q15-82 15-69Q15-57 0-54", stroke="#7b6746", sw=8)
    s += path("M-38 0Q-31-28-29-43Q-27-62 0-63Q27-62 29-43Q32-25 39 0Z", "#dab572")
    s += path("M-29-43Q-25-58-9-58L-10-4H-35Z", "#f1d699")
    s += path("M18-56Q29-50 29-37L39 0H17Z", "#b38d55")
    s += ellipse(0, 1, 43, 13, "#8d704a") + ellipse(0, -3, 44, 10, "#e9cc8e")
    s += circle(0, 12, 10, "#b48c56")
    s += path("M-19-59Q-55-85-53-58Q-50-41-20-52Q-2-25 11-49Q13-71-19-59Z", "#8cb7af")
    s += path("M-20-51-45-21-28-22-22-9-10-48", "#b4d3b9")
    return s


def guarding():
    s = rect(0, 0, 640, 400, "#304f57", 18)
    s += path("M1 327Q117 274 261 316Q434 293 640 336V400H0Z", "#466568")
    s += ellipse(341, 212, 220, 181, "#446b6f")
    s += path("M333 40Q395 92 491 111L469 230Q446 308 333 356Q222 306 199 229L176 111Q269 92 333 40Z", "#75aba5")
    s += path("M333 62Q397 111 468 126L447 225Q425 289 333 332Q239 289 219 225L198 126Q273 108 333 62Z", "#c2ddcb")
    s += path("M333 62V332Q425 289 447 225L468 126Q397 111 333 62Z", "#99c3b6")
    s += path("M333 62Q397 111 468 126L447 225Q425 289 333 332Q239 289 219 225L198 126Q273 108 333 62Z", stroke="#ecf0cc", sw=8)
    # A big leaf crest provides a quiet enclosed centre, with no need for a face.
    s += path("M334 264Q268 230 274 162Q338 161 351 205Q361 151 408 144Q423 211 334 264Z", "#649e92")
    s += path("M335 265V204M335 232 299 193M338 230 384 180", stroke="#dce8c7", sw=6)
    # Incoming arrow is secondary and visibly stops at the barrier.
    s += path("M612 49 498 111", stroke="#c7b9a2", sw=9)
    s += poly("490,100 471,126 508,120", "#eee4c5")
    s += path("M593 58 590 37M598 55 621 59", stroke="#a78b73", sw=6)
    s += glint(475, 126, 29, "#fff1bd")
    s += path("M466 92 460 73M505 134 524 139M484 159 489 175", stroke="#d7e4c7", sw=5)
    s += path("M147 277Q155 208 206 186M165 290Q173 245 204 232", stroke="#82b8ae", sw=7)
    s += group(bell(), "translate(128 321) rotate(-14) scale(1.35)")
    s += glint(214, 68, 13, "#c6dfc8") + glint(544, 251, 10, "#9ec8bd")
    return s


def smoking():
    s = rect(0, 0, 640, 400, "#45495c", 18)
    s += path("M0 302Q151 248 308 282Q482 248 640 307V400H0Z", "#555b6b")
    s += path("M86 229Q38 211 54 172Q52 133 99 126Q109 67 166 90Q203 29 257 68Q314 32 348 87Q412 68 430 113Q491 97 512 151Q562 157 549 204Q569 249 524 270L147 290Z", "#96a4ab")
    # A small head fragment indicates shelter; the fog, not the heroine, is the subject.
    shelter = ellipse(277, 226, 32, 37, HAIR)
    shelter += path("M235 282Q232 250 253 246H298Q321 251 322 282Z", "#758b66")
    shelter += path("M253 226Q243 241 255 256M300 225Q311 241 300 257", stroke=HAIR, sw=12)
    shelter += group(straw_hat(), "translate(215 169) scale(.62)")
    s += path("M21 287Q-4 241 41 219Q25 171 79 161Q76 114 127 110Q151 65 196 97Q247 76 269 121Q316 98 349 140Q396 116 426 161Q482 149 494 195Q557 188 574 239Q627 250 613 294Q610 346 543 348H93Q29 351 21 287Z", "#c9d0ca")
    s += shelter
    # One continuous low blanket gives this card a broad horizontal silhouette.
    s += path("M40 296Q42 273 77 276Q72 238 112 237Q139 215 166 248Q196 240 206 267Q263 244 289 277Q340 254 365 286Q404 267 435 295Q485 266 514 299Q563 280 586 309Q570 345 527 344H97Q53 344 40 296Z", "#a5b5b4")
    s += path("M71 189Q110 155 148 179M171 133Q199 124 218 145M338 184Q373 167 401 191M473 232Q512 214 538 246", stroke="#e4e5d4", sw=11)
    s += path("M119 282Q111 255 138 253Q166 253 157 276M348 307Q332 284 354 274Q377 266 387 287", stroke="#d9dfd4", sw=8)
    # Resin torch is kept in the lower corner, with a short ember instead of an explosion.
    s += path("M537 412 486 304", stroke="#927454", sw=20)
    s += path("M537 412 490 308", stroke="#c39a6b", sw=7)
    s += path("M480 323 503 313M476 313 500 302M472 303 495 291", stroke="#725b49", sw=10)
    s += path("M475 299Q456 277 473 252Q475 269 486 265Q504 290 490 302Z", "#d2a575")
    s += path("M475 300Q472 283 483 280L487 298Z", "#e8d09c")
    return s


def shooting_b():
    s = rect(0, 0, 640, 400, "#e8e7df", 18)
    s += path("M41 82Q173 77 184 238", stroke="#686b64", sw=23)
    s += path("M41 82 51 236 184 238", stroke="#b8bab1", sw=5)
    s += path("M85 119 460 291", stroke="#777b70", sw=18)
    s += poly("443,262 589,351 425,312 470,296", "#42493f")
    s += poly("104,113 63,56 53,93 87,138", "#9da18f")
    s += path("M105 181 311 267M161 113 371 206", stroke="#c4c6bb", sw=10)
    return s


def guarding_b():
    s = rect(0, 0, 640, 400, "#4c5352", 18)
    s += path("M94 316Q94 153 321 146Q546 153 546 316L520 335H118Z", "#a2b1a7")
    s += path("M124 313Q124 178 321 173Q516 178 516 313", stroke="#e1e5d8", sw=11)
    s += group(bell(), "translate(321 132) scale(1.45)")
    s += ellipse(322, 259, 27, 31, "#59675e")
    s += path("M281 320 294 279H349L362 320Z", "#59675e")
    s += path("M534 86 502 176", stroke="#c9cfc2", sw=12)
    s += glint(499, 182, 26, "#f5f1d5")
    return s


def smoking_b():
    s = rect(0, 0, 640, 400, "#4c5057", 18)
    s += path("M0 80Q51 34 89 71Q145 16 193 67Q257 31 293 90Q362 57 382 118Q451 99 457 154Q523 149 520 219Q591 243 562 291Q590 360 513 400H0Z", "#b7c0bb")
    s += path("M0 267Q63 210 112 246Q173 216 206 267Q265 244 294 304Q349 276 395 323Q454 302 497 353L515 400H0Z", "#929f9c")
    s += path("M55 114Q104 88 127 128M212 124Q251 106 271 147M96 298Q140 266 172 302M340 226Q377 208 405 246", stroke="#e2e5db", sw=12)
    s += path("M570 400 531 291", stroke="#d5d2bb", sw=17)
    return s


def gray(body):
    import re
    def replace(match):
        value = match.group()[1:]
        r, g, b = (int(value[i:i+2], 16) for i in (0, 2, 4))
        level = round(.2126*r + .7152*g + .0722*b)
        return "#" + f"{level:02x}" * 3
    return re.sub(r"#[0-9a-fA-F]{6}", replace, body)


def write(name, body):
    target = OUT / (name + ".svg")
    target.parent.mkdir(parents=True, exist_ok=True)
    # High-resolution SVG import keeps the large comparison board crisp.
    target.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="800" viewBox="0 0 640 400">{body}</svg>\n', encoding="utf-8", newline="\n")


if __name__ == "__main__":
    for key, main, alternate in [("forest_shoot", shooting, shooting_b), ("forest_guard_bell", guarding, guarding_b), ("forest_smoke_screen", smoking, smoking_b)]:
        body = main()
        write(key, body)
        write("sketches/" + key + "_a", gray(body))
        write("sketches/" + key + "_b", gray(alternate()))
    print("CARD_READABILITY_STUDY: 3 color artworks + 6 grayscale composition studies")
