
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  





with validation_errors as (

    select
        row_key, dataset_version
    from `dfe-apprenticeships-2026`.`silver`.`stg_apprenticeships`
    group by row_key, dataset_version
    having count(*) > 1

)

select *
from validation_errors



  
  
      
    ) dbt_internal_test