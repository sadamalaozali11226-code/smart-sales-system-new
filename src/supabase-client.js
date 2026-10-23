(function () {
  "use strict";

  // Only the canonical production hostname may connect to production.
  // Every preview, local, and alternate hostname is isolated to staging.
  const PRODUCTION_HOSTNAMES = new Set([
    "smart-sales-system-new.vercel.app"
  ]);
  const isProduction = PRODUCTION_HOSTNAMES.has(
    String(window.location && window.location.hostname || "").toLowerCase()
  );

  const url = isProduction
    ? "https://kpllyyeirhdjwvkrwspg.supabase.co"
    : "https://jqedxgdstifezjrtgucw.supabase.co";
  const publishableKey = isProduction
    ? "sb_publishable_OCdRHiaZySGrsgNYV3w0jQ_bWSL1ACV"
    : "sb_publishable_aCesoZEa-JkUFaNUcX9u3g_jQZcs-jK";

  window.SmartSalesSupabase = Object.freeze({
    url,
    publishableKey
  });
})();
