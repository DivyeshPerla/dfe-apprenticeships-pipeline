# DfE Apprenticeships — end-to-end data platform on GCP

**Case study goal:** demonstrate production-grade data engineering — ingestion,
orchestration, dimensional modelling, data quality, CI/CD, IaC — on a real,
genuinely messy public dataset, then layer AI capability that is *earned by the
data problem* rather than bolted on.

Source profiling evidence: [`docs/profiling/PROFILE.md`](docs/profiling/PROFILE.md).

---

## 1. Why this dataset actually works

Most portfolio projects use clean Kaggle extracts, so the "T" in ETL is trivial.
This one hands you three real problems that senior reviewers will recognise:

1. **Measures are strings carrying suppression codes** (`low`, `c`, `z`).
   18–23% of counts are withheld. You must design a typed model that preserves
   *why* a value is missing — not `COALESCE(...,0)`.
2. **80.4% of rows are pre-aggregated subtotals.** Every filter dimension has
   its own `Total` member. Naive `SUM()` overstates by **24x** (measured: 8,484,310 vs a true 353,500
   for England 2024/25). Catching this is the single most persuasive slide.
3. **Six published versions with rows added, removed *and* restated** — and a
   trap where ~4,200 "changes" per version are pure formatting (`'4'` → `'4.0'`).
   This gives a *real* incremental-load story with *real* deltas, not a
   simulated one.

**The narrative spine of the presentation:** *"The naive pipeline gives the
wrong answer three different ways. Here is the pipeline that doesn't."*

---

## 2. Target architecture

```
                    Cloud Scheduler (daily)
                            │
                            ▼
              ┌──────────────────────────┐
              │ Cloud Run Job: watcher   │  polls /versions
              │ (version change detect)  │
              └────────────┬─────────────┘
                           │ publishes only on change
                           ▼
                      Pub/Sub topic
                           │
                           ▼
              ┌──────────────────────────┐
              │ Cloud Composer (Airflow) │  orchestration + backfill
              └────────────┬─────────────┘
                           ▼
              ┌──────────────────────────┐
              │ Cloud Run Job: extract   │ ──► GCS  gs://.../bronze/
              │ (API → CSV + meta JSON)  │      version=2.0.2/ingest_date=…
              └────────────┬─────────────┘
                           ▼
                   BigQuery  bronze  (external / raw load)
                           │  dbt
                           ▼
                   BigQuery  silver  (typed, suppression-split, deduped)
                           │  dbt
                           ▼
                   BigQuery  gold    (star schema, SCD-2 fact)
                           │
              ┌────────────┼────────────────┬──────────────┐
              ▼            ▼                ▼              ▼
        Looker Studio   BigQuery ML    Vertex AI      Dataplex
         dashboard      (clustering,   (RAG agent)    (quality scans,
                        anomalies)                     catalog)
```

**Stack:** Terraform (IaC) · Cloud Run Jobs (Python) · GCS · BigQuery ·
dbt Core · Cloud Composer / Airflow · Pub/Sub · Cloud Scheduler · Dataplex ·
BigQuery ML · Vertex AI (Gemini) · Looker Studio · GitHub Actions (CI/CD).

### Key design decisions to defend in the deck
| Decision | Rationale |
|---|---|
| GCS bronze layer, immutable per version | Replayability — rebuild any historical state from raw |
| dbt Core over Dataform | Industry standard, portable, testable, generates docs/lineage |
| SCD-2 on the fact, keyed by dataset version | Source restates history; you must answer "what did we report in Jan?" |
| Integer-range partition on `academic_year_start` | 9 values, even ~5.7k rows each — prunes cleanly |
| Cluster by `region_code, apprenticeship_level` | Matches dominant filter pattern in the marts |
| Cloud Run Jobs over Cloud Functions | Long-running batch, container parity with local dev |
| Event-driven trigger, not fixed schedule | Source updates quarterly — polling for *change* is honest |

---

## 3. Data model

### Silver: `stg_apprenticeships`
Each measure explodes into two columns — this is the core transform:

| raw | becomes |
|---|---|
| `start_count = '1430'` | `start_count = 1430`, `start_count_status = 'published'` |
| `start_count = 'low'` | `start_count = NULL`, `start_count_status = 'low'` |
| `participation_count = 'z'` | `participation_count = NULL`, `..._status = 'not_applicable'` |

Plus derived: `academic_year_start` (202425 → 2024), `academic_year_label`
('2024/25'), `aggregation_depth` (0–5), `is_detail_grain`, `is_provisional`.

### Gold: star schema
- **Dimensions:** `dim_academic_year`, `dim_geography` (ONS codes),
  `dim_apprenticeship_level`, `dim_age_group`, `dim_age_youth_adult`,
  `dim_funding_type`, `dim_provider_type`, `dim_suppression_status`
- **Fact:** `fct_apprenticeship_headline` — grain = the 8-part natural key,
  SCD-2 via `valid_from_version` / `valid_to_version` / `is_current`
- **Marts:** `mart_regional_trends`, `mart_level_mix`,
  `mart_restatement_history` (← the version-diff story, uniquely yours)

### Non-negotiable transform rules
1. Split every measure into value + status. Never zero-fill a suppression.
2. Compute `aggregation_depth`; default all marts to `is_detail_grain`.
3. **Cast to typed values before diffing versions** — otherwise `'4'` vs `'4.0'`
   creates ~4,200 phantom SCD-2 rows per release.
4. Handle removed keys as soft deletes (`is_current = FALSE`), never hard delete.

---

## 4. Phase plan

Assumes ~2–3 focused hours/day. Compresses to ~10 full days if you go hard.

