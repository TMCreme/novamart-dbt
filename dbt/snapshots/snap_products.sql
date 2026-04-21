{% snapshot snap_products %}

{{
    config(
        unique_key='product_id',
        strategy='timestamp',
        updated_at='updated_at',
        invalidate_hard_deletes=True
    )
}}

select
    product_id,
    name,
    category,
    price_cents,
    created_at,
    updated_at

from {{ source('app_db', 'products') }}

{% endsnapshot %}