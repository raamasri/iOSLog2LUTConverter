#!/usr/bin/env python3
"""Read-only media inventory and independent RGB LUT/opacity/audio checks.

Requires ffmpeg, ffprobe, and Pillow. Writes only --output, never the source
folder. Existing converted clips are observations, not golden masters: the
archived desktop implementation used overlay instead of normal opacity.

Example:
  python3 scripts/validation/validate_media.py /path/to/lutconvertertest \
    --output build/validation/media
"""
from __future__ import annotations
import argparse
import array
import concurrent.futures
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
from PIL import Image, ImageChops, ImageStat

FRAMES = [0, 60, 150]
FPS = 30000 / 1001
SIZE = (960, 540)
COMMANDS: list[list[str]] = []


def run(command: list[str], binary: bool = False) -> str | bytes:
    COMMANDS.append(command)
    result = subprocess.run(command, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(f"Command failed: {command!r}\n{result.stderr.decode(errors='replace')[-4000:]}")
    return result.stdout if binary else result.stdout.decode()


def probe(path: Path) -> dict:
    data = json.loads(run(['ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(path)]))
    data['file'] = path.name
    data['sha256'] = hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()
    data['role'] = 'original_log_source' if 'original' in path.name.lower() else 'existing_conversion_not_golden'
    return data


def cube(path: Path) -> dict:
    size = None
    rows = []
    domain = {}
    for line in path.read_text().splitlines():
        parts = line.split('#', 1)[0].split()
        if not parts:
            continue
        if parts[0] == 'LUT_3D_SIZE':
            size = int(parts[1])
        elif parts[0] in ('DOMAIN_MIN', 'DOMAIN_MAX'):
            domain[parts[0]] = [float(p) for p in parts[1:]]
        elif len(parts) == 3:
            try:
                rows.append([float(p) for p in parts])
            except ValueError:
                pass
    return {'file': path.name, 'sha256': hashlib.file_digest(path.open('rb'), 'sha256').hexdigest(),
            'dimension': size, 'rows': len(rows), 'cardinality_valid': size is not None and len(rows) == size ** 3,
            'finite': all(math.isfinite(v) for row in rows for v in row), 'domain': domain,
            'output_min': [min(row[c] for row in rows) for c in range(3)],
            'output_max': [max(row[c] for row in rows) for c in range(3)]}


def ffmpeg_filter_path(path: Path) -> str:
    return str(path).replace('\\', '\\\\').replace(':', '\\:').replace("'", "'\\''")


def extract(path: Path, output: Path, frame: int, matrix: str = 'bt601', value_range: str = 'full', native: bool = False) -> None:
    # Select by decoded frame index, avoiding seek/keyframe ambiguity.
    vf = f"select=eq(n\\,{frame}),scale=in_color_matrix={matrix}:in_range={value_range}:out_range=full"
    if not native:
        vf += f",scale={SIZE[0]}:{SIZE[1]}:flags=lanczos"
    vf += ',format=rgb48be' if native else ',format=rgb24'
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-threads', '2', '-i', str(path),
         '-vf', vf, '-frames:v', '1', '-y', str(output)])


def grade(source: Path, primary: Path, secondary: Path | None, output: Path) -> None:
    vf = f"format=gbrp16le,lut3d=file='{ffmpeg_filter_path(primary)}':interp=trilinear"
    if secondary:
        vf += f",lut3d=file='{ffmpeg_filter_path(secondary)}':interp=trilinear"
    vf += f",scale={SIZE[0]}:{SIZE[1]}:flags=lanczos,format=rgb24"
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-threads', '2', '-i', str(source),
         '-vf', vf, '-frames:v', '1', '-y', str(output)])


