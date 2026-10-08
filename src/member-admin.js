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
      ensureInvitationUI();
      renderAdmin();
      await loadInvitations();
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
      row.innerHTML = `
        <td><code>${esc(member.user_id)}</code></td>
        <td>
          <select data-member-role="${esc(member.member_id)}"${canChangeRole ? "" : " disabled"}>
            ${roleOptions}
          </select>
        </td>
        <td><div class="member-store-list">${stores}</div></td>
        <td>
          <span class="status-badge ${member.status === "active" ? "status-paid" : "status-unpaid"}">
            ${member.status === "active" ? "نشط" : "غير نشط"}
          </span>
        </td>
        <td>
          <div class="member-admin-actions">
            <button class="edit-btn" onclick="saveMemberRole('${esc(member.member_id)}')" ${canChangeRole ? "" : "disabled"}>حفظ الدور</button>
            <button class="sale-btn" onclick="saveMemberStores('${esc(member.member_id)}')" ${canChangeStatus ? "" : "disabled"}>حفظ الفروع</button>
            <button class="${member.status === "active" ? "danger-btn" : "sale-btn"}"
              onclick="toggleMemberStatus('${esc(member.member_id)}','${member.status === "active" ? "inactive" : "active"}')"
              ${canChangeStatus ? "" : "disabled"}>
              ${member.status === "active" ? "تعطيل" : "تفعيل"}
            </button>
          </div>
        </td>`;
      table.appendChild(row);
    });
  }


  function ensureInvitationUI() {
    if (document.getElementById("memberInvitationPanel")) return;

    const section = document.getElementById("memberAdminSection");
    if (!section) return;

    const panel = document.createElement("div");
    panel.id = "memberInvitationPanel";
    panel.style.marginTop = "18px";
    panel.innerHTML = `
      <div class="section-header">
        <h3 style="margin:0">دعوة عضو جديد</h3>
      </div>
      <div id="memberInvitationMessage" class="message"></div>
      <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;align-items:end">
        <div>
          <label>البريد الإلكتروني</label>
          <input id="memberInviteEmail" type="email" autocomplete="email" placeholder="name@example.com">
        </div>
        <div>
          <label>الدور</label>
          <select id="memberInviteRole"></select>
        </div>
        <div>
          <label>الفروع</label>
          <div id="memberInviteStores" style="display:flex;gap:8px;flex-wrap:wrap"></div>
        </div>
        <div>
          <button class="payment-confirm" onclick="sendMemberInvitation()">إرسال الدعوة</button>
        </div>
      </div>
      <div style="margin-top:18px">
        <h4>الدعوات</h4>
        <div style="overflow:auto">
          <table>
            <thead><tr><th>البريد</th><th>الدور</th><th>الحالة</th><th>تنتهي</th><th>الإجراء</th></tr></thead>
            <tbody id="memberInvitationTable"></tbody>
          </table>
        </div>
      </div>
    `;

    section.appendChild(panel);

    const roleSelect = document.getElementById("memberInviteRole");
    if (roleSelect) {
      roleSelect.innerHTML = adminRoles.map(role =>
        '<option value="' + esc(role.id) + '">' + esc(role.name) + '</option>'
      ).join("");
    }

    const storesBox = document.getElementById("memberInviteStores");
    if (storesBox) {
      storesBox.innerHTML = (adminContext.stores || []).map(store =>
        '<label style="display:inline-flex;gap:6px;align-items:center">' +
        '<input type="checkbox" data-invite-store="' + esc(store.id) + '" value="' + esc(store.id) + '">' +
        esc(store.name) +
        '</label>'
      ).join("");
    }
  }

  async function invitationAction(body) {
    const { data, error } = await client().functions.invoke(
      "organization-member-invitations",
      { body }
    );
    if (error) throw error;
    if (data && data.error) throw new Error(data.error);
    return data;
  }

  async function loadInvitations() {
    if (!document.getElementById("memberInvitationPanel")) return;

    try {
      const data = await invitationAction({
        action: "list",
        organization_id: adminContext.organization.id
      });

      const table = document.getElementById("memberInvitationTable");
      if (!table) return;
      table.innerHTML = "";

      (data.invitations || []).forEach(invitation => {
        const row = document.createElement("tr");
        const statusLabel =
          invitation.status === "pending" ? "معلقة" :
          invitation.status === "accepted" ? "مقبولة" :
          invitation.status === "revoked" ? "ملغاة" : "منتهية";

        row.innerHTML =
          "<td>" + esc(invitation.email) + "</td>" +
          "<td>" + esc(invitation.roles?.name || "-") + "</td>" +
          "<td>" + esc(statusLabel) + "</td>" +
          "<td>" + esc(new Date(invitation.expires_at).toLocaleString("ar")) + "</td>" +
          "<td>" +
            (invitation.status === "pending"
              ? '<button class="danger-btn" onclick="revokeMemberInvitation(\'' + esc(invitation.id) + '\')">إلغاء</button>'
              : "-") +
          "</td>";
        table.appendChild(row);
      });
    } catch (error) {
      console.error("INVITATION LIST ERROR:", error);
      showInvitationMessage(error.message || "تعذر تحميل الدعوات.", true);
    }
  }

  function showInvitationMessage(message, error) {
    const box = document.getElementById("memberInvitationMessage");
    if (!box) return;
    box.textContent = message || "";
    box.className = "message " + (error ? "error" : "success");
    box.style.display = message ? "block" : "none";
  }

  async function sendMemberInvitation() {
    const email = String(document.getElementById("memberInviteEmail")?.value || "").trim();
    const roleId = document.getElementById("memberInviteRole")?.value || "";
    const storeIds = [...document.querySelectorAll("[data-invite-store]:checked")]
      .map(input => input.value);

    if (!email) return showInvitationMessage("البريد الإلكتروني مطلوب.", true);
    if (!roleId) return showInvitationMessage("الدور مطلوب.", true);

    try {
      const result = await invitationAction({
        action: "invite",
        organization_id: adminContext.organization.id,
        email,
        role_id: roleId,
        store_ids: storeIds
      });

      document.getElementById("memberInviteEmail").value = "";
      document.querySelectorAll("[data-invite-store]").forEach(input => { input.checked = false; });

      await loadAdmin();
      showInvitationMessage(
        result.status === "active"
          ? "تمت إضافة المستخدم الموجود إلى المؤسسة."
          : "تم إرسال الدعوة وإنشاء العضوية بحالة انتظار.",
        false
      );
    } catch (error) {
      console.error("INVITATION ERROR:", error);
      showInvitationMessage(error.message || "تعذر إرسال الدعوة.", true);
    }
  }

  async function revokeMemberInvitation(invitationId) {
    if (!window.confirm("هل تريد إلغاء هذه الدعوة؟")) return;

    try {
      await invitationAction({
        action: "revoke",
        invitation_id: invitationId
      });
      await loadInvitations();
      await loadAdmin();
      showInvitationMessage("تم إلغاء الدعوة.", false);
    } catch (error) {
      console.error("INVITATION REVOKE ERROR:", error);
      showInvitationMessage(error.message || "تعذر إلغاء الدعوة.", true);
    }
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
  window.sendMemberInvitation = sendMemberInvitation;
  window.revokeMemberInvitation = revokeMemberInvitation;
})();