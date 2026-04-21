with products as (

    select * from {{ ref('stg_app_db__products') }}

),

inventory as (

    select
        product_id,
        sum(quantity) as total_stock_quantity,
        count(distinct warehouse_location) as warehouse_count
    from {{ ref('int_product_inventory_current') }}
    group by product_id

),

final as (

    select
        {{ generate_surrogate_key(['p.product_id']) }} as product_key,
        p.product_id,
        p.product_name,
        p.category,
        p.price_cents,
        p.price_dollars,
        p.created_at as product_created_at,

        coalesce(i.total_stock_quantity, 0) as total_stock_quantity,
        coalesce(i.warehouse_count, 0) as warehouse_count,
        case
            when coalesce(i.total_stock_quantity, 0) = 0 then 'out_of_stock'
            when i.total_stock_quantity < 50 then 'low_stock'
            else 'in_stock'
        end as stock_status

    from products as p
    left join inventory as i
        on p.product_id = i.product_id

)

select * from final
