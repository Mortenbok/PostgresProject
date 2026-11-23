{#
  Column descriptions for the staging models.

  Each block is written once and referenced with {{ doc('<name>') }} from the
  staging YAML and from every downstream model (intermediate, marts) that
  passes the column through. Edit the text here, not in the YAML.

  Naming: <staging model>__<column>.
#}

{# ------------------------------------------------------------ stg_customers #}

{% docs stg_customers__customer_id %}
Shop customer id (raw `id`). Primary key of the customer.
{% enddocs %}

{% docs stg_customers__first_name %}
Customer first name, as entered.
{% enddocs %}

{% docs stg_customers__last_name %}
Customer last name, as entered.
{% enddocs %}

{% docs stg_customers__full_name %}
Customer first_name and last_name joined by a space. Null if either part is null.
{% enddocs %}

{% docs stg_customers__email %}
Customer email, lower-cased. Not trimmed in staging, so joins on email should
trim it (int_leads_matched does).
{% enddocs %}

{% docs stg_customers__country_code %}
Customer country as an upper-cased ISO country code, e.g. 'DK'.
{% enddocs %}

{% docs stg_customers__signed_up_on %}
When the customer account was created (raw `created_at`).
{% enddocs %}

{# --------------------------------------------------------------- stg_orders #}

{% docs stg_orders__order_id %}
Shop order id (raw `id`). Primary key of the order.
{% enddocs %}

{% docs stg_orders__customer_id %}
Customer who placed the order.
{% enddocs %}

{% docs stg_orders__ordered_on %}
When the order was placed (raw `ordered_at`).
{% enddocs %}

{% docs stg_orders__status %}
Order status, lower-cased: completed, shipped, cancelled or returned. Which
statuses count as revenue is set by var('revenue_statuses').
{% enddocs %}

{# ---------------------------------------------------------- stg_order_items #}

{% docs stg_order_items__order_item_id %}
Order line id (raw `id`). Primary key of the order line.
{% enddocs %}

{% docs stg_order_items__order_id %}
Order the line belongs to.
{% enddocs %}

{% docs stg_order_items__product_id %}
Product sold on the line.
{% enddocs %}

{% docs stg_order_items__quantity %}
Number of units on the line.
{% enddocs %}

{% docs stg_order_items__unit_price_dkk %}
Price charged per unit at order time, in DKK, numeric(12,2). Can differ from
the product's current list_price_dkk.
{% enddocs %}

{# ------------------------------------------------------------- stg_products #}

{% docs stg_products__product_id %}
Product id (raw `id`). Primary key of the product.
{% enddocs %}

{% docs stg_products__product_name %}
Product display name (raw `name`).
{% enddocs %}

{% docs stg_products__category %}
Product category, as in the source.
{% enddocs %}

{% docs stg_products__list_price_dkk %}
Current list price in DKK, numeric(12,2) (raw `price_dkk`).
{% enddocs %}

{# ---------------------------------------------------------------- stg_leads #}

{% docs stg_leads__lead_id %}
CRM lead id (raw `id`). Primary key of the lead.
{% enddocs %}

{% docs stg_leads__first_name %}
Lead first name, as entered.
{% enddocs %}

{% docs stg_leads__last_name %}
Lead last name, as entered.
{% enddocs %}

{% docs stg_leads__full_name %}
Lead first_name and last_name joined by a space. Null if either part is null.
{% enddocs %}

{% docs stg_leads__email %}
Lead email, trimmed and lower-cased. The key used to match leads to customers.
{% enddocs %}

{% docs stg_leads__country_code %}
Lead country as a trimmed, upper-cased ISO country code.
{% enddocs %}

{% docs stg_leads__lead_source %}
Channel the lead came from: trimmed, lower-cased, with runs of spaces and
hyphens replaced by '_' (e.g. 'Paid Search' -> 'paid_search').
{% enddocs %}

{% docs stg_leads__status %}
Lead status, trimmed and lower-cased: new, working, qualified, disqualified or
converted.
{% enddocs %}

{% docs stg_leads__created_on %}
When the lead was created in the CRM (raw `created_at`).
{% enddocs %}

{% docs stg_leads__converted_on %}
When the lead was converted (raw `converted_at`). Null if not converted.
{% enddocs %}

{# -------------------------------------------------------- stg_opportunities #}

{% docs stg_opportunities__opportunity_id %}
CRM opportunity id (raw `id`). Primary key of the opportunity.
{% enddocs %}

{% docs stg_opportunities__lead_id %}
Lead the opportunity was opened from.
{% enddocs %}

{% docs stg_opportunities__opportunity_name %}
Opportunity name (raw `name`).
{% enddocs %}

{% docs stg_opportunities__stage %}
Sales stage, normalised to snake_case ('Closed Won', 'closed-won' ->
'closed_won'): prospecting, proposal, negotiation, closed_won or closed_lost.
{% enddocs %}

{% docs stg_opportunities__is_closed %}
True when the opportunity stage is closed_won or closed_lost.
{% enddocs %}

{% docs stg_opportunities__is_won %}
True when the opportunity stage is closed_won.
{% enddocs %}

{% docs stg_opportunities__amount_dkk %}
Expected deal value of the opportunity in DKK, numeric(12,2).
{% enddocs %}

{% docs stg_opportunities__sales_owner %}
Sales rep who owns the opportunity (raw `owner`).
{% enddocs %}

{% docs stg_opportunities__created_on %}
When the opportunity was created (raw `created_at`).
{% enddocs %}

{% docs stg_opportunities__close_on %}
Expected or actual close date of the opportunity (raw `close_date`).
{% enddocs %}
