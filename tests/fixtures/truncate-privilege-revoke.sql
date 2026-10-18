-- Candidate remediation logic tested in an isolated PostgreSQL fixture only.
-- This is deliberately not a Supabase migration and is not applied to production.
revoke truncate on table
  public.sales,
  public.sale_items,
  public.sale_returns,
  public.sale_return_items,
  public.customer_payments,
  public.customer_payment_allocations,
  public.purchase_receipts,
  public.purchase_receipt_items
from authenticated;
