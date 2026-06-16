import tb_tools

from vunit import VUnit
import difflib

vu = VUnit.from_argv() # Create VUnit instance by parsing command line arguments
vu.add_vhdl_builtins() # Add VUnit's builtin HDL utilities for checking, logging, communication...
lib = vu.add_library("lib") # Create a new library
vu.set_compile_option("ghdl.a_flags", ["-frelaxed", "-Wshared"]) # Set GHDL compile options
vu.set_sim_option("ghdl.elab_flags", ["-frelaxed", "-Wshared"]) # Set GHDL simulation options

# Add RTL files
lib.add_source_file("../rtl/generic_ram.vhd")
lib.add_source_file("../rtl/sync_fifo.vhd")

# Add testbench files
lib.add_source_files("*.vhd")

# Generate test vectors
tb_tools.generate_test_vectors_csv(32, 64, filepath="test_artefacts/sync_fifo_inputs.csv")

# Run VUnit simulation
try:
    vu.main()
except SystemExit as e:
    print(f"VUnit exited with code: {e.code}")

# Check that there is no difference between actual and expected results
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