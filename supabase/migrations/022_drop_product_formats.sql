-- 022_drop_product_formats.sql
-- Abandon du concept de « format » sur les produits TOK'COS.
-- Le regroupement multi-formats (format_group / format / format_order) introduit
-- par la migration 018 provoquait un affichage incorrect des noms de produits
-- (titres de groupe, libellés de format à la place du vrai nom). On revient au
-- modèle simple : un produit = une fiche = un nom affiché tel quel.
-- Chaque nom explicite (ex. « Soft Wass — Gobelet (mini) ») est déjà porté par la
-- colonne products.name, donc aucune donnée n'est perdue.
--
-- ORDRE CRITIQUE :
--   1) Recréer la RPC duplicate_product SANS les colonnes format (elles sont
--      listées explicitement dans son INSERT depuis la migration 021 ; sinon la
--      duplication planterait après le drop).
--   2) Dropper l'index products_format_group_idx.
--   3) Dropper les trois colonnes format_group / format / format_order.
-- À exécuter dans Supabase SQL Editor après la migration 021.

-- 1) Duplication serveur recréée sans les colonnes format.
create or replace function public.duplicate_product(p_product_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_src public.products%rowtype;
  v_new_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select role into v_role from public.profiles where id = auth.uid();
  if coalesce(v_role, '') not in ('manager', 'owner', 'gerant') then
    raise exception 'This account cannot duplicate products';
  end if;
  select * into v_src from public.products where id = p_product_id;
  if not found then raise exception 'Product not found'; end if;
  if not exists (select 1 from public.store_members where store_id = v_src.store_id and user_id = auth.uid()) then
    raise exception 'No access to this TOK''COS workspace';
  end if;
  insert into public.products
    (store_id, cat, name, price, min_price, description, icon, image_url,
     active, copie_de)
  values
    (v_src.store_id, v_src.cat, coalesce(v_src.name, 'Produit') || ' (copie)', v_src.price, null,
     v_src.description, v_src.icon, v_src.image_url,
     v_src.active,
     coalesce(v_src.copie_de, v_src.id))
  returning id into v_new_id;

  insert into public.stock (store_id, point_id, product_id, quantity)
  select v_src.store_id, pd.id, v_new_id, 0
    from public.points_de_vente pd
   where pd.store_id = v_src.store_id
     and not exists (
       select 1 from public.stock s
        where s.store_id = v_src.store_id and s.point_id = pd.id and s.product_id = v_new_id);
  return v_new_id;
end;
$$;

revoke all on function public.duplicate_product(uuid) from public, anon;
grant execute on function public.duplicate_product(uuid) to authenticated;

-- 2) Index dédié au regroupement par format_group (créé en 018).
drop index if exists public.products_format_group_idx;

-- 3) Suppression des trois colonnes de format.
alter table public.products drop column if exists format_group;
alter table public.products drop column if exists format;
alter table public.products drop column if exists format_order;
