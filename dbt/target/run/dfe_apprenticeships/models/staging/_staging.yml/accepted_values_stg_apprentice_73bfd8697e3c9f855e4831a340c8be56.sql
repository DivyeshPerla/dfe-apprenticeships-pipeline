
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

with all_values as (

    select
        aggregation_depth as value_field,
        count(*) as n_records

    from `dfe-apprenticeships-2026`.`silver`.`stg_apprenticeships`
    group by aggregation_depth

)

select *
from all_values
where value_field not in (
    0,1,2,3,4,5
)



  
  
      
    ) dbt_internal_test