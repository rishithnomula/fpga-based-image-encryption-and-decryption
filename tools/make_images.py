#!/usr/bin/env python3
"""Build the two-photo MIE SDRAM boot images.

Default project canvas: 112x144 RGB per image. Each source is resized with
aspect ratio preserved and centred on black padding (no square crop).

Usage:
  python tools/make_images.py assets/image1_cat.jpg assets/image2_portrait.png --out quartus
  python tools/make_images.py img1.jpg img2.png --width 112 --height 144 --out quartus

Outputs:
  images2.hex  : 24-bit RRGGBB words (two images concatenated)
  images_r.hex : red byte plane (one byte per pixel)
  images_g.hex : green byte plane
  images_b.hex : blue byte plane
  IMAGES.BIN   : raw RGB byte stream
"""
import argparse
from pathlib import Path
from PIL import Image, ImageOps
import numpy as np
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('images',nargs=2,help='Image 1 followed by Image 2')
p.add_argument('--width',type=int,default=112)
p.add_argument('--height',type=int,default=144)
p.add_argument('--size',type=int,default=None,help='Legacy option: set a square canvas')
p.add_argument('--out',default='quartus')
a=p.parse_args()
w,h=(a.size,a.size) if a.size is not None else (a.width,a.height)
if w<=0 or h<=0: p.error('width and height must be positive')
frames=[]
for filename in a.images:
    with Image.open(filename) as src:
        src=src.convert('RGB')
        fitted=ImageOps.contain(src,(w,h),method=Image.Resampling.LANCZOS)
        canvas=Image.new('RGB',(w,h),(0,0,0))
        canvas.paste(fitted,((w-fitted.width)//2,(h-fitted.height)//2))
        frames.append(np.asarray(canvas,dtype=np.uint8))
pixels=np.concatenate([f.reshape(-1,3) for f in frames],axis=0)
if (w*h*3)%256: p.error('width*height*3 must be divisible by 256 for complete MIE blocks')
out=Path(a.out); out.mkdir(parents=True,exist_ok=True)
# The physical M9K is addressed with 15 bits (32768 words). Pad the
# initialisation file, but keep padding out of the SDRAM transfer and MIE stream.
valid_words = ['%02x%02x%02x' % tuple(map(int, px)) for px in pixels]
ram_depth = 1 << (len(valid_words) - 1).bit_length()
padded_words = valid_words + ['000000'] * (ram_depth - len(valid_words))
hex_text = '\n'.join(padded_words) + '\n'
(out/'images2.hex').write_text(hex_text)
for name,ch in [('r',0),('g',1),('b',2)]:
    (out/f'images_{name}.hex').write_text('\n'.join(f'{int(v):02x}' for v in pixels[:,ch])+'\n')
(out/'images24.hex').write_text(hex_text)
# Quartus MIF is used by the explicit altsyncram primitive. Each line holds
# one 24-bit RRGGBB word and all 32768 addresses are explicitly initialised.
mif_lines = [
    'WIDTH=24;',
    f'DEPTH={ram_depth};',
    'ADDRESS_RADIX=HEX;',
    'DATA_RADIX=HEX;',
    'CONTENT BEGIN',
]
mif_lines.extend(f'{addr:04X} : {word};' for addr, word in enumerate(padded_words))
mif_lines.append('END;')
(out/'images2.mif').write_text('\n'.join(mif_lines) + '\n')
(out/'IMAGES.BIN').write_bytes(pixels.tobytes())
print(f'Wrote two {w}x{h} images: {pixels.shape[0]} valid pixels, {pixels.nbytes} RGB bytes, '
      f'{w*h*3//256} MIE blocks/image; padded M9K init depth={ram_depth} words '
      f'({ram_depth-len(valid_words)} zero words)')
