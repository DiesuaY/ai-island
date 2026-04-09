#!/usr/bin/env python3
"""
Generate a Matrix-rain style app icon for AI Island.
Creates a 1024x1024 PNG from a 64x64 pixel grid, then converts to .icns.
No external dependencies -- uses only stdlib (struct, zlib).
"""

import struct
import zlib
import os
import subprocess
import shutil
import tempfile

# ---------------------------------------------------------------------------
# Color palette
# ---------------------------------------------------------------------------
BLACK       = (0x00, 0x00, 0x00, 255)
TRANSPARENT = (0, 0, 0, 0)

# Green shades for matrix rain
GREEN_DARK    = (0x00, 0x33, 0x00, 255)
GREEN_MED     = (0x00, 0x77, 0x00, 255)
GREEN_BRIGHT  = (0x00, 0xAA, 0x00, 255)
GREEN_FULL    = (0x00, 0xFF, 0x00, 255)
GREEN_LEAD    = (0x88, 0xFF, 0x88, 255)  # bright leading character
GREEN_GLOW    = (0x00, 0xCC, 0x00, 255)  # glow around AI text
GREEN_GLOW_DIM = (0x00, 0x55, 0x00, 255)

# ---------------------------------------------------------------------------
# Simple deterministic PRNG (no random module needed)
# ---------------------------------------------------------------------------
_seed = 42

def _rand():
    global _seed
    _seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF
    return _seed

def rand_int(lo, hi):
    return lo + _rand() % (hi - lo + 1)

# ---------------------------------------------------------------------------
# Pixel font for "A" and "I" (each defined as list of strings)
# ---------------------------------------------------------------------------

# "A" - 10 wide, 14 tall
LETTER_A = [
    "    **    ",
    "   ****   ",
    "  **  **  ",
    "  **  **  ",
    " **    ** ",
    " **    ** ",
    " ******** ",
    " ******** ",
    "**      **",
    "**      **",
    "**      **",
    "**      **",
    "**      **",
    "**      **",
]

# "I" - 6 wide, 14 tall
LETTER_I = [
    "******",
    "******",
    "  **  ",
    "  **  ",
    "  **  ",
    "  **  ",
    "  **  ",
    "  **  ",
    "  **  ",
    "  **  ",
    "  **  ",
    "  **  ",
    "******",
    "******",
]

# ---------------------------------------------------------------------------
# 3x5 digit font for '0' and '1' (used in matrix rain)
# ---------------------------------------------------------------------------
DIGIT_0 = [
    " * ",
    "* *",
    "* *",
    "* *",
    " * ",
]

DIGIT_1 = [
    " * ",
    "** ",
    " * ",
    " * ",
    "***",
]

# ---------------------------------------------------------------------------
# Build the 64x64 grid
# ---------------------------------------------------------------------------

