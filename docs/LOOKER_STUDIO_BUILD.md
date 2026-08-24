# Building the Looker Studio report — step by step

Report name: **Apprenticeships — England (DfE)**
Signed in as **divyeshperla@gmail.com** (the account that owns the project).

---

## Step 1 — Create the report and connect BigQuery

1. Go to <https://lookerstudio.google.com>
2. **Create** → **Report**
3. In the "Add data to report" panel, choose **BigQuery**
4. First time only: click **Authorize**
5. Navigate: **My Projects** → `dfe-apprenticeships-2026` → `gold` → `mart_regional_trends`
6. Click **Add** → **Add to report** on the confirmation dialog

You now have a table on the canvas. Delete it — we'll add charts deliberately.

7. **Resource** → **Manage added data sources** → rename the source to
   `Regional trends (gold)` → **Done**

---

## Step 2 — Fix the field defaults BEFORE building charts

Looker Studio guesses aggregations, and it guesses two of ours wrong.

**Resource** → **Manage added data sources** → **Edit** next to the source.

| Field | Change to | Why |
|---|---|---|
| `suppression_rate` | Aggregation = **Average**, Type = **Percent** | It is already a per-row ratio. Left as SUM, nine regions sum to ~200% |
| `achievement_ratio` | Aggregation = **Average**, Type = **Percent** | Same reason |
| `academic_year_start` | Aggregation = **None** | It is a year, not a measure to sum |
| `is_provisional` | leave as is | Used as a filter, not a metric |

`starts`, `achievements`, `participation`, `start_rows_*` keep **Sum** — correct.

Click **Done**.

---

## Step 3 — Report-level filter (do this once, not per chart)

The residual geography bucket is not a place and will distort every chart.

1. **File** → **Report settings**
2. **Add a filter** → **Create a filter**
3. Name: `Exclude residual geography`
4. **Exclude** · `region_name` · **Equal to (=)** · `Outside of England and unknown`
5. **Save**

Every chart on the report now inherits it.

---

## Step 4 — Chart 1: starts and achievements over time

**Add a chart** → **Time series** will NOT work — there is no date field, only an
academic-year label. Use a **Combo chart** or **Line chart** instead.

- **Add a chart** → **Line chart**
- **Dimension:** `academic_year_label`
- **Metric:** `starts`, then **Add metric** → `achievements`
- **Sort:** `academic_year_start` · Ascending
  *(Sorting by the label works alphabetically here by luck; sorting by the
  integer is correct by construction.)*
- **Style** tab → Series 1 colour `#2a78d6`, Series 2 `#eb6834`, line weight 2

**Caveat to state on the slide:** 2025/26 is a part-year. Looker will not dash it
for you. Either add a text box saying so, or add a chart filter excluding
`is_provisional = true` and note that the chart shows full years only.

---

## Step 5 — Chart 2: level mix by region

- **Add a chart** → **Stacked bar chart** (horizontal)
- **Dimension:** `region_name`
- **Breakdown dimension:** `apprenticeship_level`
- **Metric:** `starts`
- **Style** → tick **Stack to 100%** (this is the point — composition, not volume)
- **Sort:** `starts` Descending
- Add a chart-level filter: exclude `is_provisional = true` (full years only)

London should surface as the outlier: highest Higher share, lowest Intermediate.

---

## Step 6 — Chart 3: suppression rate by region

- **Add a chart** → **Bar chart** (horizontal)
- **Dimension:** `region_name`
- **Metric:** `suppression_rate` (now averaging, per Step 2)
- **Sort:** `suppression_rate` Descending
- **Style** → single series colour `#eda100`

Add a text box under it: *"Share of underlying cells withheld for statistical
disclosure control. A high rate means the total is incomplete, not that
activity is low."* — this is the sentence that shows you understood the data.

---

## Step 7 — Page 2: revisions between versions

1. **Page** → **New page**
2. **Resource** → **Add data** → BigQuery → `gold` → `mart_restatement_history`
3. Rename the source to `Restatement history (gold)`
4. **Add a chart** → **Bar chart**
   - **Dimension:** `restated_in_version`
   - **Metric:** `Record Count`, then add `disclosure_status_changed` with
     aggregation **Sum** (booleans sum as 1/0 = a count of true)
   - **Sort:** `restated_in_version` Ascending
5. Optional scorecard: **Add a chart** → **Scorecard**, metric `Record Count`,
   title "Figures revised across six releases"

---

## Step 8 — Before screenshotting

- **Theme and layout** → pick a light theme; console screenshots read better light
- Give every chart a real title (click chart → **Style** → **Chart header** →
  show title) — untitled charts look unfinished in a deck
- **View** mode (top right) hides the edit chrome — screenshot from there
- **Share** → **Anyone with the link can view** if you want a live link in the deck

---

## Known limitations to mention rather than hide

- Looker Studio cannot dash the provisional year automatically; the distinction
  is carried by a filter or annotation, not the visual.
- `Record Count` on the restatement page counts SCD-2 transitions, not distinct
  figures — a single row_key revised twice contributes two.
