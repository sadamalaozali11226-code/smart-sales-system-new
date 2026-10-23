\set ON_ERROR_STOP on
CREATE SCHEMA IF NOT EXISTS private;
CREATE TABLE public.purchase_receipts(id bigint PRIMARY KEY);
CREATE TABLE public.purchase_receipt_items(id bigint PRIMARY KEY);
CREATE TABLE public.supplier_payments(id bigint PRIMARY KEY);
CREATE TABLE public.supplier_payment_allocations(id bigint PRIMARY KEY);
CREATE TABLE public.purchase_returns(id bigint PRIMARY KEY);
CREATE TABLE public.purchase_return_items(id bigint PRIMARY KEY);
CREATE TABLE public.supplier_refunds(id bigint PRIMARY KEY);
