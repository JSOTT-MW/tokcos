# Architecture SaaS TOK'COS

## Modèle multi-boutiques

- `organizations` : organisation propriétaire d'une ou plusieurs boutiques.
- `stores` : boutique publiée, avec identité, logo, coordonnées, devise et fuseau horaire.
- `store_members` : utilisateurs autorisés dans une boutique et leur rôle (`owner`, `admin`, `manager`, `cashier`, `viewer`).
- `profiles` : profil Supabase Auth conservé pour compatibilité avec l'application actuelle.
- `products`, `points_de_vente`, `stock`, `sales`, `messages` et `caisse_cloture` : données opérationnelles rattachées à `store_id`.
- `sale_items` : lignes d'une vente, isolées indirectement par la vente parente.

## Sécurité

La migration `supabase/migrations/001_multi_tenant_saas.sql` active RLS et fournit `my_store_ids()`. Une requête ne peut lire ou modifier que les données des boutiques dont l'utilisateur est membre. Le frontend ne doit jamais faire confiance à un `store_id` envoyé par le navigateur : Supabase RLS reste la frontière de sécurité.

## Onboarding

Après inscription, appeler la fonction RPC :

```js
const { data: storeId, error } = await sb.rpc('create_store_for_current_user', {
  store_name: 'Ma boutique',
  store_slug: 'ma-boutique'
});
```

La fonction crée l'organisation, la boutique et le membre propriétaire. Elle est réservée aux utilisateurs authentifiés.

## Déploiement de la migration

1. Ouvrir Supabase > SQL Editor.
2. La migration `001_multi_tenant_saas.sql` doit déjà être exécutée.
3. Exécuter ensuite `002_public_storefront_access.sql` une seule fois.
4. Vérifier les tables, index et policies RLS.
5. Le frontend charge la boutique active et inclut son `store_id` dans les opérations métier.

Cette étape prépare le SaaS sans changer immédiatement les requêtes actuelles du site vitrine. La migration rattache les données existantes à la première boutique TOK'COS.
