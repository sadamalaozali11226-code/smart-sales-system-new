-- Staging-only correction after the first catalog snapshot export.
-- Drop/recreate policies to match the source project's actual policy commands.
DROP POLICY IF EXISTS "audit_logs_select_org_members" ON "public"."audit_logs";
DROP POLICY IF EXISTS "customer_payment_allocations_select_member" ON "public"."customer_payment_allocations";
DROP POLICY IF EXISTS "customer_payments_select_member" ON "public"."customer_payments";
DROP POLICY IF EXISTS "customers_select_member" ON "public"."customers";
DROP POLICY IF EXISTS "expenses_org_access" ON "public"."expenses";
DROP POLICY IF EXISTS "inventory_movements_select_store_member" ON "public"."inventory_movements";
DROP POLICY IF EXISTS "member_stores_select_member" ON "public"."member_stores";
DROP POLICY IF EXISTS "deny direct organization invitation access" ON "public"."organization_invitations";
DROP POLICY IF EXISTS "organization_members_select_member" ON "public"."organization_members";
DROP POLICY IF EXISTS "organizations_select_member" ON "public"."organizations";
DROP POLICY IF EXISTS "payments_select_sale_member" ON "public"."payments";
DROP POLICY IF EXISTS "permissions_select_authenticated" ON "public"."permissions";
DROP POLICY IF EXISTS "products_select_member" ON "public"."products";
DROP POLICY IF EXISTS "purchase_receipt_items_select_member" ON "public"."purchase_receipt_items";
DROP POLICY IF EXISTS "purchase_receipts_select_member" ON "public"."purchase_receipts";
DROP POLICY IF EXISTS "purchase_return_items_org_access" ON "public"."purchase_return_items";
DROP POLICY IF EXISTS "purchase_returns_org_access" ON "public"."purchase_returns";
DROP POLICY IF EXISTS "refunds_select_org_store_members" ON "public"."refunds";
DROP POLICY IF EXISTS "role_permissions_select_member" ON "public"."role_permissions";
DROP POLICY IF EXISTS "roles_select_member" ON "public"."roles";
DROP POLICY IF EXISTS "sale_items_select_sale_member" ON "public"."sale_items";
DROP POLICY IF EXISTS "sale_return_items_select_member" ON "public"."sale_return_items";
DROP POLICY IF EXISTS "sale_returns_select_member" ON "public"."sale_returns";
DROP POLICY IF EXISTS "sales_select_store_member" ON "public"."sales";
DROP POLICY IF EXISTS "stock_transfers_select_member" ON "public"."stock_transfers";
DROP POLICY IF EXISTS "store_products_select_member" ON "public"."store_products";
DROP POLICY IF EXISTS "stores_select_member" ON "public"."stores";
DROP POLICY IF EXISTS "deny direct supplier allocation access" ON "public"."supplier_payment_allocations";
DROP POLICY IF EXISTS "deny direct supplier payment access" ON "public"."supplier_payments";
DROP POLICY IF EXISTS "supplier_refunds_org_access" ON "public"."supplier_refunds";
DROP POLICY IF EXISTS "deny direct supplier access" ON "public"."suppliers";

CREATE POLICY "audit_logs_select_org_members" ON "public"."audit_logs" AS PERMISSIVE FOR SELECT TO "authenticated" USING (((organization_id IS NOT NULL) AND private.is_org_member(organization_id)));

CREATE POLICY "customer_payment_allocations_select_member" ON "public"."customer_payment_allocations" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM customer_payments cp
  WHERE ((cp.id = customer_payment_allocations.customer_payment_id) AND private.is_org_store_member(cp.organization_id, cp.store_id)))));

CREATE POLICY "customer_payments_select_member" ON "public"."customer_payments" AS PERMISSIVE FOR SELECT TO "authenticated" USING (private.is_org_store_member(organization_id, store_id));

CREATE POLICY "customers_select_member" ON "public"."customers" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT private.is_org_member(customers.organization_id) AS is_org_member));

CREATE POLICY "expenses_org_access" ON "public"."expenses" AS PERMISSIVE FOR ALL TO "authenticated" USING (private.is_org_store_member(organization_id, store_id)) WITH CHECK (private.is_org_store_member(organization_id, store_id));

CREATE POLICY "inventory_movements_select_store_member" ON "public"."inventory_movements" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT private.is_org_store_member(inventory_movements.organization_id, inventory_movements.store_id) AS is_org_store_member));

CREATE POLICY "member_stores_select_member" ON "public"."member_stores" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM (organization_members om
     JOIN stores st ON ((st.organization_id = om.organization_id)))
  WHERE ((om.id = member_stores.member_id) AND (st.id = member_stores.store_id) AND private.is_org_member(om.organization_id)))));

