#!/usr/bin/env python3
"""Build unbiased high-precision Sony/M31 references with host libzimg + FFmpeg.

The app does not link libzimg. It is used only as an independent validation
engine (the same matrix/range engine as FFmpeg's optional zscale filter).
FFmpeg here decodes source YUV without an RGB conversion, then applies the
.cube files to zimg's float RGB. Source/input and output primaries/transfer
are equal during matrix conversion, so log signal values are not linearized.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import validate_media as v

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('source_directory',type=Path)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--zimg-prefix',type=Path,default=Path('/opt/homebrew/opt/zimg'))
a=p.parse_args();root=a.source_directory.resolve();out=a.output.resolve()
if out==root or root in out.parents:p.error('Output must be outside source directory.')
out.mkdir(parents=True,exist_ok=True)
commands=[]
def run(args):
 commands.append(args);subprocess.run(args,check=True)
converter=out/'zimg-reference'
run(['clang','-O2','-I'+str(a.zimg_prefix/'include'),'-L'+str(a.zimg_prefix/'lib'),'-lzimg',str(Path(__file__).with_name('zimg_reference.c').resolve()),'-o',str(converter)])
source=root/'rsiv5362 ORIGINAL SLOG3CINE.MP4'
primary=root/'1_SGamut3CineSLog3_To_LC-709.cube';creative=root/'M31 - Rec.709.cube'
manifest={'source':str(source),'source_sha256':hashlib.file_digest(source.open('rb'),'sha256').hexdigest(),
          'engine':'host libzimg3.0.5 (zscale engine), matrix/range only; FFmpeg trilinear .cube filters after RGB conversion',
          'input':'Native YUV42210 little-endian, fullrange, matrix709, original frame indices0/60/150',
          'transfer_and_primaries':'Equal input/output, no transfer-function or gamut conversion; Sony conversion LUT follows.',
          'legacy_swscale_note':'Legacy RGB16 swscale maps neutral limited10bit white940 to65283/65535, so it cannot be the normalization oracle.',
          'frames':[]}
for frame in v.FRAMES:
 yuv=out/f'original_f{frame}.yuv';rgb=out/f'original_f{frame}.gbrpf32le';png=out/f'original_bt709_f{frame}.png'
 run(['ffmpeg','-hide_banner','-loglevel','error','-threads','2','-i',str(source),'-vf',f'select=eq(n\\,{frame})','-frames:v','1','-pix_fmt','yuv422p10le','-f','rawvideo','-y',str(yuv)])
 run([str(converter),str(yuv),str(rgb),'3840','2160','10','1','0','1','1'])
 run(['ffmpeg','-hide_banner','-loglevel','error','-f','rawvideo','-pixel_format','gbrpf32le','-video_size','3840x2160','-i',str(rgb),'-frames:v','1','-pix_fmt','rgb48be','-y',str(png)])
 for label,lut in [('primary',None),('M31 - Rec.709',creative)]:
  v.grade(png,primary,lut,out/f'endpoint_bt709_{label}_f{frame}.png')
 manifest['frames'].append({'frame':frame,'rgb48_png':str(png),'sha256':hashlib.file_digest(png.open('rb'),'sha256').hexdigest()})
 yuv.unlink();rgb.unlink()
 print('zimg reference frame',frame,flush=True)
manifest['commands']=commands+v.COMMANDS
(out/'reference-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(out/'reference-manifest.json')
