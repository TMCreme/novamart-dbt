with inventory as (

    select * from {{ ref('stg_app_db__inventory') }}

),

products as (

    select * from {{ ref('stg_app_db__products') }}

),

latest_inventory as (

    select
        inventory_id,
        product_id,
        warehouse_location,
        quantity,
        updated_at,
        row_number() over (
            partition by product_id, warehouse_location
            order by updated_at desc
        ) as rn

    from inventory

),

current_inventory as (

    select
        li.inventory_id,
        li.product_id,
        p.product_name,
        p.category,
        p.price_dollars,
        li.warehouse_location,
        li.quantity,
        li.updated_at as inventory_updated_at

    from latest_inventory as li
    inner join products as p
        on li.product_id = p.product_id
    where li.rn = 1

)

select * from current_inventory