CREATE POLICY "deny direct organization invitation access" ON "public"."organization_invitations" AS PERMISSIVE FOR ALL TO "authenticated" USING (false) WITH CHECK (false);

CREATE POLICY "organization_members_select_member" ON "public"."organization_members" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT private.is_org_member(organization_members.organization_id) AS is_org_member));

CREATE POLICY "organizations_select_member" ON "public"."organizations" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT private.is_org_member(organizations.id) AS is_org_member));

CREATE POLICY "payments_select_sale_member" ON "public"."payments" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT private.can_access_sale(payments.sale_id) AS can_access_sale));

CREATE POLICY "permissions_select_authenticated" ON "public"."permissions" AS PERMISSIVE FOR SELECT TO "authenticated" USING (true);

CREATE POLICY "products_select_member" ON "public"."products" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT private.is_org_member(products.organization_id) AS is_org_member));

CREATE POLICY "purchase_receipt_items_select_member" ON "public"."purchase_receipt_items" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM purchase_receipts r
  WHERE ((r.id = purchase_receipt_items.receipt_id) AND private.is_org_store_member(r.organization_id, r.store_id)))));

CREATE POLICY "purchase_receipts_select_member" ON "public"."purchase_receipts" AS PERMISSIVE FOR SELECT TO "authenticated" USING (private.is_org_store_member(organization_id, store_id));

CREATE POLICY "purchase_return_items_org_access" ON "public"."purchase_return_items" AS PERMISSIVE FOR ALL TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM purchase_returns pr
  WHERE ((pr.id = purchase_return_items.purchase_return_id) AND private.is_org_store_member(pr.organization_id, pr.store_id))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM purchase_returns pr
  WHERE ((pr.id = purchase_return_items.purchase_return_id) AND private.is_org_store_member(pr.organization_id, pr.store_id)))));

CREATE POLICY "purchase_returns_org_access" ON "public"."purchase_returns" AS PERMISSIVE FOR ALL TO "authenticated" USING (private.is_org_store_member(organization_id, store_id)) WITH CHECK (private.is_org_store_member(organization_id, store_id));

CREATE POLICY "refunds_select_org_store_members" ON "public"."refunds" AS PERMISSIVE FOR SELECT TO "authenticated" USING (private.is_org_store_member(organization_id, store_id));

CREATE POLICY "role_permissions_select_member" ON "public"."role_permissions" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM roles r
  WHERE ((r.id = role_permissions.role_id) AND private.is_org_member(r.organization_id)))));

CREATE POLICY "roles_select_member" ON "public"."roles" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT private.is_org_member(roles.organization_id) AS is_org_member));

CREATE POLICY "sale_items_select_sale_member" ON "public"."sale_items" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT private.can_access_sale(sale_items.sale_id) AS can_access_sale));

CREATE POLICY "sale_return_items_select_member" ON "public"."sale_return_items" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM sale_returns r
  WHERE ((r.id = sale_return_items.return_id) AND private.is_org_store_member(r.organization_id, r.store_id)))));

CREATE POLICY "sale_returns_select_member" ON "public"."sale_returns" AS PERMISSIVE FOR SELECT TO "authenticated" USING (private.is_org_store_member(organization_id, store_id));

CREATE POLICY "sales_select_store_member" ON "public"."sales" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT private.is_org_store_member(sales.organization_id, sales.store_id) AS is_org_store_member));

CREATE POLICY "stock_transfers_select_member" ON "public"."stock_transfers" AS PERMISSIVE FOR SELECT TO "authenticated" USING ((private.is_org_store_member(organization_id, from_store_id) OR private.is_org_store_member(organization_id, to_store_id)));

CREATE POLICY "store_products_select_member" ON "public"."store_products" AS PERMISSIVE FOR SELECT TO "authenticated" USING (private.is_store_member(store_id));

CREATE POLICY "stores_select_member" ON "public"."stores" AS PERMISSIVE FOR SELECT TO "authenticated" USING (( SELECT private.is_org_member(stores.organization_id) AS is_org_member));

CREATE POLICY "deny direct supplier allocation access" ON "public"."supplier_payment_allocations" AS PERMISSIVE FOR ALL TO "authenticated" USING (false) WITH CHECK (false);

CREATE POLICY "deny direct supplier payment access" ON "public"."supplier_payments" AS PERMISSIVE FOR ALL TO "authenticated" USING (false) WITH CHECK (false);

CREATE POLICY "supplier_refunds_org_access" ON "public"."supplier_refunds" AS PERMISSIVE FOR ALL TO "authenticated" USING (private.is_org_store_member(organization_id, store_id)) WITH CHECK (private.is_org_store_member(organization_id, store_id));

CREATE POLICY "deny direct supplier access" ON "public"."suppliers" AS PERMISSIVE FOR ALL TO "authenticated" USING (false) WITH CHECK (false);
