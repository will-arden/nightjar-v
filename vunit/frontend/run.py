import sys, os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import tb_tools

from vunit import VUnit

vu = VUnit.from_argv() # Create VUnit instance by parsing command line arguments
vu.add_vhdl_builtins() # Add VUnit's builtin HDL utilities for checking, logging, communication...
lib = vu.add_library("lib") # Create a new library

# Add RTL files
lib.add_source_file("../rtl/common_pkg.vhd")
lib.add_source_file("../rtl/frontend.vhd")

# Add testbench files
lib.add_source_files("frontend/*.vhd")

# Set compilation and simulation options
vu.set_compile_option("ghdl.a_flags", ["-frelaxed", "-Wshared"]) # Set GHDL compile options
vu.set_sim_option("ghdl.elab_flags", ["-frelaxed", "-Wshared"]) # Set GHDL simulation options

# Run VUnit simulation
try:
    vu.main()
except SystemExit as e:
    print(f"VUnit exited with code: {e.code}")
