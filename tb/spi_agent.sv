// spi_agent.sv
// an "agent" is just a box that bundles the sequencer, driver,
// and monitor together into one reusable unit, so the
// environment (step 2.8) only has to build ONE thing instead
// of wiring up 3 separate pieces itself every time.
//
// most agents support two modes:
//   ACTIVE  - has a sequencer+driver AND a monitor (can both
//             drive stimulus and watch results)
//   PASSIVE - has ONLY a monitor (just watches, doesn't drive
//             anything - useful if you want a second monitor
//             somewhere just observing, with no ability to mess
//             with the DUT)
// we're always going to run in ACTIVE mode for this project
// since we obviously need to drive the DUT, but including the
// is_active switch is just standard good practice - it's what
// every real UVM agent looks like, so I kept it in.

`ifndef SPI_AGENT_SV
`define SPI_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "spi_sequencer.sv"
`include "spi_driver.sv"
`include "spi_monitor.sv"

class spi_agent extends uvm_agent;
    `uvm_component_utils(spi_agent)

    spi_sequencer sequencer;
    spi_driver    driver;
    spi_monitor   monitor;

    // this analysis port just passes straight through from the
    // monitor's own port, so anything outside the agent (like
    // the environment) can hook onto agent.ap without needing
    // to know the monitor even exists inside here
    uvm_analysis_port #(spi_seq_item) ap;

    function new(string name = "spi_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // monitor always gets built, active or passive
        monitor = spi_monitor::type_id::create("monitor", this);

        // sequencer and driver only get built if we're active.
        // is_active is a built-in uvm_agent field, defaults to
        // UVM_ACTIVE unless something sets it otherwise
        if (is_active == UVM_ACTIVE) begin
            sequencer = spi_sequencer::type_id::create("sequencer", this);
            driver    = spi_driver::type_id::create("driver", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // hook the agent's own ap straight to the monitor's ap
        ap = monitor.ap;

        // wire the driver up to pull items from the sequencer -
        // this is the actual TLM connection that makes
        // get_next_item/item_done work
        if (is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass

`endif
