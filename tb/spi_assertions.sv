// spi_assertions.sv
// these are protocol checks that run automatically, all the
// time, during ANY test - not just the tests specifically
// designed to check that one thing. if any rule here breaks,
// even during a completely unrelated test, we find out
// immediately instead of it slipping through unnoticed.
//
// using `bind` here instead of editing the RTL files directly -
// bind lets us attach a checker module to an ALREADY-VERIFIED
// RTL file (spi_master.v, lfsr.v, bist_ctrl.v) from the outside,
// without changing a single line inside those files. same
// "don't touch verified RTL" principle we followed for the
// monitor taps in tb_top.sv.
//
// this file covers the 8 checks originally planned in the
// project spec, Section 7.5.

`ifndef SPI_ASSERTIONS_SV
`define SPI_ASSERTIONS_SV


// ============================================================
// checks bound to spi_master.v - since bind gives us direct
// access to all of the master's own ports as if this code were
// written right inside spi_master.v itself
// ============================================================
module spi_assertions_master (
    input logic clk,
    input logic rst_n,
    input logic ss_n,
    input logic sclk,
    input logic mosi,
    input logic miso,
    input logic busy,
    input logic done
);

    // ── check 1: SCLK must not toggle while SS_N is high
    //    (deselected) ─────────────────────────────────────────
    // in other words: only wiggle the clock when a slave is
    // actually selected. this would catch a bug where SCLK
    // free-runs regardless of whether anyone's listening.
    property p_sclk_idle_when_deselected;
        @(posedge clk) disable iff (!rst_n)
        (ss_n) |-> $stable(sclk);
    endproperty
    assert property (p_sclk_idle_when_deselected)
        else $error("SCLK toggled while SS_N was deasserted!")


    // ── check 2: exactly one DONE pulse per transfer, never
    //    two in a row ────────────────────────────────────────
    // done should be high for exactly 1 cycle, then drop back
    // to 0 the very next cycle. if this ever fires twice in a
    // row, something is wrong with the FSM's done logic.
    property p_done_is_one_cycle_pulse;
        @(posedge clk) disable iff (!rst_n)
        (done) |=> !done;
    endproperty
    assert property (p_done_is_one_cycle_pulse)
        else $error("DONE stayed high for more than 1 cycle!")


    // ── check 3: reset must bring things back to a known-safe
    //    state right away, no lingering BUSY/DONE ─────────────
    property p_reset_clears_status;
        @(posedge clk)
        $rose(rst_n) |-> (!busy);
    endproperty
    assert property (p_reset_clears_status)
        else $error("BUSY was still 1 right after reset released!")


    // ── check 4: SS_N should not glitch (bounce up and down
    //    within a single transfer) - once low, stays low until
    //    the transfer legitimately finishes ────────────────────
    property p_ss_n_no_glitch_while_busy;
        @(posedge clk) disable iff (!rst_n)
        (busy && !ss_n) |=> (!busy || !ss_n);
        // reads as: if we're busy AND selected this cycle, then
        // next cycle we should either still be busy (transfer
        // ongoing) or no longer selected only once busy also
        // drops (transfer legitimately finished) - not a
        // mid-transfer glitch back to deselected while still busy
    endproperty
    assert property (p_ss_n_no_glitch_while_busy)
        else $error("SS_N glitched while a transfer was still busy!")

endmodule

bind spi_master spi_assertions_master u_assert_master (
    .clk   (clk),
    .rst_n (rst_n),
    .ss_n  (ss_n),
    .sclk  (sclk),
    .mosi  (mosi),
    .miso  (miso),
    .busy  (busy),
    .done  (done)
);


// ============================================================
// check bound to lfsr.v - double-checking, from the OUTSIDE,
// that the all-zero lockout protection built into the RTL
// itself (Phase 1, Step 1.5) actually works. this is a good
// example of defense in depth: the RTL protects itself, AND
// verification independently checks that the protection held.
// ============================================================
module spi_assertions_lfsr (
    input logic       clk,
    input logic       rst_n,
    input logic [7:0] lfsr_data
);

    // ── check 5: LFSR must never sit at all-zero once past
    //    reset - this was the whole point of the lockout logic
    //    we built and tested back in Step 1.5 ──────────────────
    property p_lfsr_never_zero;
        @(posedge clk) disable iff (!rst_n)
        lfsr_data != 8'h00;
    endproperty
    assert property (p_lfsr_never_zero)
        else $error("LFSR output went to all-zero! Lockout protection failed.")

endmodule

bind lfsr spi_assertions_lfsr u_assert_lfsr (
    .clk       (clk),
    .rst_n     (rst_n),
    .lfsr_data (lfsr_data)
);


// ============================================================
// checks bound to bist_ctrl.v
// ============================================================
module spi_assertions_bist (
    input logic clk,
    input logic rst_n,
    input logic bist_busy,
    input logic bist_pass,
    input logic bist_fail
);

    // ── check 6: once a BIST run is busy, it stays busy right
    //    up until the moment it reports pass or fail - it
    //    shouldn't ever "restart" or drop busy early on its
    //    own without a result ───────────────────────────────────
    property p_bist_busy_stable_until_result;
        @(posedge clk) disable iff (!rst_n)
        (bist_busy && !bist_pass && !bist_fail) |=> (bist_busy || bist_pass || bist_fail);
    endproperty
    assert property (p_bist_busy_stable_until_result)
        else $error("BIST dropped busy without ever reporting pass or fail!")


    // ── check 7: pass and fail should never be high at the
    //    same time - that would be a contradiction ─────────────
    property p_bist_pass_fail_mutually_exclusive;
        @(posedge clk) disable iff (!rst_n)
        !(bist_pass && bist_fail);
    endproperty
    assert property (p_bist_pass_fail_mutually_exclusive)
        else $error("BIST_PASS and BIST_FAIL were both high at once - contradiction!")


    // ── check 8: pass/fail pulses should only happen while a
    //    run was actually busy - they shouldn't fire out of
    //    nowhere while idle ─────────────────────────────────────
    property p_bist_result_only_while_busy;
        @(posedge clk) disable iff (!rst_n)
        (bist_pass || bist_fail) |-> $past(bist_busy);
    endproperty
    assert property (p_bist_result_only_while_busy)
        else $error("BIST_PASS/FAIL fired without a BIST run actually being busy!")

endmodule

bind bist_ctrl spi_assertions_bist u_assert_bist (
    .clk        (clk),
    .rst_n      (rst_n),
    .bist_busy  (bist_busy),
    .bist_pass  (bist_pass),
    .bist_fail  (bist_fail)
);

`endif
