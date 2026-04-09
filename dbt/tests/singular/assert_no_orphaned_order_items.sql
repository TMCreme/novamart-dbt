-- Order items should always reference a valid order
-- This test returns order items with no matching order

select
    oi.order_item_id,
    oi.order_id
from {{ ref('stg_shopify__order_items') }} as oi
left join {{ ref('stg_shopify__orders') }} as o
    on oi.order_id = o.order_id
where o.order_id is null