def metrics(a: Image.Image, b: Image.Image) -> dict:
    a, b = a.convert('RGB'), b.convert('RGB')
    if a.size != b.size:
        raise ValueError(f'Image size mismatch {a.size} / {b.size}')
    diff = ImageChops.difference(a, b)
    hist = diff.histogram()
    count = a.width * a.height * 3
    mae = sum((index % 256) * n for index, n in enumerate(hist)) / count
    mse = sum((index % 256) ** 2 * n for index, n in enumerate(hist)) / count
    bins = [sum(hist[c * 256 + v] for c in range(3)) for v in range(256)]
    cumulative = 0
    p95 = 0
    for value, n in enumerate(bins):
        cumulative += n
        if cumulative >= count * 0.95:
            p95 = value
            break
    return {'mae_8bit': mae, 'rmse_8bit': math.sqrt(mse),
            'psnr_db': 10 * math.log10(255 ** 2 / mse) if mse else 999,
            'p95_absolute_error_8bit': p95,
            'mean_rgb_delta': [x-y for x,y in zip(ImageStat.Stat(a).mean, ImageStat.Stat(b).mean)]}


def read_audio(path: Path) -> array.array:
    pcm = run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-i', str(path), '-map', '0:a:0',
               '-ac', '1', '-ar', '48000', '-f', 's16le', '-'], binary=True)
    result = array.array('h')
    result.frombytes(pcm)
    return result


