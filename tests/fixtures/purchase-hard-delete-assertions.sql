\set ON_ERROR_STOP on
BEGIN;
INSERT INTO public.purchase_receipts VALUES (1);
INSERT INTO public.purchase_receipt_items VALUES (1);
INSERT INTO public.supplier_payments VALUES (1);
INSERT INTO public.supplier_payment_allocations VALUES (1);
INSERT INTO public.purchase_returns VALUES (1);
INSERT INTO public.purchase_return_items VALUES (1);
INSERT INTO public.supplier_refunds VALUES (1);

DO $hard_delete_tests$
BEGIN
  BEGIN DELETE FROM public.purchase_receipts WHERE id=1; RAISE EXCEPTION 'FAIL: purchase_receipts delete was not blocked'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
  IF NOT EXISTS (SELECT 1 FROM public.purchase_receipts WHERE id=1) THEN RAISE EXCEPTION 'FAIL: purchase receipt row was removed'; END IF;

  BEGIN DELETE FROM public.purchase_receipt_items WHERE id=1; RAISE EXCEPTION 'FAIL: purchase_receipt_items delete was not blocked'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
  IF NOT EXISTS (SELECT 1 FROM public.purchase_receipt_items WHERE id=1) THEN RAISE EXCEPTION 'FAIL: purchase receipt item row was removed'; END IF;

  BEGIN DELETE FROM public.supplier_payments WHERE id=1; RAISE EXCEPTION 'FAIL: supplier_payments delete was not blocked'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
  IF NOT EXISTS (SELECT 1 FROM public.supplier_payments WHERE id=1) THEN RAISE EXCEPTION 'FAIL: supplier payment row was removed'; END IF;

  BEGIN DELETE FROM public.supplier_payment_allocations WHERE id=1; RAISE EXCEPTION 'FAIL: supplier_payment_allocations delete was not blocked'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
  IF NOT EXISTS (SELECT 1 FROM public.supplier_payment_allocations WHERE id=1) THEN RAISE EXCEPTION 'FAIL: supplier payment allocation row was removed'; END IF;

  BEGIN DELETE FROM public.purchase_returns WHERE id=1; RAISE EXCEPTION 'FAIL: purchase_returns delete was not blocked'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
  IF NOT EXISTS (SELECT 1 FROM public.purchase_returns WHERE id=1) THEN RAISE EXCEPTION 'FAIL: purchase return row was removed'; END IF;

  BEGIN DELETE FROM public.purchase_return_items WHERE id=1; RAISE EXCEPTION 'FAIL: purchase_return_items delete was not blocked'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
  IF NOT EXISTS (SELECT 1 FROM public.purchase_return_items WHERE id=1) THEN RAISE EXCEPTION 'FAIL: purchase return item row was removed'; END IF;

  BEGIN DELETE FROM public.supplier_refunds WHERE id=1; RAISE EXCEPTION 'FAIL: supplier_refunds delete was not blocked'; EXCEPTION WHEN SQLSTATE '55000' THEN NULL; END;
  IF NOT EXISTS (SELECT 1 FROM public.supplier_refunds WHERE id=1) THEN RAISE EXCEPTION 'FAIL: supplier refund row was removed'; END IF;
END;
$hard_delete_tests$;
ROLLBACK;
SELECT 'PASS: hard-delete guard blocks all seven supplier purchase/return financial tables; fixture rolled back.' AS result;
