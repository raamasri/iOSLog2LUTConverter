#!/usr/bin/env python3
"""Read-only identity comparisons for existing converted inputs and iOS exports.

The existing clips are treated as inputs, not grade goldens. libzimg performs
matrix/range-only YUV->RGB conversion. Declared input range is honored; absent
matrix/range tags produce explicit alternative interpretations in the output.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import validate_media as v
from PIL import Image

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('source_directory',type=Path);p.add_argument('app_results_directory',type=Path)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--converter',type=Path,default=Path('build/validation/media-zimg/zimg-reference'))
a=p.parse_args();root=a.source_directory.resolve();out=a.output.resolve();app=a.app_results_directory.resolve();converter=a.converter.resolve()
if out==root or root in out.parents:p.error('Output must be outside source folder.')
out.mkdir(parents=True,exist_ok=True);commands=[]
def run(cmd):commands.append(cmd);subprocess.run(cmd,check=True)
def native_frames(path,label):
 probe=json_probe(path);stream=next(s for s in probe['streams']if s['codec_type']=='video')
 width,height=stream['width'],stream['height'];pixel=stream['pix_fmt']
 if pixel not in ('yuv420p','yuvj420p'):raise ValueError(f'Expected8bit420:{pixel}')
 raw=out/f'{label}.raw.yuv'
 run(['ffmpeg','-hide_banner','-loglevel','error','-threads','2','-i',str(path),'-vf','select=eq(n\\,0)+eq(n\\,60)+eq(n\\,150)','-fps_mode','passthrough','-frames:v','3','-pix_fmt',pixel,'-f','rawvideo','-y',str(raw)])
 size=width*height*3//2;paths={}
 with raw.open('rb')as data:
  for frame in v.FRAMES:
   native=out/f'{label}_f{frame}.yuv';chunk=data.read(size)
   if len(chunk)!=size:raise ValueError('Missing decoded sample frame')
   native.write_bytes(chunk);paths[frame]=native
 raw.unlink();return probe,stream,paths

def json_probe(path):
 return json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)]))
def rgb_frame(raw,width,height,matrix,range_name,target):
 floating=target.with_suffix('.gbrpf32le')
 run([str(converter),str(raw),str(floating),str(width),str(height),'8','1','1','1'if range_name=='full'else'0',str(matrix)])
 run(['ffmpeg','-hide_banner','-loglevel','error','-f','rawvideo','-pixel_format','gbrpf32le','-video_size',f'{width}x{height}','-i',str(floating),'-vf','scale=960:540:flags=lanczos,format=rgb24','-frames:v','1','-y',str(target)])
 floating.unlink();return Image.open(target).convert('RGB')
manifest={'method':'Existingclipsasidentityinputs;libzimgfloatmatrix/rangeonly,RGB8metrics960x540,decodedframes0/60/150. LowexportsincluderesolutionreductionandH264compression.',
          'matrix_ambiguity':'Everyuntaggedinputistestedas601and709;bestfitisobserveddecoderbehavior,notproofoftheoriginalcreatorintention.',
          'inputs':[]}
for index,source in enumerate(sorted(root.glob('*_converted_*.mp4'))):
 choices=list(app.glob(source.stem+'_graded_*.mp4'))
 if not choices:raise ValueError(f'NoactualiOSpassthroughoutput:{source.name}')
 output=max(choices,key=lambda f:f.stat().st_mtime)
 ip,ins,inframes=native_frames(source,f'input{index}');op,outs,outframes=native_frames(output,f'output{index}')
 declared_range=ins.get('color_range');ranges=['full']if declared_range=='pc'else['limited']if declared_range=='tv'else['limited','full']
 declared_matrix=ins.get('color_space');matrices=[('709',1)]if declared_matrix=='bt709'else[('601',5)]if declared_matrix in('smpte170m','bt470bg')else[('601',5),('709',1)]
 record={'source':str(source),'output':str(output),'source_sha256':hashlib.file_digest(source.open('rb'),'sha256').hexdigest(),'output_sha256':hashlib.file_digest(output.open('rb'),'sha256').hexdigest(),'source_declared_range':declared_range,'source_declared_matrix':declared_matrix,
         'output_metadata':{k:outs.get(k)for k in('color_range','color_space','color_transfer','color_primaries','width','height','duration','nb_frames')},
         'comparisons':[]}
 actual={frame:rgb_frame(outframes[frame],outs['width'],outs['height'],1,'limited',out/f'output{index}_f{frame}.png')for frame in v.FRAMES}
 for name,matrix in matrices:
  for range_name in ranges:
   rows=[]
   for frame in v.FRAMES:
    expected=rgb_frame(inframes[frame],ins['width'],ins['height'],matrix,range_name,out/f'input{index}_{name}_{range_name}_f{frame}.png')
    rows.append({'frame':frame,**v.metrics(actual[frame],expected)})
   record['comparisons'].append({'input_matrix':name,'input_range':range_name,'mean_mae_8bit':sum(r['mae_8bit']for r in rows)/len(rows),'frames':rows})
 record['comparisons'].sort(key=lambda r:r['mean_mae_8bit']);record['best_fit']=record['comparisons'][0]
 manifest['inputs'].append(record)
 for raw in [*inframes.values(),*outframes.values()]:raw.unlink()
 print(source.name,record['best_fit']['input_matrix'],record['best_fit']['input_range'],record['best_fit']['mean_mae_8bit'],flush=True)
manifest['commands']=commands
(out/'passthrough-validation.json').write_text(json.dumps(manifest,indent=2)+'\n');print(out/'passthrough-validation.json')
