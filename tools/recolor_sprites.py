"""Recolor a folder of sprite PNGs by hue/saturation/brightness/contrast.

Used to derive enemy variants (Wasp, Hornet) from the hero bee sprite set
without re-rendering in Meshy.

Usage (from project root):
    python tools/recolor_sprites.py
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageEnhance


# ---- Image ops --------------------------------------------------------------

def hue_shift(img: Image.Image, degrees: float) -> Image.Image:
    """Rotate the hue of an RGBA image by `degrees` (signed, can wrap)."""
    rgba = img.convert("RGBA")
    r, g, b, a = rgba.split()
    rgb = Image.merge("RGB", (r, g, b)).convert("HSV")
    h, s, v = rgb.split()
    h_arr = np.array(h, dtype=np.int32)
    shift = int(round((degrees / 360.0) * 256.0)) % 256
    h_arr = (h_arr + shift) % 256
    h = Image.fromarray(h_arr.astype(np.uint8))
    rgb = Image.merge("HSV", (h, s, v)).convert("RGB")
    r2, g2, b2 = rgb.split()
    return Image.merge("RGBA", (r2, g2, b2, a))


def adjust_saturation(img: Image.Image, factor: float) -> Image.Image:
    return ImageEnhance.Color(img).enhance(factor)


def adjust_brightness(img: Image.Image, factor: float) -> Image.Image:
    return ImageEnhance.Brightness(img).enhance(factor)


def adjust_contrast(img: Image.Image, factor: float) -> Image.Image:
    return ImageEnhance.Contrast(img).enhance(factor)


# ---- Pipeline ---------------------------------------------------------------

def process(
    img: Image.Image,
    hue_deg: float = 0.0,
    saturation: float = 1.0,
    brightness: float = 1.0,
    contrast: float = 1.0,
) -> Image.Image:
    """Apply hue → sat → brightness → contrast in that order."""
    out = img
    if hue_deg != 0.0:
        out = hue_shift(out, hue_deg)
    if saturation != 1.0:
        out = adjust_saturation(out, saturation)
    if brightness != 1.0:
        out = adjust_brightness(out, brightness)
    if contrast != 1.0:
        out = adjust_contrast(out, contrast)
    return out


def recolor_directory(
    src_dir: Path,
    dst_dir: Path,
    name_prefix: str,
    hue_deg: float = 0.0,
    saturation: float = 1.0,
    brightness: float = 1.0,
    contrast: float = 1.0,
) -> None:
    """Recolor every PNG in src_dir to dst_dir, renaming with name_prefix.

    Files are expected to be `{old_prefix}_{dir}.png` (e.g. hero_se.png).
    They are saved as `{name_prefix}_{dir}.png` (e.g. wasp_se.png).
    """
    dst_dir.mkdir(parents=True, exist_ok=True)
    pngs = sorted(src_dir.glob("*.png"))
    if not pngs:
        print(f"  WARN: no PNGs in {src_dir}")
        return

    for src in pngs:
        # Strip the source prefix, keep the direction suffix.
        # hero_se.png → se
        stem = src.stem  # hero_se
        if "_" in stem:
            suffix = stem.split("_", 1)[1]
        else:
            suffix = stem
        dst = dst_dir / f"{name_prefix}_{suffix}.png"

        img = Image.open(src).convert("RGBA")
        out = process(img, hue_deg, saturation, brightness, contrast)
        out.save(dst)
        print(f"  {src.name}  ->  {dst.name}")


# ---- Main -------------------------------------------------------------------

PROJECT = Path(__file__).resolve().parent.parent
HERO_DIR = PROJECT / "assets" / "sprites" / "hero"
SPRITES_DIR = PROJECT / "assets" / "sprites"


def main() -> None:
    print("\n=== WASP (orange swarm) ===")
    recolor_directory(
        src_dir=HERO_DIR,
        dst_dir=SPRITES_DIR / "wasp",
        name_prefix="wasp",
        hue_deg=-25.0,        # yellow → orange
        saturation=1.25,      # punchier
        brightness=0.95,      # slightly muted
        contrast=1.05,
    )

    print("\n=== HORNET (dark crimson tank) ===")
    recolor_directory(
        src_dir=HERO_DIR,
        dst_dir=SPRITES_DIR / "hornet",
        name_prefix="hornet",
        hue_deg=-55.0,        # yellow → red
        saturation=1.35,      # deep red
        brightness=0.78,      # darker, more menacing
        contrast=1.10,
    )

    print("\nDone.")


if __name__ == "__main__":
    main()
