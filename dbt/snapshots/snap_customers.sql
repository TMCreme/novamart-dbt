{% snapshot snap_customers %}

{{
    config(
        unique_key='user_id',
        strategy='timestamp',
        updated_at='updated_at',
        invalidate_hard_deletes=True
    )
}}

select
    user_id,
    email,
    name,
    tier,
    created_at,
    updated_at

from {{ source('app_db', 'users') }}

{% endsnapshot %}