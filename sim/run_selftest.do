# ModelSim/Questa: MIE built-in self-test
# Run from the sim/ directory:  do run_selftest.do
vlib work
vlog -work work  ../rtl/blk_ram.v ../rtl/chaotic8d_core.v ../rtl/derivative_function.v ../rtl/fixed_mult.v ../rtl/josephus_permute.v ../rtl/josephus_seq_gen.v ../rtl/key_expand.v ../rtl/key_gen_triple.v ../rtl/key_generator_top.v ../rtl/mie_core.v ../rtl/process_queue_sbox.v ../rtl/random_extractor.v ../rtl/rule30_generator.v ../rtl/rule30_inverse_builder.v ../rtl/rule30_shuffle_engine.v ../rtl/rule30_stage_top.v ../rtl/simple_pass.v ../rtl/stage_process.v ../tb/selftest_tb.v
vsim -onfinish stop -voptargs=+acc work.selftest_tb
run -all