### Phase 0 — Foundations (Days 1–2)
- [ ] Install `gcloud` SDK and Docker Desktop *(neither is on this machine yet)*
- [ ] Create GCP project, link billing, **set a budget alert at £20 first**
- [ ] Enable APIs: bigquery, storage, run, composer, pubsub, scheduler,
      artifactregistry, dataplex, aiplatform, secretmanager
- [ ] Terraform: GCS buckets (bronze/artifacts), BQ datasets
      (bronze/silver/gold), service accounts + least-privilege IAM
- [ ] GitHub repo, branch protection, `.github/workflows/ci.yml` (lint + tests)
- **Deliverable:** `terraform apply` builds the whole substrate from zero

### Phase 1 — Batch ETL (Days 3–8) ← *the core*
- [ ] Extraction job: API → GCS bronze, partitioned `version=X/ingest_date=Y`,
      writes a manifest (row count, sha256, API version) for reconciliation
- [ ] Backfill **all 6 versions** into bronze — this is what makes the
      incremental story real
- [ ] Load bronze → BigQuery raw tables
- [ ] dbt: staging models (suppression split, typing, `aggregation_depth`)
- [ ] dbt: dimensions + SCD-2 fact with typed-diff merge
- [ ] dbt tests: uniqueness on natural key, not-null, accepted values on
      suppression codes, relationship tests, plus a **custom test asserting
      subtotals reconcile to the sum of their detail rows**
- [ ] Airflow DAG: extract → load → dbt run → dbt test → publish
- [ ] Looker Studio dashboard on the marts
- **Deliverable:** one command backfills 9 years across 6 versions, tests green

### Phase 2 — Event-driven + streaming (Days 9–12)
- [ ] Version-watcher Cloud Run Job on Cloud Scheduler; publishes to Pub/Sub
      only when `latestVersion` changes; DAG triggered by the message
- [ ] Prove idempotency: re-run the same version → zero rows change
- [ ] Prove incrementality: replay 1.0 → 1.0.2 → 2.0 → 2.0.2 and show the
      restatement history materialise in `mart_restatement_history`
- [ ] *Optional* streaming demo: synthetic apprenticeship-start event generator
      → Pub/Sub → Dataflow streaming → BigQuery.
      **Label it clearly as simulated** — the real source is quarterly.
      Honest framing beats a fake real-time claim.
- **Deliverable:** pipeline that wakes only when the source actually changes

### Phase 3 — AI capabilities (Days 13–17)
Ordered by how well each is *justified by the data problem*:

1. **Suppression-aware analytics agent** (centrepiece)
   Vertex AI + Gemini, NL → SQL over the gold marts, grounded via RAG on the
   DfE methodology docs. Its differentiator: it **refuses to state a figure
   that is statistically suppressed** and explains why instead. Ties AI
   directly to governance — very few portfolios do this.
2. **`ML.DETECT_ANOMALIES` on restatements** — flag which version-over-version
   revisions moved beyond expected bounds. AI serving data quality.
3. **`ML.KMEANS` regional segmentation** — cluster regions by apprenticeship
   level/provider/funding mix. Works well at this data volume.
4. **`ML.GENERATE_TEXT` (Gemini remote model)** — auto-write per-region
   narrative summaries for the dashboard.
5. **`ML.ARIMA_PLUS` forecast** — *include with an explicit caveat.* 9 annual
   points per series is genuinely too few for reliable forecasting. Present it
   as MLOps mechanics + honest uncertainty, not as a credible prediction.
   **Stating this limitation out loud will impress more than hiding it.**
- **Deliverable:** agent demo video + BQML notebooks

### Phase 4 — Presentation (Days 18–20)
- [ ] Capture screenshots *as you go* (see checklist below) — do not retrofit
- [ ] Architecture diagram, data lineage (dbt docs), cost breakdown
- [ ] Deck spine: problem → naive approach fails 3 ways → architecture →
      the three findings → AI layer → results → what I'd do differently
- [ ] Record a 5-min walkthrough video
- [ ] Tear down billable resources; keep BigQuery (cheap at this size)

---

## 5. Screenshot checklist (capture live, in the moment)
GCS bronze with version partitions · BigQuery dataset tree (bronze/silver/gold) ·
partition & cluster detail on the fact · **Airflow DAG graph, green** ·
Airflow Gantt (runtime profile) · dbt lineage graph · dbt test results ·
Pub/Sub topic + subscription metrics · Cloud Run Job execution logs ·
Cloud Scheduler · Dataplex quality scan · BQML model evaluation ·
Vertex AI agent conversation (esp. a *refusal* on a suppressed figure) ·
Looker Studio dashboard · Cloud Monitoring dashboard · billing/cost breakdown ·
Terraform plan/apply output · GitHub Actions green run

---

## 6. Cost control
- **Cloud Composer is the only expensive item (~£250–400/month).**
  Develop DAGs locally with Airflow in Docker (UI screenshots are identical),
  then deploy to Composer for a **3–5 day window** to capture cloud-native
  evidence, and destroy it. Budget ~£40–70 total.
- Cheaper alternative if budget is tight: Cloud Workflows + Cloud Scheduler
  (≈£0). Weaker on the CV than Airflow — your call.
- BigQuery at 51k rows is effectively free. GCS pennies. Vertex AI pay-per-call.
- New GCP accounts get $300 free credits — likely covers the whole project.
- **Set the budget alert before writing any code.**

---

## 7. Risks
| Risk | Mitigation |
|---|---|
| Composer cost overrun | Budget alert + hard teardown date in calendar |
| Suppression codes misinterpreted | Confirm against DfE methodology page before modelling |
| ARIMA results look weak | Reframe as mechanics + stated limitation, don't oversell |
| Scope creep on the streaming phase | It is explicitly optional; Phase 1 is the deliverable |
| Source publishes a new version mid-project | That's a *gift* — a live incremental run for the demo |
