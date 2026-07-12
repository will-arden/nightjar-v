import sys, os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import tb_tools

###################
# Test parameters #
###################

T_IMEM_DEPTH = 256
T_MEM_INIT_PATH = "test_artefacts/imem.csv"

###############
# VUnit Setup #
###############

from vunit import VUnit

vu = VUnit.from_argv() # Create VUnit instance by parsing command line arguments
vu.add_vhdl_builtins() # Add VUnit's builtin HDL utilities for checking, logging, communication...
lib = vu.add_library("lib") # Create a new library

# Add RTL files
lib.add_source_file("../rtl/common_pkg.vhd")
lib.add_source_file("../rtl/frontend.vhd")
lib.add_source_file("../sim/imem.vhd")

# Declare the testbench
lib.add_source_files("frontend/*.vhd")
tb = lib.test_bench("tb_frontend")

# Set generics
tb.set_generic("G_IMEM_DEPTH", T_IMEM_DEPTH)
tb.set_generic("G_MEM_INIT_PATH", T_MEM_INIT_PATH)

# Set compilation and simulation options
vu.set_compile_option("ghdl.a_flags", ["-frelaxed", "-Wshared"])    # Set GHDL compile options
vu.set_sim_option("ghdl.elab_flags", ["-frelaxed", "-Wshared"])     # Set GHDL simulation options

##############################################
# Generate test vectors and expected results #
##############################################

# Generate random memory contents
tb_tools.generate_test_vectors_csv(width=32, num_rows=T_IMEM_DEPTH, filepath=T_MEM_INIT_PATH)

# Index the memory with addresses
addr_list = []
for i in range(0, T_IMEM_DEPTH):
    addr_list.append(i * 4)
tb_tools.csv_add_column_left(csv_path=T_MEM_INIT_PATH, row_data=addr_list)

# Add headers
tb_tools.csv_insert_row(csv_path=T_MEM_INIT_PATH, new_row=["address", "data"])

##########################
# Begin VUnit simulation #
##########################

try:
    vu.main()
except SystemExit as e:
    print(f"VUnit exited with code: {e.code}")
