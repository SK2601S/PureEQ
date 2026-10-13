"""Generates the SK EQ app icon for Windows (.ico) and macOS (AppIcon set).

Usage (from the project root):  python tool/generate_icons.py
Requires Pillow:                python -m pip install pillow
"""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SIZE = 1024
SS = 2  # supersampling factor for smooth edges

BG_TOP = (34, 34, 38)
BG_BOTTOM = (15, 15, 17)
CYAN = (0, 212, 255)
DEEP = (10, 108, 255)
TIP = (184, 244, 255)


def vertical_gradient(w, h, top, bottom):
    grad = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        grad.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return grad.resize((w, h))


def render(inset: float) -> Image.Image:
    """Renders the icon. `inset` is the transparent margin as a fraction of the size."""
    s = SIZE * SS
    pad = round(s * inset)
    box = (pad, pad, s - pad, s - pad)
    side = box[2] - box[0]
    radius = round(side * 0.225)

    # Rounded-square mask and dark background.
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
    icon = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    icon.paste(vertical_gradient(s, s, BG_TOP, BG_BOTTOM), (0, 0), mask)

    # Five equalizer bars.
    heights = [0.38, 0.62, 0.84, 0.56, 0.30]
    n = len(heights)
    area_l = box[0] + side * 0.20
    area_r = box[2] - side * 0.20
    base = box[1] + side * 0.78
    max_h = side * 0.58
    col = (area_r - area_l) / n
    bar_w = col * 0.58

    bars = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(bars)
    for i, h in enumerate(heights):
        cx = area_l + col * (i + 0.5)
        d.rounded_rectangle(
            (cx - bar_w / 2, base - max_h * h, cx + bar_w / 2, base),
            radius=bar_w / 2,
            fill=255,
        )

    # Cyan glow behind the bars, clipped to the rounded square.
    glow = bars.filter(ImageFilter.GaussianBlur(s * 0.035))
    glow = ImageChops.multiply(glow, mask).point(lambda v: int(v * 0.75))
    icon.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", (s, s), CYAN).split(), glow)))

    # Bars filled with a bottom-to-top gradient (deep blue -> cyan -> bright tip).
    top_y, bot_y = round(base - max_h), round(base)
    fill = Image.new("RGB", (s, s), TIP)
    grad = Image.new("RGB", (1, bot_y - top_y))
    for y in range(bot_y - top_y):
        t = 1 - y / max(bot_y - top_y - 1, 1)  # 0 at bottom, 1 at top
        if t < 0.7:
            k = t / 0.7
            c = tuple(round(DEEP[j] + (CYAN[j] - DEEP[j]) * k) for j in range(3))
        else:
            k = (t - 0.7) / 0.3
            c = tuple(round(CYAN[j] + (TIP[j] - CYAN[j]) * k) for j in range(3))
        grad.putpixel((0, y), c)
    fill.paste(grad.resize((s, bot_y - top_y)), (0, top_y))
    icon.paste(fill, (0, 0), bars)

    # Subtle top highlight border.
    ImageDraw.Draw(icon).rounded_rectangle(box, radius, outline=(255, 255, 255, 28), width=max(2, s // 256))

    return icon.resize((SIZE, SIZE), Image.LANCZOS)


def render_tray(px: int, color) -> Image.Image:
    """Bars only, no background: reads well at 16-32 px in a tray / menu bar."""
    s = px * 8  # heavy supersampling for crisp small sizes
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    heights = [0.45, 0.75, 1.0, 0.68, 0.38]
    col = s / len(heights)
    bar_w = col * 0.62
    for i, h in enumerate(heights):
        cx = col * (i + 0.5)
        d.rounded_rectangle(
            (cx - bar_w / 2, s * (0.94 - 0.88 * h), cx + bar_w / 2, s * 0.94),
            radius=bar_w / 2,
            fill=color,
        )
    return img.resize((px, px), Image.LANCZOS)


def main():
    # macOS: Apple's template leaves ~10% transparent margin around the shape.
    mac = render(inset=0.10)
    mac_dir = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for px in (16, 32, 64, 128, 256, 512, 1024):
        mac.resize((px, px), Image.LANCZOS).save(mac_dir / f"app_icon_{px}.png")

    # Windows: nearly full-bleed so it reads well on the taskbar.
    win = render(inset=0.03)
    win.save(
        ROOT / "windows/runner/resources/app_icon.ico",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    win.save(ROOT / "installer/app_icon_preview.png")

    # Tray icons: cyan on Windows; black template on macOS (tinted by the OS).
    tray_dir = ROOT / "assets/tray"
    tray_dir.mkdir(parents=True, exist_ok=True)
    render_tray(256, CYAN + (255,)).save(
        tray_dir / "tray_icon.ico",
        sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (48, 48), (64, 64)],
    )
    render_tray(36, (0, 0, 0, 255)).save(tray_dir / "tray_icon_template.png")
    print("Icons written.")


if __name__ == "__main__":
    main()
