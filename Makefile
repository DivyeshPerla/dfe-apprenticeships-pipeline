# Convenience wrapper. The SSL_CERT_FILE export works around this machine's
# Python 3.10.0 lacking a usable system CA bundle (breaks dbt + some pip builds).
VENV := ./.venv/bin
export SSL_CERT_FILE := $(shell ./.venv/bin/python -c "import certifi;print(certifi.where())" 2>/dev/null)
export DBT_PROFILES_DIR := $(CURDIR)/dbt
PROJECT := dfe-apprenticeships-2026
BUCKET  := dfe-appr-bronze-dfe-apprenticeships-2026

.PHONY: extract backfill bronze dbt-debug run test docs clean

extract:            ## pull the latest published version into GCS bronze
	PYTHONPATH=src $(VENV)/python -m ingestion.extract --gcs-bucket $(BUCKET)

backfill:           ## pull every published version into GCS bronze
	PYTHONPATH=src $(VENV)/python -m ingestion.extract --all-versions --gcs-bucket $(BUCKET)

bronze:             ## (re)create the bronze external table
	PROJECT=$(PROJECT) BUCKET=$(BUCKET) ./sql/bronze/create_external_table.sh

dbt-debug:
	cd dbt && ../$(VENV)/dbt debug

run:
	cd dbt && ../$(VENV)/dbt run

test:
	cd dbt && ../$(VENV)/dbt test

docs:
	cd dbt && ../$(VENV)/dbt docs generate

clean:
	cd dbt && ../$(VENV)/dbt clean
