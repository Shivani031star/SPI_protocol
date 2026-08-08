//==============================================================
// spi_seq_item.sv  (SIMPLE VERSION - explained for beginners)
//---------------------------------------------------------------
// Project : SPI Bus Protocol with Built-In Self-Test (BIST)
// Author  : Sarthak (C-DAC ACTS DVLSI, Pune)
// Step    : Phase 2, Step 2.1
//---------------------------------------------------------------
// WHAT IS THIS FILE FOR? (read this first)
//
// Think of this class like a "form" or "slip of paper" that
// describes ONE thing we want to do to the chip - for example:
//   "Send the byte 0xA5 with clk_div = 4"
//   or
//   "Run a BIST test using Mode 2 (random pattern)"
//
// Later, other UVM parts will use this "slip" like this:
//   1. A Sequence fills in the slip with random values
//   2. The Driver reads the slip and does register writes on
//      the DUT to actually perform what the slip says
//   3. The Monitor watches the DUT and writes down what
//      actually happened, on a COPY of this same slip
//   4. The Scoreboard compares "what we asked for" vs
//      "what actually happened" and decides pass/fail
//
// So this file does NOT do anything by itself. It's just the
// DEFINITION of what one "slip of paper" looks like.
//==============================================================

`ifndef SPI_SEQ_ITEM_SV
`define SPI_SEQ_ITEM_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

//---------------------------------------------------------------
// This list says: "what KIND of thing are we asking the chip
// to do?" Every one of our 16 test cases falls into one of
// these 7 buckets.
//---------------------------------------------------------------
typedef enum {
    NORMAL_XFER,             // just send one byte normally
    SS_ABORT_XFER,            // send a byte but cut it short on purpose
    RESET_MID_XFER,           // send a byte but reset the chip halfway
    BIST_RUN,                 // run a normal (healthy) BIST test
    BIST_FAULT_INJECT,         // run BIST but break something on purpose
    BIST_START_WHILE_BUSY,     // try to start BIST twice too fast
    BIST_BACK_TO_BACK          // run BIST twice in a row
} spi_txn_kind_e;

//---------------------------------------------------------------
// This list says: "if we ARE doing BIST, which of the 3 modes?"
// These numbers must match CTRL_REG bits [4:3] exactly.
//---------------------------------------------------------------
typedef enum bit [1:0] {
    BIST_MODE_LOOPBACK = 2'b00,   // always sends the same byte
    BIST_MODE_WALK1    = 2'b01,   // walks a single 1-bit through
    BIST_MODE_PRBS      = 2'b10   // random-looking pattern (LFSR)
} bist_mode_e;


