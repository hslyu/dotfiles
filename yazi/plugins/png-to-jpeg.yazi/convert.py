#!/usr/bin/env python3
"""Create a preview-sized JPEG cache entry for a PNG image."""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageOps


def main() -> None:
    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    bound = int(sys.argv[3])
    quality = int(sys.argv[4])

    with Image.open(source) as image:
        image = ImageOps.exif_transpose(image)
        image.thumbnail((bound, bound), Image.LANCZOS)

        if image.mode in {"RGBA", "LA"} or (image.mode == "P" and "transparency" in image.info):
            background = Image.new("RGBA", image.size, "white")
            background.alpha_composite(image.convert("RGBA"))
            image = background.convert("RGB")
        else:
            image = image.convert("RGB")

        destination.parent.mkdir(parents=True, exist_ok=True)
        image.save(destination, "JPEG", quality=quality, optimize=True)


if __name__ == "__main__":
    main()
