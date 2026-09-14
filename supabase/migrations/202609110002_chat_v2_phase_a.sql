-- CHAT V2 — PHASE A: SERVER SCHEMA / RLS / TRIGGER-FREE GUARD / RPC
--
-- Backward-compatible server foundation for: paginated conversation
-- history, delete-for-me, delete-for-everyone, reconnect catch-up, and
-- future edit-message compatibility. Nothing here changes the existing
-- Flutter client's behavior: messages_friend_read / messages_friend_insert
-- are untouched, and no UPDATE grant is added to `authenticated` on
-- public.messages — every new write path is a narrowly-scoped RPC.
--
-- Confirmed live before writing this migration (not assumed):
--   - public.messages has no triggers today.
--   - `authenticated` has SELECT/INSERT only on public.messages (no
--     UPDATE grant) — this is why delete-for-everyone MUST go through a
--     SECURITY DEFINER RPC rather than a client-facing UPDATE policy.
--   - messages.text is already nullable — no constraint change needed to
--     clear it on delete.
--   - public.message_user_state does not exist yet.

-- ---------------------------------------------------------------------------
-- 1. Additive columns on public.messages
-- ---------------------------------------------------------------------------
alter table public.messages
  add column if not exists deleted_at timestamptz null;

alter table public.messages
  add column if not exists updated_at timestamptz not null default now();

-- Backfill existing rows' updated_at from their own original timestamp
-- (rather than leaving them all stamped at migration-apply time), so
-- historical data stays meaningful once catch-up/edit features read it.
update public.messages
   set updated_at = "timestamp"
 where updated_at is distinct from "timestamp";

comment on column public.messages.deleted_at is
  'NULL = normal message. NOT NULL = deleted for everyone (set only via delete_message_for_everyone()).';
comment on column public.messages.updated_at is
  'Bumped on every server-side mutation (delete-for-everyone today; future edit-message). Used for reconnect catch-up.';

-- ---------------------------------------------------------------------------
-- 2. message_user_state — persistence for "delete for me"
-- ---------------------------------------------------------------------------
create table if not exists public.message_user_state (
  message_id text not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

alter table public.message_user_state enable row level security;

drop policy if exists message_user_state_select on public.message_user_state;
create policy message_user_state_select
  on public.message_user_state for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists message_user_state_insert on public.message_user_state;
create policy message_user_state_insert
  on public.message_user_state for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.messages m
      where m.id = message_user_state.message_id
        and (m.sender_id = auth.uid()::text or m.receiver_id = auth.uid()::text)
    )
  );

drop policy if exists message_user_state_delete on public.message_user_state;
create policy message_user_state_delete
  on public.message_user_state for delete
  to authenticated
  using (user_id = auth.uid());

-- No UPDATE policy: a hidden-state row is only ever inserted or removed,
-- never modified in place.

revoke all on public.message_user_state from public, anon;
grant select, insert, delete on public.message_user_state to authenticated;

-- ---------------------------------------------------------------------------
-- 3. hide_message_for_me(message_id) — "delete for me"
--
-- SECURITY INVOKER (deliberately, not DEFINER): the caller's own
-- message_user_state_insert RLS policy above already correctly authorizes
-- this exact action, so no elevated privilege is needed — this keeps the
-- authorization rule in exactly one place (the RLS policy) instead of
-- duplicating it inside the function.
-- ---------------------------------------------------------------------------
create or replace function public.hide_message_for_me(p_message_id text)
returns void
language plpgsql
security invoker
set search_path to 'public', 'pg_catalog'
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  insert into public.message_user_state (message_id, user_id, hidden_at)
  values (p_message_id, auth.uid(), now())
  on conflict (message_id, user_id) do nothing;
end;
$$;

