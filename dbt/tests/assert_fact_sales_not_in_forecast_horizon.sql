-- El horizonte de pronóstico (d_1942..d_1969) no tiene ventas: si aparece en el fact, hay fuga
-- o una entrega mal cargada. Devuelve las fechas ofensoras; el test pasa si no devuelve filas.

select distinct f.date_key
from {{ ref('fact_sales') }} f
join {{ ref('dim_date') }} d on d.date_key = f.date_key
where d.is_forecast_horizon
