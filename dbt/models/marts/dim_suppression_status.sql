{{ config(materialized='table') }}

/* Decodes the statistical disclosure control markers carried in the source's
   numeric columns, so downstream consumers -- and the analytics agent -- can
   explain WHY a figure is absent rather than treating it as zero or missing.

   Code meanings follow DfE convention. Confirm against the release
   methodology before quoting these definitions externally. */

select * from unnest([
    struct(
        'published' as status_code,
        'Published' as status_label,
        true as has_value,
        'Figure is published and usable.' as explanation
    ),
    struct(
        'suppressed_low', 'Suppressed (low)', false,
        'Value too small to publish without risking disclosure of an individual.'
    ),
    struct(
        'suppressed_confidential', 'Suppressed (confidential)', false,
        'Withheld for confidentiality reasons.'
    ),
    struct(
        'not_applicable', 'Not applicable', false,
        'This measure is not collected for this breakdown.'
    ),
    struct(
        'missing', 'Missing', false,
        'Absent from the source with no marker given.'
    ),
    struct(
        'unrecognised', 'Unrecognised marker', false,
        'A marker not seen during profiling. Investigate before using.'
    )
])