revoke execute on function public.hide_message_for_me(text) from public, anon;
grant execute on function public.hide_message_for_me(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. delete_message_for_everyone(message_id) — sender-only, trusted
--
-- SECURITY DEFINER is required here: `authenticated` has no UPDATE grant
-- on public.messages at all (confirmed live), so only a definer function
-- (running as its owner, which does have UPDATE) can perform this write.
-- auth.uid() is read server-side; the caller can never pass their own
-- identity or another user's id as authority.
-- ---------------------------------------------------------------------------
create or replace function public.delete_message_for_everyone(p_message_id text)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $$
declare
  v_sender_id text;
  v_already_deleted timestamptz;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  select sender_id, deleted_at into v_sender_id, v_already_deleted
    from public.messages
    where id = p_message_id
    for update;

  if v_sender_id is null then
    raise exception 'message not found' using errcode = 'P0002';
  end if;

  if v_sender_id <> auth.uid()::text then
    raise exception 'only the sender can delete this message for everyone'
      using errcode = '42501';
  end if;

  if v_already_deleted is not null then
    return; -- idempotent no-op: already deleted, nothing to do
  end if;

  update public.messages
     set text = null,
         deleted_at = now(),
         updated_at = now()
   where id = p_message_id;
end;
$$;

revoke execute on function public.delete_message_for_everyone(text) from public, anon;
grant execute on function public.delete_message_for_everyone(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. travel_conversation_messages(...) — paginated conversation history
--
-- SECURITY INVOKER: relies on (and is additionally protected by) the
-- existing messages_friend_read RLS policy plus the message_user_state
-- SELECT policy above — this RPC's own WHERE clause narrows results, and
-- RLS independently enforces the same boundary underneath as defense in
-- depth. Deterministic keyset pagination on (timestamp, id); no OFFSET;
-- hard server-side page-size cap; no dynamic SQL.
-- current_user is always taken from auth.uid(), never from a parameter.
-- Deleted-for-everyone rows are excluded here (MVP wants them fully
-- hidden from normal history) — they still surface via the catch-up RPC
-- below so local caches can purge them.
-- ---------------------------------------------------------------------------
create or replace function public.travel_conversation_messages(
  p_other_user_id uuid,
  p_limit int default 50,
  p_before_created_at timestamptz default null,
  p_before_id text default null
)
returns table (
  id text,
  sender_id text,
  receiver_id text,
  body text,
  created_at timestamptz,
  updated_at timestamptz,
  deleted_at timestamptz
)
language sql
stable
security invoker
set search_path to 'public', 'pg_catalog'
as $$
  select m.id, m.sender_id, m.receiver_id, m.text as body,
         m.timestamp as created_at, m.updated_at, m.deleted_at
  from public.messages m
  where m.deleted_at is null
    and (
      (m.sender_id = auth.uid()::text and m.receiver_id = p_other_user_id::text)
      or
      (m.sender_id = p_other_user_id::text and m.receiver_id = auth.uid()::text)
    )
    and exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and (
          (f.user_id_1 = auth.uid() and f.user_id_2 = p_other_user_id)
          or
          (f.user_id_2 = auth.uid() and f.user_id_1 = p_other_user_id)
        )
    )
    and not exists (
      select 1 from public.message_user_state s
      where s.message_id = m.id and s.user_id = auth.uid()
    )
    and (
      p_before_created_at is null
      or (m.timestamp, m.id) < (p_before_created_at, p_before_id)
    )
  order by m.timestamp desc, m.id desc
  limit least(greatest(p_limit, 1), 100);
$$;

revoke execute on function public.travel_conversation_messages(uuid, int, timestamptz, text) from public, anon;
grant execute on function public.travel_conversation_messages(uuid, int, timestamptz, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. travel_conversation_catchup(...) — reconnect catch-up
--
-- Same security posture as travel_conversation_messages. Filters on
-- updated_at (not timestamp/created_at) specifically so that an old
-- message soft-deleted while the caller was offline is still returned
-- (its updated_at was bumped even though its timestamp wasn't) — this is
-- what lets the local cache remove the tombstone instead of showing a
-- ghost message. Unlike the history RPC, deleted rows are NOT excluded
-- here — the id + deleted_at + updated_at is exactly what the client
-- needs to purge them locally, even with body already cleared.
-- ---------------------------------------------------------------------------
create or replace function public.travel_conversation_catchup(
  p_other_user_id uuid,
  p_since_updated_at timestamptz,
  p_limit int default 200
)
returns table (
  id text,
  sender_id text,
  receiver_id text,
  body text,
  created_at timestamptz,
  updated_at timestamptz,
  deleted_at timestamptz
)
language sql
stable
security invoker
set search_path to 'public', 'pg_catalog'
as $$
  select m.id, m.sender_id, m.receiver_id, m.text as body,
         m.timestamp as created_at, m.updated_at, m.deleted_at
  from public.messages m
  where m.updated_at > p_since_updated_at
    and (
      (m.sender_id = auth.uid()::text and m.receiver_id = p_other_user_id::text)
      or
      (m.sender_id = p_other_user_id::text and m.receiver_id = auth.uid()::text)
    )
    and exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and (
          (f.user_id_1 = auth.uid() and f.user_id_2 = p_other_user_id)
          or
          (f.user_id_2 = auth.uid() and f.user_id_1 = p_other_user_id)
        )
    )
    and not exists (
      select 1 from public.message_user_state s
      where s.message_id = m.id and s.user_id = auth.uid()
    )
  order by m.updated_at asc, m.id asc
  limit least(greatest(p_limit, 1), 500);
$$;

revoke execute on function public.travel_conversation_catchup(uuid, timestamptz, int) from public, anon;
grant execute on function public.travel_conversation_catchup(uuid, timestamptz, int) to authenticated;
