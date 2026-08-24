-- The trap inside the trap: why SCD-2 comparison must happen on TYPED values.
--
-- Between versions 1.0.2 and 2.0 the publisher reformatted ~4,200 percentage
-- values ('4' -> '4.0'). Semantically identical; textually different. A
-- string-level diff treats every one as a restatement and opens a spurious
-- SCD-2 record for it.
--
-- Result:
--   STRING diff (naive)    73,797 records
--   TYPED  diff (shipped)  69,589 records
--   ------------------------------------
--   phantom records avoided  4,208
--
-- 4,208 is exactly the restatement count measured between 1.0.2 and 2.0
-- during source profiling -- i.e. every "change" in that release was cosmetic.

WITH base AS (
  SELECT
    TO_HEX(MD5(CONCAT(time_period,'|',geographic_level,'|',IFNULL(NULLIF(region_code,''),'NA'),'|',
      apprenticeship_level,'|',age_youth_adult,'|',age_group,'|',funding_type,'|',provider_type))) AS row_key,
    v.version_seq,
    CONCAT(r.start_count,'~',r.achievement_count,'~',r.participation_count,'~',
           r.starts_percent,'~',r.achievements_percent) AS raw_blob
  FROM `dfe-apprenticeships-2026.bronze.raw_apprenticeships` r
  JOIN `dfe-apprenticeships-2026.silver.dataset_versions` v ON r.version = v.version
),
flagged AS (
  SELECT row_key, version_seq,
    CASE WHEN LAG(raw_blob) OVER (PARTITION BY row_key ORDER BY version_seq)
              IS DISTINCT FROM raw_blob THEN 1 ELSE 0 END AS is_change
  FROM base
),
grp AS (
  SELECT row_key, SUM(is_change) OVER (PARTITION BY row_key ORDER BY version_seq
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS g
  FROM flagged
)
SELECT 'STRING diff (naive)' AS method, COUNT(*) AS scd2_records
FROM (SELECT row_key, g FROM grp GROUP BY row_key, g)
UNION ALL
SELECT 'TYPED diff (shipped)', COUNT(*)
FROM `dfe-apprenticeships-2026.gold.fct_apprenticeship_headline`;
