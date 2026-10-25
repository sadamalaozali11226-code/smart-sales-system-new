-- Keep fully returned invoices in gross-sales aggregates while reporting refunds separately.
-- This migration changes report function definitions only; it does not alter financial records.
-- Guard the expected source predicates so unexpected definitions fail without partial changes.

do $migration$
declare
  v_definition text;
  v_old_predicate constant text := 's.status in (''completed'',''partially_returned'')';
  v_new_predicate constant text := 's.status in (''completed'',''partially_returned'',''fully_returned'')';
  v_occurrences integer;
begin
  select pg_get_functiondef(
    'private.profitability_summary(uuid,uuid,date,date)'::regprocedure
  )
  into v_definition;

  if v_definition is null then
    raise exception 'Expected function private.profitability_summary(uuid,uuid,date,date) was not found';
  end if;

  v_occurrences :=
    (length(v_definition) - length(replace(v_definition, v_old_predicate, '')))
    / length(v_old_predicate);

  if v_occurrences <> 1 then
    raise exception 'Expected 1 returned-sales predicate in private.profitability_summary; found %; no change applied', v_occurrences;
  end if;

  v_definition := replace(v_definition, v_old_predicate, v_new_predicate);

  if position(v_old_predicate in v_definition) > 0 then
    raise exception 'Validation failed for private.profitability_summary; no change applied';
  end if;

  execute v_definition;
end;
$migration$;

do $migration$
declare
  v_definition text;
  v_old_predicate constant text := 's.status in (''completed'',''partially_returned'')';
  v_new_predicate constant text := 's.status in (''completed'',''partially_returned'',''fully_returned'')';
  v_occurrences integer;
begin
  select pg_get_functiondef(
    'private.commercial_reports_summary(uuid,uuid,date,date)'::regprocedure
  )
  into v_definition;

  if v_definition is null then
    raise exception 'Expected function private.commercial_reports_summary(uuid,uuid,date,date) was not found';
  end if;

  v_occurrences :=
    (length(v_definition) - length(replace(v_definition, v_old_predicate, '')))
    / length(v_old_predicate);

  if v_occurrences <> 7 then
    raise exception 'Expected 7 returned-sales predicates in private.commercial_reports_summary; found %; no change applied', v_occurrences;
  end if;

  v_definition := replace(v_definition, v_old_predicate, v_new_predicate);

  if position(v_old_predicate in v_definition) > 0 then
    raise exception 'Validation failed for private.commercial_reports_summary; no change applied';
  end if;

  execute v_definition;
end;
$migration$;
