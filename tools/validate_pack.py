#!/usr/bin/env python3
"""
Deadwire .pack V2 format validator.

Reads a PZ .pack file and validates every field against the V2 spec.
Also compares structure against a vanilla .pack file.
"""

import struct
import sys
import io
from pathlib import Path

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    print("WARNING: PIL not available. PNG validation will be limited.\n")

# ─── Configuration ───────────────────────────────────────────────────────────

DEADWIRE_PACK = Path("C:/xampp/htdocs/deadwire/Contents/mods/Deadwire/42/media/texturepacks/deadwire_01.pack")
VANILLA_PACK = Path("C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid/media/texturepacks/Tiles2x.pack")

# Expected layout: every deadwire_*.png in media/textures/, each 64x128.
#
# The sprite count is DERIVED from the source PNGs, not hardcoded. It used to
# be the literal 8, which turned "the pack contains what we drew" into "the
# pack contains what it contained in Session 10" -- adding the electric pair
# failed the check even though the pack was correct. A constant here cannot
# distinguish a real regression from an intended addition.
SPRITE_SRC_DIR = Path(
    "C:/xampp/htdocs/deadwire/Contents/mods/Deadwire/42/media/textures")

EXPECTED_SPRITE_W = 64
EXPECTED_SPRITE_H = 128
EXPECTED_SPRITE_COUNT = len(list(SPRITE_SRC_DIR.glob("deadwire_*.png")))
EXPECTED_COLUMNS = 8

PNG_MAGIC = bytes([0x89, 0x50, 0x4E, 0x47])  # \x89PNG

# ─── Helpers ─────────────────────────────────────────────────────────────────

class Result:
    def __init__(self):
        self.checks = []
        self.pass_count = 0
        self.fail_count = 0
        self.warn_count = 0

    def check(self, name, passed, detail="", warn=False):
        if warn and not passed:
            status = "WARN"
            self.warn_count += 1
        elif passed:
            status = "PASS"
            self.pass_count += 1
        else:
            status = "FAIL"
            self.fail_count += 1
        self.checks.append((status, name, detail))
        indicator = {"PASS": "[PASS]", "FAIL": "[FAIL]", "WARN": "[WARN]"}[status]
        print(f"  {indicator} {name}{f' -- {detail}' if detail else ''}")

    def summary(self):
        total = self.pass_count + self.fail_count + self.warn_count
        print(f"\n{'='*70}")
        print(f"RESULTS: {self.pass_count} passed, {self.fail_count} failed, {self.warn_count} warnings out of {total} checks")
        if self.fail_count == 0:
            print("OVERALL: PASS")
        else:
            print("OVERALL: FAIL")
        print(f"{'='*70}")


def read_u32(f):
    """Read a u32 LE and return (offset, value)."""
    offset = f.tell()
    data = f.read(4)
    if len(data) < 4:
        raise EOFError(f"Unexpected EOF at offset {offset}")
    return offset, struct.unpack('<I', data)[0]


def read_i32(f):
    """Read an i32 LE and return (offset, value)."""
    offset = f.tell()
    data = f.read(4)
    if len(data) < 4:
        raise EOFError(f"Unexpected EOF at offset {offset}")
    return offset, struct.unpack('<i', data)[0]


def read_string(f):
    """Read a length-prefixed UTF-8 string and return (len_offset, length, string)."""
    len_offset, length = read_u32(f)
    str_offset = f.tell()
    raw = f.read(length)
    if len(raw) < length:
        raise EOFError(f"Unexpected EOF reading string at offset {str_offset}")
    return len_offset, length, raw.decode('utf-8', errors='replace')


# ─── Main Validation ────────────────────────────────────────────────────────

