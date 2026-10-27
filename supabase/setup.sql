create table if not exists public.store_admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.store_admins enable row level security;
revoke all on public.store_admins from anon, authenticated;

create or replace function public.is_store_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.store_admins
    where user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_store_admin() from public;
grant execute on function public.is_store_admin() to authenticated;

create table if not exists public.products (
  id text primary key,
  name text not null,
  cat text not null,
  price numeric(12, 2) not null check (price >= 0),
  discount_price numeric(12, 2) check (discount_price is null or (discount_price >= 0 and discount_price < price)),
  is_new boolean not null default false,
  description text not null default '',
  img text not null default '',
  image_path text,
  ts bigint not null default 0,
  deleted boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.products enable row level security;
revoke all on public.products from anon, authenticated;
grant select on public.products to anon, authenticated;
grant insert, update, delete on public.products to authenticated;

drop policy if exists "Anyone can read products" on public.products;
create policy "Anyone can read products"
  on public.products for select
  to anon, authenticated
  using (true);

drop policy if exists "Store admins can insert products" on public.products;
create policy "Store admins can insert products"
  on public.products for insert
  to authenticated
  with check ((select public.is_store_admin()));

drop policy if exists "Store admins can update products" on public.products;
create policy "Store admins can update products"
  on public.products for update
  to authenticated
  using ((select public.is_store_admin()))
  with check ((select public.is_store_admin()));

drop policy if exists "Store admins can delete products" on public.products;
create policy "Store admins can delete products"
  on public.products for delete
  to authenticated
  using ((select public.is_store_admin()));

insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do update set public = true;

drop policy if exists "Anyone can view product images" on storage.objects;
create policy "Anyone can view product images"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'product-images');

drop policy if exists "Store admins can upload product images" on storage.objects;
create policy "Store admins can upload product images"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'product-images' and (select public.is_store_admin()));

drop policy if exists "Store admins can update product images" on storage.objects;
create policy "Store admins can update product images"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'product-images' and (select public.is_store_admin()))
  with check (bucket_id = 'product-images' and (select public.is_store_admin()));

drop policy if exists "Store admins can delete product images" on storage.objects;
create policy "Store admins can delete product images"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'product-images' and (select public.is_store_admin()));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'products'
  ) then
    alter publication supabase_realtime add table public.products;
  end if;
end
$$;
