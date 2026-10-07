alter table public.sale_return_items
  add constraint sale_return_items_return_sale_item_unique
  unique (return_id, sale_item_id);

alter table public.purchase_return_items
  add constraint purchase_return_items_return_receipt_item_unique
  unique (purchase_return_id, purchase_receipt_item_id);
