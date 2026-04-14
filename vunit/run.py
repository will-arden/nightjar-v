from vunit import VUnit
import tb_tools

vu = VUnit.from_argv() # Create VUnit instance by parsing command line arguments
vu.add_vhdl_builtins() # Add VUnit's builtin HDL utilities for checking, logging, communication...

# Create library
lib = vu.add_library("lib")

# Add RTL files
lib.add_source_files("../rtl/*.vhd")

# Add testbench files
lib.add_source_files("*.vhd")

# Generate test vectors
tb_tools.generate_test_vectors_csv(32, 512, filepath="inputs/sync_fifo_inputs.csv")

# Run vunit function
vu.main()