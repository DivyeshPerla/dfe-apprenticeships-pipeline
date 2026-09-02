# Case study deck — outline and screenshot plan

Audience: UK training-provider employer. Graded on the **data engineering
pipeline**; analytics and compliance are the differentiators.

Spine: *the naive pipeline gets the wrong answer four different ways — here is
the one that doesn't, and here is what it then tells you about the market.*

Screenshot slots are marked **[SHOT n]** and listed with capture instructions
at the end.

---

## Act 1 — The problem (3 slides)

**1. Title**
DfE apprenticeships: a production data platform on GCP
One line: 51,298 rows, 9 academic years, 6 published versions, fully automated.

**2. The source looks trivial. It isn't.**
17 columns of government statistics, free API, no key. Then the four traps:
suppression codes inside numeric columns; 80% of rows are subtotals; six
versions that restate history; every figure rounded to 10.

**3. What a naive pipeline returns**
The 24× slide. 8,484,310 vs a true 353,500 for England 2024/25.
**[SHOT 1]** BigQuery console running `double_counting_proof.sql`.

## Act 2 — The pipeline (6 slides)

**4. Architecture**
Diagram: API → Cloud Run → GCS bronze → BigQuery (bronze/silver/gold) →
Looker Studio, orchestrated by Workflows + Scheduler, dbt for transforms,
Terraform for everything. Note under it: no Composer — free tier by design.

**5. Infrastructure as code**
33 resources, `terraform apply` from nothing.
**[SHOT 2]** `terraform plan` output showing the resource count.

**6. Bronze — immutable and replayable**
Hive-partitioned `version=/ingest_date=`, versioning on, manifests with SHA-256
that reconcile against the API row count for all six versions.
**[SHOT 3]** GCS browser showing the partition tree.

**7. Silver — where the traps get handled**
Suppression split into value + status; `aggregation_depth`; typed casting.
Distributions match profiling exactly, zero unrecognised markers.
**[SHOT 4]** BigQuery query showing the status breakdown.

**8. Gold — SCD-2 across six versions**
69,589 records from 58,092 keys; `is_current` = 51,298, matching v2.0.2 exactly.
The typed-diff detail: string comparison would have opened 4,208 phantom records.
**[SHOT 5]** BigQuery showing typed vs string diff counts.

**9. Orchestration**
Watcher → extract → dbt build, event-driven not blind polling.
**[SHOT 6]** Workflow execution graph, succeeded.
**[SHOT 7]** Cloud Run transform logs showing `PASS=26 ERROR=0`.

## Act 3 — Engineering rigour (3 slides)

**10. Tests as the safety net**
26 tests: uniqueness, referential, accepted values, plus two business-logic
tests — current records must equal the latest version, and detail grain must
reconcile to the published total within 0.1%.

**11. The bug the tests caught**
The idempotency story: date rolled over, bronze gained a second partition for
the same version, silver saw every row twice, the uniqueness test failed and
**stopped the run before anything reached gold**. Fix: silver resolves each
version to its latest extraction.
*This is the strongest slide in the deck — it shows the system working.*

**12. Cost**
Whole platform inside GCP always-free. Composer would have been £250–400/month;
Cloud Workflows does the same job here for ~£0.
**[SHOT 8]** Billing report.

## Act 4 — Compliance (2 slides)

**13. Compliance as code**
`verify_compliance.sh` — 8 control families checked against live GCP state,
exits non-zero, gates a release. 18/18 passing.
**[SHOT 9]** Terminal output of the script.

**14. Two findings it caught**
- Cloud Build was staging source, including a dbt seed, in a **US** bucket.
- The default compute SA carried project-wide `roles/editor`.
Both remediated; the second could not be fixed naively because Cloud Build was
using that identity.
Plus the UK GDPR position: no personal data, asserted as an automated check
rather than an assumption.

## Act 5 — What the data says (4 slides)

**15. The market moved upmarket**
Intermediate 43.0% → 17.3%; Higher 12.8% → 41.0%; Advanced flat. Volumes flat.
**[SHOT 10]** Looker Studio or the dashboard.

**16. National but uneven**
London +33.8pts vs North East +21.8pts.

**17. Three structural markets**
BQML k-means recovers London as its own cluster without being told.
**[SHOT 11]** BigQuery ML model / cluster assignment.

**18. What this data cannot answer**
No completion rates (no cohort linkage), no provider detail, no sector split.
Naming limits is part of the analysis.

## Close (2 slides)

**19. What I'd do differently**
Confirm suppression codes against DfE methodology first; add CI on the repo;
Dataform vs dbt trade-off; add cohort-lagged analysis if given the raw ILR.

**20. Summary**
One pipeline, four traps handled, 26 tests, 18 compliance checks, £0/month.

---

## Screenshot capture list

| # | Where | What must be visible |
|---|---|---|
| 1 | BigQuery console | `double_counting_proof.sql` results: 8,484,310 vs 353,500 |
| 2 | Terminal | `terraform plan` — resource count line |
| 3 | GCS browser | `apprenticeships/data/version=*` partition folders |
| 4 | BigQuery | suppression status counts by measure |
| 5 | BigQuery | typed vs string diff: 69,589 vs 73,797 |
| 6 | Workflows | execution graph, SUCCEEDED, all steps green |
| 7 | Cloud Run | transform job logs, `PASS=26 WARN=0 ERROR=0` |
| 8 | Billing | current spend / budget page |
| 9 | Terminal | `./scripts/verify_compliance.sh` full output |
| 10 | Looker Studio / dashboard | level mix over time |
| 11 | BigQuery | `region_segments` cluster assignments |

Links for every console page: `docs/GCP_LINKS.md`.
