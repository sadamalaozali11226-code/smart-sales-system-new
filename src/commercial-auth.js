(function () {
  "use strict";

  const CONFIG = {
    defaultOrganizationName: "العوذلي",
    defaultOrganizationSlug: "alawdli",
    defaultStoreName: "المتجر الرئيسي",
    defaultStoreCode: "MAIN"
  };

  let client = null;
  let context = null;

  function ensureClient() {
    if (client) return client;

    if (!window.supabase || !window.SmartSalesSupabase) {
      throw new Error("Supabase client is not available.");
    }

    const config = window.SmartSalesSupabase;

    client = window.supabase.createClient(
      config.url,
      config.publishableKey,
      {
        auth: {
          autoRefreshToken: true,
          persistSession: true,
          detectSessionInUrl: true
        }
      }
    );

    return client;
  }

  function htmlEscape(value) {
    const div = document.createElement("div");
    div.textContent = value == null ? "" : String(value);
    return div.innerHTML;
  }

  function getLabels() {
    return {
      ar: {
        loginTitle: "تسجيل الدخول",
        loginSubtitle: "الدخول إلى نظام المبيعات التجاري",
        email: "البريد الإلكتروني",
        password: "كلمة المرور",
        login: "دخول",
        signup: "إنشاء حساب",
        name: "اسم المؤسسة",
        slug: "معرّف المؤسسة",
        store: "اسم الفرع",
        code: "رمز الفرع",
        createWorkspace: "إنشاء مساحة العمل",
        newWorkspace: "لا توجد مؤسسة مرتبطة بهذا الحساب. أنشئ مساحة العمل الأولى.",
        logout: "تسجيل الخروج",
        loading: "جارٍ التحقق...",
        invalid: "أدخل البريد وكلمة المرور.",
        signupDone: "تم إنشاء الحساب. إذا طُلب تأكيد البريد، افتح رسالة التأكيد ثم سجّل الدخول.",
        error: "تعذر إكمال العملية.",
        signedIn: "تم تسجيل الدخول",
        workspace: "المؤسسة",
        organizationLabel: "المؤسسة",
        storeLabel: "الفرع"
      },
      en: {
        loginTitle: "Sign in",
        loginSubtitle: "Access your commercial sales system",
        email: "Email",
        password: "Password",
        login: "Sign in",
        signup: "Create account",
        name: "Organization name",
        slug: "Organization slug",
        store: "Store name",
        code: "Store code",
        createWorkspace: "Create workspace",
        newWorkspace: "No organization is linked to this account. Create the first workspace.",
        logout: "Sign out",
        loading: "Checking session...",
        invalid: "Enter email and password.",
        signupDone: "Account created. If email confirmation is required, confirm your email and then sign in.",
        error: "The operation could not be completed.",
        signedIn: "Signed in",
        workspace: "Organization",
        organizationLabel: "Organization",
        storeLabel: "Store"
      }
    };
  }

  function createGate() {
    if (document.getElementById("commercialAuthGate")) {
      return document.getElementById("commercialAuthGate");
    }

    const style = document.createElement("style");
    style.id = "commercialAuthStyles";
    style.textContent = `
      #commercialAuthGate {
        position: fixed;
        inset: 0;
        z-index: 99999;
        background: #f4f6f8;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 20px;
      }
      #commercialAuthGate .auth-card {
        width: min(460px, 100%);
        background: #fff;
        border-radius: 16px;
        padding: 28px;
        box-shadow: 0 12px 40px rgba(0,0,0,.10);
      }
      #commercialAuthGate h2 {
        margin-bottom: 8px;
      }
      #commercialAuthGate p {
        color: #666;
        line-height: 1.7;
        margin-bottom: 18px;
      }
      #commercialAuthGate form {
        display: grid;
        gap: 10px;
      }
      #commercialAuthGate input {
        width: 100%;
        padding: 12px;
        border: 1px solid #ddd;
        border-radius: 8px;
        font-size: 15px;
      }
      #commercialAuthGate .auth-actions {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 10px;
        margin-top: 6px;
      }
      #commercialAuthGate button {
        border: 0;
        border-radius: 8px;
        padding: 11px 14px;
        cursor: pointer;
        font-size: 15px;
      }
      #commercialAuthGate .primary {
        background: #2563eb;
        color: #fff;
      }
      #commercialAuthGate .secondary {
        background: #e5e7eb;
        color: #111827;
      }
      #commercialAuthGate .auth-message {
        margin-top: 12px;
        padding: 10px;
        border-radius: 8px;
        display: none;
        line-height: 1.6;
      }
      #commercialAuthGate .auth-message.error {
        display: block;
        background: #fee2e2;
        color: #991b1b;
      }
      #commercialAuthGate .auth-message.success {
        display: block;
        background: #dcfce7;
        color: #166534;
      }
      #commercialAuthGate .workspace-fields {
        display: none;
        gap: 10px;
        margin-top: 12px;
      }
      #commercialAuthGate .workspace-fields.visible {
        display: grid;
      }
      #commercialSessionBar {
        position: fixed;
        top: 10px;
        inset-inline-start: 10px;
        z-index: 9999;
        background: rgba(255,255,255,.96);
        border: 1px solid #e5e7eb;
        border-radius: 10px;
        padding: 8px 10px;
        box-shadow: 0 4px 16px rgba(0,0,0,.08);
        display: none;
        align-items: center;
        gap: 8px;
        font-size: 13px;
      }
      #commercialSessionBar button {
        border: 0;
        background: #dc2626;
        color: #fff;
        border-radius: 7px;
        padding: 6px 9px;
        cursor: pointer;
      }
    `;
    document.head.appendChild(style);

    const gate = document.createElement("div");
    gate.id = "commercialAuthGate";
    gate.innerHTML = `
      <div class="auth-card">
        <h2 id="commercialAuthTitle"></h2>
        <p id="commercialAuthSubtitle"></p>

        <form id="commercialAuthForm">
          <input id="commercialAuthEmail" type="email" autocomplete="email">
          <input id="commercialAuthPassword" type="password" autocomplete="current-password">

          <div class="auth-actions">
            <button type="submit" class="primary" id="commercialLoginButton"></button>
            <button type="button" class="secondary" id="commercialSignupButton"></button>
          </div>

          <div class="workspace-fields" id="commercialWorkspaceFields">
            <input id="commercialOrgName" type="text">
            <input id="commercialOrgSlug" type="text">
            <input id="commercialStoreName" type="text">
            <input id="commercialStoreCode" type="text">
            <button type="button" class="primary" id="commercialWorkspaceButton"></button>
          </div>

          <div class="auth-message" id="commercialAuthMessage"></div>
        </form>
      </div>
    `;

    document.body.appendChild(gate);

    const bar = document.createElement("div");
    bar.id = "commercialSessionBar";
    document.body.appendChild(bar);

    return gate;
  }

  function setMessage(message, type) {
    const el = document.getElementById("commercialAuthMessage");
    if (!el) return;
    el.textContent = message || "";
    el.className = "auth-message" + (type ? " " + type : "");
  }

  function hideGate() {
    const gate = document.getElementById("commercialAuthGate");
    if (gate) gate.style.display = "none";

    const bar = document.getElementById("commercialSessionBar");
    if (bar && context) {
      const t = getLabels()[document.documentElement.lang === "en" ? "en" : "ar"];
      const storeOptions = (context.stores || []).map(function(store) {
        return (
          "<option value=\"" +
          htmlEscape(store.id) +
          "\"" +
          (String(store.id) === String(context.store.id) ? " selected" : "") +
          ">" +
          htmlEscape(store.name) +
          "</option>"
        );
      }).join("");

      const organizationOptions = (context.organizations || []).map(function(organization) {
        return (
          "<option value=\"" +
          htmlEscape(organization.id) +
          "\"" +
          (String(organization.id) === String(context.organization.id) ? " selected" : "") +
          ">" +
          htmlEscape(organization.name) +
          "</option>"
        );
      }).join("");

      bar.innerHTML =
        "<label>" +
        htmlEscape(t.organizationLabel) +
        ": " +
        "<select id=\"commercialOrganizationSelector\">" +
        organizationOptions +
        "</select>" +
        "</label>" +
        "<label>" +
        htmlEscape(t.storeLabel) +
        ": " +
        "<select id=\"commercialStoreSelector\">" +
        storeOptions +
        "</select>" +
        "</label>" +
        "<button type=\"button\" id=\"commercialLogoutButton\">" +
        htmlEscape(t.logout) +
        "</button>";
      bar.style.display = "flex";
      document.getElementById("commercialLogoutButton").onclick = signOut;
      const organizationSelector = document.getElementById("commercialOrganizationSelector");
      if (organizationSelector) {
        organizationSelector.onchange = function(event) {
          switchOrganization(event.target.value);
        };
      }
      const storeSelector = document.getElementById("commercialStoreSelector");
      if (storeSelector) {
        storeSelector.onchange = function(event) {
          switchStore(event.target.value);
        };
      }
    }
  }

  function showGate() {
    const gate = document.getElementById("commercialAuthGate");
    if (gate) gate.style.display = "flex";
    const bar = document.getElementById("commercialSessionBar");
    if (bar) bar.style.display = "none";
  }

  async function loadContext(userId, selectedOrganizationId) {
    const supabase = ensureClient();

    const { data: memberships, error: membershipError } = await supabase
      .from("organization_members")
      .select("id,organization_id,role_id,status")
      .eq("user_id", userId)
      .eq("status", "active");

    if (membershipError) throw membershipError;
    if (!memberships || memberships.length === 0) return null;

    const organizationIds = memberships.map(function(item) {
      return item.organization_id;
    });

    const { data: organizations, error: orgError } = await supabase
      .from("organizations")
      .select("id,name,slug,status")
      .in("id", organizationIds)
      .eq("status", "active");

    if (orgError) throw orgError;
    if (!organizations || organizations.length === 0) return null;

    const organizationId =
      selectedOrganizationId && organizationIds.includes(selectedOrganizationId)
        ? selectedOrganizationId
        : organizations[0].id;

    const membership = memberships.find(function(item) {
      return String(item.organization_id) === String(organizationId);
    });
    const organization = organizations.find(function(item) {
      return String(item.id) === String(organizationId);
    });

    if (!membership || !organization) return null;

    const { data: storeMemberships, error: storeMembershipError } = await supabase
      .from("member_stores")
      .select("store_id")
      .eq("member_id", membership.id);

    if (storeMembershipError) throw storeMembershipError;

    const storeIds = (storeMemberships || []).map(item => item.store_id);

    let storesQuery = supabase
      .from("stores")
      .select("id,name,code,status")
      .eq("organization_id", organizationId)
      .eq("status", "active");

    if (storeIds.length > 0) {
      storesQuery = storesQuery.in("id", storeIds);
    }

    const { data: stores, error: storesError } = await storesQuery;

    if (storesError) throw storesError;
    if (!stores || stores.length === 0) return null;

    return {
      userId,
      membership,
      organizations,
      organization,
      stores,
      store: stores[0]
    };
  }

  async function switchOrganization(organizationId) {
    if (!context || !organizationId || String(organizationId) === String(context.organization.id)) return;

    const nextContext = await loadContext(context.userId, organizationId);
    if (!nextContext) return;

    context = nextContext;
    hideGate();

    if (typeof window.initializeCommercialApp === "function") {
      await window.initializeCommercialApp(context);
    }
  }

  async function switchStore(storeId) {
    if (!context || !storeId) return;
    const nextStore = (context.stores || []).find(function(store) {
      return String(store.id) === String(storeId);
    });
    if (!nextStore || String(nextStore.id) === String(context.store.id)) return;

    context = Object.assign({}, context, { store: nextStore });
    hideGate();

    if (typeof window.initializeCommercialApp === "function") {
      await window.initializeCommercialApp(context);
    }
  }

  async function bootstrapWorkspace() {
    const supabase = ensureClient();
    const labels = getLabels()[document.documentElement.lang === "en" ? "en" : "ar"];

    const name = document.getElementById("commercialOrgName").value.trim();
    const slug = document.getElementById("commercialOrgSlug").value.trim();
    const storeName = document.getElementById("commercialStoreName").value.trim();
    const storeCode = document.getElementById("commercialStoreCode").value.trim();

    if (!name || !slug || !storeName || !storeCode) {
      setMessage(labels.invalid, "error");
      return;
    }

    setMessage(labels.loading, "");

    const { error } = await supabase.rpc("bootstrap_organization", {
      p_organization_name: name,
      p_slug: slug,
      p_store_name: storeName,
      p_store_code: storeCode
    });

    if (error) {
      setMessage(error.message || labels.error, "error");
      return;
    }

    const user = (await supabase.auth.getUser()).data.user;
    context = await loadContext(user.id);

    if (!context) {
      setMessage(labels.error, "error");
      return;
    }

    await finishReady();
  }


  async function acceptPendingInvitations() {
    const supabase = ensureClient();
    const { data, error } = await supabase.functions.invoke(
      "organization-member-invitations",
      { body: { action: "accept" } }
    );

    // No pending invitation is a normal state for existing users.
    if (error) {
      console.warn("INVITATION ACCEPT ERROR:", error);
      return null;
    }
    if (data && data.error && !/No pending invitation/i.test(data.error)) {
      console.warn("INVITATION ACCEPT ERROR:", data.error);
      return null;
    }
    return data || null;
  }

  async function finishReady() {
    hideGate();

    if (typeof window.initializeCommercialApp === "function") {
      await window.initializeCommercialApp(context);
    }
  }

  async function signOut() {
    const supabase = ensureClient();
    await supabase.auth.signOut();
    context = null;
    showGate();
    setMessage("", "");
  }

  function authErrorMessage(error, labels) {
    const message = String((error && error.message) || "").toLowerCase();

    if (message.includes("invalid login credentials")) {
      return "بيانات الدخول غير صحيحة. إذا لم تنشئ الحساب بعد، استخدم «إنشاء حساب».";
    }
    if (message.includes("email not confirmed")) {
      return "البريد الإلكتروني غير مؤكد. افتح رسالة التأكيد في بريدك الإلكتروني ثم حاول تسجيل الدخول.";
    }
    if (message.includes("user already registered") || message.includes("already registered")) {
      return "هذا البريد مسجل مسبقًا. استخدم «دخول» بدل «إنشاء حساب».";
    }
    if (message.includes("password") && (message.includes("6") || message.includes("weak"))) {
      return "كلمة المرور يجب أن تكون من 6 أحرف على الأقل.";
    }
    if (message.includes("rate limit") || message.includes("too many")) {
      return "تم تجاوز عدد المحاولات المسموح بها مؤقتًا. انتظر قليلًا ثم حاول مرة أخرى.";
    }

    return (error && error.message) || labels.error;
  }

  async function signIn() {
    const supabase = ensureClient();
    const labels = getLabels()[document.documentElement.lang === "en" ? "en" : "ar"];
    const email = document.getElementById("commercialAuthEmail").value.trim();
    const password = document.getElementById("commercialAuthPassword").value;

    if (!email || !password) {
      setMessage(labels.invalid, "error");
      return;
    }

    setMessage("جارٍ تسجيل الدخول...", "");

    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password
    });

    if (error) {
      setMessage(authErrorMessage(error, labels), "error");
      return;
    }

    if (!data || !data.user) {
      setMessage(labels.error, "error");
      return;
    }

    await acceptPendingInvitations();
    await acceptPendingInvitations();
    context = await loadContext(data.user.id);

    if (!context) {
      document.getElementById("commercialWorkspaceFields").classList.add("visible");
      setMessage(labels.newWorkspace, "success");
      return;
    }

    await finishReady();
  }

  async function signUp() {
    const supabase = ensureClient();
    const labels = getLabels()[document.documentElement.lang === "en" ? "en" : "ar"];
    const email = document.getElementById("commercialAuthEmail").value.trim();
    const password = document.getElementById("commercialAuthPassword").value;

    if (!email || !password) {
      setMessage(labels.invalid, "error");
      return;
    }

    if (password.length < 6) {
      setMessage("كلمة المرور يجب أن تكون من 6 أحرف على الأقل.", "error");
      return;
    }

    setMessage("جارٍ إنشاء الحساب...", "");

    const { data, error } = await supabase.auth.signUp({
      email,
      password
    });

    if (error) {
      setMessage(authErrorMessage(error, labels), "error");
      return;
    }

    // Confirm Email is enabled in Supabase. When it is enabled, signUp()
    // intentionally returns without a session until the email is confirmed.
    if (!data || !data.user) {
      setMessage(labels.error, "error");
      return;
    }

    if (!data.session) {
      setMessage(
        "تم إنشاء الحساب بنجاح. افتح رسالة التأكيد في بريدك الإلكتروني، ثم ارجع واضغط «دخول».",
        "success"
      );
      return;
    }

    context = await loadContext(data.user.id);

    if (!context) {
      document.getElementById("commercialWorkspaceFields").classList.add("visible");
      setMessage(labels.newWorkspace, "success");
      return;
    }

    await finishReady();
  }

  async function start(options) {
    window.initializeCommercialApp =
      options && typeof options.onReady === "function"
        ? options.onReady
        : null;

    createGate();

    const labels = getLabels()[document.documentElement.lang === "en" ? "en" : "ar"];
    document.getElementById("commercialAuthTitle").textContent = labels.loginTitle;
    document.getElementById("commercialAuthSubtitle").textContent = labels.loginSubtitle;
    document.getElementById("commercialAuthEmail").placeholder = labels.email;
    document.getElementById("commercialAuthPassword").placeholder = labels.password;
    document.getElementById("commercialLoginButton").textContent = labels.login;
    document.getElementById("commercialSignupButton").textContent = labels.signup;
    document.getElementById("commercialOrgName").placeholder = labels.name;
    document.getElementById("commercialOrgSlug").placeholder = labels.slug;
    document.getElementById("commercialStoreName").placeholder = labels.store;
    document.getElementById("commercialStoreCode").placeholder = labels.code;
    document.getElementById("commercialWorkspaceButton").textContent = labels.createWorkspace;

    document.getElementById("commercialAuthForm").onsubmit = async function (event) {
      event.preventDefault();
      // Enter in the form always means Sign in. Account creation is a
      // separate explicit action and never falls through to signIn().
      await signIn();
    };

    document.getElementById("commercialLoginButton").onclick = async function (event) {
      event.preventDefault();
      await signIn();
    };

    document.getElementById("commercialSignupButton").onclick = async function (event) {
      event.preventDefault();
      await signUp();
    };
    document.getElementById("commercialWorkspaceButton").onclick = bootstrapWorkspace;

    showGate();

    try {
      const supabase = ensureClient();
      const { data } = await supabase.auth.getSession();

      if (!data.session) {
        return;
      }

      const user = (await supabase.auth.getUser()).data.user;
      await acceptPendingInvitations();
      context = await loadContext(user.id);

      if (!context) {
        document.getElementById("commercialWorkspaceFields").classList.add("visible");
        setMessage(labels.newWorkspace, "success");
        return;
      }

      await finishReady();
    } catch (error) {
      console.error("COMMERCIAL AUTH ERROR:", error);
      setMessage(error.message || labels.error, "error");
    }

  }

  window.SmartSalesAuth = Object.freeze({
    start,
    signOut,
    getClient: ensureClient,
    getContext: function () { return context; }
  });
})();
