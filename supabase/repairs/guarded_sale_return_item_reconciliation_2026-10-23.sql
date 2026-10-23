-- GUARDED HISTORICAL REPAIR RECORD — 2026-10-23.
-- This script documents the narrow correction for sale_return_items.id = 1.
-- It was already applied under guarded conditions; the current production value is 120.
-- DO NOT rerun against the current production state: the precondition deliberately expects refund_amount = 0 and will abort if it no longer matches.
-- This is NOT a schema migration and must never be applied automatically.

BEGIN;

DO $guarded_reconciliation$
DECLARE
  v_matches integer;
  v_updated integer;
  v_audit_id bigint;
BEGIN
  SELECT count(*)
    INTO v_matches
  FROM public.sale_return_items sri
  JOIN public.sale_returns sr ON sr.id = sri.return_id
  JOIN public.sale_items si ON si.id = sri.sale_item_id
  JOIN public.refunds r ON r.sale_id = sr.sale_id
  WHERE sri.id = 1
    AND sri.return_id = 1
    AND sri.sale_item_id = 29
    AND sri.product_id = 63
    AND sri.quantity = 1
    AND sri.unit_price = 120
    AND sri.refund_amount = 0
    AND sr.sale_id = 22
    AND sr.organization_id = '9e7c7504-0d5b-4589-84ac-f884b8a2712d'::uuid
    AND sr.store_id = '69d98dd5-b0c5-419d-819a-85a7d37a4511'::uuid
    AND sr.reason = 'اختبار مرتجع بيع'
    AND sr.notes = 'اختبار إعادة التكلفة إلى المخزون'
    AND si.sale_id = 22
    AND si.product_id = 63
    AND si.quantity = 3
    AND si.unit_price = 120
    AND si.discount = 0
    AND si.total = 360
    AND r.id = 2
    AND r.amount = 120
    AND r.reference = 'TEST-RETURN-001'
    AND r.organization_id = sr.organization_id
    AND r.store_id = sr.store_id
    AND r.reason = sr.reason
    AND (SELECT count(*) FROM public.sale_return_items WHERE return_id = 1) = 1
    AND (SELECT count(*) FROM public.refunds WHERE sale_id = 22) = 1;

  IF v_matches <> 1 THEN
    RAISE EXCEPTION 'Precondition failed: expected the exact known test-return mismatch; no repair applied.';
  END IF;

  UPDATE public.sale_return_items
     SET refund_amount = 120
   WHERE id = 1
     AND return_id = 1
     AND sale_item_id = 29
     AND quantity = 1
     AND unit_price = 120
     AND refund_amount = 0;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated <> 1 THEN
    RAISE EXCEPTION 'Guarded repair expected to update exactly one row; updated %.', v_updated;
  END IF;

  v_audit_id := private.write_audit_log(
    '9e7c7504-0d5b-4589-84ac-f884b8a2712d'::uuid,
    '69d98dd5-b0c5-419d-819a-85a7d37a4511'::uuid,
    'financial.reconciliation',
    'sale_return_item',
    '1',
    jsonb_build_object(
      'source_return_id', 1,
      'sale_id', 22,
      'sale_item_id', 29,
      'refund_id', 2,
      'previous_refund_amount', 0,
      'corrected_refund_amount', 120,
      'basis', 'one returned unit at 120.00 matches the linked 120.00 refund header and sale-line unit price',
      'repair_script', 'supabase/repairs/guarded_sale_return_item_reconciliation_2026-10-23.sql'
    )
  );

  IF (SELECT coalesce(sum(refund_amount), 0) FROM public.sale_return_items WHERE return_id = 1) <> 120
     OR (SELECT coalesce(sum(amount), 0) FROM public.refunds WHERE sale_id = 22) <> 120 THEN
    RAISE EXCEPTION 'Postcondition failed: item allocation and refund header do not reconcile.';
  END IF;
END;
$guarded_reconciliation$;

COMMIT;
