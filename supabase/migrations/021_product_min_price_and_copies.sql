-- Prix minimum (seuil), duplication de produits et prix personnalisé TOK'COS.
-- 1) `products.min_price` : seuil plancher défini par le propriétaire ; un prix
--    personnalisé saisi à la commande ne peut jamais descendre en dessous
--    (plancher absolu de 50 FCFA appliqué par l'application ET validé ici).
-- 2) `products.copie_de` : trace l'origine d'une copie ; le gérant peut modifier
--    les copies créées par duplication sans toucher aux produits d'origine.
-- 3) RPC `duplicate_product` : copie le produit côté serveur (security definer,
--    rôles manager/owner/gerant) et crée une ligne de stock à 0 par point de vente.
-- 4) `submit_online_order` et `record_pos_sale` acceptent un `unit_price`
--    optionnel par ligne, validé contre le plancher (50 FCFA) et le seuil produit.
-- À exécuter dans Supabase SQL Editor après la migration 020.

alter table public.products add column if not exists min_price integer;
alter table public.products add column if not exists copie_de uuid references public.products(id) on delete set null;
create index if not exists products_copie_de_idx on public.products(copie_de);

-- 3) Duplication serveur : la copie reprend tous les détails (prix, seuil,
--    format, photo...) ; le stock de la copie démarre à 0 sur chaque point.
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
     format_group, format, format_order, active, copie_de)
  values
    (v_src.store_id, v_src.cat, coalesce(v_src.name, 'Produit') || ' (copie)', v_src.price, null,
     v_src.description, v_src.icon, v_src.image_url,
     null, null, 0, v_src.active,
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

-- 4a) Commande en ligne : `unit_price` optionnel par ligne (prix personnalisé),
--     validé contre le plancher 50 FCFA et le seuil `min_price` du produit.
create or replace function public.submit_online_order(
  p_store_id uuid,
  p_point_id uuid,
  p_client_name text,
  p_client_phone text,
  p_delivery_mode text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item record;
  v_stock integer;
  v_reserved integer;
  v_price numeric;
  v_unit_price numeric;
  v_min_price integer;
  v_floor numeric;
  v_product_name text;
  v_sale_id uuid;
  v_total numeric := 0;
  v_line_total numeric;
begin
  if not exists (select 1 from public.stores where id = p_store_id and active = true)
     or not exists (select 1 from public.points_de_vente where id = p_point_id and store_id = p_store_id and active = true) then
    raise exception 'Store or point of sale is unavailable';
  end if;
  if coalesce(trim(p_client_name), '') = '' or coalesce(trim(p_client_phone), '') = '' then
    raise exception 'Client name and phone are required';
  end if;
  if coalesce(p_delivery_mode, '') not in ('Livraison boutique', 'Retrait au point') then
    raise exception 'Invalid delivery mode';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Order must contain at least one item';
  end if;
  perform public.assert_tokcos_register_open(p_store_id);

  -- 1) Contrôle du stock, agrégé PAR PRODUIT (comme la migration 017) : la quantité
  --    totale demandée pour un produit ne peut dépasser le stock disponible, quel que
  --    soit le nombre de lignes (ou de prix personnalisés) le concernant.
  for v_item in
    select (value->>'product_id')::uuid as product_id,
           sum((value->>'qty')::integer)::integer as qty
      from jsonb_array_elements(p_items)
     group by (value->>'product_id')::uuid
     order by (value->>'product_id')::uuid
  loop
    if v_item.qty is null or v_item.qty <= 0 then raise exception 'Order quantities must be positive'; end if;
    select quantity into v_stock from public.stock
     where store_id = p_store_id and point_id = p_point_id and product_id = v_item.product_id
     for update;
    if not found then raise exception 'Product is out of stock'; end if;
    select coalesce(sum(si.qty), 0)::integer into v_reserved
      from public.sales s join public.sale_items si on si.sale_id = s.id
     where s.store_id = p_store_id and s.point_id = p_point_id
       and s.channel = 'en_ligne' and s.status = 'vendu' and s.fulfilled = false
       and si.product_id = v_item.product_id;
    if v_stock - v_reserved < v_item.qty then raise exception 'Insufficient available stock'; end if;
    select name into v_product_name
      from public.products where id = v_item.product_id and store_id = p_store_id and active = true;
    if not found then raise exception 'Product is unavailable'; end if;
  end loop;

  -- 2) Prix personnalisé par ligne : plancher absolu 50 FCFA, relevé par le seuil
  --    `min_price` du produit ; cumul du total de la commande.
  for v_item in select value from jsonb_array_elements(p_items)
  loop
    select name, price, min_price into v_product_name, v_price, v_min_price
      from public.products
     where id = (v_item.value->>'product_id')::uuid and store_id = p_store_id and active = true;
    if not found then raise exception 'Product is unavailable'; end if;
    v_floor := greatest(50, coalesce(v_min_price, 0));
    v_unit_price := coalesce(nullif(v_item.value->>'unit_price', '')::numeric, v_price);
    if v_unit_price is null or v_unit_price < v_floor then
      raise exception 'Unit price below the allowed minimum for %', v_product_name;
    end if;
    v_total := v_total + v_unit_price * (v_item.value->>'qty')::integer;
  end loop;


  insert into public.sales (
    point_id, client_name, client_phone, delivery_mode, payment_method,
    total, status, channel, fulfilled, store_id
  ) values (
    p_point_id, trim(p_client_name), trim(p_client_phone), coalesce(nullif(trim(p_delivery_mode), ''), 'Sur place'),
    'À régler', v_total, 'vendu', 'en_ligne', false, p_store_id
  ) returning id into v_sale_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    select name, price, min_price into v_product_name, v_price, v_min_price
      from public.products
     where id = (v_item.value->>'product_id')::uuid and store_id = p_store_id and active = true;
    v_floor := greatest(50, coalesce(v_min_price, 0));
    v_unit_price := coalesce(nullif(v_item.value->>'unit_price', '')::numeric, v_price);
    if v_unit_price is null or v_unit_price < v_floor then
      raise exception 'Unit price below the allowed minimum for %', v_product_name;
    end if;
    v_line_total := v_unit_price * (v_item.value->>'qty')::integer;
    insert into public.sale_items (sale_id, product_id, product_name, qty, price, subtotal)
    values (v_sale_id, (v_item.value->>'product_id')::uuid, v_product_name, (v_item.value->>'qty')::integer, v_unit_price, v_line_total);
  end loop;
  return v_sale_id;
