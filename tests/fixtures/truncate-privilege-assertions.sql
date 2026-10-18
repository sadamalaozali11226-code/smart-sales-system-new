do $test$
declare
  v_table text;
  v_tables text[] := array[
    'sales',
    'sale_items',
    'sale_returns',
    'sale_return_items',
    'customer_payments',
    'customer_payment_allocations',
    'purchase_receipts',
    'purchase_receipt_items'
  ];
begin
  foreach v_table in array v_tables loop
    if has_table_privilege('authenticated', format('public.%I', v_table), 'TRUNCATE') then
      raise exception 'TRUNCATE unexpectedly remains granted to authenticated on public.%', v_table;
    end if;
  end loop;

  if not has_table_privilege('authenticated', 'public.sales', 'SELECT') then
    raise exception 'Narrow revocation unexpectedly removed SELECT from public.sales';
  end if;

  raise notice 'isolated truncate privilege revocation assertions passed';
end
$test$;
