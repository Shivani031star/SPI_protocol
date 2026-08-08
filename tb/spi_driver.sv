// spi_driver.sv
// This is the part that actually DOES something to the chip.
// It gets a "slip" (spi_seq_item) from the sequencer, figures
// out what kind of test it is, and does the real register
// writes/reads on the DUT through the virtual interface.
//
// note on interface tasks: for the tricky tests (SS_N abort,
// reset mid-transfer, fault injection) I'm assuming the
// interface (spi_if, built in step 2.10) gives me some helper
// tasks to do that:
//   vif.do_ss_abort(bits)     - forces SS_N high early
//   vif.do_reset_pulse(cyc)   - pulses reset partway through
//   vif.do_fault_inject()     - forces a real bit flip on the
//                               loopback datapath for a moment
// these need direct access to internal DUT wires, which an
// interface bound alongside the DUT can do but a driver
// reaching into the DUT directly really shouldn't (breaks the
// whole point of having a clean DUT-agnostic driver). so those
// three stay as interface-level helpers, not driver code.

`ifndef SPI_DRIVER_SV
`define SPI_DRIVER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "spi_seq_item.sv"

class spi_driver extends uvm_driver #(spi_seq_item);
    `uvm_component_utils(spi_driver)

    virtual spi_if vif;   // handle to the interface, filled in below

    // register addresses - same as the real spi_regfile.v map
    localparam A_CTRL    = 4'h0;
    localparam A_STATUS  = 4'h1;
    localparam A_TXDATA  = 4'h2;
    localparam A_RXDATA  = 4'h3;
    localparam A_SIGEXP  = 4'h4;
    localparam A_SIGACT  = 4'h5;

    // how many times to poll STATUS before giving up (safety net,
    // don't want the sim hanging forever if something's stuck)
    localparam int POLL_LIMIT = 5000;

    function new(string name = "spi_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // build_phase - this is where UVM components fetch things
    // they need, like the interface handle. uvm_config_db is
    // basically a shared lookup table set up in tb_top.
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual spi_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "couldn't find vif in config_db - did tb_top set it?")
    endfunction

    // run_phase - this is the main loop. keep grabbing items
    // from the sequencer forever and driving them.
    task run_phase(uvm_phase phase);
        spi_seq_item req;

        //wait for hardware to come out fo reset first
        wait(vif.rst_n == 1'b1);
        @(posedge vif.clk);
        
        forever begin
            seq_item_port.get_next_item(req);
            drive_item(req);
            seq_item_port.item_done();
        end
    endtask


    // ------------------------------------------------------------
    // basic register write - hold wr_en high for one clock, same
    // as how the testbenches did it back in the RTL phase
    // ------------------------------------------------------------
    task reg_write(bit [3:0] addr, bit [15:0] data);
        @(posedge vif.clk);
        vif.wr_en   = 1;
        vif.wr_addr = addr;
        vif.wr_data = data;
        @(posedge vif.clk);
        vif.wr_en   = 0;
    endtask

    // basic register read - just settle rd_addr and read rd_data
    task reg_read(bit [3:0] addr, output bit [15:0] data);
        vif.rd_addr = addr;
        #1;
        data = vif.rd_data;
    endtask


    // ------------------------------------------------------------
    // works out what the MISR signature SHOULD be for a given
    // BIST mode, using the exact same rotate-left-XOR math as the
    // real misr.v hardware. WORD_COUNT=8 matches the RTL parameter.
    // this is basically our "answer key" generator.
    // ------------------------------------------------------------
    function bit [7:0] compute_golden_sig(bist_mode_e mode);
        bit [7:0] sig;
        bit [7:0] lfsr;
        bit [7:0] pattern;
        sig  = 8'h00;
        lfsr = 8'h01;   // matches LFSR_SEED_VAL in spi_bist_top.v

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
            // rotate sig left by 1, then XOR in the pattern byte
            // (this is exactly what misr.v does)
            sig = {sig[6:0], sig[7]} ^ pattern;
        end
        return sig;
    endfunction


    // ------------------------------------------------------------
    // the big dispatcher - looks at what kind of item this is and
    // calls the right drive task
    // ------------------------------------------------------------
    task drive_item(spi_seq_item item);
        case (item.kind)
            NORMAL_XFER:            drive_normal_xfer(item);
            SS_ABORT_XFER:           drive_ss_abort(item);
            RESET_MID_XFER:          drive_reset_mid_xfer(item);
            BIST_RUN:                drive_bist_run(item, 0);
            BIST_BACK_TO_BACK:       drive_bist_run(item, 0);
            BIST_FAULT_INJECT:       drive_bist_run(item, 1);
            BIST_START_WHILE_BUSY:   drive_bist_start_while_busy(item);
            default: `uvm_error("DRV", $sformatf("unknown item kind: %s", item.kind.name()))
        endcase
    endtask


    // TC01, TC05, TC08, TC09 all come through here
    task drive_normal_xfer(spi_seq_item item);
        bit [15:0] status;
        int polls;

        reg_write(A_TXDATA, {8'h00, item.tx_data});
        reg_write(A_CTRL, {item.clk_div, 7'h00, 1'b1});  // clk_div + SPI_EN=1

        polls = 0;
        status = 0;
        while (!status[1] && polls < POLL_LIMIT) begin   // wait for DONE bit
            reg_read(A_STATUS, status);
            @(posedge vif.clk);
            polls++;
        end
        if (polls >= POLL_LIMIT)
            `uvm_error("DRV", "timed out waiting for DONE in drive_normal_xfer")

        reg_write(A_STATUS, 16'h0002);  // clear DONE (write-1-to-clear)
    endtask


    // TC06 - starts a normal transfer then cuts SS_N short
    task drive_ss_abort(spi_seq_item item);
        reg_write(A_TXDATA, {8'h00, item.tx_data});
        reg_write(A_CTRL, {item.clk_div, 7'h00, 1'b1});

        // let the interface handle forcing SS_N high early -
        // see the note at the top of this file about why
        vif.do_ss_abort(item.abort_after_bits);

        // give it a few cycles to settle back to IDLE, then move on
        repeat (10) @(posedge vif.clk);
    endtask


    // TC07 - starts a transfer then resets partway through
    task drive_reset_mid_xfer(spi_seq_item item);
        reg_write(A_TXDATA, {8'h00, item.tx_data});
        reg_write(A_CTRL, {item.clk_div, 7'h00, 1'b1});

        vif.do_reset_pulse(item.reset_after_cycles);

        repeat (10) @(posedge vif.clk);
    endtask


    // TC10, TC11, TC12, TC13, TC15 all come through here.
    // inject_fault=1 is the ONLY difference for TC13 - a real
    // force/release fault, done through the interface, while
    // the expected signature we write is still the CORRECT one.
    // (writing a wrong expected value on purpose is a different,
    // simpler test - that's what corrupt_sig_exp on the item is
    // for, if a sequence ever wants that instead)
    task drive_bist_run(spi_seq_item item, bit inject_fault);
        bit [7:0]  golden;
        bit [15:0] status;
        int polls;

        golden = compute_golden_sig(item.bist_mode);
        if (item.corrupt_sig_exp)
            golden = golden ^ 8'hFF;   // deliberately wrong, simple negative test

        reg_write(A_SIGEXP, {8'h00, golden});

        // one write launches everything: clk_div, bist_mode,
        // BIST_START, BIST_EN all together
        reg_write(A_CTRL, {item.clk_div, 1'b0, 2'b00, item.bist_mode, 1'b1, 1'b1, 1'b0});

        if (inject_fault)
            vif.do_fault_inject();   // real hardware fault, mid-run

        polls = 0;
        status = 0;
        while (!status[2] && !status[3] && polls < POLL_LIMIT) begin  // PASS or FAIL bit
            reg_read(A_STATUS, status);
            @(posedge vif.clk);
            polls++;
        end
        if (polls >= POLL_LIMIT)
            `uvm_error("DRV", "timed out waiting for BIST_PASS/BIST_FAIL")

        reg_write(A_STATUS, 16'h000E);  // clear DONE/PASS/FAIL sticky bits
    endtask


    // TC14 - fire BIST_START twice quickly, second one should
    // just get ignored by the FSM since it's already busy
    task drive_bist_start_while_busy(spi_seq_item item);
        bit [7:0]  golden;
        bit [15:0] status;
        int polls;

        golden = compute_golden_sig(item.bist_mode);
        reg_write(A_SIGEXP, {8'h00, golden});

        // first start - this one should actually take effect
        reg_write(A_CTRL, {item.clk_div, 1'b0, 2'b00, item.bist_mode, 1'b1, 1'b1, 1'b0});

        // second start, right away - FSM should already be busy
        // by now and just ignore this one
        reg_write(A_CTRL, {item.clk_div, 1'b0, 2'b00, item.bist_mode, 1'b1, 1'b1, 1'b0});

        polls = 0;
        status = 0;
        while (!status[2] && !status[3] && polls < POLL_LIMIT) begin
            reg_read(A_STATUS, status);
            @(posedge vif.clk);
            polls++;
        end

        reg_write(A_STATUS, 16'h000E);
    endtask

endclass

`endif
