#!/usr/bin/env python3
"""Import only Track00..98.ogg from the RRU music ZIP into the native cache.
Never installs the archive's Windows DLLs or modifies an original game folder.
"""
import argparse
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tempfile
import zipfile

DEFAULT_DEST = Path.home() / 'Library/Application Support/RockRaidersNativeMenu/ConvertedMedia/Music'


def import_music(archive, destination=DEFAULT_DEST, ffmpeg='ffmpeg'):
    executable = shutil.which(ffmpeg)
    if not executable:
        raise ValueError('FFmpeg is required: brew install ffmpeg')
    destination = Path(destination)
    with zipfile.ZipFile(archive) as z:
        entries = []
        names = set()
        for info in z.infolist():
            name = PurePosixPath(info.filename.replace('\\', '/')).name
            match = re.fullmatch(r'Track(\d{2})\.ogg', name, re.I)
            if not match or int(match[1]) > 98:
                continue
            canonical = f'Track{match[1]}'
            if canonical in names:
                raise ValueError(f'Duplicate track: {canonical}')
            if not 0 < info.file_size <= 50_000_000:
                raise ValueError(f'Track is empty or too large: {canonical}')
            names.add(canonical)
            entries.append((info, canonical))
        if not entries or len(entries) > 99 or sum(i.file_size for i, _ in entries) > 500_000_000:
            raise ValueError('ZIP must contain a bounded collection of Track00..98.ogg files')
        # Decode all tracks before publishing any output. Temporary files use
        # canonical basenames, never archive-controlled extraction paths.
        destination.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.music-import-', dir=destination) as work:
            work = Path(work)
            staged = []
            for info, name in sorted(entries, key=lambda entry: entry[1]):
                target = destination / (name + '.m4a')
                if target.exists():
                    print(f'Keeping existing {target.name}')
                    continue
                source = work / (name + '.ogg')
                source.write_bytes(z.read(info))
                converted = work / (name + '.m4a')
                subprocess.run([executable, '-nostdin', '-n', '-hide_banner', '-loglevel', 'error',
                                '-i', str(source), '-map', '0:a:0', '-vn', '-c:a', 'aac', '-b:a', '192k',
                                str(converted)], check=True)
                if not converted.is_file() or converted.stat().st_size == 0:
                    raise ValueError(f'No converted audio for {name}')
                staged.append((converted, target))
            for converted, target in staged:
                # Atomic publication without overwriting an existing track.
                try:
                    os.link(converted, target)
                except FileExistsError:
                    print(f'Keeping existing {target.name}')
            print(f'Mission music ready in {destination}. Return to the menu and reopen the mission.')
            return len(staged)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('zip', type=Path)
    parser.add_argument('--destination', type=Path, default=DEFAULT_DEST)
    args = parser.parse_args()
    try:
        import_music(args.zip, args.destination)
    except (ValueError, OSError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Music import failed: {error}\n')


if __name__ == '__main__':
    main()
