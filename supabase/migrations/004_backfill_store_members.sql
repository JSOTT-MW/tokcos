-- Attach existing profiles to their store for the permissions screen.
update public.profiles pr
set organization_id = st.organization_id
from public.stores st
join public.points_de_vente pt on pt.store_id = st.id
where pr.point_id = pt.id and pr.organization_id is null;

insert into public.store_members (store_id, user_id, role)
select pt.store_id, pr.id,
  case when pr.role = 'manager' then 'owner' else 'cashier' end
from public.profiles pr
join public.points_de_vente pt on pt.id = pr.point_id
where pr.point_id is not null
on conflict (store_id, user_id) do nothing;
