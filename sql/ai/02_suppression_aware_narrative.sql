-- Suppression-aware regional narratives.
--
-- The differentiator: the prompt is built from data that carries its own
-- disclosure status, and the model is instructed to say a figure is withheld
-- rather than estimate it. Most LLM-over-warehouse demos will happily invent
-- a number for a suppressed cell; this one is architecturally prevented from
-- seeing one, because suppressed measures are NULL in silver and their reason
-- travels alongside in a status column.
--
-- Cost note: Gemini calls are the only non-free component of this project.
-- Restricted to 9 regions x 1 row = 9 calls.

CREATE OR REPLACE TABLE `dfe-apprenticeships-2026.gold.regional_narratives` AS
WITH facts AS (
  SELECT
    region_name,
    SUM(IF(academic_year_start = 2024, starts, NULL))             AS starts_2024,
    SUM(IF(academic_year_start = 2017, starts, NULL))             AS starts_2017,
    SUM(IF(academic_year_start = 2024, achievements, NULL))       AS achievements_2024,
    SUM(start_rows_suppressed)                                    AS suppressed_cells,
    SUM(start_rows_published)                                     AS published_cells
  FROM `dfe-apprenticeships-2026.gold.mart_regional_trends`
  WHERE region_name != 'Outside of England and unknown'
  GROUP BY region_name
),
prompts AS (
  SELECT
    region_name,
    suppressed_cells,
    CONCAT(
      'You are a careful analyst of UK official statistics. Write two sentences ',
      'about apprenticeship starts in ', region_name, ', England.\n\n',
      'These are PUBLISHED HISTORICAL FIGURES, not forecasts or projections.\n',
      'DATA (all figures rounded to the nearest 10 by the publisher):\n',
      '- 2017/18 starts: ', IFNULL(CAST(starts_2017 AS STRING), 'WITHHELD'), '\n',
      '- 2024/25 starts: ', IFNULL(CAST(starts_2024 AS STRING), 'WITHHELD'), '\n',
      '- 2024/25 achievements: ', IFNULL(CAST(achievements_2024 AS STRING), 'WITHHELD'), '\n',
      '- underlying cells withheld for disclosure control: ', CAST(suppressed_cells AS STRING),
      ' of ', CAST(suppressed_cells + published_cells AS STRING), '\n\n',
      'RULES:\n',
      '1. Never estimate, infer or invent a figure marked WITHHELD. Say it is ',
      'not published and explain that this is disclosure control.\n',
      '2. Do not imply precision the rounding does not support.\n',
      '3. If a large share of cells is withheld, say the totals are incomplete.\n',
      '4. Never write "projected", "expected", "forecast" or "will" -- these are ',
      'figures already published for years that have happened.\n',
      '5. Refer to the region by its exact name: ', region_name, '. Do not ',
      'abbreviate or substitute a broader area.\n',
      '6. No preamble. Two sentences.'
    ) AS prompt
  FROM facts
)
SELECT
  region_name,
  suppressed_cells,
  ml_generate_text_llm_result AS narrative
FROM ML.GENERATE_TEXT(
  MODEL `dfe-apprenticeships-2026.gold.gemini`,
  TABLE prompts,
  STRUCT(0.1 AS temperature, 300 AS max_output_tokens, TRUE AS flatten_json_output)
);
