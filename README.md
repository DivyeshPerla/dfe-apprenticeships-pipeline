# Apprenticeships data platform

A production data pipeline on Google Cloud over UK apprenticeship statistics —
built because the obvious query against this source returns an answer that is
**24× too large**, and nothing errors.

- **Deck:** [`docs/presentation/deck.html`](docs/presentation/deck.html)
- **How it was built:** [`docs/BUILD_WALKTHROUGH.md`](docs/BUILD_WALKTHROUGH.md)
- **Findings:** [`docs/INSIGHTS.md`](docs/INSIGHTS.md)
- **Source profiling (the evidence):** [`docs/profiling/PROFILE.md`](docs/profiling/PROFILE.md)
- **Governance:** [`docs/COMPLIANCE.md`](docs/COMPLIANCE.md)
- **What is not proven:** [`docs/OPEN_QUESTIONS.md`](docs/OPEN_QUESTIONS.md)

---

## Why it exists

The source is the DfE *Explore Education Statistics* API — free, no key,
17 tidy columns, ~51,000 rows. Profiling it before writing any pipeline code
turned up four defects, none visible in the schema and none of which raise an
error:

| # | Defect | Consequence |
|---|---|---|
| 1 | 80% of rows are pre-aggregated subtotals | naive `SUM` overstates by **24×** |
| 2 | Measures are strings carrying suppression markers (`low`, `c`, `z`) | up to 23% of counts vanish on cast, or become fake zeros |
| 3 | Six published versions silently restate history | analysis pinned to one download goes stale |
| 4 | Every figure rounded to the nearest 10 | parts can never exactly equal the whole |

A fifth is documented but deliberately not "solved": same-year achievements ÷
starts is **not** a completion rate, because apprenticeships run 1–4 years and
this extract has no cohort linkage. The honest response is to not compute it.

## Architecture

```
Cloud Scheduler ──► Cloud Workflows ──┬─► version watcher  (Cloud Run)
                                      │      exit 0 = new version
                                      │      exit 3 = nothing changed
                                      ├─► extract          (Cloud Run) ──► GCS bronze
                                      └─► dbt build        (Cloud Run) ──► BigQuery
```

Bronze is append-only and immutable; silver and gold are rebuilt from it, so
any past state is reproducible. The pipeline is event-driven rather than
scheduled-blind: the source publishes quarterly, so a daily rebuild would
repeat identical work ~90 times per release.

**No Cloud Composer.** It has no free tier (~£250–400/month) and this workload
is quarterly. Cloud Workflows expresses the same branch for effectively nothing.

## Data model

| Layer | Contents |
|---|---|
| `bronze` | External table over GCS. Every column `STRING` by design — typing here would destroy the suppression markers. `version` and `ingest_date` come free from Hive partitioning. |
| `silver` | Typed. Each measure split into a value **and a status explaining any NULL**. `aggregation_depth` (0–5) derived so downstream models cannot double-count. |
| `gold` | Star schema. Type-2 fact across all six source versions, three dimensions, four marts, four ML models. |

Two details worth knowing:

- **SCD-2 comparison is on typed values, never raw strings.** One release
  reformatted ~4,200 values (`'4'` → `'4.0'`); a string diff would have opened
  a phantom history record for every one.
- **Silver resolves each version to its latest extraction.** Bronze keeps every
  copy, so re-extracting an unchanged version would otherwise double every
  figure downstream. A test caught this in production when a date rolled over.

## Quickstart

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
PYTHONPATH=src python -m ingestion.extract --list-versions
```

To stand the platform up in your own project:

```bash
BILLING_ACCOUNT=XXXXXX-XXXXXX-XXXXXX ./scripts/bootstrap_gcp.sh   # project, billing, budget
cd terraform && cp terraform.tfvars.example terraform.tfvars      # set project_id
terraform init && terraform apply
cd .. && ./scripts/deploy.sh                                      # build image, deploy jobs
make backfill                                                     # all six source versions
```

## Verification

Everything below is reproducible, not asserted:

```bash
make test                        # 26 dbt tests: uniqueness, referential, business logic
./scripts/verify_compliance.sh   # 18 controls checked against live GCP state
```

Two of the dbt tests encode judgement rather than structure: current records
must equal the latest source version exactly, and detail-grain sums must
reconcile to the publisher's own totals **within 0.1%** — a tolerance derived
from the rounding regime, not an invented fudge factor.

## Layout

```
src/ingestion/     API client, extractor, version watcher
terraform/         49 resources — buckets, datasets, IAM, Cloud Run, workflow, schedule
dbt/               staging, dimensions, facts, marts, tests
sql/ai/            BQML: clustering, forecasting, anomaly detection
sql/analysis/      the proofs behind the headline numbers
scripts/           bootstrap, deploy, compliance verification
docs/              profiling evidence, insights, compliance, open questions, deck
```

## Licence and attribution

Contains public sector information licensed under the
[Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/).
Source: Department for Education, *Explore Education Statistics* — "Headline
Full year: Starts, Achievements, Participation by Level, Levy, Age, Region,
Provider type".

No personal data is processed; the source is aggregate official statistics with
a minimum published cell size of 10. This is asserted as an automated check
(control C6), not an assumption — the build fails if an identifier-shaped
column ever appears in `gold`.
