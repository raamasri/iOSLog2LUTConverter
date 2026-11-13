#!/usr/bin/env python3
"""Copy supplied media into an installed Simulator app without altering the source."""
import argparse
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("device", help="Booted Simulator UUID")
    parser.add_argument("--bundle-id", default="raamblings.iOSLOG2LUTConverter")
    parser.add_argument("--photos", action="store_true", help="Also seed the original and one converted sample in Photos")
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    if not source.is_dir():
        parser.error("source must be a directory")
    result = subprocess.run(["xcrun", "simctl", "get_app_container", args.device, args.bundle_id, "data"], check=True, text=True, capture_output=True)
    container = Path(result.stdout.strip()).resolve(strict=True)
    destination = container / "Documents" / "RealMediaFixtures"
    destination.mkdir(parents=True, exist_ok=True)
    files = sorted(p for p in source.iterdir() if p.is_file() and p.suffix.lower() in {".mp4", ".mov", ".cube"})
    if not files:
        parser.error("source contains no MP4, MOV, or cube fixtures")
    for path in files:
        target = destination / path.name
        if target.exists():
            if target.stat().st_size != path.stat().st_size:
                raise RuntimeError(f"Existing fixture differs in size; remove that test copy and retry: {target}")
            continue
        # APFS clone is cheap and independent; other filesystems use a normal copy.
        result = subprocess.run(["cp", "-c", str(path), str(target)], capture_output=True)
        if result.returncode:
            shutil.copy2(path, target)
    if args.photos:
        photos = [source / "rsiv5362 ORIGINAL SLOG3CINE.MP4", source / "rsiv5362_converted_M31 - Rec.709_47percent.mp4"]
        missing = [str(p) for p in photos if not p.is_file()]
        if missing:
            raise FileNotFoundError(", ".join(missing))
        subprocess.run(["xcrun", "simctl", "addmedia", args.device, *(str(p) for p in photos)], check=True)
    print(f"Staged {len(files)} fixtures in {destination}")


if __name__ == "__main__":
    main()
