############## Makefile ##############
# ---------------------------------- #
############## chomp-v ###############
# Make targets:
#   - help          : Prints Makefile help information
#   - clean         : Removes temporary/unwanted files, such as logs
#   - all           : (Default option) creates the Vivado project from scratch, placing it in chomp-v/project
#   - project       : Creates the Vivado project from scratch, placing it in chomp-v/project
#   - find_vivado   : Shows the detected Vivado installation

# Provide your Vivado installation location manually by setting this variable:
# VIVADO_PATH := /path/to/vivado

TCL_SCRIPT := scripts/create_project.tcl

ifndef VIVADO_PATH
  ifeq ($(OS),Windows_NT)
    VIVADO_FULL := $(shell where vivado 2>nul)
    ifneq ($(VIVADO_FULL),)
      VIVADO := vivado
    else
      VIVADO :=
    endif
  else
    VIVADO := $(shell which vivado 2>/dev/null)
  endif
else
  VIVADO := $(VIVADO_PATH)
endif

ifeq ($(VIVADO),)
  VIVADO_FOUND := no
  VIVADO_MSG := Vivado not found in PATH!
else
  VIVADO_FOUND := yes
  VIVADO_MSG := Found Vivado at: $(VIVADO)
endif

.PHONY: all project clean help find_vivado

all: project

find_vivado:
	@echo "$(VIVADO_MSG)"
ifeq ($(VIVADO_FOUND),no)
	@echo ""
	@echo "You can edit this Makefile to manually enter the path to your Vivado installation."
	@echo ""
endif

project:
ifeq ($(VIVADO_FOUND),no)
	@echo "Error: $(VIVADO_MSG)"
	@echo "Run 'make find_vivado' for more information"
	@exit 1
endif
	@echo "Using Vivado: $(VIVADO)"
	$(VIVADO) -mode batch -source $(TCL_SCRIPT)
	@echo ""
	@echo "The Vivado project can be found in chomp-v/project/"

clean:
	@echo "Cleaning project files..."
	rm -rf project
	rm -rf *.log *.jou .Xil

vunit_all:
	@echo "Running all VUnit tests..."
	python3 vunit/run.py

help:
	@echo ""
	@echo "chomp-v Makefile"
	@echo "----------------------------"
	@echo ""
	@echo "Make targets:"
	@echo "  help               - Prints Makefile help information"
	@echo "  clean              - Removes temporary/unwanted files, such as logs"
	@echo "  all (default)      - (Default option) creates the Vivado project from scratch, placing it in chomp-v/project"
	@echo "  project            - Creates the Vivado project from scratch, placing it in chomp-v/project"
	@echo "  find_vivado        - Shows the detected Vivado installation "