(function () {
  "use strict";

  // The verified production domain stays on production.
  // Every other host (Vercel Preview, localhost, or direct deployment URL)
  // defaults to the isolated staging project. Never use a service-role key here.
  const isProduction =
    String(window.location.hostname || "").toLowerCase() ===
    "smart-sales-system-new.vercel.app";

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