def make_grid():
    G = [[BLACK] * 64 for _ in range(64)]

    def s(r, c, color):
        if 0 <= r < 64 and 0 <= c < 64:
            G[r][c] = color

    def get(r, c):
        if 0 <= r < 64 and 0 <= c < 64:
            return G[r][c]
        return BLACK

    # --- Rounded corners (radius ~6 in the 64x64 grid) ---
    # Precompute which pixels are outside the rounded rect
    corner_radius = 6
    corner_pixels = set()
    for r in range(64):
        for c in range(64):
            # Check each corner
            in_corner = False
            # Top-left
            if r < corner_radius and c < corner_radius:
                dr = corner_radius - r - 0.5
                dc = corner_radius - c - 0.5
                if dr * dr + dc * dc > corner_radius * corner_radius:
                    in_corner = True
            # Top-right
            if r < corner_radius and c >= 64 - corner_radius:
                dr = corner_radius - r - 0.5
                dc = c - (64 - corner_radius) + 0.5
                if dr * dr + dc * dc > corner_radius * corner_radius:
                    in_corner = True
            # Bottom-left
            if r >= 64 - corner_radius and c < corner_radius:
                dr = r - (64 - corner_radius) + 0.5
                dc = corner_radius - c - 0.5
                if dr * dr + dc * dc > corner_radius * corner_radius:
                    in_corner = True
            # Bottom-right
            if r >= 64 - corner_radius and c >= 64 - corner_radius:
                dr = r - (64 - corner_radius) + 0.5
                dc = c - (64 - corner_radius) + 0.5
                if dr * dr + dc * dc > corner_radius * corner_radius:
                    in_corner = True
            if in_corner:
                corner_pixels.add((r, c))

    # --- Place "AI" text centered ---
    # A is 10 wide, I is 6 wide, gap is 3 => total 19 wide
    # Height is 14 tall
    text_w = 10 + 3 + 6  # 19
    text_h = 14
    text_start_c = (64 - text_w) // 2  # col 22
    text_start_r = (64 - text_h) // 2  # row 25

    # Record which pixels are "AI" text
    ai_pixels = set()

    # Draw letter A
    a_col = text_start_c
    for dr, row_str in enumerate(LETTER_A):
        for dc, ch in enumerate(row_str):
            if ch == '*':
                r, c = text_start_r + dr, a_col + dc
                ai_pixels.add((r, c))

    # Draw letter I
    i_col = text_start_c + 10 + 3
    for dr, row_str in enumerate(LETTER_I):
        for dc, ch in enumerate(row_str):
            if ch == '*':
                r, c = text_start_r + dr, i_col + dc
                ai_pixels.add((r, c))

    # Compute glow pixels (pixels adjacent to AI text but not part of it)
    glow_pixels = set()
    glow2_pixels = set()  # second ring, dimmer
    for (pr, pc) in ai_pixels:
        for dr in range(-1, 2):
            for dc in range(-1, 2):
                nr, nc = pr + dr, pc + dc
                if (nr, nc) not in ai_pixels and 0 <= nr < 64 and 0 <= nc < 64:
                    glow_pixels.add((nr, nc))
    for (pr, pc) in glow_pixels:
        for dr in range(-1, 2):
            for dc in range(-1, 2):
                nr, nc = pr + dr, pc + dc
                if (nr, nc) not in ai_pixels and (nr, nc) not in glow_pixels and 0 <= nr < 64 and 0 <= nc < 64:
                    glow2_pixels.add((nr, nc))

    # Define the "AI zone" where rain should be dimmer/absent
    ai_zone_r_min = text_start_r - 3
    ai_zone_r_max = text_start_r + text_h + 2
    ai_zone_c_min = text_start_c - 2
    ai_zone_c_max = text_start_c + text_w + 1

    # --- Generate matrix rain columns ---
    # Each column has characters (0 or 1) at various positions with varying brightness
    # We'll use the 3x5 digit font

    global _seed
    _seed = 42  # reset for determinism

    for col_start in range(0, 64, 4):  # columns every 4 pixels (digit is 3 wide + 1 gap)
        if col_start + 3 > 64:
            continue

        # Decide column properties
        col_length = rand_int(6, 12)  # how many digits in this column
        col_top = rand_int(-5, 10)  # starting row (in digit units, each 6 tall)
        lead_pos = col_top + col_length - 1  # the "leading" bright character

        for digit_idx in range(col_length):
            digit_row = col_top + digit_idx
            pixel_r = digit_row * 6  # each digit is 5 tall + 1 gap
            pixel_c = col_start

            # Skip if entirely off-screen
            if pixel_r + 5 < 0 or pixel_r >= 64:
                continue

            # Choose 0 or 1
            digit = DIGIT_0 if rand_int(0, 1) == 0 else DIGIT_1

            # Determine brightness based on position in the column
            # Characters near the lead are brighter, older ones fade
            dist_from_lead = lead_pos - digit_idx
            if digit_idx == lead_pos - col_top:
                color = GREEN_LEAD
            elif dist_from_lead <= 2:
                color = GREEN_FULL
            elif dist_from_lead <= 4:
                color = GREEN_BRIGHT
            elif dist_from_lead <= 7:
                color = GREEN_MED
            else:
                color = GREEN_DARK

            # Check if this digit overlaps the AI zone -- dim it
            in_ai_zone = False
            if pixel_r + 5 >= ai_zone_r_min and pixel_r <= ai_zone_r_max:
                if pixel_c + 3 >= ai_zone_c_min and pixel_c <= ai_zone_c_max:
                    in_ai_zone = True

            if in_ai_zone:
                # Make it much dimmer
                color = GREEN_DARK

            # Draw the digit
            for dr, row_str in enumerate(digit):
                for dc, ch in enumerate(row_str):
                    if ch == '*':
                        r = pixel_r + dr
                        c = pixel_c + dc
                        if 0 <= r < 64 and 0 <= c < 64:
                            if (r, c) not in ai_pixels and (r, c) not in glow_pixels and (r, c) not in glow2_pixels:
                                s(r, c, color)

    # --- Draw AI text and glow on top ---
    for (r, c) in glow2_pixels:
        s(r, c, GREEN_GLOW_DIM)

    for (r, c) in glow_pixels:
        s(r, c, GREEN_GLOW)

    for (r, c) in ai_pixels:
        s(r, c, GREEN_FULL)

    # --- Apply rounded corners ---
    for (r, c) in corner_pixels:
        G[r][c] = TRANSPARENT

    return G


