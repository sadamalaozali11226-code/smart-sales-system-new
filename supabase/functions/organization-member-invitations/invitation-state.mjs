export function getInviteMembershipAction(status) {
  if (status == null) return "create";
  if (status === "suspended" || status === "inactive") return "reinvite";
  return "reject";
}

export function getAcceptanceAction(status) {
  if (status === "invited") return "activate";
  if (status === "active") return "accept";
  return "reject";
}

export function isInvitationExpired(expiresAt, now = Date.now()) {
  const expiry = Date.parse(expiresAt);
  return !Number.isFinite(expiry) || expiry <= now;
}
