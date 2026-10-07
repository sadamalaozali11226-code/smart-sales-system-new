-- Harden the private document-number sequence table.
-- Number allocation is performed by SECURITY DEFINER routines; the table itself
-- must not be directly exposed to client roles.
alter table private.document_sequences enable row level security;
