"""Install EasyAppIcon packs + extract transparent in-app logo marks.

Folders under assets/branding/:
  easyappicon-icons-1786098761011 = white background launcher
  easyappicon-icons-1786098776325 = dark/black background launcher

Launcher + splash use the dark pack. In-app marks are extracted from the
foreground layer and recolored green / black / white.
"""
from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
WHITE_PACK = ROOT / "assets" / "branding" / "easyappicon-icons-1786098761011"
BLACK_PACK = ROOT / "assets" / "branding" / "easyappicon-icons-1786098776325"
BRANDING = ROOT / "assets" / "branding"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS_ICON = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"


def recolor(im: Image.Image, rgb: tuple[int, int, int]) -> Image.Image:
    _r, _g, _b, a = im.convert("RGBA").split()
    solid = Image.new("RGBA", im.size, (*rgb, 255))
    solid.putalpha(a)
    return solid


def to_square(im: Image.Image, size: int = 1024, fill: float = 0.90) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    scale = (size * fill) / max(im.width, im.height)
    tw = max(1, int(im.width * scale))
    th = max(1, int(im.height * scale))
    resized = im.resize((tw, th), Image.Resampling.LANCZOS)
    canvas.paste(resized, ((size - tw) // 2, (size - th) // 2), resized)
    return canvas


def extract_book(path: Path, *, dark_bg: bool) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    px = im.load()
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    od = out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 10:
                continue
            if dark_bg:
                if r < 55 and g < 55 and b < 55:
                    continue
                if abs(r - 40) < 20 and abs(g - 40) < 20 and abs(b - 40) < 20:
                    continue
            else:
                if r > 230 and g > 230 and b > 230:
                    continue
                if (
                    r > 200
                    and g > 200
                    and b > 200
                    and abs(r - g) < 15
                    and abs(g - b) < 15
                ):
                    continue
            od[x, y] = (r, g, b, a)
    return out


def main() -> None:
    # Dark pack → Android / iOS launcher.
    for density in (
        "mipmap-ldpi",
        "mipmap-mdpi",
        "mipmap-hdpi",
        "mipmap-xhdpi",
        "mipmap-xxhdpi",
        "mipmap-xxxhdpi",
    ):
        src = BLACK_PACK / "android" / density
        if not src.exists():
            continue
        dst = ANDROID_RES / density
        dst.mkdir(parents=True, exist_ok=True)
        for f in src.glob("*.png"):
            shutil.copy2(f, dst / f.name)
            print("copied", density, f.name)

    anydpi = ANDROID_RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    shutil.copy2(
        BLACK_PACK / "android" / "mipmap-anydpi-v26" / "ic_launcher.xml",
        anydpi / "ic_launcher.xml",
    )
    shutil.copy2(
        BLACK_PACK / "android" / "mipmap-anydpi-v26" / "ic_launcher_round.xml",
        anydpi / "ic_launcher_round.xml",
    )

    (ANDROID_RES / "values" / "colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        '    <color name="bol_khata_splash">#282828</color>\n'
        '    <color name="ic_launcher_background">#282828</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )

    ios_src = BLACK_PACK / "ios" / "AppIcon.appiconset"
    for f in ios_src.iterdir():
        if f.is_file():
            shutil.copy2(f, IOS_ICON / f.name)
            print("ios", f.name)

    fg = BLACK_PACK / "android" / "mipmap-xxxhdpi" / "ic_launcher_foreground.png"
    book = extract_book(fg, dark_bg=True)
    bbox = book.getbbox()
    if not bbox:
        raise SystemExit("could not extract book from foreground")
    mark = book.crop(bbox)
    pad = 10
    padded = Image.new(
        "RGBA", (mark.width + pad * 2, mark.height + pad * 2), (0, 0, 0, 0)
    )
    padded.paste(mark, (pad, pad), mark)
    mark = padded

    green = recolor(mark, (15, 122, 76))
    black = recolor(mark, (0, 0, 0))
    white = recolor(mark, (255, 255, 255))

    to_square(green).save(BRANDING / "bol_khata_logo.png")
    to_square(black).save(BRANDING / "bol_khata_logo_black.png")
    to_square(white).save(BRANDING / "bol_khata_logo_white_on_dark.png")
    green.save(BRANDING / "bol_khata_mark_green.png")
    black.save(BRANDING / "bol_khata_mark_black.png")
    white.save(BRANDING / "bol_khata_mark_white.png")
    print("mark", mark.size, "aspect", mark.width / mark.height)

    splash = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    scale = 360 / max(white.width, white.height)
    tw, th = int(white.width * scale), int(white.height * scale)
    resized = white.resize((tw, th), Image.Resampling.LANCZOS)
    splash.paste(resized, ((512 - tw) // 2, (512 - th) // 2), resized)
    splash.save(ANDROID_RES / "drawable" / "splash_logo.png")
    print("done")


if __name__ == "__main__":
    main()
