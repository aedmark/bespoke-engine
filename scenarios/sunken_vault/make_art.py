#!/usr/bin/env python3
"""Generate the six 320x180 RGBA PNG room backdrops for The Sunken Vault (P49-03)."""

from pathlib import Path
import struct
import zlib

WIDTH = 320
HEIGHT = 180

PALETTE = {
    "..": (0, 0, 0, 0),
    "bg": (10, 12, 22, 255),
    "s1": (26, 30, 44, 255),
    "s2": (44, 50, 68, 255),
    "s3": (70, 78, 98, 255),
    "s4": (102, 112, 134, 255),
    "wd": (58, 38, 26, 255),
    "wl": (92, 62, 40, 255),
    "ir": (42, 46, 56, 255),
    "ih": (118, 126, 144, 255),
    "gd": (196, 156, 48, 255),
    "gl": (242, 214, 112, 255),
    "w1": (20, 56, 104, 255),
    "w2": (32, 88, 148, 255),
    "w3": (54, 134, 194, 255),
    "w4": (116, 188, 228, 255),
    "w5": (196, 236, 250, 255),
    "f1": (142, 34, 18, 255),
    "f2": (206, 78, 22, 255),
    "f3": (242, 144, 30, 255),
    "f4": (252, 204, 68, 255),
    "f5": (255, 244, 166, 255),
    "m1": (36, 48, 82, 255),
    "m2": (72, 94, 142, 255),
    "m3": (138, 166, 212, 255),
    "m4": (208, 224, 246, 255),
    "e1": (18, 66, 58, 255),
    "e2": (34, 112, 92, 255),
    "e3": (64, 174, 140, 255),
    "e4": (136, 232, 198, 255),
}


def validate_palette() -> None:
    opaque = [rgba[:3] for code, rgba in PALETTE.items() if code != ".."]
    if len(opaque) != len(set(opaque)):
        raise ValueError("Duplicate RGB colour in palette")


def new_canvas(fill: str = "bg") -> list[list[str]]:
    return [[fill] * WIDTH for _ in range(HEIGHT)]


def rect(img: list[list[str]], x: int, y: int, w: int, h: int, code: str) -> None:
    x0 = max(0, x)
    y0 = max(0, y)
    x1 = min(WIDTH, x + w)
    y1 = min(HEIGHT, y + h)
    for py in range(y0, y1):
        row = img[py]
        for px in range(x0, x1):
            row[px] = code


def circle(img: list[list[str]], cx: int, cy: int, r: int, code: str) -> None:
    r2 = r * r
    for py in range(max(0, cy - r), min(HEIGHT, cy + r + 1)):
        for px in range(max(0, cx - r), min(WIDTH, cx + r + 1)):
            if (px - cx) ** 2 + (py - cy) ** 2 <= r2:
                img[py][px] = code


def arch(img: list[list[str]], cx: int, top: int, bottom: int, rx: int, border: int, fill: str, frame_code: str) -> None:
    rect(img, cx - rx - border, top + rx, (rx + border) * 2, bottom - (top + rx), frame_code)
    circle(img, cx, top + rx, rx + border, frame_code)
    rect(img, cx - rx, top + rx, rx * 2, bottom - (top + rx), fill)
    circle(img, cx, top + rx, rx, fill)


