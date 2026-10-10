# متابعة مطابقة الترحيلات وبوابات الإطلاق

تاريخ الفحص: 2026-10-10  
مرجع الإنتاج الذي جرى تثبيته: `087585f097fd7524c3fc5a234df6e35fb3459c94`  
النطاق: جرد أسماء/إصدارات فقط، قراءة دون تعديل قاعدة البيانات.

## النتيجة الأولية

- ملفات SQL في `supabase/migrations` بالمستودع: **38**.
- سجلات الترحيل في Supabase الإنتاجي: **56**.
- تطابق أولي بالرقم أو الاسم بعد إزالة بادئة الإصدار: **24**.
- ملفات مستودع لم يعثر الجرد على سجل مقابل لها بالرقم أو الاسم: **14**.
- سجلات قاعدة بيانات لم يعثر الجرد على ملف مطابق لها بالرقم أو الاسم: **32**.

**هذه مقارنة أسماء وليست إثباتًا بأن 32 ترحيلًا غائب فعليًا أو أن 14 ترحيلًا لم يُطبق.** أسماء وإصدارات عدة تغيّرت، وقد تحتوي الملفات الحالية على بدائل أو إصلاحات لاحقة. يلزم مقارنة تعريفات الدوال والجداول والسياسات والفهارس الفعلية مع محتوى كل ترحيل، وتحديد ترتيب التنفيذ وأثره قبل تقرير أي تسوية.

## ملفات المستودع التي لم يطابقها الجرد الاسمي

```text
20261006202000_harden_sales_numbering_and_payments.sql
20261006210000_harden_sale_returns.sql
20261006213000_harden_sale_cancellation.sql
20261006220000_add_purchase_returns.sql
20261006230000_add_expenses.sql
20261006233000_add_profitability_reporting.sql
20261006234000_correct_profitability_revenue.sql
20261007001500_add_commercial_reports.sql
20261007010000_harden_public_rpc_execute_privileges.sql
20261007012000_harden_purchase_return_numbering_privilege.sql
20261007014000_harden_product_update_and_purchase_read_helpers.sql
20261007032000_enforce_supplier_payment_allocation_integrity.sql
20261008000000_enable_document_sequences_rls.sql
20261008145700_harden_member_admin_search_path.sql
```

## سجلات قاعدة البيانات التي لم يطابقها الجرد الاسمي

```text
20261003184923_add_tenant_scope_to_core_tables
20261003185145_add_authorization_helpers
20261003185423_harden_private_authorization_helpers
20261003185440_add_tenant_select_rls_policies
20261003185912_create_private_sale_transaction
20261003190151_add_permission_catalog_and_checker
20261003190217_enforce_sales_create_permission
20261003190424_add_secure_organization_bootstrap
20261005092546_grant_authenticated_execute_private_bootstrap
20261005110643_grant_authenticated_execute_record_sale_payment
20261005114338_add_secure_product_update
20261005221342_add_supplier_purchase_financial_schema
20261005221353_lock_supplier_tables_for_rpc_access
20261005221855_add_supplier_purchase_permissions
20261005221915_add_supplier_purchase_core_rpcs
20261005221936_add_supplier_payment_rpc
20261005222352_add_supplier_purchase_read_rpcs
20261005222452_add_purchase_payment_balances_to_read_rpc
20261005223015_add_safe_purchase_cancellation
20261006144126_fix_purchase_cancellation_inventory_movement_type
20261006230154_20261007030000_fix_profitability_rpc_execute_privilege
20261006230325_20261007032000_add_profitability_report_v2_rpc
20261006230819_20261007033000_fix_profitability_return_status_column
20261008140156_fix_purchase_return_sequence_schema
20261008141101_fix_profitability_partially_returned_sales
20261008141147_fix_profitability_return_revenue_basis
20261008184639_add_organization_invitations
20261008184833_lock_down_organization_invitations
20261008201127_fix_commercial_reports_summary_cost_known_group
20261008212522_fix_purchase_return_multi_item_cost_tracking
20261008213956_prevent_duplicate_sale_items_in_return_request
20261008214951_harden_cancel_sale_cost_tracking
```

## اختلافات معروفة تستلزم فحص محتوى الترحيلات

- `20261010143537_scope_report_rpcs_to_authorized_stores.sql` مقابل سجل `20261010143537_20261010150000_scope_report_rpcs_to_authorized_stores`.
- `20261010143948_fix_expense_rpc_execute_permissions.sql` مقابل سجل `20261010143948_20261010160000_fix_expense_rpc_execute_permissions`.
- `20261010152500_fix_account_summary_helper_execute_permissions.sql` مقابل سجل `20261010153133_fix_account_summary_helper_execute_permissions`.
- توجد مجموعات أخرى تطابق الاسم مع اختلاف رقم الإصدار، منها كشوف الحسابات، أدوار المؤسسة، وفهارس دعوات المؤسسة.

## خطة التسوية الآمنة

1. استخراج تعريفات الكائنات الحالية من PostgreSQL (الدوال، التواقيع، `search_path`، المالك، `SECURITY DEFINER/INVOKER)، وسياسات RLS، والامتيازات، والقيود والفهارس.
2. ربط كل ملف ترحيل بكائناته المتوقعة ومقارنة الحالة الفعلية؛ مراجعة ملفات الترحيل غير المطابقة مع الإصلاحات اللاحقة قبل تصنيفها.
3. إعداد جدول لكل ترحيل: `applied / equivalent replacement / absent / needs manual review`، مع الدليل، الاعتماديات، وخطر التنفيذ.
4. إعادة تشغيل الاختبارات على بيئة معزولة فقط. لا تُنشأ بيئة جديدة قبل التحقق من التكلفة والحصول على موافقة صريحة.
5. لا تعِد تشغيل ترحيلات قديمة ولا تعدّل سجل `schema_migrations` ولا تطبق تسوية على الإنتاج استنادًا إلى اختلاف الأسماء وحده.

## بوابات إطلاق أخرى لم تُثبت بعد

- **اختبارات العمليات المالية:** خطة القبول موجودة في `docs/ACCEPTANCE_TEST_PLAN.md`، لكن لا توجد بيئة Supabase منفصلة في وقت الفحص. لا تُجرَ مبيعات أو دفعات أو مرتجعات اختبارية على بيانات الإنتاج.
- **البريد:** يلزم اختبار فعلي لدعوة عضو، وتأكيد البريد، وإعادة تعيين كلمة المرور بحساب اختبار، مع التحقق من وصول الرسائل وصلاحية الروابط. لا يُرسل اختبار إلى مستخدم حقيقي دون موافقة.
- **النسخ الاحتياطي والاستعادة:** يلزم إثبات وجود نسخة قابلة للاستعادة ثم استعادتها في بيئة غير إنتاجية ومطابقة الجداول والقيود والحركات؛ لم يثبت هذا الاختبار في هذه الجولة.
- **الجاهزية التجارية:** سياسة الخصوصية، شروط الاستخدام، الباقات والأسعار، قناة الدعم وسياسة الأعطال والنسخ الاحتياطي.
- **فحوص CI الحالية فحوص دخان واختبارات ثابتة؛ لا تُعد بديلًا لاختبار قبول وظيفي شامل.**

## حالة التغيير

هذه الوثيقة توثّق الجرد وخطوات المتابعة فقط. لم تُعدّل بيانات الإنتاج، أو تعريفات قاعدة البيانات، أو إعدادات البريد/النسخ الاحتياطي، ولم تُنشأ موارد مدفوعة. يلزم إنهاء المطابقة الفنية قبل أي تغيير في ترحيلات الإنتاج.
