# How this was built

A chronological account, reconstructed from the commit history. It includes
the wrong turns, because several of them produced the findings worth
presenting.

---

## Phase 0 · Profile the source before building anything

**No code was written until the data had been characterised.** This is the
step that determined everything after it.

1. Queried the DfE Explore Education Statistics API directly with `curl` to
   confirm the endpoints, response shapes and paging behaviour.
2. Downloaded the flat CSV for the latest version and profiled it in Python:
   column types, distinct values, null patterns, cardinality.
3. Downloaded **every published version** and diffed them against each other.

Four defects surfaced, none visible in the schema:

| Defect | Evidence |
|---|---|
| 80% of rows are pre-aggregated subtotals | only 10,066 of 51,298 rows sit at detail grain |
| Measures are strings carrying suppression markers | `low` in 18% of `start_count`, `z` in 64% of `participation_count` |
| Six versions silently restate history | 2,996–4,307 figures revised per release |
| Every figure rounded to the nearest 10 | 42,045 of 42,045 published values are multiples of 10 |

Written up in `docs/profiling/PROFILE.md`. **Every design decision downstream
traces back to one of these four.**

## Phase 1 · GCP foundation, as code

4. Installed the Cloud SDK; created the project and linked billing via
   `scripts/bootstrap_gcp.sh`.
5. **Set a £25 budget with 50/90/100% alerts before provisioning anything.**
   The guardrail goes up before the thing it guards.
6. Wrote Terraform for the substrate: API enablement, a versioned GCS bucket
   with lifecycle rules, three BigQuery datasets, and service accounts scoped
   at bucket and dataset level rather than project level.
7. `terraform plan` reviewed, then applied — 28 resources on the first pass.

Nothing in this project was ever clicked into existence in a console.

## Phase 2 · Ingestion

8. Wrote a typed API client (`src/ingestion/dfe_client.py`) covering five
   endpoints. Three gotchas were coded around: `pageSize` on `/versions` caps
   at 20; `page`/`pageSize` on `POST /query` must go in the **body**; the CSV
   arrives gzipped.
9. Wrote the extractor to land raw files in GCS partitioned
   `version=X/ingest_date=Y`, writing a manifest with row count and SHA-256
   per load.
10. Backfilled all six published versions. **Every manifest row count
    reconciled exactly against the API's own reported total.**

## Phase 3 · Warehouse

11. Created a BigQuery external table over the bronze bucket with **AUTO hive
    partitioning**, so `version` and `ingest_date` become queryable columns
    derived from the object path — no ingestion code required.

    A constraint shaped the layout here: BigQuery permits only **one wildcard**
    per source URI. Data files and JSON sidecars therefore live under separate
    prefixes, so the table can glob `data/*` without trying to CSV-parse JSON.

12. Proved the 24× defect in BigQuery and committed the query as
    `sql/analysis/double_counting_proof.sql`.
13. Built the silver layer in dbt: each measure split into a typed value **and
    a status explaining any NULL**, plus `aggregation_depth` (0–5) so no
    downstream model can double-count by accident.
14. Built the gold layer: a **type-2 fact** collapsing all six source versions
    into validity intervals.

    The critical detail: comparison is on **typed values, never raw strings**.
    One release reformatted ~4,200 values (`'4'` → `'4.0'`) — a string diff
    would have opened a phantom history record for every one. Measured:
    73,797 records versus 69,589.

15. Added 26 tests. Two encode judgement rather than structure: current
    records must equal the latest source version exactly, and detail-grain
    sums must reconcile to the publisher's totals **within 0.1%** — a
    tolerance derived from the rounding regime, not invented.

## Phase 4 · Orchestration

16. **Rejected Cloud Composer.** No free tier (~£250–400/month) for a source
    that publishes quarterly. Chose Cloud Workflows + Cloud Scheduler +
    Cloud Run Jobs, all inside always-free allowances.
17. Containerised ingestion and dbt into **one image** with per-job command
    overrides, keeping Artifact Registry inside its 0.5 GB free tier.
18. Wrote a version watcher that polls the source and signals whether anything
    changed, so a normal day costs one API call rather than a full rebuild.
19. Wired the workflow: watcher → branch → extract → `dbt build`.

### Three failures worth keeping

- **Exit codes as control flow didn't survive the connector.** Cloud Workflows
  surfaces a non-zero Cloud Run exit as a generic failure, and the original
  `try/except` swallowed genuine errors alongside the intended signal. Replaced
  with an explicit decision object written to GCS.
