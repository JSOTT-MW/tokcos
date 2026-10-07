import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
  const isUuid = (value: string) =>
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
  if (action !== "invite" && action !== "remove") {
    return respond({ error: "Action non prise en charge." }, 400);
  }
  if (action === "invite" && (
    !displayName || displayName.length > 80 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254 ||
    phone.length > 40 || !isUuid(pointId)
  )) {
    return respond({ error: "Vérifiez le nom, l’e-mail, le téléphone et le point de vente." }, 400);
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
    .in("id", memberships.map((membership) => membership.store_id));
  if (storesError) {
    console.error("Impossible de vérifier la boutique du propriétaire.", storesError);
    return respond({ error: "Impossible de vérifier la boutique du propriétaire." }, 500);
  }
  const storeId = ownedStores?.[0]?.id;
  if (!storeId) return respond({ error: "Aucune boutique autorisée pour ce compte." }, 403);

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
    .select("id, store_id, active")
    .eq("id", pointId)
    .eq("store_id", storeId)
    .single();
  if (pointError || !point || !point.active) {
    return respond({ error: "Le point de vente sélectionné est introuvable ou inactif." }, 400);
  }

  const appUrl = Deno.env.get("APP_URL");
  const { data: inviteData, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(
    email,
    {
      data: { display_name: displayName },
      ...(appUrl ? { redirectTo: appUrl } : {}),
    },
  );
  if (inviteError || !inviteData.user) {
    console.error("Invitation Supabase Auth échouée.", inviteError);
    return respond({ error: inviteError?.message || "L’invitation n’a pas pu être envoyée." }, 400);
  }

  const invitedUser = inviteData.user;
  const { error: profileError } = await adminClient.from("profiles").insert({
    id: invitedUser.id,
    email,
    display_name: displayName,
    phone: phone || null,
    role: "gerant",
    point_id: point.id,
    organization_id: owner.organization_id,
  });
  if (profileError) {
    console.error("Création du profil gérant échouée.", profileError);
    await adminClient.auth.admin.deleteUser(invitedUser.id);
    return respond({ error: "Le compte a été invité, mais son profil n’a pas pu être créé." }, 500);
  }

  const { error: storeMemberError } = await adminClient.from("store_members").upsert(
    { store_id: point.store_id, user_id: invitedUser.id, role: "cashier" },
    { onConflict: "store_id,user_id" },
  );
  if (storeMemberError) {
    console.error("Ajout du gérant à la boutique échoué.", storeMemberError);
    await adminClient.from("profiles").delete().eq("id", invitedUser.id);
    await adminClient.auth.admin.deleteUser(invitedUser.id);
    return respond({ error: "Le compte a été invité, mais son accès au point n’a pas pu être créé." }, 500);
  }

  return respond({ message: `Invitation envoyée à ${email}.` }, 201);
});
