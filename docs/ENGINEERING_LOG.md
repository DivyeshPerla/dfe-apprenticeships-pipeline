# Engineering log — problems hit and how they were diagnosed

Real defects encountered building this pipeline, kept because the diagnosis is
more interesting than the fix, and because a case study that shows only the
happy path is not credible.

---

## 1. Naive aggregation overstated starts by 24x

Every filter dimension carries its own `Total` member, so the extract mixes
detail rows with subtotals at five levels. `SUM(start_count)` over the raw
table returned 8,484,310 against a true 353,500.

**Diagnosis:** counted how many dimensions were rolled up per row — only
19.6% of rows are true detail grain.
**Fix:** derive `aggregation_depth` (0–5); default all marts to depth 0.

## 2. Suppression markers hidden inside numeric columns

18–23% of counts are withheld and carry `low`, `c` or `z` in the numeric
field. A typed load would silently null them; `COALESCE(...,0)` would
understate every aggregate.

**Fix:** split every measure into a typed value plus a status column
recording *why* it is null.

## 3. String-level version diffs created 4,208 phantom records

Between versions 1.0.2 and 2.0 the publisher reformatted ~4,200 percentage
values (`'4'` → `'4.0'`). Semantically identical, textually different.

**Diagnosis:** compared SCD-2 record counts under both comparison strategies —
73,797 (string) vs 69,589 (typed).
**Fix:** cast before comparing.

## 4. Exact reconciliation was impossible, and the first test asserted it

A test asserting the detail sum equals the published grand total failed on 7 of
9 years. The initial spot-check had used 2024/25, which matches by luck.

**Diagnosis:** all 42,045 published values are exact multiples of 10 — the
source rounds as part of disclosure control. Summing ~122 rounded values cannot
equal an independently rounded total.
**Fix:** assert a 0.1% tolerance (~350 on a 350,000 base) — above rounding
noise, far below the ~24x error a real aggregation bug produces.

## 5. Exit codes were the wrong orchestration signal

The version watcher signalled "no change" with exit code 3. But Cloud Run marks
*any* non-zero exit as failed, so the workflow could not tell "nothing to do"
from "the watcher crashed" — genuine failures would have been swallowed as
routine skips.

**Fix:** always exit 0; write an explicit decision object to GCS that the
workflow reads and branches on. Failures now propagate loudly.

## 6. Cloud Run v1 connector 403s while polling

`googleapis.run.v1.namespaces.jobs.run` resolves executions under a
project-number namespace the workflow identity cannot read. The job succeeded;
the *poll* returned 403 PERMISSION_DENIED.

**Fix:** use the v2 connector, matching the v2 job resources. Also grant
`roles/run.viewer` — `run.invoker` starts a job but cannot read its execution.

## 7. A missing seed file, fixed at the wrong layer twice

The containerised dbt build failed: `depends on a node named
'dataset_versions' which was not found`.

**First attempt:** assumed `.dockerignore`'s `*.csv` rule; added a
`!dbt/seeds/*.csv` negation. Still failed.
**Second attempt:** scoped the rule to `/*.csv`. Still failed.
**Actual diagnosis:** listed `/app/dbt/seeds` during the image build — empty.
The cause was two layers higher: `.gitignore` also has `*.csv`, so the seed was
**never committed**, and `gcloud builds submit` falls back to `.gitignore` when
no `.gcloudignore` exists. The file never reached the build context, so no
`.dockerignore` change could ever have fixed it.
**Fix:** track the seed (`git add -f`), add an explicit `.gcloudignore`.

**Lesson:** verify the artefact, don't infer the layer. One `ls` inside the
build would have saved two wrong fixes.
