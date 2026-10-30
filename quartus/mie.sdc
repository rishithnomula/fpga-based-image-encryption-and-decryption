# Timing constraints for the MIE designs (50 MHz board clock)
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]
derive_clock_uncertainty

# asynchronous board inputs / pure outputs: no timing paths to analyse
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to   [get_ports {LEDR[*] LEDG[*] VGA_* }]

# ---- multicycle paths ---------------------------------------------------------------------------
# The key generator (chained 32x32 multipliers), the Process-Queue S-box builder (x^3 mod 257) and the Rule 30
# table builder (variable modulo) only change state once every CE_DIV = 16 clock cycles (clock enable generated in
# mie_core.v), so every path *inside* these blocks has 16 clock periods to settle.
set slow_keys [get_registers -nowarn {*u_keys*}]
set slow_pq   [get_registers -nowarn {*u_pq*}]
set slow_r30  [get_registers -nowarn {*u_r30|fwd_sbox* *u_r30|inv_sbox* *u_r30|b_state* *u_r30|fwd_start* *u_r30|inv_start* *u_r30|build_p*}]
foreach grp [list $slow_keys $slow_pq $slow_r30] {
    if {[get_collection_size $grp] > 0} {
        set_multicycle_path -setup -end 16 -from $grp -to $grp
        set_multicycle_path -hold  -end 15 -from $grp -to $grp
    }
}

# The current RTL drives the DE2-115 SDRAM clock directly from CLOCK_50.
# These interface constraints should be refined against the exact fitted
# SDRAM timing report and board/device datasheet after the first Quartus build.
create_generated_clock -name SDRAM_CLK -source [get_ports {CLOCK_50}] -divide_by 1 [get_ports {DRAM_CLK}]
set_output_delay -clock SDRAM_CLK 2.0 [get_ports {DRAM_ADDR[*] DRAM_BA[*] DRAM_CS_N DRAM_RAS_N DRAM_CAS_N DRAM_WE_N DRAM_DQM[*]}]
set_input_delay -clock SDRAM_CLK 4.0 [get_ports {DRAM_DQ[*]}]
