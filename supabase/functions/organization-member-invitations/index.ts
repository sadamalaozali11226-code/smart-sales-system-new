import { createClient } from "npm:@supabase/supabase-js@2";
import { getInviteMembershipAction, getAcceptanceAction, isInvitationExpired, getInvitationDisplayStatus } from "./invitation-state.mjs";

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

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
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
  if (ids.some(id => !isUuid(id))) throw new Error("One or more store ids are invalid");
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
  if (!isUuid(organizationId)) throw new Error("Invalid organization id");
  if (!isUuid(roleId)) throw new Error("Invalid role id");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error("Invalid email address");

  const actor = await requireOrgPermission(admin, userId, organizationId);
  const { role, storeIds: validStoreIds } = await validateRoleAndStores(admin, organizationId, actor.roleCode, roleId, storeIds);

  const { data: pending, error: pendingError } = await admin
    .from("organization_invitations")
    .select("id,expires_at,auth_user_id,accepted_at")
    .eq("organization_id", organizationId)
    .eq("email", email)
    .eq("status", "pending")
    .maybeSingle();

  if (pendingError) throw pendingError;
  if (pending) {
    let activeMembership: any = null;
    if (pending.auth_user_id) {
      const { data, error } = await admin
        .from("organization_members")
        .select("id,status")
        .eq("organization_id", organizationId)
        .eq("user_id", pending.auth_user_id)
        .eq("status", "active")
        .maybeSingle();
      if (error) throw error;
      activeMembership = data;
    }

    const reconciledAt = new Date().toISOString();
    if (activeMembership) {
      const { data: reconciled, error } = await admin
        .from("organization_invitations")
        .update({
          status: "accepted",
          accepted_at: pending.accepted_at || reconciledAt,
          updated_at: reconciledAt,
        })
        .eq("id", pending.id)
        .eq("status", "pending")
        .select("id")
        .maybeSingle();
      if (error) throw error;
      if (!reconciled) throw new Error("Invitation changed while reconciling; refresh and try again");
    } else if (isInvitationExpired(pending.expires_at)) {
      const { data: expired, error } = await admin
        .from("organization_invitations")
        .update({ status: "expired", updated_at: reconciledAt })
        .eq("id", pending.id)
        .eq("status", "pending")
        .select("id")
        .maybeSingle();
      if (error) throw error;
      if (!expired) throw new Error("Invitation changed while expiring; refresh and try again");
    } else {
      throw new Error("A pending invitation already exists for this email");
    }
  }

  const existingUser = await findAuthUserByEmail(admin, email);
  let authUserId = existingUser?.id || null;
  let membershipStatus: "active" | "invited" = "invited";
  let inviteSent = false;
  let createdAuthUser = false;
  let existingMember: any = null;
  let previousStoreIds: string[] = [];

  if (existingUser) {
    const { data, error: existingMemberError } = await admin
      .from("organization_members")
      .select("id,status,role_id")
      .eq("organization_id", organizationId)
      .eq("user_id", existingUser.id)
      .maybeSingle();

    if (existingMemberError) throw existingMemberError;
    existingMember = data;
    const inviteAction = getInviteMembershipAction(existingMember?.status ?? null);
    if (inviteAction === "reject") throw new Error("This user is already a member of the organization");

    if (existingMember) {
      const { data: currentStores, error: currentStoresError } = await admin
        .from("member_stores")
        .select("store_id")
        .eq("member_id", existingMember.id);
      if (currentStoresError) throw currentStoresError;
      previousStoreIds = (currentStores || []).map((row: any) => row.store_id);
    }

    if (existingUser.email_confirmed_at) {
      membershipStatus = "active";
    } else {
      const { error: resendError } = await admin.auth.resend({ type: "signup", email });
      if (resendError) throw new Error("User exists but the invitation could not be resent: " + resendError.message);
      inviteSent = true;
    }
  } else {
    const { data: inviteData, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email);
    if (inviteError) throw inviteError;
    authUserId = inviteData.user?.id || null;
    if (!authUserId) throw new Error("Auth invitation did not return a user id");
    createdAuthUser = true;
    inviteSent = true;
  }

  if (!authUserId) throw new Error("Unable to resolve invited user");

  const cleanupCreatedAuthUser = async () => {
    if (!createdAuthUser || !authUserId) return;
    const { error } = await admin.auth.admin.deleteUser(authUserId);
    if (error) console.error("Failed to clean up created Auth user", error);
  };

  let member: any;
  if (existingMember) {
    const { data, error } = await admin
      .from("organization_members")
      .update({ role_id: role.id, status: membershipStatus })
      .eq("id", existingMember.id)
      .in("status", ["suspended", "inactive", "invited"])
      .select("id")
      .maybeSingle();
    if (error) throw error;
    if (!data) throw new Error("Membership changed while re-inviting; refresh and try again");
    member = data;
  } else {
    const { data, error } = await admin
      .from("organization_members")
      .insert({ organization_id: organizationId, user_id: authUserId, role_id: role.id, status: membershipStatus })
      .select("id")
      .single();
    if (error) {
      await cleanupCreatedAuthUser();
      throw error;
    }
    member = data;
  }

  const restoreMembership = async () => {
    if (existingMember) {
      const { error: restoreError } = await admin.from("organization_members")
        .update({ role_id: existingMember.role_id, status: existingMember.status }).eq("id", existingMember.id);
      if (restoreError) console.error("Failed to restore membership after invitation error", restoreError);
      const { error: clearError } = await admin.from("member_stores").delete().eq("member_id", existingMember.id);
      if (clearError) console.error("Failed to clear updated member stores during rollback", clearError);
      if (previousStoreIds.length) {
        const { error: storeRestoreError } = await admin.from("member_stores")
          .insert(previousStoreIds.map(storeId => ({ member_id: existingMember.id, store_id: storeId })));
        if (storeRestoreError) console.error("Failed to restore member stores after invitation error", storeRestoreError);
      }
    } else {
      const { error: storeDeleteError } = await admin.from("member_stores").delete().eq("member_id", member.id);
      if (storeDeleteError) console.error("Failed to clean up member stores", storeDeleteError);
      const { error: memberDeleteError } = await admin.from("organization_members").delete().eq("id", member.id);
      if (memberDeleteError) console.error("Failed to clean up membership", memberDeleteError);
      await cleanupCreatedAuthUser();
    }
  };

  const { error: clearStoresError } = await admin.from("member_stores").delete().eq("member_id", member.id);
  if (clearStoresError) {
    await restoreMembership();
    throw clearStoresError;
  }
  if (validStoreIds.length) {
    const { error: storesError } = await admin.from("member_stores").insert(
      validStoreIds.map(storeId => ({ member_id: member.id, store_id: storeId }))
    );
    if (storesError) {
      await restoreMembership();
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
    await restoreMembership();
    throw invitationError;
  }

  return { ok: true, invitation, membership_id: member.id, status: membershipStatus, invite_sent: inviteSent };
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

  const invitations = data || [];
  const pendingUserIds = [...new Set(
    invitations
      .filter((invitation: any) => invitation.status === "pending" && invitation.auth_user_id)
      .map((invitation: any) => invitation.auth_user_id)
  )];
  let activeUserIds = new Set<string>();

  if (pendingUserIds.length) {
    const { data: activeMembers, error: membersError } = await admin
      .from("organization_members")
      .select("user_id")
      .eq("organization_id", organizationId)
      .eq("status", "active")
      .in("user_id", pendingUserIds);
    if (membersError) throw membersError;
    activeUserIds = new Set((activeMembers || []).map((member: any) => member.user_id));
  }

  return {
    invitations: invitations.map((invitation: any) => ({
      ...invitation,
      status: getInvitationDisplayStatus(
        invitation.status,
        invitation.expires_at,
        activeUserIds.has(invitation.auth_user_id) ? "active" : null
      ),
    })),
  };
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

  let member: any = null;
  if (invitation.auth_user_id) {
    const { data, error: memberError } = await admin
      .from("organization_members")
      .select("id,status")
      .eq("organization_id", invitation.organization_id)
      .eq("user_id", invitation.auth_user_id)
      .maybeSingle();
    if (memberError) throw memberError;
    member = data;
  }

  const { data: revoked, error: updateError } = await admin
    .from("organization_invitations")
    .update({ status: "revoked", updated_at: new Date().toISOString() })
    .eq("id", invitationId)
    .eq("status", "pending")
    .select("id")
    .maybeSingle();
  if (updateError) throw updateError;
  if (!revoked) throw new Error("Invitation changed before it could be revoked");

  if (member?.status === "invited") {
    const { data: suspended, error: suspendError } = await admin
      .from("organization_members")
      .update({ status: "suspended" })
      .eq("id", member.id)
      .eq("status", "invited")
      .select("id")
      .maybeSingle();
    if (suspendError || !suspended) {
      const { error: rollbackError } = await admin.from("organization_invitations")
        .update({ status: "pending", updated_at: new Date().toISOString() })
        .eq("id", invitationId).eq("status", "revoked");
      if (rollbackError) console.error("Failed to restore invitation after revoke failure", rollbackError);
      if (suspendError) throw suspendError;
      throw new Error("Membership changed while revoking; refresh and try again");
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
    if (isInvitationExpired(invitation.expires_at)) {
      const { data: member, error: memberError } = await admin
        .from("organization_members")
        .select("id,status")
        .eq("organization_id", invitation.organization_id)
        .eq("user_id", userId)
        .maybeSingle();
      if (memberError) throw memberError;

      let suspendedMemberId: string | null = null;
      if (member?.status === "invited") {
        const { data: suspended, error: suspendError } = await admin
          .from("organization_members")
          .update({ status: "suspended" })
          .eq("id", member.id)
          .eq("status", "invited")
          .select("id")
          .maybeSingle();
        if (suspendError) throw suspendError;
        if (!suspended) throw new Error("Membership changed while expiring invitation; refresh and try again");
        suspendedMemberId = member.id;
      }

      const { data: expired, error: expireError } = await admin.from("organization_invitations")
        .update({ status: "expired", updated_at: new Date().toISOString() })
        .eq("id", invitation.id).eq("status", "pending")
        .select("id")
        .maybeSingle();
      if (expireError || !expired) {
        if (suspendedMemberId) {
          const { error: restoreError } = await admin.from("organization_members")
            .update({ status: "invited" })
            .eq("id", suspendedMemberId)
            .eq("status", "suspended");
          if (restoreError) console.error("Failed to restore invited membership after expiry failure", restoreError);
        }
        if (expireError) throw expireError;
        continue;
      }
      continue;
    }

    const { data: member, error: memberError } = await admin
      .from("organization_members")
      .select("id,status")
      .eq("organization_id", invitation.organization_id)
      .eq("user_id", userId)
      .maybeSingle();
    if (memberError) throw memberError;

    if (!member) {
      const { error: revokeOrphanError } = await admin.from("organization_invitations")
        .update({ status: "revoked", updated_at: new Date().toISOString() })
        .eq("id", invitation.id).eq("status", "pending");
      if (revokeOrphanError) throw revokeOrphanError;
      continue;
    }

    const acceptanceAction = getAcceptanceAction(member.status);
    if (acceptanceAction === "reject") {
      const { error: revokeInactiveError } = await admin.from("organization_invitations")
        .update({ status: "revoked", updated_at: new Date().toISOString() })
        .eq("id", invitation.id).eq("status", "pending");
      if (revokeInactiveError) throw revokeInactiveError;
      continue;
    }

    const acceptedAt = new Date().toISOString();
    const { data: claimedInvitation, error: invitationUpdateError } = await admin
      .from("organization_invitations")
      .update({ status: "accepted", accepted_at: acceptedAt, updated_at: acceptedAt })
      .eq("id", invitation.id)
      .eq("status", "pending")
      .select("id")
      .maybeSingle();
    if (invitationUpdateError) throw invitationUpdateError;
    if (!claimedInvitation) continue;

    if (acceptanceAction === "activate") {
      const { data: activatedMember, error: memberUpdateError } = await admin
        .from("organization_members")
        .update({ status: "active" })
        .eq("id", member.id)
        .eq("status", "invited")
        .select("id")
        .maybeSingle();

      if (memberUpdateError || !activatedMember) {
        const { error: rollbackError } = await admin.from("organization_invitations")
          .update({ status: "pending", accepted_at: null, updated_at: new Date().toISOString() })
          .eq("id", invitation.id).eq("status", "accepted");
        if (rollbackError) console.error("Failed to restore pending invitation after acceptance failure", rollbackError);
        if (memberUpdateError) throw memberUpdateError;
        throw new Error("Membership is no longer awaiting invitation acceptance");
      }
    }

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
