-- CHAT V2 — PHASE A.1 HARDENING
--
-- Closes 3 issues found during Phase A (202609110002) post-apply review,
-- before any local Drift cache is built against this API:
--
--   1. message_user_state carried default-ACL grants (UPDATE/TRUNCATE/
--      REFERENCES/TRIGGER for `authenticated`) beyond what the design
--      needs. RLS already blocked all of these (no UPDATE policy exists),
--      but the grants themselves are tightened for real least-privilege,
--      not just RLS-as-compensating-control.
--   2. travel_conversation_catchup's cursor was single-part
--      (updated_at only). If more rows share the exact same updated_at
--      than fit in one page, a repeat call using only max(updated_at)
--      with a strict `>` comparison would silently skip the remaining
--      same-timestamp rows. Replaced with a deterministic two-part
--      keyset cursor (change_at, id).
--   3. Confirmed multi-device ghost-message bug: catch-up excluded
--      hidden-for-me rows entirely with no signal that they became
--      hidden. A device that already cached a message before another
--      device hid it for the same account would never be told to remove
--      it. Fixed by having catch-up also emit hidden-for-me tombstones
--      (hidden_for_me = true), using message_user_state.hidden_at as a
--      second change-time source unified onto the same (change_at, id)
--      cursor (id = the message id in both branches, since
--      message_user_state.message_id shares that same id space).
--
-- travel_conversation_messages (normal history) and delete_message_for_
-- everyone are NOT touched — their semantics are already correct and are
-- explicitly out of scope for this hardening pass. hide_message_for_me is
-- also unchanged: its existing `ON CONFLICT (message_id, user_id) DO
-- NOTHING` already makes repeated hides a true no-op (hidden_at is not
-- bumped on a repeat call), which is exactly the required idempotency —
-- confirmed by re-reading its live definition, not assumed.

-- ---------------------------------------------------------------------------
-- 1. Grant hygiene: message_user_state
-- ---------------------------------------------------------------------------
revoke update, truncate, references, trigger
  on public.message_user_state
  from authenticated;

-- Resulting authenticated privileges on message_user_state: SELECT,
-- INSERT, DELETE only — matching exactly what the 3 RLS policies allow.

-- ---------------------------------------------------------------------------
-- 2 & 3. travel_conversation_catchup: two-part cursor + hidden-for-me
--        tombstones
--
-- Signature changes (new parameter inserted, new return column) require
-- DROP + CREATE rather than CREATE OR REPLACE, which cannot change a
-- function's return type or parameter list in place. This also removes
-- the old 3-parameter overload so Phase B never has two conflicting
-- versions to choose between.
-- ---------------------------------------------------------------------------
drop function if exists public.travel_conversation_catchup(uuid, timestamptz, integer);

create or replace function public.travel_conversation_catchup(
  p_other_user_id uuid,
  p_since_change_at timestamptz,
  p_since_change_id text default null,
  p_limit int default 200
)
returns table (
  id text,
  sender_id text,
  receiver_id text,
  body text,
  created_at timestamptz,
  updated_at timestamptz,
  deleted_at timestamptz,
  hidden_for_me boolean
)
language sql
stable
security invoker
set search_path to 'public', 'pg_catalog'
as $$
  with changed_messages as (
    select
      m.id, m.sender_id, m.receiver_id, m.text as body,
      m.timestamp as created_at, m.updated_at, m.deleted_at,
      false as hidden_for_me,
      m.updated_at as change_at
    from public.messages m
    where (
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
      and (m.updated_at, m.id) > (p_since_change_at, coalesce(p_since_change_id, ''))
  ),
  hidden_tombstones as (
    select
      m.id, m.sender_id, m.receiver_id, null::text as body,
      m.timestamp as created_at, m.updated_at, m.deleted_at,
      true as hidden_for_me,
      s.hidden_at as change_at
    from public.message_user_state s
    join public.messages m on m.id = s.message_id
    where s.user_id = auth.uid()
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
      and (s.hidden_at, s.message_id) > (p_since_change_at, coalesce(p_since_change_id, ''))
  )
  select id, sender_id, receiver_id, body, created_at, updated_at, deleted_at, hidden_for_me
  from (
    select * from changed_messages
    union all
    select * from hidden_tombstones
  ) merged
  order by change_at asc, id asc
  limit least(greatest(p_limit, 1), 500);
$$;

revoke execute on function public.travel_conversation_catchup(uuid, timestamptz, text, int)
  from public, anon;
grant execute on function public.travel_conversation_catchup(uuid, timestamptz, text, int)
  to authenticated;
