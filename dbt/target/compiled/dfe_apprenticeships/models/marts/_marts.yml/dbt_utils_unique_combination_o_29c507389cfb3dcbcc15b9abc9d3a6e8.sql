





with validation_errors as (

    select
        row_key, valid_from_seq
    from `dfe-apprenticeships-2026`.`gold`.`fct_apprenticeship_headline`
    group by row_key, valid_from_seq
    having count(*) > 1

)

select *
from validation_errors


