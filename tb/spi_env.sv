// spi_env.sv
// this is where everything from steps 2.1-2.7 actually gets
// wired together into one working environment. the important
// part is right at the bottom of connect_phase - one single
// broadcast from the agent gets connected to BOTH the
// scoreboard AND the coverage collector at the same time.
//
// this "one broadcast, many listeners" thing is the whole point
// of analysis ports in UVM - the monitor doesn't need to know
// or care how many things are listening to it. it just does
// ap.write(item) once, and UVM fans that out to everyone who
// connected to it. could be 2 listeners like here, could be 5,
// monitor code never changes either way.

`ifndef SPI_ENV_SV
`define SPI_ENV_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "spi_agent.sv"
`include "spi_scoreboard.sv"
`include "spi_coverage.sv"

class spi_env extends uvm_env;
    `uvm_component_utils(spi_env)

    spi_agent      agent;
    spi_scoreboard scoreboard;
    spi_coverage   coverage;

    function new(string name = "spi_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = spi_agent::type_id::create("agent", this);
        scoreboard = spi_scoreboard::type_id::create("scoreboard", this);
        coverage   = spi_coverage::type_id::create("coverage", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // this is the important bit - same agent.ap, two
        // separate connections. both the scoreboard and the
        // coverage collector get an identical copy of every
        // single item the monitor ever observes.
        agent.ap.connect(scoreboard.imp);
        agent.ap.connect(coverage.analysis_export);
    endfunction

endclass

`endif
