#!/usr/bin/env python3
"""Generate deterministic Research Atlas desktop icons from simple vector-like primitives."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
SIZE = 1024


def font(size: int) -> ImageFont.FreeTypeFont:
    candidates = [
        "/System/Library/Fonts/SFNSRounded.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ]
    for candidate in candidates:
        if Path(candidate).exists():
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default(size=size)


def build_icon() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((92, 112, 932, 952), radius=210, fill=(0, 0, 0, 95))
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    image.alpha_composite(shadow)

    base = Image.new("RGBA", image.size, (0, 0, 0, 0))
    pixels = base.load()
    for y in range(72, 922):
        progress = (y - 72) / 850
        color = (
            int(69 - progress * 33),
            int(166 - progress * 57),
            int(91 - progress * 45),
            255,
        )
        for x in range(72, 952):
            pixels[x, y] = color
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((72, 72, 952, 952), radius=220, fill=255)
    base.putalpha(mask)
    image.alpha_composite(base)

    draw = ImageDraw.Draw(image)
    contour = (220, 248, 225, 45)
    for inset in (155, 215, 275):
        draw.ellipse((inset, inset + 20, SIZE - inset, SIZE - inset + 20), outline=contour, width=9)
    nodes = [(255, 310), (767, 280), (814, 690), (515, 790), (218, 690)]
    for start, end in zip(nodes, nodes[1:] + nodes[:1]):
        draw.line((*start, *end), fill=(227, 252, 231, 76), width=13)
    for x, y in nodes:
        draw.ellipse((x - 22, y - 22, x + 22, y + 22), fill=(232, 255, 235, 155))

    label_font = font(330)
    label = "RA"
    box = draw.textbbox((0, 0), label, font=label_font, stroke_width=2)
    width, height = box[2] - box[0], box[3] - box[1]
    draw.text(((SIZE - width) / 2, (SIZE - height) / 2 - 58), label,
              font=label_font, fill=(248, 252, 244, 255), stroke_width=2,
              stroke_fill=(248, 252, 244, 255))
    return image


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    icon = build_icon()
    icon.save(ASSETS / "icon.png", optimize=True)
    icon.save(ASSETS / "icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    icon.save(ASSETS / "icon.icns", format="ICNS")


if __name__ == "__main__":
    main()
