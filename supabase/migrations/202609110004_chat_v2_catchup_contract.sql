-- CHAT V2 — PHASE A.2: CATCH-UP RESPONSE CONTRACT FIX
--
-- Confirmed live bug: travel_conversation_catchup's two source CTEs each
-- compute change_at correctly (messages.updated_at for normal/deleted
-- rows, message_user_state.hidden_at for hidden-for-me tombstones) and
-- use it correctly for ORDER BY / the keyset filter — but the function's
-- outer SELECT never returned change_at to the caller. A client had no
-- way to recover the true event time for a hidden_for_me row, since its
-- returned `updated_at` is the message's own last content-update time,
-- unrelated to when this account hid it. Using updated_at as the next
-- cursor for such a row (as the Phase A.1 handoff notes suggested) is
-- wrong in general and could skip or endlessly repeat hidden-tombstone
-- events.
--
-- Minimal fix: return change_at explicitly. Nothing else about the
-- query, its security, or its scoping changes.
--
-- Tie-uniqueness review (documented, not fixed with new complexity):
-- (change_at, id) is unique across different messages (id alone already
-- distinguishes them). The only theoretical collision is the SAME
-- message producing both a "changed" event and a "hidden" event at the
-- exact same microsecond change_at — this requires delete_message_for_
-- everyone and hide_message_for_me (two structurally separate RPCs, never
-- invoked together in one transaction by this design) to land on the
-- identical microsecond for the identical message. Not reachable by any
-- current code path, and not worth a 3-part client-facing cursor for an
-- unproven case. hidden_for_me is added as a free (no new parameter, no
-- cursor change) third ORDER BY key purely to make in-page ordering
-- fully deterministic even in that theoretical case; the cursor
-- comparison itself intentionally stays 2-part. Worst case if this ever
-- did occur: one tombstone stays stale in a local cache until the next
-- full travel_conversation_messages resync (which already correctly
-- excludes hidden/deleted rows) — a recoverable staleness, not silent
-- wrong data forever.
-- ---------------------------------------------------------------------------

drop function if exists public.travel_conversation_catchup(uuid, timestamptz, text, integer);

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
  hidden_for_me boolean,
  change_at timestamptz
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
  select id, sender_id, receiver_id, body, created_at, updated_at, deleted_at, hidden_for_me, change_at
  from (
    select * from changed_messages
    union all
    select * from hidden_tombstones
  ) merged
  order by change_at asc, id asc, hidden_for_me asc
  limit least(greatest(p_limit, 1), 500);
$$;

revoke execute on function public.travel_conversation_catchup(uuid, timestamptz, text, int)
  from public, anon;
grant execute on function public.travel_conversation_catchup(uuid, timestamptz, text, int)
  to authenticated;
