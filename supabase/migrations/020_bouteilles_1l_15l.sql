-- 020_bouteilles_1l_15l.sql
-- Section « Bouteilles — Jus & Wass » : 6 marques × 2 formats (1 litre et 1,5 litre).
--   Wonder Wass, Soft Wass, Dax'ar, Bissap'Paral, Tarkinda, Anaconda.
-- Idempotent : n'insère que les articles manquants (vérifie format_group + format),
-- puis crée une ligne de stock à 0 pour chaque point de vente (quantités à saisir
-- ensuite dans l'onglet Inventaire de l'espace de gestion).
-- Prix par défaut : 1L = 1500 FCFA, 1,5L = 2000 FCFA (modifiables dans Produits).
-- À exécuter dans Supabase SQL Editor après la migration 019.

-- Colonnes de format (rappel idempotent, créées par la migration 018).
alter table public.products add column if not exists format_group text;
alter table public.products add column if not exists format text;
alter table public.products add column if not exists format_order integer not null default 0;

-- 0) Assouplir la contrainte de catégorie du schéma initial : elle refusait
--    'bouteille' (erreur 23514 products_cat_check) et aurait aussi bloqué les
--    sections personnalisées créées depuis l'espace de gestion.
--    Les sections valides sont celles de stores.menu_sections (gérées par l'app).
do $$
declare
  v_def text;
begin
  select pg_get_constraintdef(oid) into v_def
    from pg_constraint
   where conrelid = 'public.products'::regclass
     and conname = 'products_cat_check';
  if v_def is not null then
    raise notice 'Ancienne contrainte products_cat_check : %', v_def;
    execute 'alter table public.products drop constraint products_cat_check';
  end if;
end $$;

alter table public.products
  add constraint products_cat_check
  check (cat is not null and char_length(trim(cat)) between 1 and 60);

-- 1) Les 12 articles bouteille.
with target_store as (
  select id from public.stores where active = true order by created_at limit 1
), brands(brand, boisson, description) as (
  values
    ('Wonder Wass', 'Wonder Wass (bouye)', 'Wonder Wass (bouye), boisson à base de fruit du baobab.'),
    ('Soft Wass', 'Soft Wass (thé jasmin)', 'Soft Wass, wass rafraîchissant à base de jasmin.'),
    ('Dax''ar', 'Dax''ar', 'Dax''ar, boisson TOK''COS en bouteille.'),
    ('Bissap''Paral', 'Bissap''Paral', 'Bissap''Paral, jus d''hibiscus.'),
    ('Tarkinda', 'Tarkinda (gingembre)', 'Tarkinda, boisson au gingembre.'),
    ('Anaconda', 'Anaconda', 'Anaconda, boisson TOK''COS en bouteille.')
), formats(format, format_order, price, capacity) as (
  values
    ('Bouteille 1L', 3, 1500, '1 litre'),
    ('Bouteille 1,5L', 4, 2000, '1,5 litre')
)
insert into public.products (store_id, cat, name, price, description, icon, active, format_group, format, format_order)
select ts.id,
       'bouteille',
       b.brand || ' — ' || f.format,
       f.price,
       b.description || ' Format ' || f.capacity || '.',
       '🍾',
       true,
       b.brand,
       f.format,
       f.format_order
from target_store ts
cross join brands b
cross join formats f
where not exists (
  select 1
  from public.products p
  where p.store_id = ts.id
    and p.cat = 'bouteille'
    and p.format_group = b.brand
    and p.format = f.format
);

-- 2) Une ligne de stock (quantité 0) par produit bouteille et par point de vente.
insert into public.stock (store_id, point_id, product_id, quantity)
select p.store_id, pd.id, p.id, 0
from public.products p
join public.points_de_vente pd on pd.store_id = p.store_id
where p.cat = 'bouteille'
  and not exists (
    select 1 from public.stock s
    where s.product_id = p.id and s.point_id = pd.id
  );