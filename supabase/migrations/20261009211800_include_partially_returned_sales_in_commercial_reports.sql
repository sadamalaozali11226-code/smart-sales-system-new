-- Include partially returned sales in commercial report aggregates without changing financial records.
-- This migration updates only the existing private report function definition.
-- It fails closed if the expected source predicate count differs from the reviewed baseline.

do $migration$
declare
  v_definition text;
  v_old_predicate constant text := 's.status=''completed''';
  v_new_predicate constant text := 's.status in (''completed'',''partially_returned'')';
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
    raise exception 'Expected 7 completed-only sales predicates in private.commercial_reports_summary; found %; no change applied', v_occurrences;
  end if;

  v_definition := replace(v_definition, v_old_predicate, v_new_predicate);

  if position(v_old_predicate in v_definition) > 0 then
    raise exception 'Validation failed: completed-only sales predicates remain; no change applied';
  end if;

  execute v_definition;
end;
$migration$;
