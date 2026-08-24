# Source profiling — evidence log

Dataset: **Headline Full year — Starts, Achievements, Participation by Level, Levy, Age, Region, Provider type**
API dataset id: `1d419801-a90e-f970-9335-a13623faccbe`
Profiled: 2026-08-24 against live API, version 2.0.2.

## Shape
- 51,298 rows × 17 columns, ~7.5 MB uncompressed CSV (API serves it gzipped).
- 9 academic years, 2017/18 → 2025/26 (2025/26 = first 3 quarters only, provisional).
- ~5,700 rows per year — very even, so year is a good partition key.
- Geography: National (England) + 10 regions incl. "Outside of England and unknown".

## Natural key (verified UNIQUE — 51,298 distinct / 51,298 rows)
`time_period, geographic_level, region_code, apprenticeship_level,
 age_youth_adult, age_group, funding_type, provider_type`

## Finding 1 — measures are strings carrying suppression codes
Numeric columns are NOT numeric. They carry statistical disclosure control markers:

| column | numeric | `low` | `c` | `z` |
|---|---|---|---|---|
| start_count | 82.0% | 18.0% | – | – |
| achievement_count | 76.7% | 23.3% | – | – |
| participation_count | 30.5% | 5.3% | – | 64.2% |
| starts_percent | 48.4% | 18.0% | 33.5% | – |
| achievements_percent | 47.5% | 23.3% | 29.2% | – |

`participation_count` is **only populated for 30.5% of rows** — it is not
collected at every breakdown. Treat as legitimately absent, not a defect.

> TODO before modelling: confirm exact code meanings from the DfE release
> methodology page rather than assuming. Working assumption: `z` = not
> applicable, `c` = suppressed for confidentiality, `low` = value too small
> to publish.

## Finding 2 — 80% of rows are pre-aggregated subtotals (double-count trap)
Each of the 5 filter dimensions carries its own `Total` member.

| `Total` dims in row | rows | note |
|---|---|---|
| 0 | 10,066 (19.6%) | true detail grain |
| 1 | 18,296 | subtotal |
| 2 | 14,864 | subtotal |
| 3 | 6,595 | subtotal |
| 4 | 1,378 | subtotal |
| 5 | 99 | grand total |

Naive `SUM(start_count)` over the raw table overstates reality by roughly 5×.
Mitigation: derive `aggregation_depth` (0–5) and expose `is_detail_grain`.

## Finding 3 — six published versions with real, messy deltas
| version | type | published | rows | vs prior: added / removed / restated |
|---|---|---|---|---|
| 1.0 | Major | 2025-07-25 | 40,230 | baseline |
| 1.0.1 | Patch | 2025-10-08 | 40,230 | 0 / 0 / **0** (metadata-only patch) |
| 1.0.2 | Patch | 2025-11-27 | 45,746 | 12,113 / 6,597 / 2,996 |
| 2.0 | Major | 2026-01-29 | 51,228 | 5,661 / 179 / 4,208 |
| 2.0.1 | Patch | 2026-03-26 | 51,237 | 24 / 15 / 4,191 |
| 2.0.2 | Patch | 2026-07-16 | 51,298 | 67 / 6 / 4,307 |

Rows are **added, removed and restated** across versions — so the load needs
true upsert + soft-delete, not append-only.

## Finding 4 — the trap inside the trap: cosmetic restatements
Of the 4,208 "restated" rows in 1.0.2 → 2.0, many are formatting-only:

```
before ('1430', '800', '5010', '2.7', '4'  )
after  ('1430', '800', '5010', '2.7', '4.0')
```

`'4'` → `'4.0'` is the *same number*. A string-level diff would open 4,208
spurious SCD-2 records. **Cast to typed values before comparing.**

Genuine restatements also exist, including disclosure-status changes:
```
2.0 -> 2.0.1   before ('20','low','70','c','low')
               after  ('20','10' ,'80','c','c'  )
```
i.e. a figure moved from suppressed to published between releases.

## API notes (all verified)
- Base: `https://api.education.gov.uk/statistics/v1`
- `GET /data-sets/{id}` → summary incl. `latestVersion.version`
- `GET /data-sets/{id}/versions` → history; **`pageSize` max 20**, must paginate
- `GET /data-sets/{id}/meta` → filters/indicators/locations; the only way to
  resolve the opaque IDs returned by `/query`
- `GET /data-sets/{id}/csv?dataSetVersion=X` → flat CSV for any version
- `POST /data-sets/{id}/query` → paged JSON; **`page`/`pageSize` go in the
  BODY**, not the query string (400 otherwise)
- No API key required.
