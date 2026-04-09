{% test valid_currency_code(model, column_name) %}

select {{ column_name }}
from {{ model }}
where lower({{ column_name }}) not in (
    'usd', 'eur', 'gbp', 'cad', 'aud', 'jpy', 'chf', 'cny', 'inr', 'brl'
)

{% endtest %}