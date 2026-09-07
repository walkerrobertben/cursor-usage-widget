#!/usr/bin/env python3
"""Crop and compare usage-widget PNG snapshots.

Crop uses PIL's C-backed difference/bbox instead of a Python pixel walk.
Bar-color counts use per-channel LUTs so CI compare stays in C as well.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

BAR_COLORS = {
    "green": (0x34, 0xC7, 0x59),
    "yellow": (0xFF, 0xCC, 0x00),
    "orange": (0xFF, 0x9F, 0x0A),
    "red": (0xFF, 0x3B, 0x30),
}
COLOR_DELTA = 20
CROP_PAD = 24
WINDOW_SIZE = "760,1800"
DEVICE_SCALE = "2"
CHROME_TIMEOUT = 45


def _pil():
    try:
        from PIL import Image, ImageChops
    except ImportError as exc:
        raise SystemExit(2) from exc
    return Image, ImageChops


def crop_to_content(src: Path, dest: Path) -> None:
    Image, ImageChops = _pil()
    image = Image.open(src).convert("RGB")
    background = Image.new("RGB", image.size, image.getpixel((0, 0)))
    bbox = ImageChops.difference(image, background).getbbox()
    if bbox is None:
        raise SystemExit(3)
    left, top, right, bottom = bbox
    box = (
        max(0, left - CROP_PAD),
        max(0, top - CROP_PAD),
        min(image.width, right + CROP_PAD),
        min(image.height, bottom + CROP_PAD),
    )
    image.crop(box).save(dest, "PNG")


def _near_count(image, target: tuple[int, int, int], delta: int = COLOR_DELTA) -> int:
    ImageChops = _pil()[1]
    mask = None
    for band, center in zip(image.split(), target):
        lut = [255 if abs(value - center) <= delta else 0 for value in range(256)]
        channel = band.point(lut)
        mask = channel if mask is None else ImageChops.multiply(mask, channel)
    histogram = mask.histogram()
    return histogram[255] if len(histogram) > 255 else 0


def counts(path: Path) -> tuple[tuple[int, int], dict[str, int]]:
    Image, _ = _pil()
    image = Image.open(path).convert("RGB")
    tallies = {name: _near_count(image, color) for name, color in BAR_COLORS.items()}
    return image.size, tallies


def compare(gold: Path, actual: Path) -> None:
    gold_size, gold_counts = counts(gold)
    shot_size, shot_counts = counts(actual)
    if gold_size != shot_size:
        print(f"size mismatch gold={gold_size} actual={shot_size}")
        raise SystemExit(1)
    for name in BAR_COLORS:
        allowed = max(20, int(gold_counts[name] * 0.05))
        if abs(gold_counts[name] - shot_counts[name]) > allowed:
            print(f"{name} bar pixels gold={gold_counts[name]} actual={shot_counts[name]}")
            raise SystemExit(1)


def chrome_arguments(chrome: str, user_data: str, screenshot: str) -> list[str]:
    return [
        chrome,
        "--headless=new",
        "--disable-gpu",
        "--hide-scrollbars",
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--no-first-run",
        "--disable-background-networking",
        "--disable-component-update",
        "--disable-default-apps",
        "--disable-extensions",
        "--disable-sync",
        "--disable-translate",
        "--metrics-recording-only",
        "--mute-audio",
        "--no-default-browser-check",
        f"--user-data-dir={user_data}",
        f"--window-size={WINDOW_SIZE}",
        f"--force-device-scale-factor={DEVICE_SCALE}",
        f"--screenshot={screenshot}",
    ]


def screenshot(chrome: str, html: Path, dest: Path) -> None:
    temp = Path(tempfile.mkdtemp(prefix="cursor-usage-shot-"))
    raw = temp / "raw.png"
    try:
        process = subprocess.run(
            chrome_arguments(chrome, str(temp / "profile"), str(raw)) + [html.resolve().as_uri()],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=CHROME_TIMEOUT,
            check=False,
        )
        if process.returncode != 0 or not raw.is_file():
            raise SystemExit(f"Chrome failed to screenshot {html.name}")
        crop_to_content(raw, dest)
    except subprocess.TimeoutExpired as exc:
        raise SystemExit(f"Chrome timed out screenshotting {html.name}") from exc
    finally:
        shutil.rmtree(temp, ignore_errors=True)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: snapshot_png.py crop|compare|screenshot ...", file=sys.stderr)
        return 2
    command = argv[1]
    if command == "crop":
        crop_to_content(Path(argv[2]), Path(argv[3]))
        return 0
    if command == "compare":
        compare(Path(argv[2]), Path(argv[3]))
        return 0
    if command == "screenshot":
        screenshot(argv[2], Path(argv[3]), Path(argv[4]))
        return 0
    print(f"unknown command {command}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
