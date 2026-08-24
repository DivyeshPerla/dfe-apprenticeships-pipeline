
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select row_key
from `dfe-apprenticeships-2026`.`gold`.`fct_apprenticeship_headline`
where row_key is null



  
  
      
    ) dbt_internal_test