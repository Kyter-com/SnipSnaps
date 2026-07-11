#!/usr/bin/env python3
"""Stamp EXIF GPS coordinates onto specific seed photos so they import into the
sim's Photos library with a location.

A location is what lights up the "Location" map in the app's photo-details sheet
(PhotoMetadataSheet renders the map only when `asset.location` is non-nil). The
Today review lands on the 3rd photo (alley/beach/boat, newest-first) when the
details shot is taken, so those three carry plausible coordinates; boat.jpg is
the one actually shown in the "04-details" marketing screenshot.

simctl addmedia carries embedded EXIF into PHAsset the same way it does the
capture date, and refresh-seed-dates.py preserves this GPS block on every run
(it only rewrites the date fields), so a one-time stamp survives future runs.

Usage:
    seed-locations.py <seed-dir>
"""
from __future__ import annotations

import glob
import os
import sys

try:
    import piexif
except ImportError:
    print("error: install piexif first: pip3 install --user --break-system-packages piexif", file=sys.stderr)
    sys.exit(1)

# filename (in seed-dir) -> (latitude, longitude). Chosen to suit each photo's
# subject and to render a pleasant ~1.5km map thumbnail (the sheet's span).
LOCATIONS = {
    "boat.jpg": (36.6045, -121.8912),   # Monterey harbor, CA — shown in 04-details
    "beach.jpg": (34.0100, -118.4960),  # Santa Monica beach, CA
    "alley.jpg": (37.7946, -122.4062),  # downtown San Francisco, CA
}


def _dms(dec: float):
    """Decimal degrees -> EXIF ((deg,1),(min,1),(sec*10000,10000)) rationals."""
    dec = abs(dec)
    d = int(dec)
    m = int((dec - d) * 60)
    s = round((dec - d - m / 60) * 3600, 4)
    return ((d, 1), (m, 1), (int(s * 10000), 10000))


def stamp(path: str, lat: float, lon: float) -> None:
    try:
        exif = piexif.load(path)
    except Exception:
        exif = {"0th": {}, "Exif": {}, "GPS": {}, "1st": {}, "thumbnail": None}
    exif["GPS"] = {
        piexif.GPSIFD.GPSVersionID: (2, 3, 0, 0),
        piexif.GPSIFD.GPSLatitudeRef: "N" if lat >= 0 else "S",
        piexif.GPSIFD.GPSLatitude: _dms(lat),
        piexif.GPSIFD.GPSLongitudeRef: "E" if lon >= 0 else "W",
        piexif.GPSIFD.GPSLongitude: _dms(lon),
    }
    piexif.insert(piexif.dump(exif), path)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    seed_dir = sys.argv[1]
    stamped = 0
    for name, (lat, lon) in LOCATIONS.items():
        path = os.path.join(seed_dir, name)
        if not os.path.exists(path):
            print(f"skip (missing): {name}", file=sys.stderr)
            continue
        stamp(path, lat, lon)
        stamped += 1
    print(f"stamped GPS on {stamped}/{len(LOCATIONS)} seed photos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
