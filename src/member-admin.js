(function () {
  "use strict";

  let adminContext = null;
  let adminMembers = [];
  let adminRoles = [];

  function client() {
    return window.SmartSalesAuth.getClient();
  }

  function context() {
    return adminContext || window.SmartSalesAuth.getContext();
  }

  function esc(value) {
    if (typeof window.escapeHtml === "function") return window.escapeHtml(String(value ?? ""));
    return String(value ?? "").replace(/[&<>"']/g, ch => ({
      "&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#039;"
    }[ch]));
  }

  function showAdminMessage(message, error) {
    const box = document.getElementById("memberAdminMessage");
    if (!box) return;
    box.textContent = message || "";
    box.className = "message " + (error ? "error" : "success");
    box.style.display = message ? "block" : "none";
  }

  async function loadAdmin() {
    const section = document.getElementById("memberAdminSection");
    if (!section) return;

    adminContext = context();
    section.style.display = "none";

    try {
      const { data, error } = await client().rpc("list_organization_members", {
        p_organization_id: adminContext.organization.id
      });
      if (error) {
        if (/permission denied|not authorized/i.test(error.message || "")) return;
        throw error;
      }

      adminMembers = data || [];

      const { data: roles, error: rolesError } = await client()
        .from("roles")
        .select("id,name,code,is_system")
        .eq("organization_id", adminContext.organization.id)
        .order("name");

      if (rolesError) throw rolesError;

      adminRoles = roles || [];
      section.style.display = "block";
      renderAdmin();
    } catch (error) {
      console.error("MEMBER ADMIN ERROR:", error);
      showAdminMessage(error.message || "تعذر تحميل إدارة الأعضاء.", true);
    }
  }

  function renderAdmin() {
    const table = document.getElementById("memberAdminTable");
    const empty = document.getElementById("memberAdminEmpty");
    if (!table || !empty) return;

    table.innerHTML = "";
    empty.style.display = adminMembers.length ? "none" : "block";

    const actor = adminMembers.find(m =>
      String(m.user_id) === String(adminContext.userId)
    );
    const actorIsOwner = actor && actor.role_code === "owner";
    const canManageMembers = true;

    adminMembers.forEach(member => {
      const roleOptions = adminRoles.map(role =>
        '<option value="' + esc(role.id) + '"' +
        (String(role.id) === String(member.role_id) ? " selected" : "") + ">" +
        esc(role.name) + "</option>"
      ).join("");

      const stores = (adminContext.stores || []).map(store => {
        const checked = (member.store_ids || []).some(id =>
          String(id) === String(store.id)
        );
        return '<label class="member-store-option"><input type="checkbox" data-member-store="' +
          esc(member.member_id) + '" value="' + esc(store.id) + '"' +
          (checked ? " checked" : "") + '>' + esc(store.name) + '</label>';
      }).join("");

      const isOwner = member.role_code === "owner";
      const canChangeRole = actorIsOwner || (!isOwner && member.user_id !== adminContext.userId);
      const canChangeStatus = actorIsOwner || !isOwner;

      const row = document.createElement("tr");
      row.innerHTML =
        "<td><code>" + esc(member.user_id) + "</code></td>" +
        "<td><select data-member-role="" + esc(member.member_id) + """ +
          (canChangeRole ? "" : " disabled") + ">" + roleOptions + "</select></td>" +
        "<td><div class="member-store-list">" + stores + "</div></td>" +
        '<td><span class="status-badge ' +
          (member.status === "active" ? "status-paid" : "status-unpaid") + '">' +
          (member.status === "active" ? "نشط" : "غير نشط") + "</span></td>" +
        "<td><div class="member-admin-actions">" +
          '<button class="edit-btn" onclick="saveMemberRole(\'' + esc(member.member_id) + '\')" ' +
            (canChangeRole ? "" : "disabled") + ">حفظ الدور</button>" +
          '<button class="sale-btn" onclick="saveMemberStores(\'' + esc(member.member_id) + '\')" ' +
            (canChangeStatus ? "" : "disabled") + ">حفظ الفروع</button>" +
          '<button class="' + (member.status === "active" ? "danger-btn" : "sale-btn") +
            '" onclick="toggleMemberStatus(\'' + esc(member.member_id) + '\',\'' +
            (member.status === "active" ? "inactive" : "active") + '\')" ' +
            (canChangeStatus ? "" : "disabled") + ">" +
            (member.status === "active" ? "تعطيل" : "تفعيل") + "</button>" +
        "</div></td>";
      table.appendChild(row);
    });
  }

  async function saveMemberRole(memberId) {
    const select = document.querySelector('[data-member-role="' + CSS.escape(memberId) + '"]');
    if (!select) return;
    try {
      await client().rpc("assign_member_role", {
        p_organization_id: adminContext.organization.id,
        p_member_id: memberId,
        p_role_id: select.value
      }).then(result => {
        if (result.error) throw result.error;
      });
      await loadAdmin();
      showAdminMessage("تم تحديث دور العضو.");
    } catch (error) {
      console.error(error);
      showAdminMessage(error.message || "تعذر تحديث الدور.", true);
    }
  }

  async function saveMemberStores(memberId) {
    const inputs = [...document.querySelectorAll(
      '[data-member-store="' + CSS.escape(memberId) + '"]'
    )];
    const storeIds = inputs.filter(input => input.checked).map(input => input.value);
    try {
      const { error } = await client().rpc("set_member_stores", {
        p_organization_id: adminContext.organization.id,
        p_member_id: memberId,
        p_store_ids: storeIds
      });
      if (error) throw error;
      await loadAdmin();
      showAdminMessage("تم تحديث فروع العضو.");
    } catch (error) {
      console.error(error);
      showAdminMessage(error.message || "تعذر تحديث الفروع.", true);
    }
  }

  async function toggleMemberStatus(memberId, status) {
    const label = status === "active" ? "تفعيل" : "تعطيل";
    if (!window.confirm("هل تريد " + label + " هذا العضو؟")) return;
    try {
      const { error } = await client().rpc("set_member_status", {
        p_organization_id: adminContext.organization.id,
        p_member_id: memberId,
        p_status: status
      });
      if (error) throw error;
      await loadAdmin();
      showAdminMessage("تم تحديث حالة العضو.");
    } catch (error) {
      console.error(error);
      showAdminMessage(error.message || "تعذر تحديث حالة العضو.", true);
    }
  }

  window.loadMemberAdmin = loadAdmin;
  window.saveMemberRole = saveMemberRole;
  window.saveMemberStores = saveMemberStores;
  window.toggleMemberStatus = toggleMemberStatus;
})();