// spi_coverage.sv
// this file's job: keep track of WHICH scenarios we've actually
// tested so far, out of everything we COULD test. this is
// "functional coverage" - it's separate from the scoreboard
// (which checks if results are correct) - coverage just checks
// "did we even try this situation at all?"
//
// extends uvm_subscriber instead of uvm_component this time -
// uvm_subscriber already comes with the analysis port wiring
// built in, we just override write() and that's it. a little
// less setup than the scoreboard needed.
//
// honest note: the original project plan had a coverpoint for
// CPOL/CPHA (all 4 clock modes). since the RTL got hardwired to
// Mode 0 only, that coverpoint doesn't mean anything anymore -
// removed it rather than leaving in a fake coverpoint that could
// never show real variation. same reasoning as dropping TC02/03/
// 04/16 back in the sequences file.

`ifndef SPI_COVERAGE_SV
`define SPI_COVERAGE_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "spi_seq_item.sv"

class spi_coverage extends uvm_subscriber #(spi_seq_item);
    `uvm_component_utils(spi_coverage)

    // this is the actual coverage model - a list of "things we
    // want to see happen at least once". SystemVerilog tracks
    // this automatically once we call .sample() on it.
    covergroup cg_spi_transactions with function sample(spi_seq_item t);

        // did we exercise all 7 scenario types at least once?
        cp_kind: coverpoint t.kind;

        // did we run all 3 BIST modes at least once? (only
        // counts for BIST-related kinds, other kinds don't set
        // bist_mode to anything meaningful so we skip them
        // using "iff")
        cp_bist_mode: coverpoint t.bist_mode
            iff (t.kind inside {BIST_RUN, BIST_FAULT_INJECT,
                                 BIST_BACK_TO_BACK, BIST_START_WHILE_BUSY}) {
            bins loopback = {BIST_MODE_LOOPBACK};
            bins walk1    = {BIST_MODE_WALK1};
            bins prbs      = {BIST_MODE_PRBS};
        }

        // have we seen BIST actually PASS at least once?
        cp_bist_pass_seen: coverpoint t.observed_bist_pass
            iff (t.kind inside {BIST_RUN, BIST_FAULT_INJECT, BIST_BACK_TO_BACK}) {
            bins seen_pass = {1};
        }

        // have we seen BIST actually FAIL at least once?
        // (important - if this bin never fills, it means we
        // never actually tested the "unhealthy chip" case)
        cp_bist_fail_seen: coverpoint t.observed_bist_fail
            iff (t.kind inside {BIST_RUN, BIST_FAULT_INJECT, BIST_BACK_TO_BACK}) {
            bins seen_fail = {1};
        }

        // clk_div across its whole legal range, split into 3
        // buckets so we're not demanding all 16 exact values,
        // just a reasonable spread
        cp_clk_div: coverpoint t.clk_div
            iff (t.kind inside {NORMAL_XFER, SS_ABORT_XFER, RESET_MID_XFER}) {
            bins low  = {[1:5]};
            bins mid  = {[6:10]};
            bins high = {[11:16]};
        }

        // the "gotcha" data values from TC09, plus a catch-all
        // bin for everything else (random bytes)
        cp_data_value: coverpoint t.tx_data
            iff (t.kind == NORMAL_XFER) {
            bins all_zero = {8'h00};
            bins all_one  = {8'hFF};
            bins alt_55   = {8'h55};
            bins alt_AA   = {8'hAA};
            bins others   = default;
        }

        // did we try resetting early/mid/late into a transfer?
        cp_reset_timing: coverpoint t.reset_after_cycles
            iff (t.kind == RESET_MID_XFER) {
            bins early = {[1:6]};
            bins mid   = {[7:13]};
            bins late  = {[14:20]};
        }

        // same idea for cutting SS_N short at different points
        cp_abort_timing: coverpoint t.abort_after_bits
            iff (t.kind == SS_ABORT_XFER) {
            bins early = {[1:2]};
            bins mid   = {[3:5]};
            bins late  = {[6:7]};
        }

    endgroup

    function new(string name = "spi_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_spi_transactions = new();
    endfunction

    // this is the function uvm_subscriber requires us to fill
    // in - gets called automatically every time something
    // broadcasts to us (the monitor, in our case, once the
    // environment wires it up in step 2.8)
    function void write(spi_seq_item t);
        cg_spi_transactions.sample(t);
    endfunction

    // print a coverage summary at the end of the run, same idea
    // as the scoreboard's report_phase
    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf("overall functional coverage = %0.2f%%",
                                     cg_spi_transactions.get_coverage()), UVM_LOW)
    endfunction

endclass

`endif
