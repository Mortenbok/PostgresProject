-- Run in the `development` database AS development_user (so raw_reader's
-- default privileges apply). Generates deterministic sample CRM data that is
-- consistent with raw_customers / raw_orders. Safe to re-run (truncates first).
--
--   psql -U development_user -d development -f setup/03_crm_sample_data.sql
--
-- Stitching is deliberately "realistic": leads are NOT linked to customers by
-- id. Converted leads share the customer's email (with messy casing and
-- whitespace), some people have duplicate leads, and opportunities only
-- reference lead_id. dbt resolves lead -> customer via normalised email.
\set ON_ERROR_STOP on

create table if not exists raw.raw_leads (
    id            integer,
    first_name    text,
    last_name     text,
    email         text,
    country_code  text,
    lead_source   text,
    status        text,
    created_at    date,
    converted_at  date
);

create table if not exists raw.raw_opportunities (
    id          integer,
    lead_id     integer,
    name        text,
    stage       text,
    amount_dkk  integer,
    owner       text,
    created_at  date,
    close_date  date
);

truncate raw.raw_leads, raw.raw_opportunities;

-- Deterministic pseudo-random number in [0, 1) from a text seed.
create function pg_temp.rnd(seed text) returns double precision
language sql immutable as
$$ select ('x' || substr(md5(seed), 1, 8))::bit(32)::bigint / 4294967296.0 $$;

-- Pick an element of an array deterministically.
create function pg_temp.pick(arr text[], seed text) returns text
language sql immutable as
$$ select arr[1 + floor(pg_temp.rnd(seed) * array_length(arr, 1))::int] $$;

create temp table sources (v text[]);
insert into sources values (array['Web', 'Referral', 'Paid Social', 'Trade Show', 'Outbound', 'Newsletter']);

-- ---------------------------------------------------------------------------
-- Leads
-- ---------------------------------------------------------------------------
create temp table tmp_leads (
    lead_key     text,
    kind         text,      -- converted | duplicate | prospect
    first_name   text,
    last_name    text,
    email        text,
    country_code text,
    lead_source  text,
    status       text,
    created_at   date,
    converted_at date
);

create temp table customers as
select c.*,
       least(c.created_at,
             coalesce((select min(o.ordered_at) from raw.raw_orders o where o.customer_id = c.id),
                      c.created_at)) as acquired_on
from raw.raw_customers c;

-- ~80% of customers came in through a lead.
insert into tmp_leads
select 'c' || c.id,
       'converted',
       c.first_name,
       c.last_name,
       case when pg_temp.rnd('em' || c.id) < 0.15 then upper(c.email)
            when pg_temp.rnd('em' || c.id) < 0.30 then lower(c.email)
            when pg_temp.rnd('em' || c.id) < 0.38 then ' ' || lower(c.email) || ' '
            else c.email end,
       case when pg_temp.rnd('cc' || c.id) < 0.2 then lower(c.country_code) else c.country_code end,
       pg_temp.pick(s.v, 'src' || c.id),
       'Converted',
       c.acquired_on - (7 + floor(pg_temp.rnd('lag' || c.id) * 60))::int,
       c.acquired_on
from customers c cross join sources s
where pg_temp.rnd('conv' || c.id) < 0.8;

-- Some converted people filled in a form again later -> duplicate lead.
insert into tmp_leads
select 'd' || c.id,
       'duplicate',
       c.first_name,
       c.last_name,
       upper(c.email),
       c.country_code,
       'Web',
       'New',
       c.acquired_on + (10 + floor(pg_temp.rnd('dupday' || c.id) * 80))::int,
       null
from customers c
where pg_temp.rnd('conv' || c.id) < 0.8
  and pg_temp.rnd('dup' || c.id) < 0.15;

-- Prospects that never became customers.
insert into tmp_leads
select 'p' || g,
       'prospect',
       fn,
       ln,
       fn || '.' || ln || (1000 + g) || '@example.org',
       pg_temp.pick(array['DK', 'DK', 'DK', 'SE', 'NO', 'DE', 'NL', 'FR', 'US'], 'pcc' || g),
       pg_temp.pick(s.v, 'psrc' || g),
       case when pg_temp.rnd('pst' || g) < 0.30 then 'Disqualified'
            when pg_temp.rnd('pst' || g) < 0.55 then 'New'
            when pg_temp.rnd('pst' || g) < 0.80 then 'Working'
            else 'Qualified' end,
       date '2025-01-01' + floor(pg_temp.rnd('pday' || g) * 318)::int,
       null
