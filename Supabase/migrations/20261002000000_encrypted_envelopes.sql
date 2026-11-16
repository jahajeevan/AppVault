-- Optional sync schema. Keep this migration unused unless a user explicitly enables sync.
-- Clients upload only AES-GCM encrypted opaque envelopes; no client contains a service-role key.
create table if not exists public.appvault_envelopes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  version integer not null check (version = 1),
  nonce bytea not null,
  ciphertext bytea not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.appvault_envelopes enable row level security;
revoke all on public.appvault_envelopes from public, anon;
grant select, insert, update, delete on public.appvault_envelopes to authenticated;
create policy "users access only their own envelopes" on public.appvault_envelopes
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create index if not exists appvault_envelopes_user_id_updated_at_idx on public.appvault_envelopes (user_id, updated_at desc);
