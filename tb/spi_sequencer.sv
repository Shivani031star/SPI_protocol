// spi_sequencer.sv
// the sequencer's job is basically just traffic control - it
// sits between the sequences (step 2.2) and the driver (step
// 2.3), and manages the get_next_item/item_done handshake for
// us automatically.
//
// there's barely any code to write here because uvm_sequencer
// already does all the real work - we just make our own typed
// version of it so it knows it's carrying spi_seq_item objects
// specifically, not some generic item.

`ifndef SPI_SEQUENCER_SV
`define SPI_SEQUENCER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "spi_seq_item.sv"

class spi_sequencer extends uvm_sequencer #(spi_seq_item);
    `uvm_component_utils(spi_sequencer)

    function new(string name = "spi_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass

`endif
