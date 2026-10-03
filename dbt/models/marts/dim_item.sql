-- Dimensión producto: una fila por item (3.049), con su jerarquía item → departamento → categoría.
-- Sale de stg_sales porque es la única fuente con dept_id y cat_id. El test unique de item_id
-- garantiza que cada item tiene un solo departamento y categoría.

with sales as (
    select * from {{ ref('stg_sales') }}
)

select distinct
    item_id,
    dept_id,
    cat_id
from sales
