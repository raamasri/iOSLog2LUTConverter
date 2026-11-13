#!/usr/bin/env python3
"""Compare decoded native 10-bit ramp luma against source and ideal signal.

No RGB conversion is used for these measurements. FFmpeg only decodes planar
10-bit YUV; this catches range errors independently of an RGB scaler oracle.
"""
import argparse
import array
import hashlib
import json
import math
from pathlib import Path
import subprocess

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('source',type=Path);p.add_argument('output_video',type=Path)
p.add_argument('--output',type=Path,required=True);a=p.parse_args()
commands=[]
def decoded(path):
 command=['ffmpeg','-hide_banner','-loglevel','error','-i',str(path),'-frames:v','1','-pix_fmt','yuv420p10le','-f','rawvideo','-']
 commands.append(command);data=subprocess.check_output(command)
 values=array.array('H');values.frombytes(data[:1024*64*2]);return list(values)
def compare(actual,expected):
 delta=[x-y for x,y in zip(actual,expected)];mse=sum(x*x for x in delta)/len(delta)
 return {'signed_mean_code_error':sum(delta)/len(delta),'mean_absolute_code_error':sum(abs(x)for x in delta)/len(delta),
         'maximum_absolute_code_error':max(abs(x)for x in delta),'rmse_codes':math.sqrt(mse),
         'psnr_peak1023_db':10*math.log10(1023**2/mse) if mse else 999,
         'psnr_nominal_signal876_db':10*math.log10(876**2/mse) if mse else 999,
         'minimum':min(actual),'maximum':max(actual),'unique_levels':len(set(actual))}
source=decoded(a.source);actual=decoded(a.output_video)
ideal=[64+int(876*x/1023)for y in range(64)for x in range(1024)]
manifest={'source':str(a.source.resolve()),'output':str(a.output_video.resolve()),
          'source_sha256':hashlib.file_digest(a.source.open('rb'),'sha256').hexdigest(),
          'output_sha256':hashlib.file_digest(a.output_video.open('rb'),'sha256').hexdigest(),
          'source_against_ideal':compare(source,ideal),'output_against_source':compare(actual,source),
          'output_against_ideal':compare(actual,ideal),
          'middle_row_against_source':compare(actual[32*1024:33*1024],source[32*1024:33*1024]),
          'per_x_middle_row':[{'x':x,'source':source[32*1024+x],'output':actual[32*1024+x],
                              'signed_error':actual[32*1024+x]-source[32*1024+x]}for x in range(1024)],'commands':commands}
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest['output_against_source'],indent=2))
