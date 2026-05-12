#!/usr/bin/env python3
"""Set EXIF DateTimeOriginal on every seed photo to "now" so they import into
the sim's Photos library with today's creation date.

This is what makes the "Today" and "On This Day" review modes show photos
during capture runs — without it, simctl-imported photos can fall outside
the date filter the app uses.

Usage:
    refresh-seed-dates.py <seed-dir>
"""
from __future__ import annotations

import datetime
import glob
import os
import sys

try:
    import piexif
except ImportError:
    print("error: install piexif first: pip3 install --user --break-system-packages piexif", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    seed_dir = sys.argv[1]
    now = datetime.datetime.now()
    files = sorted(glob.glob(f"{seed_dir}/*.jpg"))
    if not files:
        print(f"no jpgs in {seed_dir}", file=sys.stderr)
        return 1

    for i, path in enumerate(files):
        # Stagger by 1 minute so each photo has a distinct timestamp.
        ts = now - datetime.timedelta(minutes=i)
        date_str = ts.strftime("%Y:%m:%d %H:%M:%S")
        try:
            exif = piexif.load(path)
        except Exception:
            exif = {"0th": {}, "Exif": {}, "GPS": {}, "1st": {}, "thumbnail": None}
        exif["Exif"][piexif.ExifIFD.DateTimeOriginal] = date_str.encode()
        exif["Exif"][piexif.ExifIFD.DateTimeDigitized] = date_str.encode()
        exif["0th"][piexif.ImageIFD.DateTime] = date_str.encode()
        piexif.insert(piexif.dump(exif), path)
        os.utime(path, (ts.timestamp(), ts.timestamp()))

    print(f"refreshed {len(files)} files to {now:%Y-%m-%d}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
