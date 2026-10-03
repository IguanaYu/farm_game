# -*- coding: utf-8 -*-
"""Download NH character renders from dodo.ac CDN via md5-derived paths."""
import hashlib
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent / "villagers"

# Base render filenames ("X NH.png", canonical underscore form), page 1: A-Limberg
NAMES = """Ace_NH.png
Admiral_NH.png
Agent_S_NH.png
Agnes_NH.png
Al_NH.png
Alfonso_NH.png
Alice_NH.png
Alli_NH.png
Amelia_NH.png
Anabelle_NH.png
Anchovy_NH.png
Angus_NH.png
Anicotti_NH.png
Ankha_NH.png
Annalisa_NH.png
Annalise_NH.png
Antonio_NH.png
Apollo_NH.png
Apple_NH.png
Astrid_NH.png
Audie_NH.png
Aurora_NH.png
Ava_NH.png
Avery_NH.png
Axel_NH.png
Azalea_NH.png
Baabara_NH.png
Bam_NH.png
Bangle_NH.png
Barold_NH.png
Bea_NH.png
Beardo_NH.png
Beau_NH.png
Becky_NH.png
Bella_NH.png
Benedict_NH.png
Benjamin_NH.png
Bertha_NH.png
Bettina_NH.png
Bianca_NH.png
Biff_NH.png
Big_Top_NH.png
Bill_NH.png
Billy_NH.png
Biskit_NH.png
Bitty_NH.png
Blaire_NH.png
Blanche_NH.png
Blathers_NH.png
Bluebear_NH.png
Bob_NH.png
Bonbon_NH.png
Bones_NH.png
Boomer_NH.png
Boone_NH.png
Boots_NH.png
Boris_NH.png
Boyd_NH.png
Bree_NH.png
Brewster_NH.png
Broccolo_NH.png
Broffina_NH.png
Bruce_NH.png
Bubbles_NH.png
Buck_NH.png
Bud_NH.png
Bunnie_NH.png
Butch_NH.png
Buzz_NH.png
C.J._NH.png
Cally_NH.png
Camofrog_NH.png
Canberra_NH.png
Candi_NH.png
Carmen_NH.png
Caroline_NH.png
Carrie_NH.png
Cashmere_NH.png
Cece_NH.png
Celeste_NH.png
Celia_NH.png
Cephalobot_NH.png
Cesar_NH.png
Chabwick_NH.png
Chadder_NH.png
Charlise_NH.png
Cheri_NH.png
Cherry_NH.png
Chester_NH.png
Chevre_NH.png
Chief_NH.png
Chops_NH.png
Chow_NH.png
Chrissy_NH.png
Claude_NH.png
Claudia_NH.png
Clay_NH.png
Cleo_NH.png
Clyde_NH.png
Coach_NH.png
Cobb_NH.png
Coco_NH.png
Cole_NH.png
Colton_NH.png
Cookie_NH.png
Cousteau_NH.png
Cranston_NH.png
Croque_NH.png
Cube_NH.png
Curlos_NH.png
Curly_NH.png
Curt_NH.png
Cyd_NH.png
Cyrano_NH.png
Cyrus_NH.png
Daisy_Mae_NH.png
Daisy_NH.png
Deena_NH.png
Deirdre_NH.png
Del_NH.png
Deli_NH.png
Derwin_NH.png
Diana_NH.png
Diva_NH.png
Dizzy_NH.png
DJ_KK_NH.png
Dobie_NH.png
Doc_NH.png
Dom_NH.png
Don_Resetti_NH.png
Dora_NH.png
Dotty_NH.png
Drago_NH.png
Drake_NH.png
Drift_NH.png
Ed_NH.png
Egbert_NH.png
Elise_NH.png
Ellie_NH.png
Elmer_NH.png
Eloise_NH.png
Elvis_NH.png
Erik_NH.png
Eugene_NH.png
Eunice_NH.png
Faith_NH.png
Fang_NH.png
Fauna_NH.png
Felicity_NH.png
Filbert_NH.png
Flick_NH.png
Flip_NH.png
Flo_NH.png
Flora_NH.png
Flurry_NH.png
Francine_NH.png
Frank_NH.png
Franklin_NH.png
Freckles_NH.png
Frett_NH.png
Freya_NH.png
Friga_NH.png
Frita_NH.png
Frobert_NH.png
Fuchsia_NH.png
Gabi_NH.png
Gala_NH.png
Gaston_NH.png
Gayle_NH.png
Genji_NH.png
Gigi_NH.png
Gladys_NH.png
Gloria_NH.png
Goldie_NH.png
Gonzo_NH.png
Goose_NH.png
Graham_NH.png
Grams_NH.png
Greta_NH.png
Grizzly_NH.png
Groucho_NH.png
Gruff_NH.png
Gullivarrr_NH.png
Gulliver_NH.png
Gwen_NH.png
Hamlet_NH.png
Hamphrey_NH.png
Hans_NH.png
Harriet_NH.png
Harry_NH.png
Harvey_NH.png
Hazel_NH.png
Henry_NH.png
Hippeux_NH.png
Hopkins_NH.png
Hopper_NH.png
Hornsby_NH.png
Huck_NH.png
Hugh_NH.png
Iggly_NH.png
Ike_NH.png
Ione_NH.png
Isabelle_NH.png
Jack_NH.png
Jacob_NH.png
Jacques_NH.png
Jambette_NH.png
Jay_NH.png
Jeremiah_NH.png
Jingle_NH.jpg
Jitters_NH.png
Joan_NH.png
Joey_NH.png
Judy_NH.png
Julia_NH.png
Julian_NH.png
June_NH.png
K.K._Slider_NH.png
Kabuki_NH.png
Kapp'n_NH.png
Katrina_NH.png
Katt_NH.png
Keaton_NH.png
Ken_NH.png
Ketchup_NH.png
Kevin_NH.png
Kicks_NH.png
Kid_Cat_NH.png
Kidd_NH.png
Kiki_NH.png
Kitt_NH.png
Kitty_NH.png
Klaus_NH.png
Knox_NH.png
Kody_NH.png
Kyle_NH.png
Label_NH.png
Leif_NH.png
Leila_NH.png
Leilani_NH.png
Leonardo_NH.png
Leopold_NH.png
Lily_NH.png
Limberg_NH.png""".split()

