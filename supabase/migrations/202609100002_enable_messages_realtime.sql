-- FIX PHASE 2.1 — ENABLE CHAT REALTIME
--
-- Adds public.messages to the supabase_realtime publication so that
-- INSERT events are broadcast to subscribed clients (the already-scoped
-- chatStreamProvider .eq() streams added in Phase 2 subscribe to this via
-- Realtime "postgres_changes"). No schema, RLS, or grant change: security
-- continues to be enforced entirely by the existing messages_friend_read
-- RLS SELECT policy, which Realtime evaluates per-subscriber using their
-- own JWT/auth.uid() — the same trusted pattern already in production use
-- for public.notifications.
--
-- Idempotent: only adds the table if it is not already a publication
-- member, so this migration is safe to re-run.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;