- **`.dockerignore` silently emptied `dbt/seeds/`.** A bare `*.csv` matches
  nested paths, so the containerised build could not resolve the seed the fact
  table depends on. Diagnosed by listing the image filesystem at build time
  rather than guessing.
- **The seed was untracked in git entirely**, and `gcloud builds submit` uses
  `.gcloudignore` — which falls back to `.gitignore`. Fixed with an explicit
  `.gcloudignore`.

## Phase 5 · The bug the tests caught

20. After an unrelated IAM change, the pipeline was re-run to confirm nothing
    had broken. **A uniqueness test failed.**

    The calendar date had rolled over between runs. Bronze is append-only, so
    re-extracting the same version landed a *second* `ingest_date` partition —
    and the external table globs every partition. Silver was seeing all 51,298
    rows twice.

21. Fixed by having silver resolve each version to its most recent extraction.
    Bronze keeps every copy, which is the point of an immutable raw layer.
22. **The same bug existed in the analysis SQL** and was found only because the
    absolute figures were re-checked rather than trusting that the 24× *ratio*
    still held.

The test stopped the run before anything reached gold.

## Phase 6 · Compliance as code

23. Wrote `scripts/verify_compliance.sh` — 18 controls checked against **live
    GCP state**, exiting non-zero so it can gate a release.

Two real findings:

- **Data was leaving the UK.** `gcloud builds submit` silently creates a
  staging bucket *in the US*; nine source archives had staged there. Fixed with
  an in-region bucket pinned via `--gcs-source-staging-dir`.
- **An over-privileged default identity.** GCP grants the default compute
  service account project-wide `roles/editor`, and Cloud Build was using it.
  The naive fix breaks the build — the correct one is a dedicated build
  identity holding only registry write, source read and log write.

Also asserted **as a check rather than a claim**: no identifier-shaped column
may appear in `gold`, so a schema change introducing personal data breaks the
build instead of quietly widening UK GDPR scope.

## Phase 7 · Analytics and ML

24. `mart_level_shift` — the headline finding: the market did not shrink, it
    moved upmarket. Intermediate 43.0% → 17.3%, Higher 12.8% → 41.0%, Advanced
    flat throughout.
25. **BQML k-means** segmentation on level mix, features expressed as shares so
    volume does not dominate. London separates on its own.
26. **ARIMA_PLUS forecast** trained on complete years only, with the provisional
    year held out as a genuine out-of-sample test. `auto_arima` chose
    ARIMA(0,1,0) with drift — a random walk — because eight annual observations
    cannot support more. Forecast 43.7% against an actual 41.0%: inside the 95%
    interval, but that interval spans nine points. **The width is the finding.**
27. **Gemini via a BigQuery remote model**, generating regional narratives with
    the withheld-cell counts as a first-class input — so the model reports the
    gap rather than papering over it.
28. **ML.DETECT_ANOMALIES** over 10,983 revisions, flagging 219 (2%) as a
    review queue.

## Phase 8 · Monitoring

29. Cloud Monitoring dashboard **defined in Terraform**: workflow executions by
    outcome, Cloud Run completions by result, task runtime, error log volume.
30. An alert policy on transform-job failure — the failure that leaves gold
    stale. Extract failures self-heal on the next run and do not page.
31. `gold.mart_pipeline_health` for the other half: freshness, volume,
    suppression drift, unrecognised markers, reconciliation margin.

A pipeline that runs green while silently loading wrong data is the failure
mode that matters, which is why both halves exist.

## Phase 9 · GitHub

32. Authenticated with `gh auth login`, which also created and registered an
    SSH key.
33. Rewrote commit authorship to the correct identity **before** the first
    push, so history was right from the start rather than corrected later.
34. Created the public repository and pushed with
    `gh repo create --public --source=. --push`.
35. **CI failed on its first run** — on a working tree that passed locally.
    Cause: the stricter lint config was added *after* running the linter, so
    local checks used defaults while CI used the real config. Fixed, and tool
    versions pinned, because an unpinned linter silently gains rules between
    runs.
36. Enabled **GitHub Pages** from `main` `/docs` with a landing page, verified
    by fetching the served HTML rather than trusting a 200.

Final: 39 commits, 4 CI jobs green, 51 GCP resources, 26 tests, 18 compliance
checks, 4 ML models, £0/month.
