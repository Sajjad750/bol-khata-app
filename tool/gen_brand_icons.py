"""Regenerate cropped Bol Khata brand assets + Android/iOS launcher icons."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BRANDING = ROOT / "assets" / "branding"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS_ICON = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"

GREEN = (15, 122, 76, 255)  # #0F7A4C
WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)
LAUNCHER_BG = (15, 122, 76, 255)


def tight_crop(im: Image.Image, pad: int = 8) -> Image.Image:
    im = im.convert("RGBA")
    bbox = im.getbbox()
    if not bbox:
        return im
    l, t, r, b = bbox
    l = max(0, l - pad)
    t = max(0, t - pad)
    r = min(im.width, r + pad)
    b = min(im.height, b + pad)
    return im.crop((l, t, r, b))


def recolor(im: Image.Image, rgba: tuple[int, int, int, int]) -> Image.Image:
    """Keep alpha; replace RGB of opaque pixels."""
    im = im.convert("RGBA")
    r, g, b, a = im.split()
    solid = Image.new("RGBA", im.size, (rgba[0], rgba[1], rgba[2], 255))
    solid.putalpha(a)
    return solid


def paste_centered(canvas: Image.Image, mark: Image.Image, scale: float) -> None:
    target_w = int(canvas.width * scale)
    ratio = target_w / mark.width
    size = (target_w, max(1, int(mark.height * ratio)))
    # Cap height so tall marks still fit
    if size[1] > canvas.height * 0.72:
        target_h = int(canvas.height * 0.72)
        ratio = target_h / mark.height
        size = (max(1, int(mark.width * ratio)), target_h)
    resized = mark.resize(size, Image.Resampling.LANCZOS)
    x = (canvas.width - size[0]) // 2
    y = (canvas.height - size[1]) // 2
    canvas.paste(resized, (x, y), resized)


def square_pad(im: Image.Image, size: int = 1024) -> Image.Image:
    """Transparent square with mark centered (for UI assets)."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    paste_centered(canvas, im, scale=0.88)
    return canvas


def main() -> None:
    # Prefer transparent green logo; fall back to color original.
    src_path = BRANDING / "bol_khata_logo.png"
    if not src_path.exists():
        src_path = BRANDING / "bol_khata_logo_white.png"
    src = Image.open(src_path).convert("RGBA")

    # If source is the mint launcher (fully opaque), extract near-green pixels.
    corners = [src.getpixel((2, 2)), src.getpixel((src.width - 3, 2))]
    if all(p[3] > 250 for p in corners):
        # Build alpha from green-ish pixels vs pale background
        data = src.load()
        out = Image.new("RGBA", src.size, (0, 0, 0, 0))
        od = out.load()
        for y in range(src.height):
            for x in range(src.width):
                r, g, b, a = data[x, y]
                # Brand green is strong green channel vs pale mint bg
                if g > 80 and r < 80 and b < 100 and (g - r) > 40:
                    od[x, y] = (r, g, b, 255)
                elif g > 100 and r < 120 and b < 130 and (g - r) > 20:
                    od[x, y] = (r, g, b, 255)
        src = out

    mark = tight_crop(src, pad=12)
    # Normalize to brand green (preserve anti-aliased alpha)
    mark_green = recolor(mark, GREEN)
    mark_black = recolor(mark, BLACK)
    mark_white = recolor(mark, WHITE)

    # UI assets: tight-ish square with generous mark (less empty padding)
    square_pad(mark_green, 1024).save(BRANDING / "bol_khata_logo.png")
    square_pad(mark_black, 1024).save(BRANDING / "bol_khata_logo_black.png")
    square_pad(mark_white, 1024).save(BRANDING / "bol_khata_logo_white_on_dark.png")

    # Also save wide cropped marks for reference / aspect-correct widget use
    mark_green.save(BRANDING / "bol_khata_mark_green.png")
    mark_black.save(BRANDING / "bol_khata_mark_black.png")
    mark_white.save(BRANDING / "bol_khata_mark_white.png")
    print("mark size", mark.size)

    # Launcher: solid brand green + large white mark (fills circle mask)
    launcher = Image.new("RGBA", (1024, 1024), LAUNCHER_BG)
    paste_centered(launcher, mark_white, scale=0.62)
    launcher_rgb = Image.new("RGB", (1024, 1024), LAUNCHER_BG[:3])
    launcher_rgb.paste(launcher, mask=launcher.split()[3])
    launcher_rgb.save(BRANDING / "bol_khata_launcher.png")

    sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in sizes.items():
        out = RES / folder / "ic_launcher.png"
        launcher_rgb.resize((size, size), Image.Resampling.LANCZOS).save(out, "PNG")
        print("wrote", out)

    # Adaptive icon foreground (transparent, logo large in safe zone)
    fg = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    paste_centered(fg, mark_white, scale=0.55)
    fg_dir = RES / "drawable"
    fg.save(fg_dir / "ic_launcher_foreground.png")

    # Splash logo (white mark, transparent)
    splash = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    paste_centered(splash, mark_white, scale=0.70)
    splash.save(fg_dir / "splash_logo.png")
    print("wrote splash + foreground")

    # Adaptive icon XML resources
    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
""",
        encoding="utf-8",
    )
    colors = RES / "values" / "colors.xml"
    colors.write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="bol_khata_splash">#1A1A1A</color>
    <color name="ic_launcher_background">#0F7A4C</color>
</resources>
""",
        encoding="utf-8",
    )

    # iOS icons
    specs = [
        ("Icon-App-20x20@2x.png", 40),
        ("Icon-App-20x20@3x.png", 60),
        ("Icon-App-29x29@1x.png", 29),
        ("Icon-App-29x29@2x.png", 58),
        ("Icon-App-29x29@3x.png", 87),
        ("Icon-App-40x40@2x.png", 80),
        ("Icon-App-40x40@3x.png", 120),
        ("Icon-App-60x60@2x.png", 120),
        ("Icon-App-60x60@3x.png", 180),
        ("Icon-App-20x20@1x.png", 20),
        ("Icon-App-40x40@1x.png", 40),
        ("Icon-App-76x76@1x.png", 76),
        ("Icon-App-76x76@2x.png", 152),
        ("Icon-App-83.5x83.5@2x.png", 167),
        ("Icon-App-1024x1024@1x.png", 1024),
    ]
    for name, px in specs:
        launcher_rgb.resize((px, px), Image.Resampling.LANCZOS).save(
            IOS_ICON / name, "PNG"
        )
    print("ios icons done")


if __name__ == "__main__":
    main()
