#!/usr/bin/env python3
"""Small copies of the README screenshots (screenshots/out/readme-*.png, from
`flutter test screenshots/ --update-goldens`) in docs/screenshots, scaled to
40% with the aspect ratio kept."""
from pathlib import Path

from PIL import Image

root = Path(__file__).resolve().parent.parent
out = root / "docs" / "screenshots"
out.mkdir(parents=True, exist_ok=True)
for src in sorted((root / "screenshots" / "out").glob("readme-*.png")):
    im = Image.open(src).convert("RGB")
    w, h = im.size
    small = im.resize((round(w * 0.4), round(h * 0.4)), Image.LANCZOS)
    dst = out / (src.name.removeprefix("readme-"))
    small.save(dst, optimize=True)
    print(f"{dst.relative_to(root)}  {small.size[0]}x{small.size[1]}  {dst.stat().st_size // 1024} KB")
