#!/usr/bin/env python3
"""Compare production LUTProcessor diagnostic frames/exports with independent LUT math.

Run validate_media.py first to produce original FFmpeg endpoint references.
The host harness must use the actual product sources, emit raw-frameN.png,
primary-only-frameN.png, primary-m31-{0,35,100}-frameN.png and complete
sony-primary-m31-47-{low,medium,high,maximum}.mp4 exports. Diagnostic names
are labels: compare each PNG against its own raw input to avoid seek ambiguity.
"""
from pathlib import Path
import argparse
import json
from PIL import Image
import validate_media as v


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('source_directory', type=Path)
    p.add_argument('--processor-directory', type=Path, required=True)
    p.add_argument('--diagnostic-directory', type=Path)
    p.add_argument('--reference-directory', type=Path, required=True)
    p.add_argument('--export-file', action='append', default=[], metavar='QUALITY=PATH', help='Compare explicit completed exports instead of the host harness naming convention.')
    p.add_argument('--skip-diagnostics', action='store_true')
    p.add_argument('--manifest-name', default='app-validation.json')
    args = p.parse_args()
    root = args.source_directory.resolve()
    exports = args.processor_directory.resolve()
    diagnostics = (args.diagnostic_directory or args.processor_directory).resolve()
    out = args.reference_directory.resolve()
    if root == out or root in out.parents:
        p.error('References/output must be outside supplied source folder.')
    primary = root/'1_SGamut3CineSLog3_To_LC-709.cube'
    secondary = root/'M31 - Rec.709.cube'
    manifest = {'processor_directory': str(exports), 'diagnostic_directory': str(diagnostics),
                'method': 'RGB8 byte comparisons at960x540 after Lanczos reduction; FFmpeg trilinear in16bit RGB. LUT correctness checked against same decoded raw PNG, independent of metadata interpretation or seek rounding. Export comparisons against original decoded frame indices with709/full input and709/limited output.',
                'diagnostic_frames': [], 'exports': []}
    def image(path):
        return Image.open(path).convert('RGB').resize(v.SIZE, Image.Resampling.LANCZOS)
    for frame in (() if args.skip_diagnostics else (0,60)):
        raw = diagnostics/f'raw-frame{frame}.png'
        record = {'diagnostic_label': frame, 'processing_comparisons': []}
        for label, second in [('primary',None),('m31',secondary)]:
            ref = out/f'appraw_ffmpeg_{label}_f{frame}.png'
            v.grade(raw,primary,second,ref)
            actual_path = diagnostics/(f'primary-only-frame{frame}.png' if label=='primary' else f'primary-m31-100-frame{frame}.png')
            record['processing_comparisons'].append({'stage':label, **v.metrics(image(actual_path),image(ref))})
        base = image(diagnostics/f'primary-m31-0-frame{frame}.png')
        creative = image(diagnostics/f'primary-m31-100-frame{frame}.png')
        actual = image(diagnostics/f'primary-m31-35-frame{frame}.png')
        record['processing_comparisons'].append({'stage':'35percent_vs_linear_own_endpoints', **v.metrics(actual,Image.blend(base,creative,.35))})
        record['processing_comparisons'].append({'stage':'0percent_vs_primary_only', **v.metrics(base,image(diagnostics/f'primary-only-frame{frame}.png'))})
        record['png_metadata'] = {k:str(value) for k,value in Image.open(raw).info.items() if k!='exif'}
        manifest['diagnostic_frames'].append(record)
    original = next(path for path in root.iterdir() if 'original' in path.name.lower() and path.suffix.lower()=='.mp4')
    original_audio = v.read_audio(original)
    if args.export_file:
        inputs = []
        for item in args.export_file:
            quality, path = item.split('=', 1)
            if quality not in ('low', 'medium', 'high', 'maximum'):
                p.error('Export quality must be low, medium, high, or maximum.')
            inputs.append((quality, Path(path).resolve()))
    else:
        inputs = [(quality, exports/f'sony-primary-m31-47-{quality}.mp4') for quality in ('low','medium','high','maximum')]
    for quality, path in inputs:
        record = {'quality':quality,'path':str(path),'probe':v.probe(path),'sampled_frames':[]}
        for frame in v.FRAMES:
            actual_path = out/f'app_{exports.name}_{quality}_f{frame}.png'
            v.extract(path,actual_path,frame,'bt709','limited')
            expected = Image.blend(image(out/f'endpoint_bt709_primary_f{frame}.png'),image(out/f'endpoint_bt709_M31 - Rec.709_f{frame}.png'),.47)
            record['sampled_frames'].append({'decoded_frame_index':frame, **v.metrics(image(actual_path),expected)})
        record['audio'] = v.audio_comparison(original_audio,v.read_audio(path))
        try:
            v.run(['ffmpeg','-hide_banner','-loglevel','error','-xerror','-threads','2','-i',str(path),'-map','0:v:0','-map','0:a?','-f','null','-'])
            record['full_decode_passed'] = True
        except RuntimeError as error:
            record['full_decode_passed'] = False
            record['full_decode_error'] = str(error)
        manifest['exports'].append(record)
        print(quality,record['audio'],'frames',record['sampled_frames'],flush=True)
    manifest['commands'] = v.COMMANDS
    target = out/args.manifest_name
    target.write_text(json.dumps(manifest,indent=2))
    print(target)

if __name__=='__main__':main()
