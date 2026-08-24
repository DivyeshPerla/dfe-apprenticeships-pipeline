
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

with child as (
    select dataset_version as from_field
    from `dfe-apprenticeships-2026`.`silver`.`stg_apprenticeships`
    where dataset_version is not null
),

parent as (
    select version as to_field
    from `dfe-apprenticeships-2026`.`silver`.`dataset_versions`
)

select
    from_field

from child
left join parent
    on child.from_field = parent.to_field

where parent.to_field is null



  
  
      
    ) dbt_internal_test