MAGIC = {b"\x89PNG": "png", b"\xff\xd8\xff": "jpg"}


def url_for(name: str) -> str:
    h = hashlib.md5(name.encode("utf-8")).hexdigest()
    return f"https://dodo.ac/np/images/{h[0]}/{h[:2]}/{quote(name)}"


def fetch(name: str) -> tuple[str, str]:
    dest = ROOT / name
    if dest.exists() and dest.stat().st_size > 1000:
        return name, "skip"
    url = url_for(name)
    r = subprocess.run(
        ["curl", "-sSL", "--retry", "2", "-m", "60", "-A", "farm-ref-research/1.0", "-o", str(dest), url],
        capture_output=True,
    )
    ok = dest.exists() and dest.stat().st_size > 1000
    if ok:
        with open(dest, "rb") as f:
            head = f.read(4)
        if head not in MAGIC:
            dest.unlink(missing_ok=True)
            return name, f"badmagic:{head!r}"
    return name, "ok" if ok else f"fail:{r.returncode}"


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    results = []
    with ThreadPoolExecutor(max_workers=6) as ex:
        for name, status in ex.map(fetch, NAMES):
            results.append((name, status))
            if status not in ("ok", "skip"):
                print("FAIL", name, status, flush=True)
    bad = [n for n, s in results if s not in ("ok", "skip")]
    print(f"total={len(results)} ok={sum(1 for _, s in results if s == 'ok')} "
          f"skip={sum(1 for _, s in results if s == 'skip')} fail={len(bad)}")
    Path(__file__).parent / "failed_villagers.txt"
    (Path(__file__).parent / "failed_villagers.txt").write_text("\n".join(bad), encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
