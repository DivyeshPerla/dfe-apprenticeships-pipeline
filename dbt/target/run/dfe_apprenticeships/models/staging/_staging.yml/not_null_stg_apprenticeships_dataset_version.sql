
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select dataset_version
from `dfe-apprenticeships-2026`.`silver`.`stg_apprenticeships`
where dataset_version is null



  
  
      
    ) dbt_internal_test