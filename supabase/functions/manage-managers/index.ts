import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (request: Request) => Response | Promise<Response>): unknown;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respond(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return respond({ error: "Méthode non autorisée." }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error("Variables Supabase manquantes pour l’invitation des gérants.");
    return respond({ error: "Le service d’invitation n’est pas configuré." }, 500);
  }

  const authorization = request.headers.get("Authorization") || "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (!token) return respond({ error: "Authentification requise." }, 401);

  let body: {
    action?: unknown;
    display_name?: unknown;
    email?: unknown;
    phone?: unknown;
    point_id?: unknown;
    user_id?: unknown;
  };
  try {
    body = await request.json();
  } catch {
    return respond({ error: "Corps de requête invalide." }, 400);
  }

  const action = typeof body.action === "string" ? body.action : "invite";
  const displayName = typeof body.display_name === "string" ? body.display_name.trim() : "";
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const phone = typeof body.phone === "string" ? body.phone.trim() : "";
  const pointId = typeof body.point_id === "string" ? body.point_id : "";
  const userId = typeof body.user_id === "string" ? body.user_id : "";
  const managedPointId = typeof (body as { new_point_id?: unknown }).new_point_id === "string"
    ? (body as { new_point_id: string }).new_point_id
    : "";
  const slugify = (value: string) =>
    value.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, "-").replace(/(^-+|-+$)/g, "") || "point";
  const gerantEmailForSlug = (slug: string) => `gerant.${slug}@tokcos.sn`;
  /* Mot de passe auto : 6 caractères max, sans ambiguïté (pas de 0/O/1/l). */
  const randomGerantPassword = () => {
    const alphabet = "abcdefghjkmnpqrstuvwxyz23456789";
    const bytes = new Uint8Array(6);
    crypto.getRandomValues(bytes);
    return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join("");
  };
  const isUuid = (value: string) =>
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
  if (action !== "invite" && action !== "remove" && action !== "move") {
    return respond({ error: "Action non prise en charge." }, 400);
  }
  if (action === "invite" && (
    !displayName || displayName.length > 80 ||
    phone.length > 40 || !isUuid(pointId)
  )) {
    return respond({ error: "Vérifiez le nom, le téléphone et le point de vente." }, 400);
  }
  if (action === "move" && (!isUuid(userId) || !isUuid(managedPointId))) {
    return respond({ error: "Gérant ou point de destination invalide." }, 400);
  }
  if (action === "remove" && !isUuid(userId)) {
    return respond({ error: "Identifiant de gérant invalide." }, 400);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser(token);
  if (authError || !authData.user) return respond({ error: "Session invalide ou expirée." }, 401);

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: owner, error: ownerError } = await adminClient
    .from("profiles")
    .select("id, role, organization_id")
    .eq("id", authData.user.id)
    .single();
  if (
    ownerError || !owner ||
    !["manager", "owner"].includes(owner.role) ||
    !owner.organization_id
  ) {
    return respond({ error: "Seul le propriétaire peut inviter un gérant." }, 403);
  }

  const { data: memberships, error: membershipError } = await adminClient
    .from("store_members")
    .select("store_id")
    .eq("user_id", owner.id)
    .in("role", ["owner", "admin"]);
  if (membershipError) {
    console.error("Impossible de vérifier l’accès du propriétaire.", membershipError);
    return respond({ error: "Impossible de vérifier les droits du propriétaire." }, 500);
  }
  if (!memberships?.length) return respond({ error: "Aucune boutique autorisée pour ce compte." }, 403);
  const { data: ownedStores, error: storesError } = await adminClient
    .from("stores")
    .select("id")
    .eq("organization_id", owner.organization_id)
    .in("id", memberships.map((membership: { store_id: string }) => membership.store_id));
  if (storesError) {
    console.error("Impossible de vérifier la boutique du propriétaire.", storesError);
    return respond({ error: "Impossible de vérifier la boutique du propriétaire." }, 500);
  }
  const storeId = ownedStores?.[0]?.id;
  if (!storeId) return respond({ error: "Aucune boutique autorisée pour ce compte." }, 403);

  if (action === "move") {
    const { data: target, error: targetError } = await adminClient
      .from("profiles")
      .select("id, role, point_id, organization_id")
      .eq("id", userId)
      .eq("organization_id", owner.organization_id)
      .single();
    if (targetError || !target || ["manager", "owner"].includes(target.role)) {
      return respond({ error: "Ce compte gérant est introuvable." }, 404);
    }
    const { data: dest, error: destError } = await adminClient
      .from("points_de_vente")
      .select("id, store_id, active, name, slug")
      .eq("id", managedPointId)
      .eq("store_id", storeId)
      .single();
    if (destError || !dest || !dest.active) {
      return respond({ error: "Le point de destination est introuvable ou inactif." }, 400);
    }
    if (target.point_id !== dest.id) {
      const { data: taken } = await adminClient
        .from("profiles")
        .select("id")
        .eq("organization_id", owner.organization_id)
        .eq("point_id", dest.id)
        .neq("id", target.id)
        .neq("role", "manager")
        .neq("role", "owner")
        .limit(1);
      if (taken && taken.length) {
        return respond({ error: "Le point de destination a déjà un gérant." }, 409);
      }
    }
    const destSlug = dest.slug || slugify(dest.name || "point");
    const destEmail = gerantEmailForSlug(destSlug);
    const updates: Record<string, unknown> = { point_id: dest.id, email: destEmail };
    if (displayName) updates.display_name = displayName.slice(0, 80);
    if (phone !== undefined) updates.phone = phone || null;
    const { error: moveError } = await adminClient
      .from("profiles")
      .update(updates)
      .eq("id", target.id)
      .eq("organization_id", owner.organization_id);
    if (moveError) {
      console.error("Déplacement du gérant échoué.", moveError);
      return respond({ error: "Le gérant n’a pas pu être déplacé." }, 500);
    }
    const { error: authMailError } = await adminClient.auth.admin.updateUserById(target.id, { email: destEmail });
    if (authMailError) {
      console.error("Mise à jour de l’e-mail Auth échouée.", authMailError);
      return respond({ message: `Gérant déplacé, mais l’e-mail Auth doit être resynchronisé vers ${destEmail}.` });
    }
    return respond({ message: `Gérant déplacé vers ${destEmail}.` });
  }

  if (action === "remove") {
    const { data: target, error: targetError } = await adminClient
      .from("profiles")
      .select("id, role, organization_id")
      .eq("id", userId)
      .eq("organization_id", owner.organization_id)
      .single();
    if (targetError || !target || target.id === owner.id || ["manager", "owner"].includes(target.role)) {
      return respond({ error: "Ce compte gérant n’est pas autorisé à être supprimé." }, 404);
    }
    const { data: targetMembership, error: targetMembershipError } = await adminClient
      .from("store_members")
      .select("user_id")
      .eq("store_id", storeId)
      .eq("user_id", target.id)
      .maybeSingle();
    if (targetMembershipError) {
      console.error("Impossible de vérifier le point d’accès du gérant.", targetMembershipError);
      return respond({ error: "Impossible de vérifier le compte gérant." }, 500);
    }
    if (!targetMembership) return respond({ error: "Ce gérant n’appartient pas à cette boutique." }, 404);

    const { error: deleteError } = await adminClient.auth.admin.deleteUser(target.id);
    if (deleteError) {
      console.error("Suppression du compte Supabase Auth échouée.", deleteError);
      return respond({ error: "Le compte gérant n’a pas pu être supprimé." }, 500);
    }
    return respond({ message: "Compte gérant et accès supprimés." });
  }

  const { data: point, error: pointError } = await adminClient
    .from("points_de_vente")
    .select("id, store_id, active, name, slug")
    .eq("id", pointId)
    .eq("store_id", storeId)
    .single();
  if (pointError || !point || !point.active) {
    return respond({ error: "Le point de vente sélectionné est introuvable ou inactif." }, 400);
  }
  const pointSlug = point.slug || slugify(point.name || "point");
  const autoEmail = gerantEmailForSlug(pointSlug);
  const { data: taken } = await adminClient
    .from("profiles")
    .select("id")
    .eq("organization_id", owner.organization_id)
    .eq("point_id", point.id)
    .neq("role", "manager")
    .neq("role", "owner")
    .limit(1);
  if (taken && taken.length) {
    return respond({ error: "Ce point de vente a déjà un gérant (un seul gérant par point)." }, 409);
  }

  /* Compte actif immédiatement : aucune confirmation par e-mail.
     createUser (et non inviteUserByEmail) + email_confirm:true. */
  const initialPassword = randomGerantPassword();
  const { data: createdData, error: createError } = await adminClient.auth.admin.createUser({
    email: autoEmail,
    password: initialPassword,
    email_confirm: true,
    user_metadata: { display_name: displayName },
  });
  if (createError || !createdData.user) {
    console.error("Création du compte gérant échouée.", createError);
    return respond({ error: createError?.message || "Le compte gérant n’a pas pu être créé." }, 400);
  }

  const invitedUser = createdData.user;
  const { error: profileError } = await adminClient.from("profiles").insert({
    id: invitedUser.id,
    email: autoEmail,
    display_name: displayName,
    phone: phone || null,
    role: "gerant",
    point_id: point.id,
    organization_id: owner.organization_id,
  });
  if (profileError) {
    console.error("Création du profil gérant échouée.", profileError);
    await adminClient.auth.admin.deleteUser(invitedUser.id);
    return respond({ error: "Le compte a été créé, mais son profil n’a pas pu être enregistré." }, 500);
  }

  const { error: storeMemberError } = await adminClient.from("store_members").upsert(
    { store_id: point.store_id, user_id: invitedUser.id, role: "cashier" },
    { onConflict: "store_id,user_id" },
  );
  if (storeMemberError) {
    console.error("Ajout du gérant à la boutique échoué.", storeMemberError);
    await adminClient.from("profiles").delete().eq("id", invitedUser.id);
    await adminClient.auth.admin.deleteUser(invitedUser.id);
    return respond({ error: "Le compte a été créé, mais son accès au point n’a pas pu être enregistré." }, 500);
  }

  return respond({
    message: `Compte gérant actif : ${autoEmail}.`,
    email: autoEmail,
    initial_password: initialPassword,
  }, 201);
});
