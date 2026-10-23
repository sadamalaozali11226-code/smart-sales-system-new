\set ON_ERROR_STOP on
BEGIN;

INSERT INTO public.products(id,organization_id,name,price)
VALUES (1,'22000000-0000-4000-8000-000000000001','Return fixture product',10);
INSERT INTO public.sales(id,invoice_number,subtotal,discount,tax,total,payment_status,status,organization_id,store_id)
VALUES (1,'RET-FIXTURE-001',20,0,0,20,'paid','completed','22000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000001');
INSERT INTO public.sale_items(id,sale_id,product_id,product_name,unit_price,quantity,discount,total,unit_cost,cost_total)
VALUES (1,1,1,'Return fixture product',10,2,0,20,4,8);
INSERT INTO public.store_products(id,store_id,product_id,quantity,average_cost,cost_known)
VALUES (1,'33000000-0000-4000-8000-000000000001',1,3,4,true);
INSERT INTO public.payments(id,sale_id,amount,payment_method) VALUES (1,1,20,'cash');
INSERT INTO public.inventory_movements(id,product_id,movement_type,quantity_change,reference_type,reference_id,organization_id,store_id)
VALUES (1,1,'sale',-2,'sale',1,'22000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000001');
INSERT INTO public.audit_logs(id,organization_id,store_id,action,entity_type,entity_id,metadata)
VALUES (1,'22000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000001','sale.created','sale','1','{}'::jsonb);

-- Explicit fixture IDs must advance identity sequences before RPC-generated rows.
SELECT setval(pg_get_serial_sequence('public.inventory_movements','id'),
              (SELECT max(id) FROM public.inventory_movements), true);
SELECT setval(pg_get_serial_sequence('public.audit_logs','id'),
              (SELECT max(id) FROM public.audit_logs), true);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000001',true);
SELECT set_config('test.is_org_store_member','true',true);
SELECT set_config('test.has_org_permission','true',true);

DO $return_test$
DECLARE v_return jsonb; v_rejected boolean:=false;
BEGIN
  v_return := public.return_sale_items(
    '22000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000001',1,
    '[{"sale_item_id":1,"quantity":1,"refund_amount":10}]'::jsonb,
    'valid partial return','matching line allocation',10,'cash','RET-FIXTURE-001'
  );
  IF (v_return->>'refund_amount')::numeric<>10 OR (v_return->>'total_refunded_for_sale')::numeric<>10 THEN
    RAISE EXCEPTION 'FAIL: valid return response totals do not match';
  END IF;

  BEGIN
    PERFORM public.return_sale_items(
      '22000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000001',1,
      '[{"sale_item_id":1,"quantity":1,"refund_amount":0}]'::jsonb,
      'invalid legacy payload','header refund without item allocation',5,'cash','RET-FIXTURE-002'
    );
  EXCEPTION WHEN OTHERS THEN
    IF position('sum of item refund allocations must equal refund amount' in SQLERRM)>0 THEN
      v_rejected:=true;
    ELSE
      RAISE;
    END IF;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'FAIL: mismatched header and line refund was accepted'; END IF;
END;
$return_test$;

RESET ROLE;

DO $assertions$
BEGIN
  IF (SELECT count(*) FROM public.sale_returns)<>1 THEN RAISE EXCEPTION 'FAIL: rejected request wrote another return'; END IF;
  IF (SELECT count(*) FROM public.sale_return_items)<>1 OR (SELECT sum(refund_amount) FROM public.sale_return_items)<>10 THEN
    RAISE EXCEPTION 'FAIL: item refund allocation mismatch';
  END IF;
  IF (SELECT count(*) FROM public.refunds)<>1 OR (SELECT sum(amount) FROM public.refunds)<>10 THEN
    RAISE EXCEPTION 'FAIL: refund header mismatch';
  END IF;
  IF (SELECT quantity FROM public.store_products WHERE id=1)<>4 THEN RAISE EXCEPTION 'FAIL: return inventory quantity mismatch'; END IF;
  IF (SELECT count(*) FROM public.inventory_movements)<>2 THEN RAISE EXCEPTION 'FAIL: expected one sale and one return movement'; END IF;
  IF (SELECT count(*) FROM public.audit_logs)<>2 THEN RAISE EXCEPTION 'FAIL: expected one sale and one return audit event'; END IF;
  IF (SELECT status FROM public.sales WHERE id=1)<>'partially_returned' THEN RAISE EXCEPTION 'FAIL: sale return status mismatch'; END IF;
END;
$assertions$;

ROLLBACK;
SELECT 'PASS: return refund allocation invariant, rollback behavior, stock, movement, audit and sale status assertions.' AS result;
