-- Khata cloud schema (run in Supabase SQL editor)
--
-- Auth setup (Dashboard → Authentication):
--   1. Enable Phone provider (OTP via SMS). Disable Anonymous if it was on.
--   2. Configure an SMS provider (Twilio / MessageBird / etc.).
--   3. Optional: add test phone numbers under Phone Auth for emulator testing.
--
-- RLS: every row is scoped to auth.uid(). A shopkeeper can ONLY read/write
-- their own customers and transactions — never another account's data.

-- Customers (mirrors local Drift Customers + aliases/balance for backup)
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  local_id integer not null,
  name text not null,
  phone_number text not null,
  photo_path text,
  address text,
  reference_note text,
  created_at timestamptz not null default now(),
  current_balance double precision not null default 0,
  aliases jsonb not null default '[]'::jsonb,
  unique (user_id, local_id),
  unique (user_id, phone_number)
);

alter table public.customers add column if not exists address text;
alter table public.customers add column if not exists reference_note text;

-- Transactions (mirrors Drift Transactions; line items stored as JSON)
create table if not exists public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  local_id integer not null,
  customer_id uuid not null references public.customers (id) on delete cascade,
  local_customer_id integer not null,
  amount double precision not null check (amount > 0),
  type text not null check (type in ('credit_given', 'payment_received')),
  note text,
  created_at timestamptz not null default now(),
  source_type text not null default 'manual'
    check (source_type in ('manual', 'voice')),
  reverses_local_id integer,
  reverses_transaction_id uuid references public.transactions (id),
  is_voided boolean not null default false,
  items jsonb not null default '[]'::jsonb,
  unique (user_id, local_id)
);

create index if not exists transactions_user_id_idx on public.transactions (user_id);
create index if not exists transactions_customer_id_idx on public.transactions (customer_id);

alter table public.customers enable row level security;
alter table public.transactions enable row level security;

-- Drop legacy policies if re-running this script
drop policy if exists "customers_select_own" on public.customers;
drop policy if exists "customers_insert_own" on public.customers;
drop policy if exists "customers_update_own" on public.customers;
drop policy if exists "customers_delete_own" on public.customers;
drop policy if exists "transactions_select_own" on public.transactions;
drop policy if exists "transactions_insert_own" on public.transactions;
drop policy if exists "transactions_update_own" on public.transactions;
drop policy if exists "transactions_delete_own" on public.transactions;

-- Customers: own rows only
create policy "customers_select_own"
  on public.customers for select
  to authenticated
  using (auth.uid() = user_id);

create policy "customers_insert_own"
  on public.customers for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "customers_update_own"
  on public.customers for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "customers_delete_own"
  on public.customers for delete
  to authenticated
  using (auth.uid() = user_id);

-- Transactions: own rows only
create policy "transactions_select_own"
  on public.transactions for select
  to authenticated
  using (auth.uid() = user_id);

create policy "transactions_insert_own"
  on public.transactions for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "transactions_update_own"
  on public.transactions for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "transactions_delete_own"
  on public.transactions for delete
  to authenticated
  using (auth.uid() = user_id);

-- Deny the anon role explicitly (phone OTP users are `authenticated`)
revoke all on public.customers from anon;
revoke all on public.transactions from anon;
grant select, insert, update, delete on public.customers to authenticated;
grant select, insert, update, delete on public.transactions to authenticated;
