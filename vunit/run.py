import tb_tools

from vunit import VUnit
import difflib

vu = VUnit.from_argv() # Create VUnit instance by parsing command line arguments
vu.add_vhdl_builtins() # Add VUnit's builtin HDL utilities for checking, logging, communication...

# Setup VUnit with GHDL
lib = vu.add_library("lib") # Create a new library
lib.add_source_files("../rtl/*.vhd") # Add RTL files
lib.add_source_files("*.vhd") # Add testbench files
vu.set_compile_option("ghdl.a_flags", ["-frelaxed", "-Wshared"]) 
vu.set_sim_option("ghdl.elab_flags", ["-frelaxed", "-Wshared"]) # Configure GHDL simulation arguments

# Generate test vectors
tb_tools.generate_test_vectors_csv(32, 64, filepath="test_artefacts/sync_fifo_inputs.csv")

# Run vunit function
try:
    vu.main()
except SystemExit as e:
    print(f"VUnit exited with code: {e.code}")

# Diff the inputs and  outputs
with open("test_artefacts/sync_fifo_inputs.csv") as f1, open("test_artefacts/sync_fifo_outputs.csv") as f2:
    diff = difflib.unified_diff(
        f1.readlines(),
        f2.readlines(),
        fromfile="test_artefacts/sync_fifo_inputs.csv",
        tofile="test_artefacts/sync_fifo_outputs.csv"
    )

if ("".join(diff) == ""):
    print(f"No diff!")
print("".join(diff))