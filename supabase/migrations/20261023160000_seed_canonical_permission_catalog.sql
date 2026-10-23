-- Restore the canonical permission catalog required by organization bootstrap.
-- Idempotent: re-running this migration does not create duplicate permission codes.
begin;

insert into public.permissions (code, description) values
  ('customers.create', 'Create customers'),
  ('customers.read', 'View customers'),
  ('customers.update', 'Update customers'),
  ('expenses.create', 'Create expense records'),
  ('inventory.adjust', 'Adjust inventory quantities'),
  ('inventory.read', 'View inventory and stock movements'),
  ('members.manage', 'Manage organization members and assign roles'),
  ('payments.create', 'Record payments against sales'),
  ('payments.refund', 'Refund sale payments'),
  ('products.create', 'Create products'),
  ('products.read', 'View products'),
  ('products.update', 'Update products'),
  ('purchases.cancel', 'Cancel purchase receipts and reverse their financial and stock effects'),
  ('purchases.create', 'Create purchase receipts and receive stock'),
  ('purchases.view', 'View purchase receipts and balances'),
  ('reports.read', 'View reports and dashboards'),
  ('roles.manage', 'Manage organization roles and role permissions'),
  ('sales.cancel', 'Cancel sales invoices'),
  ('sales.create', 'Create sales invoices and record their initial payment'),
  ('sales.read', 'View sales invoices and sale details'),
  ('sales.update', 'Edit permitted sales information'),
  ('stores.manage', 'Manage organization stores and branch assignments'),
  ('supplier_payments.create', 'Record payments to suppliers and allocate them to purchase receipts'),
  ('suppliers.manage', 'Create and update suppliers'),
  ('suppliers.view', 'View suppliers')
on conflict (code) do update
set description = excluded.description;

commit;
