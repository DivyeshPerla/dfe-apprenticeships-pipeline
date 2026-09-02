# Open questions and unverified assumptions

Things this project asserts that have not been confirmed at source. Kept
separate from the findings so nothing here is mistaken for evidence.

---

## 1. Meaning of the suppression markers — UNVERIFIED

`dim_suppression_status` decodes three markers found in the measure columns:

| marker | assumed meaning | basis |
|---|---|---|
| `low` | value too small to publish without risking disclosure | inference |
| `c` | withheld for confidentiality | inference |
| `z` | not applicable for this breakdown | inference |

**These meanings were inferred from the data's own behaviour, not read from
DfE documentation.** The inference is well supported — `z` appears only in
`participation_count` and only for breakdowns where participation is not
collected; `low` co-occurs with the smallest published values; `c` appears in
percentage columns whose numerator is suppressed — but it remains an inference.

### Verification attempted, four routes, all unsuccessful

| route | result |
|---|---|
| Release page for Academic year 2025/26 | no symbols section |
| Release data guidance page | no symbols table; points to a metadata PDF |
| Explore Education Statistics glossary (~200 entries) | no entry for any marker |
| API `/meta` endpoint `hint` fields | all empty |

The definitions appear to live only in the **"Metadata for underlying data
files" PDF** in the release's supporting files, which is not exposed through
the API.

### How to close it

Download that PDF from the release's supporting files, or contact the
producing team at `FE.OFFICIALSTATISTICS@education.gov.uk`.

If a definition differs from the assumption, `dim_suppression_status` is the
**single place** that needs correcting — the codes propagate from there, so
nothing else changes.

### What is NOT affected

Every quantitative finding in `docs/INSIGHTS.md` holds regardless. The
pipeline never interprets the markers to compute a figure; it only records
that a value is absent and carries the reason through. A wrong label would
mislabel a category, not corrupt a number.

---

## 2. The £0 running cost is measured on a free-trial account

The billing console shows **$0.00**, but the account is on the Google Cloud
free trial, so credits may be absorbing charges that would otherwise appear.

The free-tier analysis stands on its own — measured usage sits inside the
monthly always-free allowances for every service used (BigQuery 148 MB against
10 GB; Cloud Run a few minutes against 180k vCPU-seconds; Scheduler 1 job
against 3; Workflows dozens of steps against 5,000). But **"the screenshot
shows $0.00" and "this runs free after the trial" are different claims**, and
only the second is an argument.

Honest phrasing: *"usage sits within the always-free tier; the current bill is
zero, on a trial account."*

---

## 3. Suppressed values are excluded, not imputed

Regional and level totals sum only published figures. Where cells are
withheld, totals understate reality by an unknown amount —
`mart_regional_trends.suppression_rate` exposes how much of each total is
missing, but no imputation is attempted.

This is deliberate. Imputing statistically suppressed values would partly
defeat the disclosure control the publisher applied, and could re-identify
small cohorts by triangulation. Any future imputation work should be treated
as a disclosure risk, not just a modelling choice.
