// spi_if.sv
// this bundles up every wire the driver/monitor need to touch,
// so instead of passing 10+ separate signals around everywhere,
// we just pass ONE handle to this interface.
//
// a design choice worth explaining: do_ss_abort() and
// do_fault_inject() below need to reach INSIDE the DUT (force a
// signal that isn't a normal port) - but interfaces reaching
// into a sibling module's internals is a bit of a grey area
// across different simulators. so instead of doing the force
// directly here, this interface just raises a "please do this"
// request flag and waits for tb_top to say "done" - tb_top is
// the one place that legitimately, unambiguously has access to
// the DUT's internals (since it's the module that instantiates
// the DUT directly), so that's where the actual force/release
// happens. this file just exposes a clean task the driver can
// call without needing to know any of that.
//
// do_reset_pulse() is simpler and doesn't need any of this -
// rst_n is already a normal port, so this interface can just
// drive it directly, no handshake needed.

`ifndef SPI_IF_SV
`define SPI_IF_SV

interface spi_if(input bit clk);

    // ── reset - driven from tb_top at the start, and also
    //    directly by do_reset_pulse() below when needed ──────
    logic rst_n;

    // ── register bus (same signals as spi_bist_top.v's ports) ─
    logic        wr_en;
    logic [3:0]  wr_addr;
    logic [15:0] wr_data;
    logic [3:0]  rd_addr;
    logic [15:0] rd_data;

    // ── external SPI pins ─────────────────────────────────────
    logic spi_sclk;
    logic spi_mosi;
    logic spi_ss_n;
    logic spi_miso;

    // ── debug pulses straight from the DUT ────────────────────
    logic bist_pass_pulse;
    logic bist_fail_pulse;

    // ── monitor-only taps - tb_top wires these directly to the
    //    DUT's internal wires with continuous assigns, giving
    //    the monitor a clean always-live view with no bus
    //    contention (see the note in spi_monitor.sv about why) ─
    logic [7:0] mon_rx_data;
    logic       mon_done;
    logic       mon_bist_pass;
    logic       mon_bist_fail;
    logic [3:0] mon_err_code;
    logic [7:0] mon_bist_sig_act;

    // ── request/ack handshake for the two tests that need to
    //    reach inside the DUT (tb_top watches these) ───────────
    logic       ss_abort_req;
    logic [2:0] ss_abort_bits;
    logic       ss_abort_done;

    logic       fault_inject_req;
    logic       fault_inject_done;


    // simplest one - reset is a normal port, no handshake needed
    task do_reset_pulse(input int cycles);
        repeat (cycles) @(posedge clk);
        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
    endtask

    // raises the request, waits for tb_top to signal it's done
    task do_ss_abort(input int bits);
        ss_abort_bits = bits;
        ss_abort_req  = 1;
        @(posedge ss_abort_done);
        ss_abort_req  = 0;
        @(posedge clk);
    endtask

    // same handshake idea for fault injection
    task do_fault_inject();
        fault_inject_req = 1;
        @(posedge fault_inject_done);
        fault_inject_req = 0;
        @(posedge clk);
    endtask

endinterface

`endif
