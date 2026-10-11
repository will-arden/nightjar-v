import sys, os
import random
import math
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import tb_tools

###################
# Test parameters #
###################

###############
# VUnit Setup #
###############

from vunit import VUnit

vu = VUnit.from_argv() # Create VUnit instance by parsing command line arguments
vu.add_vhdl_builtins() # Add VUnit's builtin HDL utilities for checking, logging, communication...
lib = vu.add_library("lib") # Create a new library

# Add VHDL sources and testbenches
lib.add_source_file("../rtl/common_pkg.vhd")
lib.add_source_file("../sim/wb_mem.vhd")
lib.add_source_file("../rtl/wb_master.vhd")

# Declare the testbench
lib.add_source_files("wb_master/*.vhd")
tb = lib.test_bench("tb_wb_master")

# Set generics
# tb.set_generic("G_CACHE_SETS", T_CACHE_SETS)

# Set compilation and simulation options
vu.set_compile_option("ghdl.a_flags", ["-frelaxed", "-Wshared"])    # Set GHDL compile options
vu.set_sim_option("ghdl.elab_flags", ["-frelaxed", "-Wshared"])     # Set GHDL simulation options

##########################
# Begin VUnit simulation #
##########################

try:
    vu.main()
except SystemExit as e:
    print(f"VUnit exited with code: {e.code}")