from generate_series(1, 200) g
cross join sources s
cross join lateral (
    select pg_temp.pick(array['Anna', 'Emma', 'Ida', 'Freja', 'Clara', 'Noah', 'William', 'Oscar',
                              'Lucas', 'Carl', 'Sofia', 'Alma', 'Elias', 'Felix', 'Laura'], 'pfn' || g) as fn,
           pg_temp.pick(array['Andersen', 'Pedersen', 'Larsen', 'Sorensen', 'Rasmussen', 'Berg',
                              'Lindqvist', 'Muller', 'De Vries', 'Martin', 'Smith', 'Olsen'], 'pln' || g) as ln
) n;

insert into raw.raw_leads
select row_number() over (order by created_at, lead_key),
       first_name, last_name, email, country_code, lead_source, status, created_at, converted_at
from tmp_leads;

create temp table lead_ids as
select row_number() over (order by created_at, lead_key) as lead_id, *
from tmp_leads;

-- ---------------------------------------------------------------------------
-- Opportunities (reference lead_id only)
-- ---------------------------------------------------------------------------
create temp table tmp_opps (
    opp_key     text,
    lead_id     bigint,
    last_name   text,
    stage       text,
    created_at  date,
    close_date  date
);

-- Every converted lead had a won opportunity closing on the acquisition date.
insert into tmp_opps
select 'w' || l.lead_key, l.lead_id, l.last_name, 'Closed Won',
       l.created_at + floor(pg_temp.rnd('oc' || l.lead_key) * (l.converted_at - l.created_at))::int,
       l.converted_at
from lead_ids l
where l.kind = 'converted';

-- ~30% of converted leads later got an upsell opportunity.
insert into tmp_opps
select 'u' || l.lead_key, l.lead_id, l.last_name,
       case when pg_temp.rnd('ust' || l.lead_key) < 0.40 then 'Closed Won'
            when pg_temp.rnd('ust' || l.lead_key) < 0.70 then 'Closed Lost'
            when pg_temp.rnd('ust' || l.lead_key) < 0.85 then 'Proposal'
            else 'Negotiation' end,
       d.created_at,
       d.created_at + (14 + floor(pg_temp.rnd('ucl' || l.lead_key) * 30))::int
from lead_ids l
cross join lateral (
    select l.converted_at + (30 + floor(pg_temp.rnd('uday' || l.lead_key) * 120))::int as created_at
) d
where l.kind = 'converted'
  and pg_temp.rnd('up' || l.lead_key) < 0.30;

-- Qualified prospects all have an opportunity; some working / disqualified ones too.
insert into tmp_opps
select 'q' || l.lead_key, l.lead_id, l.last_name,
       case when l.status = 'Disqualified' then 'Closed Lost'
            when l.status = 'Working' then 'Prospecting'
            when pg_temp.rnd('qst' || l.lead_key) < 0.35 then 'Closed Lost'
            when pg_temp.rnd('qst' || l.lead_key) < 0.60 then 'Prospecting'
            when pg_temp.rnd('qst' || l.lead_key) < 0.80 then 'Proposal'
            else 'Negotiation' end,
       d.created_at,
       d.created_at + (14 + floor(pg_temp.rnd('qcl' || l.lead_key) * 45))::int
from lead_ids l
cross join lateral (
    select l.created_at + (3 + floor(pg_temp.rnd('qday' || l.lead_key) * 18))::int as created_at
) d
where l.kind = 'prospect'
  and (   l.status = 'Qualified'
       or (l.status = 'Working'      and pg_temp.rnd('wo' || l.lead_key) < 0.30)
       or (l.status = 'Disqualified' and pg_temp.rnd('do' || l.lead_key) < 0.20));

insert into raw.raw_opportunities
select row_number() over (order by o.created_at, o.opp_key),
       o.lead_id,
       o.last_name || ' - ' || pg_temp.pick(array['Kitchen', 'Office', 'Sport', 'Toys'], 'cat' || o.opp_key) || ' deal',
       -- ~10% of stages are entered sloppily, e.g. 'closed won' or 'Closed-Lost'.
       case when pg_temp.rnd('mess' || o.opp_key) < 0.05 then lower(o.stage)
            when pg_temp.rnd('mess' || o.opp_key) < 0.10 then replace(o.stage, ' ', '-')
            else o.stage end,
       (10 + floor(pg_temp.rnd('amt' || o.opp_key) * 110))::int * 50,
       pg_temp.pick(array['Anne Holm', 'Jonas Berg', 'Sofie Lund', 'Mads Krogh'], 'own' || o.opp_key),
       o.created_at,
       o.close_date
from tmp_opps o;

select (select count(*) from raw.raw_leads) as leads,
       (select count(*) from raw.raw_opportunities) as opportunities;
