const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const apiUrl = process.env.SUPABASE_API_URL;
const anonKey = process.env.SUPABASE_ANON_KEY;
const jwtSecret = process.env.SUPABASE_JWT_SECRET;
const authId = "00000000-0000-0000-0000-000000000001";
const organizationId = "20000000-0000-0000-0000-000000000001";
const storeId = "30000000-0000-0000-0000-000000000001";
const idempotencyKey = "90000000-0000-4000-8000-000000000001";

for (const [name, value] of Object.entries({ apiUrl, anonKey, jwtSecret })) {
  if (!value) throw new Error(`Missing required local Supabase environment value: ${name}`);
}

function base64url(value) {
  return Buffer.from(value).toString("base64url");
}

function createAuthenticatedJwt() {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const payload = base64url(JSON.stringify({
    aud: "authenticated",
    role: "authenticated",
    sub: authId,
    iat: now,
    exp: now + 300
  }));
  const unsigned = `${header}.${payload}`;
  const signature = crypto.createHmac("sha256", jwtSecret).update(unsigned).digest("base64url");
  return `${unsigned}.${signature}`;
}

async function createSale(token) {
  const baseUrl = apiUrl.endsWith("/") ? apiUrl.slice(0, -1) : apiUrl;
  const response = await fetch(`${baseUrl}/rest/v1/rpc/create_sale_transaction`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      p_idempotency_key: idempotencyKey,
      p_organization_id: organizationId,
      p_store_id: storeId,
      p_invoice_number: null,
      p_customer_id: null,
      p_items: [{ product_id: 1, quantity: 2, discount: 0 }],
      p_discount: 0,
      p_tax: 0,
      p_paid_amount: 0,
      p_payment_method: "cash",
      p_reference: null,
      p_notes: null
    })
  });
  const raw = await response.text();
  if (!response.ok) {
    throw new Error(`PostgREST sale RPC returned HTTP ${response.status}: ${raw}`);
  }
  return JSON.parse(raw);
}

(async () => {
  const token = createAuthenticatedJwt();
  const first = await createSale(token);
  const retry = await createSale(token);

  assert.deepEqual(retry, first, "PostgREST retry must return the original sale response");
  assert.ok(first && first.sale_id != null, "PostgREST RPC response must contain sale_id");
  assert.ok(first.invoice_number, "PostgREST RPC response must contain invoice_number");

  process.stdout.write(JSON.stringify({
    test: "postgrest-sale-idempotency",
    passed: true,
    sale_id: first.sale_id,
    invoice_number: first.invoice_number
  }) + String.fromCharCode(10));
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
