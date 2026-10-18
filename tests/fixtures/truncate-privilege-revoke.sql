-- Candidate remediation logic tested in an isolated PostgreSQL fixture only.
-- This is deliberately not a Supabase migration and is not applied to production.
revoke truncate on table
  audit_truncate_test.sales,
  audit_truncate_test.sale_items,
  audit_truncate_test.sale_returns,
  audit_truncate_test.sale_return_items,
  audit_truncate_test.customer_payments,
  audit_truncate_test.customer_payment_allocations,
  audit_truncate_test.purchase_receipts,
  audit_truncate_test.purchase_receipt_items
from authenticated;
