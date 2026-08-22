-- VOLTX / APEX Supplier Finder schema
-- Run in a dedicated Supabase project using the SQL editor.
-- This schema intentionally exposes no data to the anon role.

create schema if not exists private;

create table public.suppliers (
  id bigint generated always as identity primary key,
  name text not null,
  domain text not null unique,
  cnpj text,
  source_url text,
  status text not null default 'candidate'
    check (status in ('candidate', 'verified', 'approved', 'rejected', 'blocked')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint suppliers_domain_lowercase check (domain = lower(domain))
);

create table public.supplier_products (
  id bigint generated always as identity primary key,
  supplier_id bigint not null references public.suppliers(id) on delete cascade,
  external_id text,
  title text not null,
  category text not null,
  product_url text not null,
  image_url text,
  currency text not null default 'BRL' check (currency = 'BRL'),
  cost numeric(12,2) check (cost is null or cost >= 0),
  stock integer check (stock is null or stock >= 0),
  minimum_order_qty integer check (minimum_order_qty is null or minimum_order_qty > 0),
  raw_data jsonb not null default '{}'::jsonb,
  scraped_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint supplier_products_supplier_url_unique unique (supplier_id, product_url)
);

create table public.apex_recommendations (
  id bigint generated always as identity primary key,
  supplier_product_id bigint references public.supplier_products(id) on delete set null,
  source_url text not null unique,
  source_title text,
  supplier_name text,
  supplier_domain text,
  supplier_verified boolean not null default false,
  cnpj text,
  product_name text,
  category text,
  cost_brl numeric(12,2) check (cost_brl is null or cost_brl >= 0),
  suggested_price_brl numeric(12,2) check (suggested_price_brl is null or suggested_price_brl >= 0),
  gross_margin_pct numeric(6,2)
    check (gross_margin_pct is null or gross_margin_pct between -999.99 and 100),
  stock_status text not null default 'unknown'
    check (stock_status in ('in_stock', 'out_of_stock', 'preorder', 'unknown')),
  minimum_order_qty integer check (minimum_order_qty is null or minimum_order_qty > 0),
  shipping_notes text,
  risk_level text not null default 'medium'
    check (risk_level in ('low', 'medium', 'high', 'blocked')),
  decision text not null default 'review'
    check (decision in ('recommend', 'review', 'reject', 'block')),
  score numeric(5,2) not null default 0 check (score between 0 and 100),
  reasons jsonb not null default '[]'::jsonb,
  evidence jsonb not null default '[]'::jsonb,
  human_status text not null default 'pending'
    check (human_status in ('pending', 'approved', 'rejected')),
  human_reviewed_by uuid,
  human_reviewed_at timestamptz,
  published_at timestamptz,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.ai_runs (
  id bigint generated always as identity primary key,
  workflow_name text not null,
  execution_id text,
  status text not null check (status in ('running', 'completed', 'partial', 'failed')),
  input_count integer not null default 0 check (input_count >= 0),
  success_count integer not null default 0 check (success_count >= 0),
  error_count integer not null default 0 check (error_count >= 0),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  entity_type text not null,
  entity_id bigint,
  action text not null,
  actor_type text not null check (actor_type in ('n8n', 'ai', 'admin', 'system')),
  actor_id uuid,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index supplier_products_supplier_id_idx
  on public.supplier_products (supplier_id);
create index supplier_products_category_scraped_idx
  on public.supplier_products (category, scraped_at desc);
create index apex_recommendations_supplier_product_id_idx
  on public.apex_recommendations (supplier_product_id);
create index apex_recommendations_queue_idx
  on public.apex_recommendations (human_status, decision, created_at desc);
create index apex_recommendations_risk_idx
  on public.apex_recommendations (risk_level, score desc);
create index ai_runs_status_started_idx
  on public.ai_runs (status, started_at desc);
create index audit_logs_entity_idx
  on public.audit_logs (entity_type, entity_id, created_at desc);

create or replace function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function private.set_updated_at() from public, anon, authenticated;

create trigger suppliers_set_updated_at
before update on public.suppliers
for each row execute function private.set_updated_at();

create trigger supplier_products_set_updated_at
before update on public.supplier_products
for each row execute function private.set_updated_at();

create trigger apex_recommendations_set_updated_at
before update on public.apex_recommendations
for each row execute function private.set_updated_at();

alter table public.suppliers enable row level security;
alter table public.supplier_products enable row level security;
alter table public.apex_recommendations enable row level security;
alter table public.ai_runs enable row level security;
alter table public.audit_logs enable row level security;

revoke all on public.suppliers from anon, authenticated;
revoke all on public.supplier_products from anon, authenticated;
revoke all on public.apex_recommendations from anon, authenticated;
revoke all on public.ai_runs from anon, authenticated;
revoke all on public.audit_logs from anon, authenticated;

grant usage on schema public to authenticated;
grant usage on schema public to service_role;
grant select, insert, update, delete on public.suppliers to authenticated;
grant select, insert, update, delete on public.supplier_products to authenticated;
grant select, insert, update, delete on public.apex_recommendations to authenticated;
grant select on public.ai_runs to authenticated;
grant select on public.audit_logs to authenticated;
grant select, insert, update, delete on public.suppliers to service_role;
grant select, insert, update, delete on public.supplier_products to service_role;
grant select, insert, update, delete on public.apex_recommendations to service_role;
grant select, insert, update, delete on public.ai_runs to service_role;
grant select, insert, update, delete on public.audit_logs to service_role;
grant usage, select on sequence public.suppliers_id_seq to authenticated;
grant usage, select on sequence public.supplier_products_id_seq to authenticated;
grant usage, select on sequence public.apex_recommendations_id_seq to authenticated;
grant usage, select on sequence public.ai_runs_id_seq to authenticated;
grant usage, select on sequence public.audit_logs_id_seq to authenticated;
grant usage, select on sequence public.suppliers_id_seq to service_role;
grant usage, select on sequence public.supplier_products_id_seq to service_role;
grant usage, select on sequence public.apex_recommendations_id_seq to service_role;
grant usage, select on sequence public.ai_runs_id_seq to service_role;
grant usage, select on sequence public.audit_logs_id_seq to service_role;

create policy suppliers_admin_all on public.suppliers
for all to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy supplier_products_admin_all on public.supplier_products
for all to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy apex_recommendations_admin_all on public.apex_recommendations
for all to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin')
with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy ai_runs_admin_read on public.ai_runs
for select to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

create policy audit_logs_admin_read on public.audit_logs
for select to authenticated
using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'admin');

comment on table public.apex_recommendations is
  'AI suggestions only. A human must approve before a product can be published.';
