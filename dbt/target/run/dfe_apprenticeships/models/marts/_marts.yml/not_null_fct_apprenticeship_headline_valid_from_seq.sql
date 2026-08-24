
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select valid_from_seq
from `dfe-apprenticeships-2026`.`gold`.`fct_apprenticeship_headline`
where valid_from_seq is null



  
  
      
    ) dbt_internal_test