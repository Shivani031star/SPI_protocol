// spi_scoreboard.sv
// this is where we actually decide "did the test pass?"
//
// the scoreboard NEVER trusts the DUT's own PASS/FAIL bit by
// itself - that would be circular (asking the chip "are you
// broken?" and just believing whatever it says). instead this
// file has its OWN independent copy of the signature math
// (same rotate-XOR algorithm as the real misr.v hardware) and
// works out what SHOULD have happened, completely separately
// from whatever the DUT claims.
//
// two different things get checked for every BIST result:
//   1. is the signature math itself correct? (observed_sig_act
//      should equal our independently computed golden value)
//   2. did the DUT correctly decide PASS or FAIL, given
//      whatever expected value was actually written? (this
//      needs to know bist_sig_exp too - see the monitor patch
//      note at the top of spi_monitor.sv for why)
//
// honest note: the golden signature math here is a second,
// independent copy of the same function that's also in
// spi_driver.sv. a "more correct" design would pull this out
// into one shared reference-model file both classes import, so
// there's zero chance of copy-paste drift between them. keeping
// it duplicated for now to keep this file self-contained and
// easier to follow - worth refactoring later if the project
// grows.

`ifndef SPI_SCOREBOARD_SV
`define SPI_SCOREBOARD_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "spi_seq_item.sv"

class spi_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(spi_scoreboard)

    // this is the "mailbox" the monitor's ap.write() calls land
    // in - uvm_analysis_imp means "I actually implement a
    // write() function myself", as opposed to uvm_analysis_port
    // which just forwards things along
    uvm_analysis_imp #(spi_seq_item, spi_scoreboard) imp;

    int pass_cnt;
    int fail_cnt;

    function new(string name = "spi_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        imp = new("imp", this);
        pass_cnt = 0;
        fail_cnt = 0;
    endfunction


    // ------------------------------------------------------------
    // same golden signature calculation as the driver - see the
    // honest note at the top of this file about why it's
    // duplicated instead of shared
    // ------------------------------------------------------------
    function bit [7:0] compute_golden_sig(bist_mode_e mode);
        bit [7:0] sig;
        bit [7:0] lfsr;
        bit [7:0] pattern;
        sig  = 8'h00;
        lfsr = 8'h01;

        for (int i = 0; i < 8; i++) begin
            case (mode)
                BIST_MODE_LOOPBACK: pattern = 8'hA5;
                BIST_MODE_WALK1:    pattern = (8'h01 << i);
                BIST_MODE_PRBS: begin
                    pattern = lfsr;
                    lfsr = {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
                end
                default: pattern = 8'h00;
            endcase
            sig = {sig[6:0], sig[7]} ^ pattern;
        end
        return sig;
    endfunction


    // ------------------------------------------------------------
    // this is the function UVM calls automatically every time
    // the monitor does ap.write(item) - this IS the "write"
    // that uvm_analysis_imp #(...) promised to implement above
    // ------------------------------------------------------------
    function void write(spi_seq_item item);
        case (item.kind)
            NORMAL_XFER: check_normal_xfer(item);
            BIST_RUN:    check_bist_run(item);
            default: `uvm_warning("SCB", $sformatf("scoreboard doesn't know how to check kind=%s yet",
                                                       item.kind.name()))
        endcase
    endfunction


    // ------------------------------------------------------------
    // normal transfer check - assumes tb_top wires spi_miso back
    // to spi_mosi externally (a simple loopback), same as our
    // Phase 1 RTL testbenches did. if that wiring isn't there,
    // this check won't make sense - just a heads up for step 2.10
    // ------------------------------------------------------------
    function void check_normal_xfer(spi_seq_item item);
        if (item.observed_rx_data === item.tx_data) begin
            `uvm_info("SCB", $sformatf("PASS - normal xfer: sent 0x%0h, got 0x%0h back",
                                         item.tx_data, item.observed_rx_data), UVM_LOW)
            pass_cnt++;
        end else begin
            `uvm_error("SCB", $sformatf("FAIL - normal xfer: sent 0x%0h, but got 0x%0h back",
                                          item.tx_data, item.observed_rx_data))
            fail_cnt++;
        end
    endfunction


    // ------------------------------------------------------------
    // BIST check - two separate things checked here, both matter
    // ------------------------------------------------------------
    function void check_bist_run(spi_seq_item item);
        bit [7:0] golden;
        bit       expected_pass;

        golden = compute_golden_sig(item.bist_mode);

        // what SHOULD the DUT decide, given what was actually
        // written as the expected value? if they match, healthy
        // hardware should PASS. if they don't match (test wrote
        // a wrong value on purpose, or hardware genuinely broke),
        // healthy comparison logic should FAIL.
        expected_pass = (golden == item.bist_sig_exp);

        // check 1 - is the signature math itself right?
        if (item.observed_bist_sig_act !== golden) begin
            `uvm_error("SCB", $sformatf(
                "FAIL - BIST mode=%0d signature wrong: DUT computed 0x%0h, should be 0x%0h",
                item.bist_mode, item.observed_bist_sig_act, golden))
            fail_cnt++;
            return;   // no point checking pass/fail decision if the
                      // signature itself is already wrong
        end

        // check 2 - did the DUT make the right PASS/FAIL call?
        if (expected_pass && item.observed_bist_pass) begin
            `uvm_info("SCB", $sformatf("PASS - BIST mode=%0d correctly reported PASS",
                                         item.bist_mode), UVM_LOW)
            pass_cnt++;
        end else if (!expected_pass && item.observed_bist_fail) begin
            `uvm_info("SCB", $sformatf("PASS - BIST mode=%0d correctly reported FAIL (as expected)",
                                         item.bist_mode), UVM_LOW)
            pass_cnt++;
        end else begin
            `uvm_error("SCB", $sformatf(
                "FAIL - BIST mode=%0d wrong verdict: expected_pass=%0b but saw pass=%0b fail=%0b",
                item.bist_mode, expected_pass, item.observed_bist_pass, item.observed_bist_fail))
            fail_cnt++;
        end
    endfunction


    // report_phase runs automatically at the very end of the
    // whole simulation - good place to print a final summary,
    // same idea as the final $display block in our old testbenches
    function void report_phase(uvm_phase phase);
        `uvm_info("SCB", $sformatf("===================================="), UVM_LOW)
        `uvm_info("SCB", $sformatf("FINAL RESULT: %0d passed, %0d failed", pass_cnt, fail_cnt), UVM_LOW)
        `uvm_info("SCB", $sformatf("===================================="), UVM_LOW)
        if (fail_cnt == 0)
            `uvm_info("SCB", "ALL CHECKS PASSED", UVM_LOW)
        else
            `uvm_error("SCB", $sformatf("%0d CHECK(S) FAILED - see log above", fail_cnt))
    endfunction

endclass

`endif