def audio_comparison(original: array.array, compared: array.array) -> dict:
    # Average to 1kHz for an inexpensive ±200ms offset search. One grid step=1ms.
    def downsample(samples: array.array) -> list[float]:
        return [sum(samples[i:i+48])/48 for i in range(0, len(samples)-47, 48)]
    x, y = downsample(original), downsample(compared)
    best = (-2.0, 0)
    zero = None
    for lag in range(-200, 201):
        start = max(0, -lag)
        end = min(len(x), len(y)-lag)
        a, b = x[start:end], y[start+lag:end+lag]
        n = len(a)
        if n < 500:
            continue
        ax, by = sum(a)/n, sum(b)/n
        numerator = sum((v-ax)*(w-by) for v,w in zip(a,b))
        denominator = math.sqrt(sum((v-ax)**2 for v in a)*sum((w-by)**2 for w in b))
        corr = numerator/denominator if denominator else 0
        if lag == 0:
            zero = corr
        if corr > best[0]:
            best = (corr, lag)
    return {'decoded_samples': len(compared), 'source_decoded_samples': len(original),
            'duration_delta_ms': (len(compared)-len(original))/48,
            'best_offset_ms_1ms_grid': best[1], 'correlation_at_best_offset': best[0],
            'correlation_at_zero_offset': zero,
            'offset_convention': 'positive means compared audio is delayed relative to original'}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source_directory', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--skip-decode', action='store_true')
    args = parser.parse_args()
    root, output = args.source_directory.resolve(), args.output.resolve()
    if output == root or root in output.parents:
        parser.error('Output must be outside the supplied source directory.')
    output.mkdir(parents=True, exist_ok=True)
    videos = sorted(p for p in root.iterdir() if p.suffix.lower() in ('.mp4', '.mov', '.m4v'))
    luts = sorted(root.glob('*.cube'))
    inventory = list(concurrent.futures.ThreadPoolExecutor(4).map(probe, videos))
    manifest = {'source_directory': str(root), 'sample_frame_indices': FRAMES, 'comparison_size': SIZE,
                'ffmpeg_version': run(['ffmpeg', '-version']).splitlines()[0], 'media': inventory,
                'luts': [cube(path) for path in luts], 'method': {
                    'original_color_uncertainty': 'Original has full range but no matrix/transfer/primaries tags. Compare both bt601 and bt709; no log gamma conversion is added before the supplied Sony conversion LUT.',
                    'lut_interpolation': 'FFmpeg trilinear to match CIColorCube, 16-bit planar RGB between LUTs, no transfer-function reinterpretation.',
                    'normal_opacity': '(1-opacity)*primary + opacity*creative(primary)',
                    'archived_overlay': 'Pillow overlay(primary, creative), then blend(primary, overlay, opacity); tested as historical evidence only.',
                    'metric_precision': 'RGB8 at960x540; endpoint quantization before Python blend can contribute up to1LSB. Not an HDR/10bit fidelity certificate.'}}
    (output/'inventory.json').write_text(json.dumps(manifest, indent=2))
    original = next(p for p in videos if 'original' in p.name.lower())
    primary = root/'1_SGamut3CineSLog3_To_LC-709.cube'
    secondaries = {'M31 - Rec.709': root/'M31 - Rec.709.cube', 'IWLTBAP Aspen - Standard': root/'IWLTBAP Aspen - Standard.cube',
                   'IWLTBAP Arapaho - Standard': root/'IWLTBAP Arapaho - Standard.cube'}
    endpoints = {}
    for matrix in ('bt601', 'bt709'):
        for frame in FRAMES:
            source = output/f'original_{matrix}_f{frame}.png'
            extract(original, source, frame, matrix, native=True)
            for name, lut in [('primary', None)] + list(secondaries.items()):
                target = output/f'endpoint_{matrix}_{name}_f{frame}.png'
                grade(source, primary, lut, target)
                endpoints[matrix,name,frame] = target
        print(f'Reference endpoints complete: {matrix}', flush=True)
    comparisons = []
    for converted in (p for p in videos if p != original):
        match = re.search(r'_converted_(.+)_(\d+)percent', converted.stem)
        if not match:
            continue
        name, opacity = match[1], int(match[2])/100
        item = {'file': converted.name, 'filename_lut': name, 'filename_opacity': opacity, 'comparisons': []}
        for frame in FRAMES:
            for decoded_range in ('full', 'limited'):
                for matrix in ('bt601', 'bt709'):
                    actual_path = output/f'existing_{converted.stem}_{matrix}_{decoded_range}_f{frame}.png'
                    extract(converted, actual_path, frame, matrix, decoded_range)
                    actual = Image.open(actual_path).convert('RGB')
                    base = Image.open(endpoints[matrix,'primary',frame]).convert('RGB')
                    creative = Image.open(endpoints[matrix,name,frame]).convert('RGB')
                    for mode in ('normal', 'archived_overlay'):
                        end = creative if mode == 'normal' else ImageChops.overlay(base, creative)
                        expected = Image.blend(base, end, opacity)
                        item['comparisons'].append({'frame': frame, 'matrix': matrix, 'decoded_range': decoded_range,
                                                    'blend': mode, **metrics(actual, expected)})
        grouped = {}
        for row in item['comparisons']:
            key = (row['matrix'], row['decoded_range'], row['blend'])
            grouped.setdefault(key, []).append(row['mae_8bit'])
        item['mean_mae_by_interpretation'] = [{'matrix': k[0], 'decoded_range': k[1], 'blend': k[2],
                                             'mae_8bit': sum(v)/len(v)} for k,v in grouped.items()]
        item['mean_mae_by_interpretation'].sort(key=lambda row: row['mae_8bit'])
        comparisons.append(item)
        print(f'Existing reference scored: {converted.name}: {item["mean_mae_by_interpretation"][0]}', flush=True)
    manifest['existing_conversion_comparisons'] = comparisons
    original_audio = read_audio(original)
    manifest['audio_comparisons'] = []
    for media, path in zip(inventory, videos):
        if path == original:
            continue
        if any(s['codec_type']=='audio' for s in media['streams']):
            result = audio_comparison(original_audio, read_audio(path))
        else:
            result = {'error': 'No audio stream; original contains stereo audio.'}
        manifest['audio_comparisons'].append({'file': path.name, **result})
    if not args.skip_decode:
        manifest['full_decode'] = []
        for path in videos:
            try:
                run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-xerror', '-threads', '2', '-i', str(path),
                     '-map', '0:v:0', '-map', '0:a?', '-f', 'null', '-'])
                result = {'file': path.name, 'passed': True}
            except RuntimeError as error:
                result = {'file': path.name, 'passed': False, 'error': str(error)}
            manifest['full_decode'].append(result)
            print(f'Decode: {path.name}: {result["passed"]}', flush=True)
    manifest['commands'] = COMMANDS
    (output/'manifest.json').write_text(json.dumps(manifest, indent=2))
    print(output/'manifest.json', flush=True)

if __name__ == '__main__':
    main()
