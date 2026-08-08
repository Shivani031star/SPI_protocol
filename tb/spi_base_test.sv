// spi_base_test.sv
// this file has the base test PLUS one small test class for
// each test case (TC01-TC15, plus a bonus regression test).
//
// the trick here: instead of writing 13 almost-identical test
// classes each with their own full build_phase/run_phase copy-
// pasted, the base class does ALL the common work (build the
// env, raise/drop the objection so the sim doesn't end too
// early) and each individual test just says "run THIS one
// sequence" - one line of real difference per test.
//
// how you'd actually run one of these from the command line
// once this is loaded into Vivado/Questa:
//   +UVM_TESTNAME=test_tc01_basic_xfer
// no recompiling needed to switch which test runs - just
// change that one argument.

`ifndef SPI_BASE_TEST_SV
`define SPI_BASE_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "spi_env.sv"
`include "spi_sequences.sv"


// ------------------------------------------------------------
// the base class - every real test extends this one
// ------------------------------------------------------------
class spi_base_test extends uvm_test;
    `uvm_component_utils(spi_base_test)

    spi_env env;

    function new(string name = "spi_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = spi_env::type_id::create("env", this);
    endfunction

    // raise_objection/drop_objection is how UVM knows when the
    // test is actually done - without this the simulation would
    // just end at time 0 before anything happens, since nothing
    // is holding it open
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_test_sequence(phase);
        phase.drop_objection(this);
    endtask

    // base version does nothing - every real test below
    // overrides this with its own specific sequence
    virtual task run_test_sequence(uvm_phase phase);
        `uvm_warning("TEST", "spi_base_test run directly - this shouldn't happen normally")
    endtask

endclass


// ------------------------------------------------------------
// TC01 - basic single transfer
// ------------------------------------------------------------
class test_tc01_basic_xfer extends spi_base_test;
    `uvm_component_utils(test_tc01_basic_xfer)
    function new(string name = "test_tc01_basic_xfer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_test_sequence(uvm_phase phase);
        seq_tc01_basic_xfer seq;
        seq = seq_tc01_basic_xfer::type_id::create("seq");
        seq.start(env.agent.sequencer);
    endtask
endclass


// ------------------------------------------------------------
// TC05 - back-to-back transfers
// ------------------------------------------------------------
class test_tc05_back_to_back extends spi_base_test;
    `uvm_component_utils(test_tc05_back_to_back)
    function new(string name = "test_tc05_back_to_back", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_test_sequence(uvm_phase phase);
        seq_tc05_back_to_back seq;
        seq = seq_tc05_back_to_back::type_id::create("seq");
        seq.start(env.agent.sequencer);
    endtask
endclass


// ------------------------------------------------------------
// TC06 - SS_N abort mid-transfer
// ------------------------------------------------------------
class test_tc06_ss_abort extends spi_base_test;
    `uvm_component_utils(test_tc06_ss_abort)
    function new(string name = "test_tc06_ss_abort", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_test_sequence(uvm_phase phase);
        seq_tc06_ss_abort seq;
        seq = seq_tc06_ss_abort::type_id::create("seq");
        seq.start(env.agent.sequencer);
    endtask
endclass


// ------------------------------------------------------------
// TC07 - reset mid-transfer
// ------------------------------------------------------------
class test_tc07_reset_mid_xfer extends spi_base_test;
    `uvm_component_utils(test_tc07_reset_mid_xfer)
    function new(string name = "test_tc07_reset_mid_xfer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_test_sequence(uvm_phase phase);
        seq_tc07_reset_mid_xfer seq;
        seq = seq_tc07_reset_mid_xfer::type_id::create("seq");
        seq.start(env.agent.sequencer);
    endtask
endclass


// ------------------------------------------------------------
// TC08 - clk_div sweep
// ------------------------------------------------------------
class test_tc08_clkdiv_sweep extends spi_base_test;
    `uvm_component_utils(test_tc08_clkdiv_sweep)
    function new(string name = "test_tc08_clkdiv_sweep", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_test_sequence(uvm_phase phase);
        seq_tc08_clkdiv_sweep seq;
        seq = seq_tc08_clkdiv_sweep::type_id::create("seq");
        seq.start(env.agent.sequencer);
    endtask
endclass


// ------------------------------------------------------------
// TC09 - edge-value data
// ------------------------------------------------------------
class test_tc09_edge_data extends spi_base_test;
    `uvm_component_utils(test_tc09_edge_data)
    function new(string name = "test_tc09_edge_data", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_test_sequence(uvm_phase phase);
        seq_tc09_edge_data seq;
        seq = seq_tc09_edge_data::type_id::create("seq");
        seq.start(env.agent.sequencer);
    endtask
endclass


// ------------------------------------------------------------
// TC10 - BIST mode 0
// ------------------------------------------------------------
class test_tc10_bist_mode0 extends spi_base_test;
    `uvm_component_utils(test_tc10_bist_mode0)
    function new(string name = "test_tc10_bist_mode0", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_test_sequence(uvm_phase phase);
        seq_tc10_bist_mode0 seq;
        seq = seq_tc10_bist_mode0::type_id::create("seq");
        seq.start(env.agent.sequencer);
    endtask
endclass


// ------------------------------------------------------------
// TC11 - BIST mode 1
// ------------------------------------------------------------
class test_tc11_bist_mode1 extends spi_base_test;
    `uvm_component_utils(test_tc11_bist_mode1)
    function new(string name = "test_tc11_bist_mode1", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_test_sequence(uvm_phase phase);
        seq_tc11_bist_mode1 seq;
        seq = seq_tc11_bist_mode1::type_id::create("seq");
        seq.start(env.agent.sequencer);
    endtask
endclass


// ------------------------------------------------------------
// TC12 - BIST mode 2
// ------------------------------------------------------------
class test_tc12_bist_mode2 extends spi_base_test;
    `uvm_component_utils(test_tc12_bist_mode2)
    function new(string name = "test_tc12_bist_mode2", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_test_sequence(uvm_phase phase);
        seq_tc12_bist_mode2 seq;
        seq = seq_tc12_bist_mode2::type_id::create("seq");
        seq.start(env.agent.sequencer);
    endtask
endclass


// ------------------------------------------------------------
// TC13 - BIST fault injection (the important one)
// ------------------------------------------------------------
class test_tc13_bist_fault_inject extends spi_base_test;
    `uvm_component_utils(test_tc13_bist_fault_inject)
    function new(string name = "test_tc13_bist_fault_inject", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_test_sequence(uvm_phase phase);
        seq_tc13_bist_fault_inject seq;
        seq = seq_tc13_bist_fault_inject::type_id::create("seq");
        seq.start(env.agent.sequencer);
    endtask
endclass


// ------------------------------------------------------------
// TC14 - BIST_START while busy
// ------------------------------------------------------------
class test_tc14_bist_start_while_busy extends spi_base_test;
    `uvm_component_utils(test_tc14_bist_start_while_busy)
    function new(string name = "test_tc14_bist_start_while_busy", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_test_sequence(uvm_phase phase);
        seq_tc14_bist_start_while_busy seq;
        seq = seq_tc14_bist_start_while_busy::type_id::create("seq");
        seq.start(env.agent.sequencer);
    endtask
endclass


// ------------------------------------------------------------
// TC15 - back-to-back BIST runs
// ------------------------------------------------------------
class test_tc15_bist_back_to_back extends spi_base_test;
    `uvm_component_utils(test_tc15_bist_back_to_back)
    function new(string name = "test_tc15_bist_back_to_back", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_test_sequence(uvm_phase phase);
        seq_tc15_bist_back_to_back seq;
        seq = seq_tc15_bist_back_to_back::type_id::create("seq");
        seq.start(env.agent.sequencer);
    endtask
endclass


// ------------------------------------------------------------
// bonus - long randomized regression, mixes everything together
// using the weighted kind distribution. good one to run last,
// after all the directed tests above already pass individually.
// ------------------------------------------------------------
class test_random_regression extends spi_base_test;
    `uvm_component_utils(test_random_regression)
    function new(string name = "test_random_regression", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    task run_test_sequence(uvm_phase phase);
        seq_random_regression seq;
        seq = seq_random_regression::type_id::create("seq");
        seq.start(env.agent.sequencer);
    endtask
endclass

`endif
