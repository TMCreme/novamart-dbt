with shopify_refunds as (

    select
        refund_id,
        order_id,
        reason,
        refund_amount_cents,
        refund_amount_dollars,
        refunded_at,
        'shopify' as source_system
    from {{ ref('stg_shopify__refunds') }}

),

stripe_refunds as (

    select
        sr.refund_id,
        c.payment_id,
        p.order_id,
        sr.reason,
        sr.amount_cents as refund_amount_cents,
        sr.amount_dollars as refund_amount_dollars,
        sr.created_at as refunded_at,
        'stripe' as source_system
    from {{ ref('stg_stripe__refunds') }} as sr
    inner join {{ ref('stg_stripe__charges') }} as c
        on sr.charge_id = c.charge_id
    inner join {{ ref('stg_stripe__payments') }} as p
        on c.payment_id = p.payment_id

),

unioned as (

    select
        refund_id,
        order_id,
        reason,
        refund_amount_cents,
        refund_amount_dollars,
        refunded_at,
        source_system
    from shopify_refunds

    union all

    select
        refund_id,
        order_id,
        reason,
        refund_amount_cents,
        refund_amount_dollars,
        refunded_at,
        source_system
    from stripe_refunds

),

final as (

    select
        {{ generate_surrogate_key(['refund_id', 'source_system']) }} as refund_key,
        refund_id,
        order_id,
        source_system,
        reason,
        refund_amount_cents,
        refund_amount_dollars,
        refunded_at

    from unioned

)

select * from final
