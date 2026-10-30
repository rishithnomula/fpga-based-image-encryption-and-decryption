# Build history

> Note: this log was written before the design was compiled and board-tested. The "Not performed" items below have since been completed (see the README verification status).

## Changes in this build

Changes applied to the previous supplied ZIP:

1. Unified image geometry at 112x144 pixels per image (16,128 pixels/image).
2. Loader depth corrected from 8,192 to 32,256 total pixels; its index and all VGA/cache addresses are 15 bits.
3. Engine cursor sizes changed to 14-bit pixel indices and 8-bit block count; 189 complete 256-byte MIE blocks are processed per image.
4. SDRAM map corrected to original 0..32,255, encrypted 32,256..64,511, decrypted 64,512..96,767.
5. DMA length and both result-cache depths updated to the complete two-image frame.
6. The loader's boot M9K image memory is reused as the original VGA cache after SDRAM readback, eliminating a duplicate full-frame plain cache.
7. MIE output RGB bytes are assembled into one pixel and written in one SDRAM transaction, reducing output-side write requests by a factor of three.
8. VGA address generation updated for 112x144 portrait images; the former divide-heavy scaler was replaced by fixed-point reciprocal multiplication and shift/add row indexing.
9. Replaced stale compiled Quartus database/output state with a source-only project package.

Source-level checks performed: generated HEX line counts and BIN length; dimensions and 189-block accounting; SDRAM region non-overlap; output RGB block-boundary assembly; VGA source-coordinate bounds; changed-module delimiter checks; and QSF source-file existence.

Not performed: Quartus compilation, fitted timing analysis, or physical DE2-115 SDRAM/VGA test. A final Quartus compile and board test are still required.

10. Replaced the inferred loader image array with an explicit Cyclone IV E `altsyncram` true dual-port M9K primitive. Port A supplies the boot stream; Port B writes SDRAM readback and then performs synchronous VGA reads.
11. Corrected M9K initialisation depth: the physical RAM is 32768 words, of which 32256 hold valid pixels and 512 are zero padding.
12. Updated `make_images.py` to regenerate `images2.mif` with WIDTH=24 and DEPTH=32768, and to pad `images2.hex`/`images24.hex` to the physical RAM depth.
13. Added the MIF to the Quartus project assignments and changed the loader init-file parameter to `images2.mif`.
14. Corrected the loader M9K Port B configuration to one-cycle registered-address VGA read latency while retaining the SDRAM readback write port.

## Quartus compile repair notes (2026-10-30)

Repair notes for Quartus log dated 2026-10-30

The failed build reported:
- Critical Warning 127005: inferred memory depth 32768 vs initialisation file depth 32256.
- Error 276003: image loader RAM was not inferred as a RAM megafunction and remaining flip-flops exceeded the device register budget.

Changes in this package:
1. sdram_image_loader.v now instantiates an explicit Cyclone IV E altsyncram BIDIR_DUAL_PORT M9K primitive.
   - Port A reads the initial image stream.
   - Port B writes SDRAM readback pixels and then reads for VGA scanout.
2. The boot M9K is 32768 words x 24 bits (15 address bits). images2.mif is now a 24-bit, 32768-word MIF.
3. The first 32256 words contain the two 112x144 RGB images; the final 512 words are zero padding only.
4. The loader still transfers only 32256 valid pixels to SDRAM. It does not transfer the padding.
5. The QSF explicitly lists images2.mif as the memory initialisation file.

Image / processing geometry remains:
- 2 images x 112 x 144 = 32256 pixels total.
- 96768 valid RGB bytes total.
- 189 complete 256-byte MIE blocks per image.
- SDRAM regions: original 0..32255, encrypted 32256..64511, decrypted 64512..96767.

Validation performed in this environment:
- MIF syntax/header, depth, address sequencing, data width and padding count checked.
- HEX and RGB plane lengths checked.
- Binary RGB file size checked.
- QSF Verilog source paths and MIF reference checked.
- RTL memory primitive and SDRAM geometry references checked.

Not performed:
- Quartus compilation or Fitter timing analysis (Quartus is not installed in this environment).
- Physical DE2-115 SDRAM or VGA test.

Please run a fresh Quartus compilation from this package. Do not reuse the old db/ or output_files/ directories. If Analysis & Synthesis passes, inspect M9K usage and proceed to Fitter/timing checks before programming the board.
