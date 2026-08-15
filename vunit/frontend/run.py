import sys, os
import random
import math
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import tb_tools

###################
# Test parameters #
###################

T_IMEM_DEPTH = 256
T_MEM_INIT_PATH = "test_artefacts/imem.csv"
T_TRANSACTION_CSV_PATH = "test_artefacts/transactions.csv"
T_RESULTS_CSV_PATH = "test_artefacts/results.csv"
T_NUM_TRANSACTIONS = 100

###############
# VUnit Setup #
###############

from vunit import VUnit

vu = VUnit.from_argv() # Create VUnit instance by parsing command line arguments
vu.add_vhdl_builtins() # Add VUnit's builtin HDL utilities for checking, logging, communication...
lib = vu.add_library("lib") # Create a new library

# Add RTL files
lib.add_source_file("../rtl/common_pkg.vhd")
lib.add_source_file("../rtl/icache.vhd")
lib.add_source_file("../rtl/frontend.vhd")
lib.add_source_file("../sim/imem.vhd")

# Declare the testbench
lib.add_source_files("frontend/*.vhd")
tb = lib.test_bench("tb_frontend")

# Set generics
tb.set_generic("G_IMEM_DEPTH", T_IMEM_DEPTH)
tb.set_generic("G_MEM_INIT_PATH", T_MEM_INIT_PATH)
tb.set_generic("G_TRANSACTIONS_PATH", T_TRANSACTION_CSV_PATH)
tb.set_generic("G_RESULTS_PATH", T_RESULTS_CSV_PATH)

# Set compilation and simulation options
vu.set_compile_option("ghdl.a_flags", ["-frelaxed", "-Wshared"])    # Set GHDL compile options
vu.set_sim_option("ghdl.elab_flags", ["-frelaxed", "-Wshared"])     # Set GHDL simulation options

##############################################
# Generate test vectors and expected results #
##############################################

# Generate random memory contents
tb_tools.generate_test_vectors_csv(width=32, num_rows=T_IMEM_DEPTH, filepath=T_MEM_INIT_PATH)
addr_list = []
for i in range(0, T_IMEM_DEPTH):
    addr_list.append(i * 4)
tb_tools.csv_add_column_left(csv_path=T_MEM_INIT_PATH, row_data=addr_list)
tb_tools.csv_insert_row(csv_path=T_MEM_INIT_PATH, new_row=["address", "data"])

# Generate random addresses to access
tb_tools.new_csv(filepath=T_TRANSACTION_CSV_PATH)
tb_tools.csv_insert_row(csv_path=T_TRANSACTION_CSV_PATH, new_row=["address", "expected_data", "actual_data", "latency"])
for i in range(0, T_NUM_TRANSACTIONS):
    csv_index = random.randint(0, T_IMEM_DEPTH - 1) + 1
    address = tb_tools.csv_read_cell(csv_path=T_MEM_INIT_PATH, row=csv_index, col=0)
    expected_data = tb_tools.csv_read_cell(csv_path=T_MEM_INIT_PATH, row=csv_index, col=1)
    new_row = [address, expected_data, "-", "-"]
    tb_tools.csv_append_row(csv_path=T_TRANSACTION_CSV_PATH, new_row=new_row)

##########################
# Begin VUnit simulation #
##########################

try:
    vu.main()
except SystemExit as e:
    print(f"VUnit exited with code: {e.code}")

###############################
# Perform analysis of results #
###############################

for row in range(1, T_NUM_TRANSACTIONS):
    result = tb_tools.csv_read_cell(csv_path=T_RESULTS_CSV_PATH, row=row, col=0)
    expected = tb_tools.csv_read_cell(csv_path=T_TRANSACTION_CSV_PATH, row=row, col=1)
    print(f"Result = {result} \tExpected = {expected}")

    if (result is None or result != expected):
        print(f"RESULTS DO NOT MATCH")