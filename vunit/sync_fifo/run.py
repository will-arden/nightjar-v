import sys, os
import random
import math
import difflib
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import tb_tools

###############
# VUnit Setup #
###############

from vunit import VUnit

vu = VUnit.from_argv() # Create VUnit instance by parsing command line arguments
vu.add_vhdl_builtins() # Add VUnit's builtin HDL utilities for checking, logging, communication...
lib = vu.add_library("lib") # Create a new library

# Add RTL files
lib.add_source_file("../rtl/common_pkg.vhd")
lib.add_source_file("../rtl/generic_ram.vhd")
lib.add_source_file("../rtl/sync_fifo.vhd")

# Declare the testbench
lib.add_source_files("sync_fifo/*.vhd")
tb = lib.test_bench("tb_sync_fifo")

# Set compilation and simulation options
vu.set_compile_option("ghdl.a_flags", ["-frelaxed", "-Wshared"])    # Set GHDL compile options
vu.set_sim_option("ghdl.elab_flags", ["-frelaxed", "-Wshared"])     # Set GHDL simulation options

# Generate test vectors
tb_tools.generate_test_vectors_csv(32, 64, filepath="test_artefacts/sync_fifo_inputs.csv")

##########################
# Begin VUnit simulation #
##########################

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