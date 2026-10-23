# Financial reconciliation still required — 2026-10-23

This reconciliation record includes one narrowly guarded production correction: sale-return item ID 1 was updated from refund_amount 0 to 120 after matching it to the single returned unit and the refund header. Supplier payment rows were not changed.

## Supplier payments

The current production records show five supplier payments, totaling 2,865, with 1,400 allocated and 1,465 unallocated.

| Payment ID | Amount | Payment method | Recorded note/reference | Allocations | Evidence currently available |
|---:|---:|---|---|---:|---|
| 1 | 780 | bank | `Initial payment for purchase ١` | 0 | No purchase receipt with ID 1 exists in the current `purchase_receipts` table. |
| 2 | 10 | cash | No note/reference | 0 | No receipt allocation or direct receipt reference found. |
| 3 | 675 | card | No note/reference | 0 | No receipt allocation or direct receipt reference found. |
| 4 | 900 | cash | `TEST-001`; note refers to `PUR-000004` | 900 to receipt 4 | Receipt 4 is `PUR-000004`, total 900, status completed, payment status paid. |
| 5 | 500 | cash | `TEST-PUR-002`; note refers to `PUR-000005` | 500 to receipt 5 | Receipt 5 is `PUR-000005`, total 500, status completed, payment status paid. |

The three unallocated payments total 1,465. Receipts 1–3 are absent from the current receipt table; receipts 4 and 5 are present. This is not enough evidence to determine whether payments 1–3 are orphaned payments, belong to deleted receipts, or require another historical accounting treatment. Do not allocate them to receipts 4 or 5 by inference.

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
