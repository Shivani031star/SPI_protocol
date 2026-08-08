// spi_monitor.sv
// The monitor's whole job is to WATCH, never touch anything.
// It never sets wr_en, never sets rd_addr, nothing. It just
// sits there sampling signals every clock and figures out
// "what just happened" on its own, then tells everyone else
// (scoreboard, coverage) via an analysis port.
//
// why does this matter? because if the monitor just copied
// whatever the driver already knew, it wouldn't really be
// CHECKING anything - it would just be trusting the driver.
// by independently watching the real DUT signals, the monitor
// gives us an honest second opinion.
//
// two different ways I'm watching things here:
//   1. write bus (wr_en/wr_addr/wr_data) - totally fine to
//      just passively snoop this, since only the driver ever
//      writes to it, monitor is just listening in
//   2. "mon_*" signals - these are direct taps wired straight
//      to the DUT's internal result wires (rx_data, done,
//      bist_pass, bist_fail, etc), NOT going through the
//      shared register read bus. reason: there's only ONE
//      read port on the real hardware (rd_addr/rd_data), and
//      the driver is already using it to poll STATUS_REG - if
//      the monitor tried to read from that same port too,
//      they'd fight over it. so instead the interface (built
//      in step 2.10) gives the monitor its own private,
//      always-live view of the results, no contention at all.

`ifndef SPI_MONITOR_SV
`define SPI_MONITOR_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "spi_seq_item.sv"

class spi_monitor extends uvm_monitor;
    `uvm_component_utils(spi_monitor)

    virtual spi_if vif;

    // this is how the monitor "broadcasts" what it saw - both
    // the scoreboard and coverage collector will hook onto this
    // same port later (step 2.8 wires that connection up)
    uvm_analysis_port #(spi_seq_item) ap;

    // register addresses, same as everywhere else
    localparam A_CTRL   = 4'h0;
    localparam A_TXDATA = 4'h2;
    localparam A_SIGEXP = 4'h4;

    // "shadow" values - remembering the last thing written to
    // each register, so when a completion happens we know what
    // was actually being requested
    bit [7:0]    shadow_tx_data;
    bit [1:0]    shadow_bist_mode;
    bit [7:0]    shadow_sig_exp;

    // remembering the previous cycle's value of each status bit,
    // so we can spot the exact moment it turns from 0 to 1
    // (that's what "edge detection" means here)
    bit prev_done;
    bit prev_bist_pass;
    bit prev_bist_fail;

    function new(string name = "spi_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual spi_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "couldn't find vif in config_db - did tb_top set it?")
    endfunction

    task run_phase(uvm_phase phase);
        prev_done      = 0;
        prev_bist_pass = 0;
        prev_bist_fail = 0;

        forever begin
            @(posedge vif.clk);

            watch_writes();
            watch_for_normal_done();
            watch_for_bist_result();

            // update "previous cycle" trackers for next time around
            prev_done      = vif.mon_done;
            prev_bist_pass = vif.mon_bist_pass;
            prev_bist_fail = vif.mon_bist_fail;
        end
    endtask


    // just watching the write bus and remembering what got
    // written where - doesn't broadcast anything by itself,
    // just updates the shadow registers above
    task watch_writes();
        if (vif.wr_en) begin
            case (vif.wr_addr)
                A_TXDATA: shadow_tx_data <= vif.wr_data[7:0];
                A_CTRL:   shadow_bist_mode <= vif.wr_data[4:3];
                A_SIGEXP: shadow_sig_exp <= vif.wr_data[7:0];
                default: ; // don't care about other addresses here
            endcase
        end
    endtask


    // a normal transfer just finished - saw DONE go from 0 to 1
    task watch_for_normal_done();
        if (vif.mon_done && !prev_done) begin
            spi_seq_item item;
            item = spi_seq_item::type_id::create("mon_item");
            item.kind             = NORMAL_XFER;
            item.tx_data          = shadow_tx_data;
            item.observed_rx_data = vif.mon_rx_data;
            item.observed_done    = 1;
            `uvm_info("MON", $sformatf("saw a normal transfer finish: tx_data=0x%0h rx_data=0x%0h",
                                         shadow_tx_data, vif.mon_rx_data), UVM_MEDIUM)
            ap.write(item);
        end
    endtask


    // a BIST run just finished - either PASS or FAIL edge
    task watch_for_bist_result();
        if (vif.mon_bist_pass && !prev_bist_pass) begin
            spi_seq_item item;
            item = spi_seq_item::type_id::create("mon_item");
            item.kind                  = BIST_RUN;
            item.bist_mode              = bist_mode_e'(shadow_bist_mode);
            item.bist_sig_exp           = shadow_sig_exp;   // what was actually written -
                                                              // scoreboard needs this to tell
                                                              // "DUT is broken" apart from
                                                              // "test asked for a mismatch on purpose"
            item.observed_bist_pass     = 1;
            item.observed_bist_fail     = 0;
            item.observed_bist_sig_act   = vif.mon_bist_sig_act;
            item.observed_err_code      = vif.mon_err_code;
            `uvm_info("MON", $sformatf("saw BIST PASS, mode=%0d sig_act=0x%0h",
                                         shadow_bist_mode, vif.mon_bist_sig_act), UVM_MEDIUM)
            ap.write(item);
        end

        if (vif.mon_bist_fail && !prev_bist_fail) begin
            spi_seq_item item;
            item = spi_seq_item::type_id::create("mon_item");
            item.kind                  = BIST_RUN;
            item.bist_mode              = bist_mode_e'(shadow_bist_mode);
            item.bist_sig_exp           = shadow_sig_exp;   // same reason as above
            item.observed_bist_pass     = 0;
            item.observed_bist_fail     = 1;
            item.observed_bist_sig_act   = vif.mon_bist_sig_act;
            item.observed_err_code      = vif.mon_err_code;
            `uvm_info("MON", $sformatf("saw BIST FAIL, mode=%0d err_code=%0d",
                                         shadow_bist_mode, vif.mon_err_code), UVM_MEDIUM)
            ap.write(item);
        end
    endtask

endclass

`endif