end;
$$;


-- 4b) Vente comptoir : idem pour un prix personnalisé éventuel saisi en caisse.
create or replace function public.record_pos_sale(
  p_point_id uuid,
  p_client_name text,
  p_payment_method text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
  v_item jsonb;
  v_product_id uuid;
  v_qty integer;
  v_product_name text;
  v_price numeric;
  v_unit_price numeric;
  v_min_price integer;
  v_floor numeric;
  v_stock_id uuid;
  v_stock_qty integer;
  v_sale_id uuid;
  v_total numeric := 0;
begin
  v_store_id := public.authorize_tokcos_point(p_point_id);

  if coalesce(trim(p_client_name), '') = '' then
    raise exception 'Client name is required';
  end if;
  if p_payment_method not in ('Espèces', 'Wave', 'Orange Money') then
    raise exception 'Invalid payment method';
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Sale must contain at least one item';
  end if;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'qty')::integer;
    if v_qty is null or v_qty <= 0 then
      raise exception 'Sale quantity must be positive';
    end if;

    select name, price, min_price
      into v_product_name, v_price, v_min_price
      from public.products
     where id = v_product_id and store_id = v_store_id and active = true;
    if not found then
      raise exception 'Product is unavailable';
    end if;

    -- Prix personnalisé : plancher absolu 50 FCFA, relevé par le seuil du produit.
    v_floor := greatest(50, coalesce(v_min_price, 0));
    v_unit_price := coalesce(nullif(v_item->>'unit_price', '')::numeric, v_price);
    if v_unit_price is null or v_unit_price < v_floor then
      raise exception 'Unit price below the allowed minimum for %', v_product_name;
    end if;

    select id, quantity
      into v_stock_id, v_stock_qty
      from public.stock
     where point_id = p_point_id and product_id = v_product_id and store_id = v_store_id
     for update;
    if not found or v_stock_qty < v_qty then
      raise exception 'Insufficient stock for %', v_product_name;
    end if;

    update public.stock
       set quantity = quantity - v_qty
     where id = v_stock_id;

    v_total := v_total + (v_unit_price * v_qty);
  end loop;

  insert into public.sales (
    point_id, client_name, client_phone, delivery_mode, payment_method,
    total, status, channel, fulfilled, store_id
  ) values (
    p_point_id, trim(p_client_name), 'Comptoir', 'Sur place', p_payment_method,
    v_total, 'vendu', 'caisse', true, v_store_id
  ) returning id into v_sale_id;

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'qty')::integer;
    select name, price, min_price into v_product_name, v_price, v_min_price
      from public.products where id = v_product_id and store_id = v_store_id;
    v_floor := greatest(50, coalesce(v_min_price, 0));
    v_unit_price := coalesce(nullif(v_item->>'unit_price', '')::numeric, v_price);
    if v_unit_price is null or v_unit_price < v_floor then
      raise exception 'Unit price below the allowed minimum for %', v_product_name;
    end if;
    insert into public.sale_items (sale_id, product_id, product_name, qty, price, subtotal)
    values (v_sale_id, v_product_id, v_product_name, v_qty, v_unit_price, v_unit_price * v_qty);
  end loop;

  return v_sale_id;
end;
$$;
