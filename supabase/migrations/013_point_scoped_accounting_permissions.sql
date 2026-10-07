-- Limit accounting entries to the assigned point for TOK'COS managers.

drop policy if exists transactions_store_access on public.transactions;
drop policy if exists transactions_member_read on public.transactions;
drop policy if exists transactions_member_insert on public.transactions;
drop policy if exists transactions_member_update on public.transactions;
drop policy if exists transactions_member_delete on public.transactions;

create policy transactions_member_read on public.transactions
  for select using (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid()
         and (
           p.role in ('manager', 'owner')
           or (p.role = 'gerant' and p.point_id = transactions.point_id)
         )
    )
  );

create policy transactions_member_insert on public.transactions
  for insert with check (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid()
         and (
           p.role in ('manager', 'owner')
           or (p.role = 'gerant' and p.point_id = transactions.point_id)
         )
    )
  );

create policy transactions_member_update on public.transactions
  for update using (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid()
         and (
           p.role in ('manager', 'owner')
           or (p.role = 'gerant' and p.point_id = transactions.point_id)
         )
    )
  )
  with check (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid()
         and (
           p.role in ('manager', 'owner')
           or (p.role = 'gerant' and p.point_id = transactions.point_id)
         )
    )
  );

create policy transactions_member_delete on public.transactions
  for delete using (
    store_id in (select public.my_store_ids())
    and exists (
      select 1 from public.profiles p
       where p.id = auth.uid()
         and (
           p.role in ('manager', 'owner')
           or (p.role = 'gerant' and p.point_id = transactions.point_id)
         )
    )
  );
