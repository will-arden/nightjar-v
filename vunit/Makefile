.PHONY: clean all

clean:
	@echo "Cleaning VUnit files..."
	rm -rf vunit_out/
	rm -rf inputs/

all: clean
	@echo "Running all VUnit tests..."
	python3 run.py --clean

fifo:
	python3 run.py --clean --gtkwave-fmt ghw