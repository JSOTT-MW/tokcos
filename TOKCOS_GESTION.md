# TOK'COS — espace de gestion

TOK'COS est une seule entreprise avec plusieurs points de vente. Les points de vente sont les lieux d'activité; ils ne sont pas des boutiques ou des comptes SaaS distincts.

## Rôles

- **Propriétaire** (`profiles.role = 'manager'`) : suit l'activité de tous les points de vente et choisit le point concerné pour la caisse et l'inventaire. La comptabilité permet de consulter tous les points ou un point précis.
- **Gérant** : son compte est associé à un `point_id`. Il utilise la caisse et consulte les ventes, l'inventaire et la comptabilité de ce point.
- Le propriétaire peut inviter les gérants par e-mail depuis **Profil → Gérants** et leur attribuer un point de vente. L'application ne permet pas l'inscription libre ni la création de boutiques.
- **Profil** permet au propriétaire de modifier son nom, sa photo, le slogan et les couleurs de la boutique, le mode sombre, ainsi que de gérer les points de vente et les gérants.
- Dans **Profil → Boutique**, le logo et la bannière se chargent depuis l'appareil; les coordonnées de boutique alimentent le pied de page. Les horaires se règlent par jour et heure. La commande client est transmise directement à Supabase et apparaît dans la caisse du point choisi; elle n'ouvre pas WhatsApp.

## Données

`stores` reste le conteneur technique unique de l'espace TOK'COS, notamment pour préserver les clés étrangères et les règles RLS déjà en place. Les ventes, produits, stocks, points de vente, transactions et clôtures conservent leur `store_id`; les opérations propres à un lieu sont en plus rattachées à `point_id`.

`store_members` relie les comptes autorisés à cet espace. Les règles RLS de Supabase restent la frontière de sécurité : le navigateur ne constitue pas un contrôle d'accès.

## Déploiement

Exécuter les migrations numérotées dans l'ordre dans Supabase SQL Editor. La migration `010_single_tokcos_workspace.sql` désactive la création de boutiques et les insertions de nouvelles lignes `stores` par les comptes authentifiés. La migration `011_pos_inventory_workflows.sql` active l'enregistrement atomique des ventes avec décrément du stock, des inventaires et des livraisons d'approvisionnement. La migration `012_online_orders_and_global_register.sql` ajoute le cycle des commandes en ligne et la clôture globale automatique de caisse. La migration `013_point_scoped_accounting_permissions.sql` applique les droits comptables limités au point de vente des gérants. La migration `014_owner_profile_and_avatars.sql` ajoute les préférences du profil et le stockage des photos. La migration `015_store_branding_assets.sql` crée le stockage des logos et bannières de boutique.

Déployer la fonction de gestion des gérants avec `supabase functions deploy manage-managers`. Configurer `APP_URL` avec l'URL publique de l'application (`supabase secrets set APP_URL=https://votre-domaine/`) et l'autoriser dans les URL de redirection Supabase Auth. La fonction utilise `SUPABASE_SERVICE_ROLE_KEY` uniquement côté serveur et valide la session ainsi que les droits du propriétaire avant chaque invitation ou suppression de compte. Ne jamais placer cette clé dans le client.

Les éventuelles anciennes boutiques créées avant ce changement ne sont pas fusionnées automatiquement. Vérifier les données avant toute opération de consolidation; les points de vente TOK'COS restent gérés dans `points_de_vente`.

Dans l'application, les changements manuels de quantité restent en brouillon jusqu'au bouton **Enregistrer l'inventaire** du point sélectionné. Une vente confirmée en caisse et une livraison d'approvisionnement validée mettent à jour le stock automatiquement pour leur point de vente.

## Caisse et commandes en ligne

Une commande en ligne est créée pour le point de vente choisi, sans réduire immédiatement le stock physique. Elle réserve toutefois les quantités disponibles. Un membre autorisé du point la prend en charge dans la caisse; le stock est vérifié et décrémenté au règlement, sur la vente d'origine, sans créer de vente en double. Une commande importée peut être libérée avant son encaissement.

Les demandes d'approvisionnement encore en attente peuvent être modifiées ou supprimées par le propriétaire. Une livraison validée ajoute automatiquement les quantités à l'inventaire du point concerné.

## Journée comptable

La clôture est globale à l'espace TOK'COS, et non à un point unique. La journée d'exploitation va de 07:00 à 04:00 (Africa/Dakar); elle se rouvre automatiquement à 07:00. Les ventes et les mouvements comptables sont bloqués pendant la fermeture. Le propriétaire peut réouvrir la caisse avant le prochain début de journée.

Les migrations `010` à `014` ont été exécutées dans l'environnement de déploiement actuel. Exécuter `015_store_branding_assets.sql` dans Supabase SQL Editor pour activer l'import des images de boutique, puis déployer la fonction `manage-managers`.
