SIM_LIST := frontend

.PHONY: all clean sim-%

clean:
	rm -rf test_artefacts/
	rm -rf vunit_out/

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