//---------------------------------------------------------------
// The actual "slip of paper" class.
// `extends uvm_sequence_item` means: "this is a real UVM
// transaction, plug it into the standard UVM machinery."
//---------------------------------------------------------------
class spi_seq_item extends uvm_sequence_item;

    // ── What are we asking for? ──────────────────────────────
    rand spi_txn_kind_e kind;     // pick ONE of the 7 buckets above

    // ── If it's a normal transfer, these matter ──────────────
    rand bit [7:0] tx_data;       // the byte to send
    rand bit [7:0] clk_div;       // how slow/fast SCLK should be

    // ── If it's a BIST run, these matter ─────────────────────
    rand bist_mode_e bist_mode;         // which of the 3 BIST modes
    rand bit         corrupt_sig_exp;    // 1 = write a WRONG expected
                                          // answer on purpose, to check
                                          // that BIST correctly says FAIL

    // ── Only used for the "break it on purpose" tests ────────
    rand int unsigned abort_after_bits;   // cut transfer short after N bits
    rand int unsigned reset_after_cycles; // reset after N clock cycles

    // ── Filled in LATER by the Monitor, not randomized here ──
    // These are like the "answer" section of the slip, filled
    // in AFTER watching what the chip actually did.
    bit [7:0] observed_rx_data;
    bit       observed_done;
    bit       observed_bist_pass;
    bit       observed_bist_fail;
    bit [3:0] observed_err_code;
    bit [7:0] observed_bist_sig_act;
    bit [7:0] bist_sig_exp;


    //-----------------------------------------------------------
    // RULES for the random values (so they never become silly
    // or illegal numbers)
    //-----------------------------------------------------------

    // clk_div must never be 0 - the hardware would break if the
    // divider counter never wraps around. Keep it small-ish too,
    // so simulations don't take forever.
    constraint c_clk_div_legal {
        clk_div inside {[1:16]};
    }

    // If we're cutting a transfer short, only cut it somewhere
    // between bit 1 and bit 7 (cutting at bit 0 or bit 8 doesn't
    // make sense for this test).
    constraint c_abort_bits_legal {
        abort_after_bits inside {[1:7]};
    }

    // Same idea for the reset timing test.
    constraint c_reset_cycles_legal {
        reset_after_cycles inside {[1:20]};
    }

    // We don't want all 7 kinds to happen equally often. In real
    // life, normal transfers happen most of the time and BIST
    // fault-injection is rare - so we tell the randomizer to
    // pick NORMAL_XFER about 40% of the time, and the rarer
    // scenarios much less often. This is just like a weighted
    // dice roll instead of a normal 1-in-7 fair dice roll.
    constraint c_kind_distribution {
        kind dist {
            NORMAL_XFER            := 40,
            SS_ABORT_XFER           := 10,
            RESET_MID_XFER          := 10,
            BIST_RUN                := 20,
            BIST_FAULT_INJECT        := 8,
            BIST_START_WHILE_BUSY    := 6,
            BIST_BACK_TO_BACK        := 6
        };
    }


    //-----------------------------------------------------------
    // These next lines are UVM "magic" macros. You don't need
    // to fully understand them yet - just know they auto-write
    // some boring but necessary code for you (how to copy this
    // object, how to compare two of them, how to print one out
    // nicely in the log). Without these, we'd have to write that
    // code by hand for every single field above.
    //-----------------------------------------------------------
    `uvm_object_utils_begin(spi_seq_item)
        `uvm_field_enum(spi_txn_kind_e, kind,        UVM_ALL_ON)
        `uvm_field_int(tx_data,                       UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(clk_div,                       UVM_ALL_ON | UVM_DEC)
        `uvm_field_enum(bist_mode_e, bist_mode,       UVM_ALL_ON)
        `uvm_field_int(corrupt_sig_exp,               UVM_ALL_ON)
        `uvm_field_int(abort_after_bits,              UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(reset_after_cycles,            UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(observed_rx_data,              UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(observed_done,                 UVM_ALL_ON)
        `uvm_field_int(observed_bist_pass,            UVM_ALL_ON)
        `uvm_field_int(observed_bist_fail,            UVM_ALL_ON)
        `uvm_field_int(observed_err_code,             UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(observed_bist_sig_act,          UVM_ALL_ON | UVM_HEX)
    `uvm_object_utils_end

    //-----------------------------------------------------------
    // Every UVM class needs a "new" function like this - it's
    // just how you create ("construct") an object in SystemVerilog.
    // You will see this exact pattern in EVERY UVM file we write.
    //-----------------------------------------------------------
    function new(string name = "spi_seq_item");
        super.new(name);
    endfunction

    //-----------------------------------------------------------
    // A short helper that turns this object into one readable
    // line of text for the simulation log - much easier to scan
    // through than the full auto-generated dump.
    //-----------------------------------------------------------
    function string convert2string();
        string s;
        s = $sformatf("kind=%s", kind.name());

        if (kind == NORMAL_XFER || kind == SS_ABORT_XFER || kind == RESET_MID_XFER)
            s = {s, $sformatf(" tx_data=0x%0h clk_div=%0d", tx_data, clk_div)};

        if (kind == BIST_RUN || kind == BIST_FAULT_INJECT ||
            kind == BIST_START_WHILE_BUSY || kind == BIST_BACK_TO_BACK)
            s = {s, $sformatf(" bist_mode=%s corrupt_exp=%0b",
                                bist_mode.name(), corrupt_sig_exp)};

        if (kind == SS_ABORT_XFER)
            s = {s, $sformatf(" abort_after_bits=%0d", abort_after_bits)};

        if (kind == RESET_MID_XFER)
            s = {s, $sformatf(" reset_after_cycles=%0d", reset_after_cycles)};

        return s;
    endfunction

endclass

`endif // SPI_SEQ_ITEM_SV
