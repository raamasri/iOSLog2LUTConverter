#!/usr/bin/env python3
"""Generate a tiny deterministic, high-precision H.264 High4:2:2 10-bit neutral ramp.

This is a test fixture only. FFmpeg/libx264 runs on the development Mac; no
encoder or GPL component is linked into the app's minimal LGPL decoder.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=Path,default=Path('build/validation/precision'))
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
video=a.output/'neutral-ramp-10bit-high422.mp4'
command=['ffmpeg','-hide_banner','-loglevel','error','-f','lavfi','-i',
         "nullsrc=s=1024x64:r=30,format=yuv422p10le,geq=lum='64+876*X/(W-1)':cb=512:cr=512",
         '-frames:v','30','-an','-c:v','libx264','-profile:v','high422','-qp','1','-preset','medium',
         '-pix_fmt','yuv422p10le','-color_range','tv','-colorspace','bt709','-color_primaries','bt709','-color_trc','bt709',
         '-fps_mode','passthrough','-y',str(video)]
subprocess.run(command,check=True)
probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(video)]))
import array
raw=subprocess.check_output(['ffmpeg','-hide_banner','-loglevel','error','-i',str(video),'-frames:v','1','-pix_fmt','yuv422p10le','-f','rawvideo','-'])
luma=array.array('H');luma.frombytes(raw[:1024*64*2])
unique_luma=len(set(luma))
if unique_luma <= 700: raise RuntimeError(f'Fixture lost intended precision: {unique_luma} luma levels')
manifest={'decoded_unique_luma_levels':unique_luma,'decoded_luma_minmax':[min(luma),max(luma)],'sha256':hashlib.file_digest(video.open('rb'),'sha256').hexdigest(),'generation_command':command,
          'encoding_note':'libx264 rejects QP0 lossless with the High4:2:2 profile (requires High4:4:4 Predictive); QP1 keeps the required High4:2:2 profile, and decodedluma cardinality is verified separately.',
          'fixture_intent':'1024 horizontal grayscale samples spanning codeY64..940, neutralU/V512, limitedrange10bit, 30identicalframes. 877distinct luma codes before RGBconversion.',
          'probe':probe}
(a.output/'fixture-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(video.resolve())
