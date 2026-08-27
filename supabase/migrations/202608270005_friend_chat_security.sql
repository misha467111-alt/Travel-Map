-- Friend-only private chat security.
-- Safe forward migration for an existing production database.

begin;

do $$
begin
  if to_regclass('public.messages') is not null then
    execute 'alter table public.messages enable row level security';

    execute 'grant select, insert on table public.messages to authenticated';
    execute 'revoke update, delete on table public.messages from authenticated';
    execute 'revoke all on table public.messages from anon';

    execute 'drop policy if exists messages_friend_read on public.messages';
    execute 'drop policy if exists messages_friend_insert on public.messages';
    execute 'drop policy if exists messages_select_own on public.messages';
    execute 'drop policy if exists messages_insert_own on public.messages';

    execute $policy$
      create policy messages_friend_read
      on public.messages
      for select
      to authenticated
      using (
        (sender_id = auth.uid() or receiver_id = auth.uid())
        and exists (
          select 1
          from public.friendships f
          where f.status = 'accepted'
            and (
              (f.user_id_1 = sender_id and f.user_id_2 = receiver_id)
              or
              (f.user_id_2 = sender_id and f.user_id_1 = receiver_id)
            )
        )
      )
    $policy$;

    execute $policy$
      create policy messages_friend_insert
      on public.messages
      for insert
      to authenticated
      with check (
        sender_id = auth.uid()
        and receiver_id <> auth.uid()
        and exists (
          select 1
          from public.friendships f
          where f.status = 'accepted'
            and (
              (f.user_id_1 = auth.uid() and f.user_id_2 = receiver_id)
              or
              (f.user_id_2 = auth.uid() and f.user_id_1 = receiver_id)
            )
        )
      )
    $policy$;
  end if;
end $$;

commit;
