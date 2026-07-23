SNAKEMAKE ?= snakemake
PROFILE ?= profiles/generic.yaml
REQ_FILE ?= requirements.txt

SHELL := /bin/bash -l

.PHONY: help setup dry-run dag run-job interactive clean reset

help:
	@printf "Available targets:\n"
	@printf "  make setup        - create/update the workflow environment\n"
	@printf "  make dry-run      - dry-run the workflow using the SLURM profile\n"
	@printf "  make dag          - render the DAG to dag.svg\n"
	@printf "  make run		     - run Snakemake directly on the login node\n"
	@printf "  make clean        - remove generated workflow files and logs\n"

setup:
	python3 -m venv venv
	venv/bin/pip install -r $(REQ_FILE)
	@echo "Virtual environment created! Please run 'source venv/bin/activate' before running other make targets."

dry-run:
	$(SNAKEMAKE) --profile $(PROFILE) --dry-run

dag:
	$(SNAKEMAKE) --profile $(PROFILE) --dag | dot -Tsvg > dag.svg

run:
	$(SNAKEMAKE) --profile $(PROFILE) --cores 1

clean:
	@rm -rf cavity/logs/* cavity/simulation_done.txt .snakemake/* efficiency_report* cavity/processor*
	@bash cavity/clean
	@foamDictionary cavity/system/controlDict -entry endTime -set 0.001
