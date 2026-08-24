
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

with all_values as (

    select
        achievements_percent_status as value_field,
        count(*) as n_records

    from `dfe-apprenticeships-2026`.`silver`.`stg_apprenticeships`
    group by achievements_percent_status

)

select *
from all_values
where value_field not in (
    'published','suppressed_low','suppressed_confidential','not_applicable','missing'
)



  
  
      
    ) dbt_internal_test