# ---------------------------------------------------------------------------
# PNG encoder (no dependencies)
# ---------------------------------------------------------------------------

def encode_png(width, height, rows_rgba):
    """Encode RGBA pixel data into a PNG file (bytes)."""

    def chunk(chunk_type, data):
        c = chunk_type + data
        crc = struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
        return struct.pack('>I', len(data)) + c + crc

    sig = b'\x89PNG\r\n\x1a\n'
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    ihdr = chunk(b'IHDR', ihdr_data)

    raw_rows = []
    for row in rows_rgba:
        raw_rows.append(b'\x00')  # filter: None
        raw_rows.append(row)
    raw = b''.join(raw_rows)
    compressed = zlib.compress(raw, 9)
    idat = chunk(b'IDAT', compressed)

    iend = chunk(b'IEND', b'')

    return sig + ihdr + idat + iend


def upscale_and_encode(grid, scale=16):
    """Upscale 64x64 grid to 1024x1024 and encode as PNG."""
    size = len(grid) * scale  # 1024
    rows = []
    for r in range(len(grid)):
        row_bytes = bytearray()
        for c in range(len(grid[0])):
            rgba = bytes(grid[r][c])
            row_bytes.extend(rgba * scale)
        row_data = bytes(row_bytes)
        for _ in range(scale):
            rows.append(row_data)

    return encode_png(size, size, rows)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)
    resources_dir = os.path.join(project_dir, 'Resources')
    os.makedirs(resources_dir, exist_ok=True)

    png_path = os.path.join(resources_dir, 'AppIcon.png')

    print("Generating 64x64 pixel art grid...")
    grid = make_grid()

    print("Upscaling to 1024x1024 and encoding PNG...")
    png_data = upscale_and_encode(grid, scale=16)

    with open(png_path, 'wb') as f:
        f.write(png_data)
    print(f"PNG saved: {png_path} ({len(png_data)} bytes)")

    # --- Convert to .icns using iconutil ---
    icns_path = os.path.join(resources_dir, 'AppIcon.icns')

    with tempfile.TemporaryDirectory() as tmpdir:
        iconset_dir = os.path.join(tmpdir, 'AppIcon.iconset')
        os.makedirs(iconset_dir)

        sizes = {
            'icon_16x16.png': 16,
            'icon_16x16@2x.png': 32,
            'icon_32x32.png': 32,
            'icon_32x32@2x.png': 64,
            'icon_128x128.png': 128,
            'icon_128x128@2x.png': 256,
            'icon_256x256.png': 256,
            'icon_256x256@2x.png': 512,
            'icon_512x512.png': 512,
            'icon_512x512@2x.png': 1024,
        }

        print("Generating icon sizes with sips...")
        for name, size in sizes.items():
            out = os.path.join(iconset_dir, name)
            subprocess.run(
                ['sips', '-z', str(size), str(size), png_path, '--out', out],
                capture_output=True, check=True
            )

        print("Creating .icns with iconutil...")
        subprocess.run(
            ['iconutil', '-c', 'icns', iconset_dir, '-o', icns_path],
            capture_output=True, check=True
        )
        print(f"ICNS saved: {icns_path}")

    # --- Copy to app bundle ---
    app_icon_dest = os.path.join(project_dir, 'AIIsland.app', 'Contents', 'Resources', 'AppIcon.icns')
    if os.path.isdir(os.path.dirname(app_icon_dest)):
        shutil.copy2(icns_path, app_icon_dest)
        print(f"Copied to app bundle: {app_icon_dest}")
    else:
        print(f"Warning: App bundle not found at expected path, skipping copy")

    print("Done!")


if __name__ == '__main__':
    main()
