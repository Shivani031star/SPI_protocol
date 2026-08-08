// spi_sequences.sv
// These are the sequences that actually fill out spi_seq_item
// "slips" and send them to the driver via the sequencer.
//
// One sequence class per test case (TC01-TC16), so it's easy
// to tell which file covers which test just from the name.
//
// note: TC02/TC03/TC04 and TC16 were originally about switching
// CPOL/CPHA modes, but that got hardwired to Mode 0 in the RTL,
// so those don't really mean anything different anymore. Not
// writing separate sequences for them - would just be duplicates
// of TC01.

`ifndef SPI_SEQUENCES_SV
`define SPI_SEQUENCES_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "spi_seq_item.sv"


// ------------------------------------------------------------
// base class - every other sequence extends this one.
// doesn't really do anything by itself, just saves repeating
// "extends uvm_sequence #(spi_seq_item)" everywhere
// ------------------------------------------------------------
class spi_base_seq extends uvm_sequence #(spi_seq_item);
    `uvm_object_utils(spi_base_seq)

    function new(string name = "spi_base_seq");
        super.new(name);
    endfunction
endclass


// ------------------------------------------------------------
// TC01 - just send one normal byte, simplest possible test
// ------------------------------------------------------------
class seq_tc01_basic_xfer extends spi_base_seq;
    `uvm_object_utils(seq_tc01_basic_xfer)

    function new(string name = "seq_tc01_basic_xfer");
        super.new(name);
    endfunction

    task body();
        spi_seq_item item;
        item = spi_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with { kind == NORMAL_XFER; })
            `uvm_error("SEQ", "randomize failed in seq_tc01_basic_xfer")
        finish_item(item);
    endtask
endclass


// ------------------------------------------------------------
// TC05 - back-to-back transfers. sends several normal bytes
// one right after another to check the FSM handles repeated
// transfers cleanly (no leftover state from the previous one)
// ------------------------------------------------------------
class seq_tc05_back_to_back extends spi_base_seq;
    `uvm_object_utils(seq_tc05_back_to_back)

    // how many transfers to do in a row, 4 seems reasonable
    int num_transfers = 4;

    function new(string name = "seq_tc05_back_to_back");
        super.new(name);
    endfunction

    task body();
        spi_seq_item item;
        for (int i = 0; i < num_transfers; i++) begin
            item = spi_seq_item::type_id::create($sformatf("item_%0d", i));
            start_item(item);
            if (!item.randomize() with { kind == NORMAL_XFER; })
                `uvm_error("SEQ", "randomize failed in seq_tc05_back_to_back")
            finish_item(item);
        end
    endtask
endclass


// ------------------------------------------------------------
// TC06 - cut a transfer short by deasserting SS_N early.
// checks the FSM aborts cleanly instead of getting stuck
// ------------------------------------------------------------
class seq_tc06_ss_abort extends spi_base_seq;
    `uvm_object_utils(seq_tc06_ss_abort)

    function new(string name = "seq_tc06_ss_abort");
        super.new(name);
    endfunction

    task body();
        spi_seq_item item;
        item = spi_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with { kind == SS_ABORT_XFER; })
            `uvm_error("SEQ", "randomize failed in seq_tc06_ss_abort")
        finish_item(item);
    endtask
endclass


// ------------------------------------------------------------
// TC07 - reset in the middle of a transfer. FSM should go
// back to IDLE cleanly, no stuck BUSY, no fake DONE pulse
// ------------------------------------------------------------
class seq_tc07_reset_mid_xfer extends spi_base_seq;
    `uvm_object_utils(seq_tc07_reset_mid_xfer)

    function new(string name = "seq_tc07_reset_mid_xfer");
        super.new(name);
    endfunction

    task body();
        spi_seq_item item;
        item = spi_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with { kind == RESET_MID_XFER; })
            `uvm_error("SEQ", "randomize failed in seq_tc07_reset_mid_xfer")
        finish_item(item);
    endtask
endclass


// ------------------------------------------------------------
// TC08 - sweep clk_div across its whole legal range, one
// transfer per value, to check the clock divider works
// correctly everywhere, not just the one value we always
// used back in the directed Phase 1 testbenches
// ------------------------------------------------------------
class seq_tc08_clkdiv_sweep extends spi_base_seq;
    `uvm_object_utils(seq_tc08_clkdiv_sweep)

    function new(string name = "seq_tc08_clkdiv_sweep");
        super.new(name);
    endfunction

    task body();
        spi_seq_item item;
        // clk_div is constrained 1 to 16 in the item, so just
        // loop through all of them directly instead of randomizing
        for (int d = 1; d <= 16; d++) begin
            item = spi_seq_item::type_id::create($sformatf("item_div%0d", d));
            start_item(item);
            if (!item.randomize() with { kind == NORMAL_XFER; clk_div == d; })
                `uvm_error("SEQ", "randomize failed in seq_tc08_clkdiv_sweep")
            finish_item(item);
        end
    endtask
endclass


// ------------------------------------------------------------
// TC09 - the "gotcha" data values. all-0 and all-1 are the
// classic ones that expose bit-ordering bugs that a plain
// random byte might accidentally hide
// ------------------------------------------------------------
class seq_tc09_edge_data extends spi_base_seq;
    `uvm_object_utils(seq_tc09_edge_data)

    function new(string name = "seq_tc09_edge_data");
        super.new(name);
    endfunction

    task body();
        spi_seq_item item;
        bit [7:0] edge_values[4] = '{8'h00, 8'hFF, 8'h55, 8'hAA};

        foreach (edge_values[i]) begin
            item = spi_seq_item::type_id::create($sformatf("item_edge%0d", i));
            start_item(item);
            if (!item.randomize() with { kind == NORMAL_XFER; tx_data == edge_values[i]; })
                `uvm_error("SEQ", "randomize failed in seq_tc09_edge_data")
            finish_item(item);
        end
    endtask
endclass


// ------------------------------------------------------------
// TC10 - BIST mode 0 (fixed pattern), healthy chip, expect PASS
// ------------------------------------------------------------
class seq_tc10_bist_mode0 extends spi_base_seq;
    `uvm_object_utils(seq_tc10_bist_mode0)

    function new(string name = "seq_tc10_bist_mode0");
        super.new(name);
    endfunction

    task body();
        spi_seq_item item;
        item = spi_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
                kind == BIST_RUN;
                bist_mode == BIST_MODE_LOOPBACK;
                corrupt_sig_exp == 0;   // healthy run, must PASS
            })
            `uvm_error("SEQ", "randomize failed in seq_tc10_bist_mode0")
        finish_item(item);
    endtask
endclass


// ------------------------------------------------------------
// TC11 - BIST mode 1 (walking 1s), healthy chip, expect PASS
// ------------------------------------------------------------
class seq_tc11_bist_mode1 extends spi_base_seq;
    `uvm_object_utils(seq_tc11_bist_mode1)

    function new(string name = "seq_tc11_bist_mode1");
        super.new(name);
    endfunction

    task body();
        spi_seq_item item;
        item = spi_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
                kind == BIST_RUN;
                bist_mode == BIST_MODE_WALK1;
                corrupt_sig_exp == 0;
            })
            `uvm_error("SEQ", "randomize failed in seq_tc11_bist_mode1")
        finish_item(item);
    endtask
endclass


// ------------------------------------------------------------
// TC12 - BIST mode 2 (PRBS/LFSR), healthy chip, expect PASS
// ------------------------------------------------------------
class seq_tc12_bist_mode2 extends spi_base_seq;
    `uvm_object_utils(seq_tc12_bist_mode2)

    function new(string name = "seq_tc12_bist_mode2");
        super.new(name);
    endfunction

    task body();
        spi_seq_item item;
        item = spi_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
                kind == BIST_RUN;
                bist_mode == BIST_MODE_PRBS;
                corrupt_sig_exp == 0;
            })
            `uvm_error("SEQ", "randomize failed in seq_tc12_bist_mode2")
        finish_item(item);
    endtask
endclass


// ------------------------------------------------------------
// TC13 - the important one. corrupt_sig_exp=1 means the driver
// will write a WRONG expected signature on purpose. if BIST is
// working correctly, it MUST report FAIL here, not PASS.
// (this is the "who verifies the verifier" test)
// ------------------------------------------------------------
class seq_tc13_bist_fault_inject extends spi_base_seq;
    `uvm_object_utils(seq_tc13_bist_fault_inject)

    function new(string name = "seq_tc13_bist_fault_inject");
        super.new(name);
    endfunction

    task body();
        spi_seq_item item;
        item = spi_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
                kind == BIST_FAULT_INJECT;
                corrupt_sig_exp == 1;   // force wrong expected value
            })
            `uvm_error("SEQ", "randomize failed in seq_tc13_bist_fault_inject")
        finish_item(item);
    endtask
endclass


// ------------------------------------------------------------
// TC14 - try to start BIST while it's already busy. the second
// request should just get ignored, not corrupt the FSM
// ------------------------------------------------------------
class seq_tc14_bist_start_while_busy extends spi_base_seq;
    `uvm_object_utils(seq_tc14_bist_start_while_busy)

    function new(string name = "seq_tc14_bist_start_while_busy");
        super.new(name);
    endfunction

    task body();
        spi_seq_item item;
        item = spi_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with { kind == BIST_START_WHILE_BUSY; })
            `uvm_error("SEQ", "randomize failed in seq_tc14_bist_start_while_busy")
        finish_item(item);
        // note: the actual "send start twice quickly" behavior
        // happens inside the driver, not here - the sequence just
        // tells the driver "this is a start-while-busy test"
    endtask
endclass


// ------------------------------------------------------------
// TC15 - run BIST twice back to back, check the FSM returns
// cleanly to IDLE after the first run and the second run
// works independently (no leftover state)
// ------------------------------------------------------------
class seq_tc15_bist_back_to_back extends spi_base_seq;
    `uvm_object_utils(seq_tc15_bist_back_to_back)

    function new(string name = "seq_tc15_bist_back_to_back");
        super.new(name);
    endfunction

    task body();
        spi_seq_item item;
        // two separate BIST runs, one after another
        for (int i = 0; i < 2; i++) begin
            item = spi_seq_item::type_id::create($sformatf("item_%0d", i));
            start_item(item);
            if (!item.randomize() with {
                    kind == BIST_RUN;
                    corrupt_sig_exp == 0;
                })
                `uvm_error("SEQ", "randomize failed in seq_tc15_bist_back_to_back")
            finish_item(item);
        end
    endtask
endclass


// ------------------------------------------------------------
// bonus - not tied to one specific TC, just throws a big mix
// of randomized items at the DUT using the weighted kind
// distribution from spi_seq_item. good for a longer regression
// run after the directed tests above all pass individually
// ------------------------------------------------------------
class seq_random_regression extends spi_base_seq;
    `uvm_object_utils(seq_random_regression)

    int num_items = 50;

    function new(string name = "seq_random_regression");
        super.new(name);
    endfunction

    task body();
        spi_seq_item item;
        for (int i = 0; i < num_items; i++) begin
            item = spi_seq_item::type_id::create($sformatf("item_%0d", i));
            start_item(item);
            // no "with" constraint here - let the item's own
            // c_kind_mix constraint pick kind using the weights
            if (!item.randomize())
                `uvm_error("SEQ", "randomize failed in seq_random_regression")
            finish_item(item);
        end
    endtask
endclass

`endif
