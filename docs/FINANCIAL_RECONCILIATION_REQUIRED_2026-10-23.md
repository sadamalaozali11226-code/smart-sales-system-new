# Financial reconciliation still required — 2026-10-23

This reconciliation record includes one narrowly guarded production correction: sale-return item ID 1 was updated from refund_amount 0 to 120 after matching it to the single returned unit and the refund header. Supplier payment rows were not changed.

## Supplier payments

The current production records show five supplier payments, totaling 2,865, with 1,400 currently allocated and 1,465 unallocated. Read-only audit evidence now identifies the likely historical receipt links for the three unallocated payments, but the original receipt headers and line items are missing.

| Payment ID | Amount | Method | Current note/reference | Current allocations | Historical evidence |
|---:|---:|---|---|---:|---|
| 1 | 780 | bank | `Initial payment for purchase ١` | 0 | Audit log 16 records purchase receipt ID 1, receipt number `١`, subtotal 780, tax 10, total 790, two items, and `paid_amount=780` at the same timestamp as this payment. |
| 2 | 10 | cash | None | 0 | Audit log 17 records `supplier.payment_recorded` for payment ID 2 with amount 10, allocated 10, unallocated 0 at 2026-10-05 23:22 UTC. At that time receipt 1 (total 790, initial paid amount 780) existed; receipt 2 was not created until 23:56 UTC. This strongly indicates the 10 completed the first receipt's 790 balance. |
| 3 | 675 | card | None | 0 | Audit log 19 records `supplier.payment_recorded` for payment ID 3 with amount 675, allocated 675, unallocated 0 at 2026-10-05 23:58 UTC. Receipt 2 had been created at 23:56 UTC with total 675. This strongly links payment 3 to receipt 2. |
| 4 | 900 | cash | `TEST-001`; note refers to `PUR-000004` | 900 to receipt 4 | Receipt 4 is `PUR-000004`, total 900, status completed, payment status paid. |
| 5 | 500 | cash | `TEST-PUR-002`; note refers to `PUR-000005` | 500 to receipt 5 | Receipt 5 is `PUR-000005`, total 500, status completed, payment status paid. |

The audit evidence reconciles the unallocated amount at the header level: payments 1 and 2 sum to receipt 1's historical total of 790, and payment 3 equals receipt 2's historical total of 675. Receipt 3 was separately recorded as total 448 and later cancelled as an unpaid invoice; it does not correspond to any of the three payment rows.

However, `purchase_receipts` and `purchase_receipt_items` currently contain no rows for IDs 1–3, and there are no retained purchase-receipt inventory movements for those IDs. The audit logs preserve receipt totals and item counts, but not the product IDs, quantities, or unit costs needed to reconstruct the line items. The current FK from `supplier_payment_allocations.purchase_receipt_id` uses `ON DELETE RESTRICT`; therefore the current absence of allocation rows cannot safely be explained as a simple cascade from receipt deletion. The allocation rows may have been removed separately or the old audit metadata may not fully reflect the surviving allocation table. No deletion event explains that gap.

**Do not allocate payments 1–3 to receipts 4 or 5.** Recreating operational receipts 1 and 2 with no line items would leave purchase totals, inventory, and reporting inconsistent. The safe resolution is to recover a backup/source export containing the original receipt lines and allocation rows, or have the accounting owner formally classify these as legacy payments against deleted receipts and approve a documented non-operational archival treatment. No receipt header, line item, allocation, or payment amount was recreated or changed in this work.

Receipt 5 also has a completed purchase return of 100 and a linked supplier refund record of 100. The existing payment allocation is 500. The intended business meaning of the refund/return balance formula should be confirmed by the accounting owner before changing any historical amount or payment status.

## Sale return

A read-only production recheck on 2026-10-23 now shows the historical line allocation is reconciled:
- Sale return header ID 1 for sale ID 22, reason `اختبار مرتجع بيع`, note `اختبار إعادة التكلفة إلى المخزون`.
- Sale return item ID 1 references sale item ID 29, product ID 63, quantity 1, unit price 120, and currently records `refund_amount = 120`.
- The source sale item has quantity 3, unit price 120, total 360, and no item discount.
- The linked refund record is ID 2, amount 120, reference `TEST-RETURN-001`, with the same return reason. The current item allocation total and refund header total are both 120.
- Audit log ID 94 records a `financial.reconciliation` event at `2026-10-23T00:37:43.892407+00:00`, noting the previous value 0 and corrected value 120. Its `actor_user_id` is null. **The update was executed as part of this repair session** under a guarded transaction with an audit record. The SQL session did not carry an authenticated human user ID, so `actor_user_id` is null; the audit event records the reason, evidence, prior value, and corrected value.
- A guarded, reproducible SQL record is preserved at `supabase/repairs/guarded_sale_return_item_reconciliation_2026-10-23.sql`. It deliberately requires the old value 0 and exact source identifiers; against the current production state it aborts without changes.

The historical sale-return line/header mismatch is therefore no longer present in the current read-only state. The new database migration remains useful because it rejects future RPC calls where the header refund and item-level allocations do not match.

## Required evidence and approval

Before any further production financial data repair:
1. Confirm the business meaning of supplier refunds and the intended net balance formula.
2. Find source receipts, payment vouchers, or accounting entries for supplier payments 1–3.
3. The test-return line was already corrected to 120 under guarded conditions; do not change it again unless source documentation contradicts the recorded sale line and refund header.
4. Approve any exact row-level changes for supplier payments and the post-repair reconciliation checks.

After approval, repairs must be narrowly guarded by primary keys and expected current values, run with a backup and transaction, and followed by checks of payment totals, allocations, receipt balances, return totals, and inventory movements. No historical amount should be inferred solely to make totals agree.
