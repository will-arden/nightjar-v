VENV_DIR=".venv"

.PHONY: clean env fifo all

clean:
	@echo "Cleaning simulation environment..."
	@rm -rf vunit_out/
	@rm -rf test_artefacts/
	@rm -rf $(VENV_DIR)/

env: clean
	@python3 --version
	@python3 -m venv $(VENV_DIR)
	@. $(VENV_DIR)/bin/activate && python3 -m pip install -r venv_reqs.txt
	@echo "Virtual environment created in $(VENV_DIR)/"
	@echo "Run . $(VENV_DIR)/bin/activate\n"

fifo:
	python3 run.py --clean --gtkwave-fmt ghw

all: clean
	@echo "Running all VUnit tests..."
	python3 run.py --clean
