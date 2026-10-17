SIM_LIST := cache wb_master sync_fifo

.PHONY: all help clean sim-%

all: help

clean:
	rm -rf test_artefacts/
	rm -rf vunit_out/

help:
	@echo "\nTo run a simulation (e.g. "frontend"), enter the following command:"
	@echo ">   make sim-cache\n"
	@echo "The list of available simulations is as follows:"
	@for sim in $(SIM_LIST); do \
		echo " - $$sim"; \
	done;
	@echo ""

sim-%: clean

# Check that the simulation exists
	@if [ -z "$(filter $*,$(SIM_LIST))" ]; then \
		echo "The simulation \"$*\" does not exist. Please choose from the following list:"; \
		for sim in $(SIM_LIST); do \
			echo " - $$sim"; \
		done; \
		exit 1; \
	fi

# Run the simulation
	@echo "--------------------------------------------------------"
	@echo "RUNNING SIMULATION: $*"
	@echo "--------------------------------------------------------"
	@echo ""
	python3 $*/run.py --gtkwave-fmt=ghw