#!/usr/bin/env bash
# Open-source alternative to the ModelSim scripts (Icarus Verilog).
# Usage: ./sim/run_iverilog.sh   (from the repository root)
set -e
CORE=$(ls rtl/{blk_ram,chaotic8d_core,derivative_function,fixed_mult,josephus_permute,josephus_seq_gen,key_expand,key_gen_triple,key_generator_top,mie_core,process_queue_sbox,random_extractor,rule30_generator,rule30_inverse_builder,rule30_shuffle_engine,rule30_stage_top,simple_pass,stage_process}.v)
mkdir -p build
for tb in mie_core_tb selftest_tb; do
  echo "=== $tb ==="
  iverilog -g2005-sv -o build/$tb $CORE tb/$tb.v
  vvp build/$tb
done
