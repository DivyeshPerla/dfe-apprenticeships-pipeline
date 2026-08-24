
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select aggregation_depth
from `dfe-apprenticeships-2026`.`silver`.`stg_apprenticeships`
where aggregation_depth is null



  
  
      
    ) dbt_internal_test