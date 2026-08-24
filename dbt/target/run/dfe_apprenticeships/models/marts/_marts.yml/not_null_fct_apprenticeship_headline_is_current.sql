
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select is_current
from `dfe-apprenticeships-2026`.`gold`.`fct_apprenticeship_headline`
where is_current is null



  
  
      
    ) dbt_internal_test