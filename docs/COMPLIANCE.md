# Compliance & data governance

Context: UK-based organisation, UK public-sector source data, GCP `europe-west2`.

**Every control below is verified against live GCP state by
[`scripts/verify_compliance.sh`](../scripts/verify_compliance.sh), not asserted
here.** The script exits non-zero on failure, so it can gate a release.

```bash
./scripts/verify_compliance.sh
```

---

## 1. Licensing and attribution

The source is DfE *Explore Education Statistics*, published under the
**Open Government Licence v3.0**. OGL permits commercial reuse, adaptation and
redistribution, and **requires attribution**.

Required notice, carried on the dashboard and every published output:

> Contains public sector information licensed under the Open Government
> Licence v3.0. Source: Department for Education, *Explore Education
> Statistics*.

No API key, no account, no rate-limit agreement — the endpoint is open. That
matters for the case study: nothing here depends on a credential that a
reviewer cannot reproduce.

## 2. UK GDPR position

**No personal data is processed.** The source is aggregate official statistics;
the smallest published cell is 10, and cells below the disclosure threshold are
withheld by the publisher before we ever see them.

Consequences, stated plainly:
- No lawful basis assessment is required — UK GDPR does not engage.
- No DPIA is required.
- No data subject rights process is required.
- No international transfer assessment is required for the source data.

This is asserted as a **control, not an assumption**: check **C6** fails the
build if any column name matching an identifier pattern (`email`, `postcode`,
`nino`, `uln`, `learner`, …) ever appears in the `gold` dataset. A future
schema change that introduced personal data would break the pipeline rather
than quietly widen scope.

## 3. Statistical disclosure control

The publisher applies two disclosure controls. Both are **preserved end to end**
rather than normalised away:

| Control | How the platform preserves it |
|---|---|
| Suppression markers (`low`, `c`, `z`) | Split into a typed value + a status code. A suppressed figure is `NULL` with a reason, **never zero** |
| Rounding to the nearest 10 | Retained; reconciliation tests assert a 0.1% tolerance rather than equality |

Check **C7** asserts that no suppressed figure carries a value, and that no
unrecognised marker has appeared. Zero-filling a suppression would understate
every aggregate *and* risk implying a figure the publisher withheld.

## 4. Data residency

All processing and storage in **europe-west2 (London)**.

> **Audit finding, since remediated.** `gcloud builds submit` silently
> auto-creates `<project>_cloudbuild` **in the US** and stages every source
> tarball there. Nine builds had staged source — including a dbt seed — outside
> the UK before this was caught. Remediation: an in-region staging bucket, with
> `--gcs-source-staging-dir` passed from `scripts/deploy.sh`. Check **C1** now
> fails if any bucket sits outside the region.

This is the kind of gap that a written policy would have missed and an
automated check catches.

## 5. Access control

| Control | Implementation |
|---|---|
| Least privilege | Three purpose-built service accounts, scoped at bucket and dataset level — the ingestion identity cannot read `gold` |
| Keyless authentication | **Zero** user-managed service account keys (check C3). Workload identity only; nothing downloadable to leak |
| Public exposure | `public_access_prevention = enforced` and uniform bucket-level access on every bucket (check C2) |
| Human access | A single project owner |

> **Audit finding.** GCP grants the **default compute service account
> `roles/editor`** at project creation — broad project-wide write access. Cloud
> Build defaults to that identity, so the role cannot simply be revoked without
> breaking builds. Remediation: a dedicated `dfe-appr-build` service account
> holding only Artifact Registry write, staged-source read, and log write;
> `deploy.sh` passes it via `--service-account`. Check **C4** reports the
> residual default-SA grant, which is a GCP default rather than something this
> project created.

## 6. Encryption

- **At rest:** Google-managed AES-256, always on, for GCS and BigQuery.
- **In transit:** TLS to the source API and between all GCP services.
- CMEK was **not** adopted: it adds key-management burden with no benefit for
  public open data carrying no personal information. Stating the reason is the
  point — an unjustified control is as much a smell as a missing one.

## 7. Auditability and retention

| Concern | Implementation |
|---|---|
| Raw immutability | Bronze object versioning on; all six source versions retained (check C8) |
| Lineage | SCD-2 fact answers "what did the publisher report as of version X?" |
| Change evidence | `mart_restatement_history` — 11,497 revised figures, 392 disclosure-status changes |
| Reproducibility | Every load writes a manifest with row count and SHA-256; counts reconcile against the API |
| Retention | Bronze: 3 newer versions then delete, Nearline at 90 days. Build staging: 14 days |
| Activity logs | Cloud Logging (Admin Activity audit logs on by default and not disableable) |

## 8. What is deliberately out of scope

Naming these is part of the assessment, not an omission:

- **VPC Service Controls / Private Service Connect** — appropriate for
  restricted data; disproportionate for public open data.
- **CMEK** — see §6.
- **Data Catalog / Dataplex governance** — a single 51k-row dataset does not
  warrant a catalogue tier that costs more than the pipeline.
- **Access Transparency / Assured Workloads** — these are OFFICIAL-SENSITIVE
  and above controls. This data is published openly on gov.uk.

## 9. Residual risks

| Risk | Severity | Mitigation |
|---|---|---|
| Suppression code meanings inferred from data, not yet confirmed against DfE methodology | Medium | Confirm before quoting definitions externally; `dim_suppression_status` is the single place to correct |
| Default compute SA retains `roles/editor` | Low | GCP default; builds no longer use it. Removable once nothing else depends on it |
| Source may change schema between versions without notice | Medium | Bronze lands as STRING; dbt tests fail loudly rather than silently coercing |
| Provisional year (2025/26) may be mistaken for final | Medium | `is_provisional` flag propagated to every mart and the dashboard |
