-- Sections du menu TOK'COS (Café, Wass, Bouteilles...) entièrement gérables
-- par le propriétaire depuis l'espace de gestion : ajout, renommage,
-- réordonnancement, couleur et masquage.
-- Chaque section possède une "key" qui correspond au champ `cat` des produits.
-- Stockée en JSONB sur stores (déjà lue publiquement par la vitrine et
-- modifiable par le propriétaire via la policy stores_public_update).
-- À exécuter dans Supabase SQL Editor après la migration 018.

alter table public.stores add column if not exists menu_sections jsonb not null default '[]'::jsonb;

-- Jeu de sections par défaut (rétro-compatible avec les catégories existantes).
do $$
declare
  v_default jsonb := jsonb_build_array(
    jsonb_build_object('key','cafe','label','Café & Douceurs Chaudes','icon','☕','accent','#B9814A','accent2','#DDA53F','ord',1,'active',true),
    jsonb_build_object('key','wass','label','Wass, Jus & Saveurs Locales','icon','🍵','accent','#A6402A','accent2','#D98A73','ord',2,'active',true),
    jsonb_build_object('key','bouteille','label','Bouteilles — Jus & Wass','icon','🍾','accent','#2E7D32','accent2','#57A862','ord',3,'active',true)
  );
begin
  update public.stores
     set menu_sections = v_default
   where menu_sections is null
      or menu_sections = '[]'::jsonb
      or jsonb_array_length(menu_sections) = 0;
end $$;
