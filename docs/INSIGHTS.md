# Analytical findings

The pipeline is the graded deliverable; this is what it makes possible.
Every figure is reproducible from `gold` — SQL is referenced per finding.

---

## Finding 1 — the market moved upmarket, it did not shrink

Total starts are roughly flat across eight years. The **composition inverted**.

| year | intermediate | advanced | higher | total starts |
|---|---|---|---|---|
| 2017/18 | **43.0%** | 44.2% | **12.8%** | 375,780 |
| 2019/20 | 30.8% | 43.7% | 25.6% | 322,610 |
| 2021/22 | 26.2% | 43.3% | 30.5% | 349,280 |
| 2023/24 | 20.9% | 43.2% | 36.0% | 339,650 |
| 2024/25 | 18.6% | 41.6% | 39.8% | 353,500 |
| 2025/26 *(provisional)* | 17.3% | 41.7% | 41.0% | 308,770 |

- Intermediate: **43.0% → 17.3%** (−25.7 pts)
- Higher: **12.8% → 41.0%** (+28.2 pts)
- Advanced: 44.2% → 41.7% — **essentially flat throughout**

Advanced holding steady is what makes the finding clean: this is not a general
drift, it is Intermediate giving way directly to Higher. Higher apprenticeships
overtook Intermediate around 2020/21 and are now close to overtaking Advanced.

**Why it matters commercially:** a provider reading only headline volumes would
conclude the market is flat and stable. It is not — demand did not fall, it
changed level. Provision built for Intermediate delivery is chasing a segment
that has lost three-fifths of its share.

Model: `gold.mart_level_shift`

## Finding 2 — the shift is national but uneven, and London is pulling away

Change in level share, 2017/18 → 2024/25, by region:

| region | higher (pts) | intermediate (pts) |
|---|---|---|
| London | **+33.8** | −23.7 |
| South East | +27.5 | −24.6 |
| East of England | +27.3 | −23.5 |
| West Midlands | +27.2 | −25.7 |
| East Midlands | +26.9 | −26.2 |
| South West | +25.6 | −21.0 |
| North West | +25.0 | −22.4 |
| Yorkshire and The Humber | +23.5 | −25.0 |
| North East | **+21.8** | −26.2 |

Every region moved the same direction — so this is structural, not local. But
the spread is **12 percentage points**, and London leads it. Note the North East
shed *more* Intermediate than London (−26.2 vs −23.7) while gaining the *least*
Higher: the segment left, and less of it came back at a higher level.

## Finding 3 — three structurally distinct regional markets

Unsupervised segmentation on level mix (BigQuery ML k-means, k=3, features are
shares so volume does not dominate):

| cluster | members | character |
|---|---|---|
| 1 | East of England | mid-high Higher share |
| 2 | **London** | highest Higher (37.3%), lowest Intermediate (20.9%) |
| 3 | the other seven regions | Intermediate-weighted |

London separates on its own without being told to — the algorithm recovers what
Finding 2 shows directly, which is a useful cross-check rather than a new fact.

Model: `gold.region_segments` · `sql/ai/01_region_clustering.sql`

## Finding 4 — the naive "achievement rate" is not a completion rate

Dividing same-year achievements by same-year starts is a trap, because
apprenticeships run 1–4 years. Achievements in 2017/18 belong largely to
cohorts that started **before** the 2017 levy reform, when volumes were higher.

| year | achievements ÷ starts (same year) |
|---|---|
| 2017/18 | 0.735 |
| 2021/22 | 0.393 |
| 2024/25 | 0.561 |

The 2017/18 figure is not a 74% completion rate — it is a large pre-reform
cohort completing against a shrunken post-reform intake. **This dataset cannot
support a true completion rate**: it has no cohort linkage between a start and
the achievement it eventually produces.

Stating that plainly is the finding. A ratio computed anyway would be the fourth
way this dataset misleads a careless analyst.

## Finding 5 — the publisher revises history, substantially

11,497 figures were revised across six releases; **392 moved between withheld
and published**.

| revision | figures revised | disclosure changes |
|---|---|---|
| 1.0 → 1.0.2 | 2,996 | 30 |
| 2.0 → 2.0.1 | 4,191 | 203 |
| 2.0.1 → 2.0.2 | 3,900 | 37 |

Any analysis pinned to a single download is quietly wrong the moment the next
version lands. The SCD-2 fact makes "what did we report in January?" answerable.

Model: `gold.mart_restatement_history`

---

## What this data cannot answer

Naming the limits is part of the analysis:

- **No completion or pass rates** — no cohort linkage (Finding 4).
- **No provider-level detail** — provider *type* only, so no benchmarking of
  individual providers.
- **No sector or subject breakdown** — this extract carries level, age, funding
  and provider type only.
- **No sub-regional geography** — region is the finest grain; no LEP, LA or
  travel-to-work area.
- **2025/26 is three quarters and provisional** — excluded from all trend
  conclusions above; flagged as `is_provisional` throughout the warehouse.