def brick_wall(img: list[list[str]], y0: int, y1: int, base: str = "s1", mortar: str = "bg", hi: str = "s2") -> None:
    rect(img, 0, y0, WIDTH, y1 - y0, base)
    for y in range(y0, y1, 12):
        rect(img, 0, y, WIDTH, 1, mortar)
        offset = 12 if (y // 12) % 2 else 0
        for x in range(offset, WIDTH, 24):
            rect(img, x, y, 1, 12, mortar)
            if (x + y) % 36 == 0:
                rect(img, x + 2, y + 2, 18, 8, hi)


def stone_floor(img: list[list[str]], y0: int = 120) -> None:
    rect(img, 0, y0, WIDTH, HEIGHT - y0, "s1")
    for y in range(y0, HEIGHT, 10):
        rect(img, 0, y, WIDTH, 1, "bg")
    for y in range(126, HEIGHT):
        if y % 12 == 0:
            rect(img, 0, y, WIDTH, 1, "bg")


def draw_torch_flame(img: list[list[str]], cx: int, cy: int) -> None:
    rect(img, cx - 2, cy, 4, 14, "wd")
    rect(img, cx - 3, cy, 6, 3, "ir")
    circle(img, cx, cy - 3, 5, "f1")
    circle(img, cx, cy - 4, 4, "f2")
    circle(img, cx, cy - 5, 3, "f3")
    rect(img, cx - 1, cy - 8, 2, 4, "f4")
    img[cy - 7][cx] = "f5"


def make_courtyard() -> list[list[str]]:
    img = new_canvas("bg")
    # Night sky with drifting moonlit mist
    for y in range(0, 88):
        band = "m1" if y < 32 else ("m2" if y < 60 else "m1")
        rect(img, 0, y, WIDTH, 1, band)
    for x in range(12, 308, 28):
        rect(img, x, 18 + (x % 3) * 10, 18, 3, "m3")
        rect(img, x + 6, 20 + (x % 3) * 10, 8, 2, "m4")
    # Moon
    circle(img, 62, 30, 14, "m4")
    circle(img, 67, 27, 11, "m1")
    # Battlements & keep wall
    brick_wall(img, 54, 122, "s1", "bg", "s2")
    for x in range(0, WIDTH, 32):
        rect(img, x, 44, 18, 12, "s2")
        rect(img, x + 2, 46, 14, 2, "s3")
    # Guardhouse archway on the right
    arch(img, 250, 62, 122, 22, 5, "bg", "s3")
    rect(img, 240, 88, 20, 34, "wd")
    rect(img, 246, 94, 8, 10, "f2")
    # Stone stair descending on the left
    rect(img, 42, 92, 62, 30, "s2")
    for step in range(5):
        rect(img, 46 + step * 8, 96 + step * 5, 50 - step * 8, 4, "s3")
    stone_floor(img, 122)
    # Rain puddles with water colour cycle
    for px, py, pw in [(96, 132, 46), (170, 140, 56), (26, 148, 38)]:
        rect(img, px, py, pw, 6, "w1")
        rect(img, px + 4, py + 1, pw - 8, 4, "w2")
        rect(img, px + 8, py + 2, pw - 16, 2, "w3")
        rect(img, px + 14, py + 2, 10, 1, "w4")
        img[py + 2][px + 18] = "w5"
    # Keep dark bottom band
    rect(img, 0, 156, WIDTH, 24, "bg")
    return img


def make_guardhouse() -> list[list[str]]:
    img = new_canvas("bg")
    brick_wall(img, 12, 122, "s1", "bg", "s2")
    rect(img, 0, 0, WIDTH, 14, "wd")
    rect(img, 0, 12, WIDTH, 4, "wl")
    # Wooden beams
    for bx in (48, 160, 272):
        rect(img, bx, 14, 10, 108, "wd")
        rect(img, bx + 2, 14, 2, 108, "wl")
    # Wall sconces
    draw_torch_flame(img, 96, 56)
    draw_torch_flame(img, 224, 56)
    # West doorway back to courtyard
    arch(img, 28, 66, 122, 16, 4, "m1", "s3")
    # Oak table with ledger and flint
    rect(img, 118, 94, 84, 8, "wl")
    rect(img, 124, 102, 8, 20, "wd")
    rect(img, 188, 102, 8, 20, "wd")
    rect(img, 142, 88, 26, 6, "s4")
    rect(img, 146, 89, 18, 4, "m4")
    rect(img, 178, 90, 10, 4, "ih")
    # Iron key peg on right wall
    rect(img, 250, 74, 14, 10, "wd")
    rect(img, 256, 78, 3, 12, "gd")
    rect(img, 254, 76, 7, 5, "gl")
    stone_floor(img, 122)
    rect(img, 0, 156, WIDTH, 24, "bg")
    return img


def make_cistern() -> list[list[str]]:
    img = new_canvas("bg")
    brick_wall(img, 10, 122, "s1", "bg", "s2")
    # Vaulted ribs
    for x in (40, 120, 200, 280):
        rect(img, x, 10, 12, 112, "s2")
        rect(img, x + 2, 10, 3, 112, "s3")
    # North crypt archway
    arch(img, 160, 46, 122, 26, 6, "bg", "s3")
    # East sluice arch
    arch(img, 294, 68, 122, 18, 4, "bg", "s2")
    # Subterranean waterfall on left wall
    for y in range(28, 124):
        c = ["w1", "w2", "w3", "w4", "w5"][(y // 3) % 5]
        rect(img, 64, y, 22, 1, c)
        c2 = ["w2", "w3", "w4", "w5", "w1"][(y // 4) % 5]
        rect(img, 70, y, 10, 1, c2)
    # Cistern pool across floor
    stone_floor(img, 122)
    for y in range(126, 154):
        c = ["w1", "w2", "w3", "w4", "w5"][((y - 126) // 3) % 5]
        rect(img, 20, y, 280, 1, c)
    # Brazier beside arch
    rect(img, 198, 98, 16, 24, "ir")
    draw_torch_flame(img, 206, 94)
    rect(img, 0, 156, WIDTH, 24, "bg")
    return img


def make_sluice() -> list[list[str]]:
    img = new_canvas("bg")
    brick_wall(img, 10, 122, "s1", "bg", "s2")
    # Culvert channel
    arch(img, 96, 56, 122, 28, 6, "bg", "s3")
    for y in range(78, 146):
        c = ["w1", "w2", "w3", "w4", "w5"][(y // 3) % 5]
        rect(img, 72, y, 48, 1, c)
    # Bronze & iron sluice wheel
    circle(img, 212, 82, 24, "gd")
    circle(img, 212, 82, 19, "bg")
    rect(img, 210, 58, 4, 48, "gd")
    rect(img, 188, 80, 48, 4, "gd")
    circle(img, 212, 82, 6, "gl")
    # Glowing sea-moss patches
    for mx, my in [(34, 48), (42, 76), (256, 52), (268, 92)]:
        circle(img, mx, my, 7, "e1")
        circle(img, mx + 2, my - 1, 5, "e2")
        circle(img, mx + 2, my - 2, 3, "e3")
        img[my - 2][mx + 2] = "e4"
    stone_floor(img, 122)
    rect(img, 0, 156, WIDTH, 24, "bg")
    return img


def make_crypt() -> list[list[str]]:
    img = new_canvas("bg")
    brick_wall(img, 10, 122, "s1", "bg", "s2")
    # Iron-barred gate at centre
    arch(img, 160, 44, 122, 30, 6, "bg", "s3")
    for gx in range(134, 188, 8):
        rect(img, gx, 48, 3, 74, "ir")
        rect(img, gx + 1, 48, 1, 74, "ih")
    rect(img, 130, 74, 60, 4, "ir")
    rect(img, 130, 100, 60, 4, "ir")
    # Lock plate
    rect(img, 180, 82, 10, 14, "gd")
    rect(img, 184, 86, 2, 6, "bg")
    # Glowing sea-moss on crypt walls
    for mx, my in [(48, 62), (62, 88), (244, 58), (262, 86), (110, 52)]:
        circle(img, mx, my, 8, "e1")
        circle(img, mx, my, 5, "e2")
        circle(img, mx, my, 3, "e3")
        img[my][mx] = "e4"
    stone_floor(img, 122)
    for y in range(130, 152):
        c = ["w1", "w2", "w3", "w4"][((y - 130) // 4) % 4]
        rect(img, 40, y, 240, 1, c)
    rect(img, 0, 156, WIDTH, 24, "bg")
    return img


def make_reliquary() -> list[list[str]]:
    img = new_canvas("bg")
    brick_wall(img, 10, 122, "s1", "bg", "s2")
    # Moonlit rune arch behind altar
    arch(img, 160, 32, 122, 34, 6, "m1", "s3")
    for ry in range(42, 92, 10):
        img[ry][134] = "m4"
        img[ry][186] = "m4"
        rect(img, 148, ry, 24, 2, "m3")
    # Ward braziers
    rect(img, 76, 94, 16, 28, "ir")
    draw_torch_flame(img, 84, 90)
    rect(img, 228, 94, 16, 28, "ir")
    draw_torch_flame(img, 236, 90)
    # Stone altar and Crown of Tides
    rect(img, 132, 96, 56, 26, "s3")
    rect(img, 128, 92, 64, 6, "s4")
    # Golden crown with emerald sea-glint
    rect(img, 148, 84, 24, 8, "gd")
    rect(img, 148, 80, 4, 4, "gl")
    rect(img, 158, 78, 4, 6, "gl")
    rect(img, 168, 80, 4, 4, "gl")
    rect(img, 152, 86, 4, 4, "e3")
    rect(img, 159, 86, 4, 4, "e4")
    rect(img, 165, 86, 4, 4, "e3")
    stone_floor(img, 122)
    rect(img, 0, 156, WIDTH, 24, "bg")
    return img


def write_png(path: Path, grid: list[list[str]]) -> None:
    raw = bytearray()
    for row in grid:
        raw.append(0)
        for code in row:
            r, g, b, a = PALETTE[code]
            raw.extend((r, g, b, a))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")
    path.write_bytes(png)


def main() -> None:
    validate_palette()
    out_dir = Path(__file__).resolve().parent / "art"
    out_dir.mkdir(parents=True, exist_ok=True)
    scenes = {
        "courtyard.png": make_courtyard(),
        "guardhouse.png": make_guardhouse(),
        "cistern.png": make_cistern(),
        "sluice.png": make_sluice(),
        "crypt.png": make_crypt(),
        "reliquary.png": make_reliquary(),
    }
    for name, grid in scenes.items():
        write_png(out_dir / name, grid)
        print(f"wrote {out_dir / name}")


if __name__ == "__main__":
    main()
