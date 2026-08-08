// tb_top.sv
// this is the actual top-level simulation file - not a UVM
// class, just a plain module. this is where:
//   - the clock and reset actually get generated
//   - the DUT gets instantiated for real
//   - the interface gets instantiated and hooked to the DUT
//   - the external MISO/MOSI loopback gets wired (the
//     scoreboard's check_normal_xfer assumes this exists -
//     see the note in spi_scoreboard.sv)
//   - the request/ack handshake from spi_if.sv actually gets
//     answered, using real hierarchical access into the DUT
//   - uvm_config_db hands the interface handle to the driver
//     and monitor
//   - run_test() actually kicks the whole thing off

`timescale 1ns / 1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

`include "spi_if.sv"
`include "spi_base_test.sv"

module tb_top;

    // ── clock generation - same 100 MHz we used all through
    //    Phase 1 ─────────────────────────────────────────────
    bit clk;
    initial clk = 0;
    always #5 clk = ~clk;   // 10 ns period = 100 MHz

    // ── the interface - this is what gets handed to the
    //    driver and monitor through uvm_config_db ─────────────
    spi_if vif(clk);

    // ── initial reset - hold rst_n low for a few cycles at
    //    the very start, same pattern as every Phase 1
    //    testbench ─────────────────────────────────────────────
    initial begin
        vif.rst_n = 0;
        repeat (5) @(posedge clk);
        vif.rst_n = 1;
    end

    // ── external loopback - whatever the DUT sends out on
    //    spi_mosi comes straight back on spi_miso. this is
    //    what makes NORMAL_XFER tests checkable at all - the
    //    scoreboard expects observed_rx_data == tx_data, which
    //    is only true because of this loopback wire ───────────
    assign vif.spi_miso = vif.spi_mosi;


    // ── the actual DUT ──────────────────────────────────────
    spi_bist_top #(
        .DATA_WIDTH   (8),
        .ADDR_WIDTH   (4),
        .WORD_COUNT   (8),
        .TIMEOUT_VAL  (512),
        .LFSR_SEED_VAL(8'h01)
    ) dut (
        .clk             (clk),
        .rst_n           (vif.rst_n),
        .wr_en           (vif.wr_en),
        .wr_addr         (vif.wr_addr),
        .wr_data         (vif.wr_data),
        .rd_addr         (vif.rd_addr),
        .rd_data         (vif.rd_data),
        .spi_sclk        (vif.spi_sclk),
        .spi_mosi        (vif.spi_mosi),
        .spi_ss_n        (vif.spi_ss_n),
        .spi_miso        (vif.spi_miso),
        .bist_pass_pulse (vif.bist_pass_pulse),
        .bist_fail_pulse (vif.bist_fail_pulse)
    );


    // ── monitor taps - straight continuous assigns from the
    //    DUT's internal wires onto the interface's mon_*
    //    signals. this is the "verification-only debug tap"
    //    idea mentioned back in spi_monitor.sv - we're not
    //    modifying spi_bist_top.v at all, just reaching in
    //    from outside since tb_top legitimately has hierarchical
    //    access to whatever it instantiates ─────────────────────
    assign vif.mon_rx_data      = dut.rx_data_m_w;
    assign vif.mon_done         = dut.done_w;
    assign vif.mon_bist_pass    = dut.bist_pass_w;
    assign vif.mon_bist_fail    = dut.bist_fail_w;
    assign vif.mon_err_code     = dut.err_code_w;
    assign vif.mon_bist_sig_act = dut.misr_sig_w;


    // ── answering the SS_N abort request ────────────────────
    // waits for the requested number of bits to have shifted,
    // then forces the master's own ss_n high early - simulating
    // an abrupt abort. honest note: in this design SS_N is
    // entirely generated internally by the master's FSM (there's
    // no external pin that lets a host force it early in real
    // operation), so this is really testing "what if a glitch or
    // fault forced SS_N high mid-transfer", not a normal
    // host-triggered scenario. still a valid robustness check.
    always @(posedge vif.ss_abort_req) begin
        repeat (vif.ss_abort_bits) @(posedge clk);
        force dut.u_master.ss_n = 1'b1;
        @(posedge clk);
        release dut.u_master.ss_n;
        vif.ss_abort_done = 1;
        @(posedge clk);
        vif.ss_abort_done = 0;
    end


    // ── answering the fault-injection request ───────────────
    // corrupts one bit on the loopback return path for a
    // couple of cycles during a BIST run - same force/release
    // technique we already used successfully back in the LFSR
    // self-healing test (Phase 1, Step 1.5)
    always @(posedge vif.fault_inject_req) begin
        repeat (20) @(posedge clk);
        force dut.slave_miso_w = 1'b0;
        repeat (2) @(posedge clk);
        release dut.slave_miso_w;
        vif.fault_inject_done = 1;
        @(posedge clk);
        vif.fault_inject_done = 0;
    end


    // ── hand the interface to UVM and start the test ────────
    initial begin
        uvm_config_db #(virtual spi_if)::set(null, "*", "vif", vif);
        run_test("test_tc01_basic_xfer");
    end

endmodule
