import { createClient } from "npm:@supabase/supabase-js@2";

type InvitePayload = {
  action?: "invite" | "list" | "revoke" | "accept";
  organization_id?: string;
  email?: string;
  role_id?: string;
  store_ids?: string[];
  invitation_id?: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return Response.json(data, { status, headers: corsHeaders });
}

function createAdminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const secretKeysRaw = Deno.env.get("SUPABASE_SECRET_KEYS");
  const legacyServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url) throw new Error("SUPABASE_URL is not configured");

  let secretKey = legacyServiceRoleKey || "";
  if (secretKeysRaw) {
    try {
      const keys = JSON.parse(secretKeysRaw);
      secretKey = keys?.default || Object.values(keys || {})[0] || secretKey;
    } catch {
      throw new Error("SUPABASE_SECRET_KEYS is invalid");
    }
  }
  if (!secretKey) throw new Error("Supabase server secret is not configured");

  return createClient(url, secretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function authenticateRequest(req: Request) {
  const authorization = req.headers.get("Authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) throw new Error("Authentication required");

  const token = match[1];
  const admin = createAdminClient();
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) throw new Error("Invalid authentication token");

  return { admin, user: data.user };
}

async function requireOrgPermission(admin: any, userId: string, organizationId: string) {
  const { data, error } = await admin
    .from("organization_members")
    .select("id,role_id,status,roles!inner(code)")
    .eq("organization_id", organizationId)
    .eq("user_id", userId)
    .eq("status", "active")
    .maybeSingle();

  if (error) throw error;
  if (!data) throw new Error("Organization access denied");

  const { data: permission, error: permissionError } = await admin
    .from("role_permissions")
    .select("permissions!inner(code)")
    .eq("role_id", data.role_id)
    .eq("permissions.code", "members.manage")
    .maybeSingle();

  if (permissionError) throw permissionError;
  if (!permission) throw new Error("Permission denied: members.manage");

  return { memberId: data.id, roleCode: data.roles?.code || null };
}

async function validateRoleAndStores(admin: any, organizationId: string, actorRoleCode: string, roleId: string, storeIds: string[]) {
  const { data: role, error: roleError } = await admin
    .from("roles")
    .select("id,organization_id,code,name")
    .eq("id", roleId)
    .maybeSingle();

  if (roleError) throw roleError;
  if (!role || role.organization_id !== organizationId) throw new Error("Role does not belong to this organization");
  if (role.code === "owner" && actorRoleCode !== "owner") throw new Error("Only the Owner can assign the Owner role");

  const ids = [...new Set((storeIds || []).map(String).filter(Boolean))];
  if (ids.length) {
    const { data: stores, error: storesError } = await admin
      .from("stores")
      .select("id,organization_id")
      .in("id", ids);

    if (storesError) throw storesError;
    if ((stores || []).length !== ids.length || (stores || []).some((s: any) => s.organization_id !== organizationId)) {
      throw new Error("One or more stores do not belong to this organization");
    }
  }

  return { role, storeIds: ids };
}

async function findAuthUserByEmail(admin: any, email: string) {
  for (let page = 1; page <= 10; page++) {
    const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const users = data?.users || [];
    const found = users.find((u: any) => String(u.email || "").toLowerCase() === email);
    if (found) return found;
    if (users.length < 1000) break;
  }
  return null;
}

async function handleInvite(admin: any, userId: string, body: InvitePayload) {
  const organizationId = String(body.organization_id || "");
  const email = String(body.email || "").trim().toLowerCase();
  const roleId = String(body.role_id || "");
  const storeIds = Array.isArray(body.store_ids) ? body.store_ids : [];

  if (!organizationId || !email || !roleId) throw new Error("organization_id, email and role_id are required");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error("Invalid email address");

  const actor = await requireOrgPermission(admin, userId, organizationId);
  const { role, storeIds: validStoreIds } = await validateRoleAndStores(admin, organizationId, actor.roleCode, roleId, storeIds);

  const { data: pending, error: pendingError } = await admin
    .from("organization_invitations")
    .select("id")
    .eq("organization_id", organizationId)
    .eq("email", email)
    .eq("status", "pending")
    .maybeSingle();

  if (pendingError) throw pendingError;
  if (pending) throw new Error("A pending invitation already exists for this email");

  const existingUser = await findAuthUserByEmail(admin, email);
  let authUserId = existingUser?.id || null;
  let membershipStatus: "active" | "invited" = "invited";
  let inviteSent = false;

  if (existingUser) {
    const { data: existingMember, error: existingMemberError } = await admin
      .from("organization_members")
      .select("id,status")
      .eq("organization_id", organizationId)
      .eq("user_id", existingUser.id)
      .maybeSingle();

    if (existingMemberError) throw existingMemberError;
    if (existingMember) throw new Error("This user is already a member of the organization");

    if (existingUser.email_confirmed_at) {
      membershipStatus = "active";
    } else {
      const { error: resendError } = await admin.auth.resend({
        type: "signup",
        email,
      });
      if (resendError) throw new Error("User exists but the invitation could not be resent: " + resendError.message);
      inviteSent = true;
    }
  } else {
    const { data: inviteData, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email);
    if (inviteError) throw inviteError;
    authUserId = inviteData.user?.id || null;
    if (!authUserId) throw new Error("Auth invitation did not return a user id");
    inviteSent = true;
  }

  if (!authUserId) throw new Error("Unable to resolve invited user");

  const { data: member, error: memberError } = await admin
    .from("organization_members")
    .insert({
      organization_id: organizationId,
      user_id: authUserId,
      role_id: role.id,
      status: membershipStatus,
    })
    .select("id")
    .single();

  if (memberError) throw memberError;

  if (validStoreIds.length) {
    const rows = validStoreIds.map(storeId => ({ member_id: member.id, store_id: storeId }));
    const { error: storesError } = await admin.from("member_stores").insert(rows);
    if (storesError) {
      await admin.from("organization_members").delete().eq("id", member.id);
      throw storesError;
    }
  }

  const invitationStatus = membershipStatus === "active" ? "accepted" : "pending";
  const { data: invitation, error: invitationError } = await admin
    .from("organization_invitations")
    .insert({
      organization_id: organizationId,
      email,
      invited_by: userId,
      role_id: role.id,
      store_ids: validStoreIds,
      auth_user_id: authUserId,
      status: invitationStatus,
      accepted_at: membershipStatus === "active" ? new Date().toISOString() : null,
    })
    .select("id,status,expires_at")
    .single();

  if (invitationError) {
    await admin.from("member_stores").delete().eq("member_id", member.id);
    await admin.from("organization_members").delete().eq("id", member.id);
    throw invitationError;
  }

  return {
    ok: true,
    invitation,
    membership_id: member.id,
    status: membershipStatus,
    invite_sent: inviteSent,
  };
}

async function handleList(admin: any, userId: string, body: InvitePayload) {
  const organizationId = String(body.organization_id || "");
  if (!organizationId) throw new Error("organization_id is required");
  await requireOrgPermission(admin, userId, organizationId);

  const { data, error } = await admin
    .from("organization_invitations")
    .select("id,email,status,expires_at,created_at,accepted_at,role_id,auth_user_id,roles(name,code),store_ids")
    .eq("organization_id", organizationId)
    .order("created_at", { ascending: false });

  if (error) throw error;
  return { invitations: data || [] };
}

async function handleRevoke(admin: any, userId: string, body: InvitePayload) {
  const invitationId = String(body.invitation_id || "");
  if (!invitationId) throw new Error("invitation_id is required");

  const { data: invitation, error: invitationError } = await admin
    .from("organization_invitations")
    .select("id,organization_id,auth_user_id,status")
    .eq("id", invitationId)
    .maybeSingle();

  if (invitationError) throw invitationError;
  if (!invitation) throw new Error("Invitation not found");

  await requireOrgPermission(admin, userId, invitation.organization_id);
  if (invitation.status !== "pending") throw new Error("Only pending invitations can be revoked");

  const { error: updateError } = await admin
    .from("organization_invitations")
    .update({ status: "revoked", updated_at: new Date().toISOString() })
    .eq("id", invitationId);

  if (updateError) throw updateError;

  if (invitation.auth_user_id) {
    const { data: member } = await admin
      .from("organization_members")
      .select("id,status")
      .eq("organization_id", invitation.organization_id)
      .eq("user_id", invitation.auth_user_id)
      .maybeSingle();

    if (member?.status === "invited") {
      await admin.from("organization_members").update({ status: "suspended" }).eq("id", member.id);
    }
  }

  return { ok: true };
}

async function handleAccept(admin: any, userId: string, body: InvitePayload) {
  const organizationId = body.organization_id ? String(body.organization_id) : null;

  let query = admin
    .from("organization_invitations")
    .select("id,organization_id,auth_user_id,status,expires_at")
    .eq("auth_user_id", userId)
    .eq("status", "pending")
    .order("created_at", { ascending: false });

  if (organizationId) query = query.eq("organization_id", organizationId);

  const { data: invitations, error: invitationError } = await query;
  if (invitationError) throw invitationError;
  if (!invitations?.length) return { ok: true, accepted: [] };

  const accepted = [];

  for (const invitation of invitations) {
    if (new Date(invitation.expires_at).getTime() < Date.now()) {
      await admin
        .from("organization_invitations")
        .update({ status: "expired", updated_at: new Date().toISOString() })
        .eq("id", invitation.id);
      continue;
    }

    const { data: member, error: memberError } = await admin
      .from("organization_members")
      .select("id,status")
      .eq("organization_id", invitation.organization_id)
      .eq("user_id", userId)
      .maybeSingle();

    if (memberError) throw memberError;
    if (!member) continue;

    const { error: memberUpdateError } = await admin
      .from("organization_members")
      .update({ status: "active" })
      .eq("id", member.id);

    if (memberUpdateError) throw memberUpdateError;

    const { error: invitationUpdateError } = await admin
      .from("organization_invitations")
      .update({
        status: "accepted",
        accepted_at: new Date().toISOString(),
        updated_at: new Date().toISOString()
      })
      .eq("id", invitation.id);

    if (invitationUpdateError) throw invitationUpdateError;

    accepted.push({
      invitation_id: invitation.id,
      membership_id: member.id,
      organization_id: invitation.organization_id
    });
  }

  return { ok: true, accepted };
}
export default {
  fetch: async (req: Request) => {
    if (req.method === "OPTIONS") {
      return new Response("ok", { status: 200, headers: corsHeaders });
    }

    try {
      if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

      const { admin, user } = await authenticateRequest(req);
      const body = (await req.json()) as InvitePayload;
      const action = body.action || "list";
      const userId = user.id;

      if (action === "invite") return json(await handleInvite(admin, userId, body));
      if (action === "list") return json(await handleList(admin, userId, body));
      if (action === "revoke") return json(await handleRevoke(admin, userId, body));
      if (action === "accept") return json(await handleAccept(admin, userId, body));

      return json({ error: "Unsupported action" }, 400);
    } catch (error) {
      console.error("organization-member-invitations error", error);
      const message = error instanceof Error ? error.message : "Unexpected error";
      const status = message === "Authentication required" || message === "Invalid authentication token" ? 401 : 400;
      return json({ error: message }, status);
    }
  },
};
