
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select academic_year_start
from `dfe-apprenticeships-2026`.`silver`.`stg_apprenticeships`
where academic_year_start is null



  
  
      
    ) dbt_internal_test