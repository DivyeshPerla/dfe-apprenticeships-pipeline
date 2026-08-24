# DfE Apprenticeships Data Platform (GCP)

End-to-end data engineering case study on the UK Department for Education
apprenticeships headline statistics: batch ETL, event-driven incremental loads,
dimensional modelling, data quality, and an AI analytics layer — all on GCP.

- **Plan:** [`PLAN.md`](PLAN.md)
- **Source profiling & evidence:** [`docs/profiling/PROFILE.md`](docs/profiling/PROFILE.md)

## Source
Explore Education Statistics API — no API key required.
Dataset `1d419801-a90e-f970-9335-a13623faccbe`:
*Headline Full year — Starts, Achievements, Participation by Level, Levy, Age,
Region, Provider type.* 51,298 rows, academic years 2017/18–2025/26.

## Quickstart
```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
PYTHONPATH=src python -m ingestion.extract --list-versions
```
