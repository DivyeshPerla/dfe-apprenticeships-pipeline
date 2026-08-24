





with validation_errors as (

    select
        row_key, dataset_version
    from `dfe-apprenticeships-2026`.`silver`.`stg_apprenticeships`
    group by row_key, dataset_version
    having count(*) > 1

)

select *
from validation_errors


