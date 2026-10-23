(function () {
  "use strict";

  // Keep production traffic pinned to the verified production project.
  // Any non-production hostname (Vercel Preview, localhost, etc.) uses staging.
  // This is a publishable client key, not a service-role secret.
  const productionHosts = new Set([
    "smart-sales-system-new.vercel.app",
    "smart-sales-system-new-my-project-3093.vercel.app",
    "smart-sales-system-new-git-main-my-project-3093.vercel.app"
  ]);
  const isProduction = productionHosts.has(
    String(window.location.hostname || "").toLowerCase()
  );

  const url = isProduction
    ? "https://kpllyyeirhdjwvkrwspg.supabase.co"
    : "https://jqedxgdstifezjrtgucw.supabase.co";
  const publishableKey = isProduction
    ? "sb_publishable_OCdRHiaZySGrsgNYV3w0jQ_bWSL1ACV"
    : "sb_publishable_aCesoZEa-JkUFaNUcX9u3g_jQZcs-jK";

  window.SmartSalesSupabase = Object.freeze({
    url,
    publishableKey,
    environment: isProduction ? "production" : "staging"
  });
})();
