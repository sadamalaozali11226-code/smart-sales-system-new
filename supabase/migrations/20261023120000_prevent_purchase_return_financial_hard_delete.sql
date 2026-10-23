-- Prevent hard deletion of purchase-return and supplier-refund financial history.
-- Use the existing shared guard; cancellation/reversal workflows remain the supported path.

DO $preflight$
BEGIN
  IF to_regprocedure('private.prevent_supplier_purchase_financial_hard_delete()') IS NULL THEN
    RAISE EXCEPTION 'Required hard-delete guard function is missing; apply 20261009205628_prevent_hard_delete_supplier_purchase_financial_records.sql first.';
  END IF;
  IF to_regclass('public.purchase_returns') IS NULL
     OR to_regclass('public.purchase_return_items') IS NULL
     OR to_regclass('public.supplier_refunds') IS NULL THEN
    RAISE EXCEPTION 'Required purchase-return/refund tables are missing; refusing to install partial hard-delete protection.';
  END IF;
END;
$preflight$;

DROP TRIGGER IF EXISTS prevent_purchase_return_hard_delete ON public.purchase_returns;
CREATE TRIGGER prevent_purchase_return_hard_delete
BEFORE DELETE ON public.purchase_returns
FOR EACH ROW EXECUTE FUNCTION private.prevent_supplier_purchase_financial_hard_delete();

DROP TRIGGER IF EXISTS prevent_purchase_return_item_hard_delete ON public.purchase_return_items;
CREATE TRIGGER prevent_purchase_return_item_hard_delete
BEFORE DELETE ON public.purchase_return_items
FOR EACH ROW EXECUTE FUNCTION private.prevent_supplier_purchase_financial_hard_delete();

DROP TRIGGER IF EXISTS prevent_supplier_refund_hard_delete ON public.supplier_refunds;
CREATE TRIGGER prevent_supplier_refund_hard_delete
BEFORE DELETE ON public.supplier_refunds
FOR EACH ROW EXECUTE FUNCTION private.prevent_supplier_purchase_financial_hard_delete();