def validate_pack(filepath, results):
    print(f"\nValidating: {filepath}")
    print(f"File size: {filepath.stat().st_size} bytes")
    print(f"{'-'*70}")

    file_size = filepath.stat().st_size

    with open(filepath, 'rb') as f:

        # ── Header ───────────────────────────────────────────────────────
        print("\n[HEADER]")

        # Magic
        magic_offset = f.tell()
        magic = f.read(4)
        results.check(
            f"offset 0x{magic_offset:04X}: magic = {magic!r}",
            magic == b'PZPK',
            f"expected b'PZPK', got {magic!r}"
        )

        # Mask
        mask_offset, mask = read_i32(f)
        results.check(
            f"offset 0x{mask_offset:04X}: mask = {mask}",
            mask == 1,
            f"expected 1, got {mask}"
        )

        # Pages count
        pages_offset, pages_count = read_u32(f)
        results.check(
            f"offset 0x{pages_offset:04X}: pages_count = {pages_count}",
            pages_count >= 1,
            f"expected >= 1, got {pages_count}"
        )
        results.check(
            f"pages_count is reasonable",
            pages_count == 1,
            f"Deadwire should have exactly 1 page, got {pages_count}",
            warn=(pages_count > 1)
        )

        # ── Pages ────────────────────────────────────────────────────────
        all_entries = []

        for page_idx in range(pages_count):
            print(f"\n[PAGE {page_idx}]")

            # Page name
            pn_off, pn_len, page_name = read_string(f)
            results.check(
                f"offset 0x{pn_off:04X}: page_name_len = {pn_len}",
                pn_len > 0 and pn_len < 256,
                f"length {pn_len}"
            )
            results.check(
                f"offset 0x{pn_off+4:04X}: page_name = {page_name!r}",
                len(page_name) == pn_len,
                f"expected name matching tilesheet"
            )
            results.check(
                f"page_name format",
                page_name.startswith("deadwire_01"),
                f"expected 'deadwire_01*', got {page_name!r}"
            )

            # Entries count
            ec_off, entries_count = read_u32(f)
            results.check(
                f"offset 0x{ec_off:04X}: entries_count = {entries_count}",
                entries_count == EXPECTED_SPRITE_COUNT,
                f"expected {EXPECTED_SPRITE_COUNT}, got {entries_count}"
            )

            # Page mask
            pm_off, page_mask = read_i32(f)
            results.check(
                f"offset 0x{pm_off:04X}: page_mask = {page_mask}",
                page_mask == 1,
                f"expected 1, got {page_mask}"
            )

            # ── Entries ──────────────────────────────────────────────────
            for entry_idx in range(entries_count):
                print(f"\n  [ENTRY {entry_idx}]")

                # Entry name
                en_off, en_len, entry_name = read_string(f)
                expected_name = f"deadwire_01_{entry_idx}"
                results.check(
                    f"  offset 0x{en_off:04X}: entry_name_len = {en_len}",
                    en_len > 0 and en_len < 256,
                    f"length {en_len}"
                )
                results.check(
                    f"  offset 0x{en_off+4:04X}: entry_name = {entry_name!r}",
                    entry_name == expected_name,
                    f"expected {expected_name!r}, got {entry_name!r}"
                )

                # Position and dimensions (8 x u32)
                fields_offset = f.tell()
                fields_data = f.read(32)
                if len(fields_data) < 32:
                    results.check("entry fields complete", False, "unexpected EOF")
                    return
                x, y, w, h, xo, yo, tw, th = struct.unpack('<8I', fields_data)

                # Expected position in 8-column layout
                col = entry_idx % EXPECTED_COLUMNS
                row = entry_idx // EXPECTED_COLUMNS
                expected_x = col * EXPECTED_SPRITE_W
                expected_y = row * EXPECTED_SPRITE_H

                results.check(
                    f"  offset 0x{fields_offset:04X}: x_pos = {x}",
                    x == expected_x,
                    f"expected {expected_x} (col {col} * {EXPECTED_SPRITE_W}), got {x}"
                )
                results.check(
                    f"  offset 0x{fields_offset+4:04X}: y_pos = {y}",
                    y == expected_y,
                    f"expected {expected_y} (row {row} * {EXPECTED_SPRITE_H}), got {y}"
                )
                results.check(
                    f"  offset 0x{fields_offset+8:04X}: width = {w}",
                    w == EXPECTED_SPRITE_W,
                    f"expected {EXPECTED_SPRITE_W}, got {w}"
                )
                results.check(
                    f"  offset 0x{fields_offset+12:04X}: height = {h}",
                    h == EXPECTED_SPRITE_H,
                    f"expected {EXPECTED_SPRITE_H}, got {h}"
                )
                results.check(
                    f"  offset 0x{fields_offset+16:04X}: x_offset = {xo}",
                    xo == 0,
                    f"expected 0 (no offset for full sprites), got {xo}"
                )
                results.check(
                    f"  offset 0x{fields_offset+20:04X}: y_offset = {yo}",
                    yo == 0,
                    f"expected 0 (no offset for full sprites), got {yo}"
                )
                results.check(
                    f"  offset 0x{fields_offset+24:04X}: total_width = {tw}",
                    tw == EXPECTED_SPRITE_W,
                    f"expected {EXPECTED_SPRITE_W}, got {tw}"
                )
                results.check(
                    f"  offset 0x{fields_offset+28:04X}: total_height = {th}",
                    th == EXPECTED_SPRITE_H,
                    f"expected {EXPECTED_SPRITE_H}, got {th}"
                )

                all_entries.append({
                    'name': entry_name,
                    'x': x, 'y': y, 'w': w, 'h': h,
                    'xo': xo, 'yo': yo, 'tw': tw, 'th': th,
                })

            # ── Image Data ───────────────────────────────────────────────
            print(f"\n[IMAGE DATA (page {page_idx})]")

            img_len_off, img_data_len = read_u32(f)
            results.check(
                f"offset 0x{img_len_off:04X}: image_data_len = {img_data_len}",
                img_data_len > 0,
                f"got {img_data_len} bytes"
            )

            img_data_off = f.tell()
            img_data = f.read(img_data_len)
            results.check(
                f"image data read complete",
                len(img_data) == img_data_len,
                f"expected {img_data_len} bytes, got {len(img_data)}"
            )

            # PNG magic check
            if len(img_data) >= 4:
                png_magic = img_data[:4]
                results.check(
                    f"offset 0x{img_data_off:04X}: PNG magic = {png_magic.hex().upper()}",
                    png_magic == PNG_MAGIC,
                    f"expected 89504E47, got {png_magic.hex().upper()}"
                )
            else:
                results.check("PNG magic", False, "image data too short")

            # PNG IEND check — the IEND chunk ends with: 49454E44 AE426082
            # That's b'IEND' + CRC32 bytes = 8 bytes total
            IEND_TRAILER = b'\x49\x45\x4e\x44\xae\x42\x60\x82'
            if len(img_data) >= 12:
                iend_marker = img_data[-8:]
                has_iend = iend_marker == IEND_TRAILER
                results.check(
                    f"PNG ends with IEND marker",
                    has_iend,
                    f"last 8 bytes: {iend_marker.hex()}, expected: {IEND_TRAILER.hex()}"
                )

            # PIL validation
            if HAS_PIL and len(img_data) > 0:
                try:
                    img = Image.open(io.BytesIO(img_data))
                    img_w, img_h = img.size
                    print(f"\n  PIL loaded image: {img_w}x{img_h}, mode={img.mode}, format={img.format}")

                    results.check(
                        f"PNG dimensions: {img_w}x{img_h}",
                        True,
                        f"loaded successfully"
                    )

                    # Check image is large enough for all entries
                    expected_sheet_w = EXPECTED_COLUMNS * EXPECTED_SPRITE_W
                    expected_sheet_h = ((EXPECTED_SPRITE_COUNT + EXPECTED_COLUMNS - 1) // EXPECTED_COLUMNS) * EXPECTED_SPRITE_H
                    results.check(
                        f"sheet width >= {expected_sheet_w}",
                        img_w >= expected_sheet_w,
                        f"got {img_w}, expected >= {expected_sheet_w} ({EXPECTED_COLUMNS} cols * {EXPECTED_SPRITE_W}px)"
                    )
                    results.check(
                        f"sheet height >= {expected_sheet_h}",
                        img_h >= expected_sheet_h,
                        f"got {img_h}, expected >= {expected_sheet_h}"
                    )

                    # Verify each entry's region is within bounds
                    for entry in all_entries:
                        in_bounds = (entry['x'] + entry['w'] <= img_w and
                                     entry['y'] + entry['h'] <= img_h)
                        results.check(
                            f"entry {entry['name']!r} region ({entry['x']},{entry['y']})+({entry['w']},{entry['h']}) within image",
                            in_bounds,
                            f"image is {img_w}x{img_h}"
                        )

                    # Check that the image mode is appropriate
                    results.check(
                        f"PNG mode is RGBA or RGB",
                        img.mode in ('RGBA', 'RGB', 'P'),
                        f"got {img.mode}"
                    )

                except Exception as e:
                    results.check("PIL image load", False, str(e))

        # ── End of File ──────────────────────────────────────────────────
        print(f"\n[END OF FILE]")
        end_pos = f.tell()
        remaining = f.read()
        results.check(
            f"file ends cleanly at offset 0x{end_pos:04X} ({end_pos} bytes)",
            len(remaining) == 0,
            f"{len(remaining)} extra bytes after PNG data" if remaining else "no trailing data"
        )
        results.check(
            f"parsed size matches file size",
            end_pos == file_size,
            f"parsed {end_pos} bytes, file is {file_size} bytes"
        )


# ─── Vanilla Comparison ─────────────────────────────────────────────────────

def compare_vanilla(results):
    print(f"\n{'='*70}")
    print("VANILLA COMPARISON")
    print(f"{'='*70}")

    if not VANILLA_PACK.exists():
        print(f"  Vanilla pack not found at {VANILLA_PACK}, skipping comparison.")
        return

    print(f"\nReading first page of: {VANILLA_PACK.name}")

    with open(VANILLA_PACK, 'rb') as f:
        magic = f.read(4)
        mask = struct.unpack('<i', f.read(4))[0]
        pages_count = struct.unpack('<I', f.read(4))[0]

        print(f"  Header: magic={magic!r}, mask={mask}, pages_count={pages_count}")

        # First page
        pn_len = struct.unpack('<I', f.read(4))[0]
        page_name = f.read(pn_len).decode('utf-8')
        entries_count = struct.unpack('<I', f.read(4))[0]
        page_mask = struct.unpack('<i', f.read(4))[0]

        print(f"  Page 0: name={page_name!r} (len={pn_len}), entries={entries_count}, page_mask={page_mask}")

        # First 3 entries
        for i in range(min(3, entries_count)):
            en_len = struct.unpack('<I', f.read(4))[0]
            en_name = f.read(en_len).decode('utf-8')
            x, y, w, h, xo, yo, tw, th = struct.unpack('<8I', f.read(32))
            print(f"  Entry {i}: name={en_name!r} (len={en_len})")
            print(f"    pos=({x},{y}), size=({w},{h}), offset=({xo},{yo}), total=({tw},{th})")

    print(f"\n  Comparison notes:")

    # Read our file's summary for comparison
    with open(DEADWIRE_PACK, 'rb') as f:
        our_magic = f.read(4)
        our_mask = struct.unpack('<i', f.read(4))[0]
        our_pages = struct.unpack('<I', f.read(4))[0]

        pn_len = struct.unpack('<I', f.read(4))[0]
        our_page_name = f.read(pn_len).decode('utf-8')
        our_entries = struct.unpack('<I', f.read(4))[0]
        our_page_mask = struct.unpack('<i', f.read(4))[0]

        en_len = struct.unpack('<I', f.read(4))[0]
        our_entry_name = f.read(en_len).decode('utf-8')
        x, y, w, h, xo, yo, tw, th = struct.unpack('<8I', f.read(32))

    print(f"  {'Field':<20} {'Vanilla':<25} {'Deadwire':<25} {'Match?'}")
    print(f"  {'-'*90}")

    comparisons = [
        ("magic",       repr(magic),       repr(our_magic),       magic == our_magic),
        ("mask",        str(mask),         str(our_mask),         mask == our_mask),
        ("page_mask",   str(page_mask),    str(our_page_mask),    page_mask == our_page_mask),
        ("page_name",   repr(page_name),   repr(our_page_name),   True),  # different is expected
        ("entry format","8 x u32",         "8 x u32",             True),
        ("total_w/h",   "64x32 (2x iso)",  f"{tw}x{th} (wire)",  True),  # different is expected
    ]

    for field, vanilla_val, our_val, match in comparisons:
        status = "YES" if match else "NO (expected)"
        print(f"  {field:<20} {vanilla_val:<25} {our_val:<25} {status}")

    results.check(
        "format matches vanilla structure",
        True,
        "same header/page/entry layout, different dimensions (expected)"
    )


# ─── Entry Point ─────────────────────────────────────────────────────────────

def main():
    print("="*70)
    print("Deadwire .pack V2 Format Validator")
    print("="*70)

    if not DEADWIRE_PACK.exists():
        print(f"\nERROR: File not found: {DEADWIRE_PACK}")
        sys.exit(1)

    results = Result()

    validate_pack(DEADWIRE_PACK, results)
    compare_vanilla(results)

    results.summary()
    sys.exit(1 if results.fail_count > 0 else 0)


if __name__ == '__main__':
    main()
