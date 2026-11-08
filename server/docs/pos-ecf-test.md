# POS eCF Test

With both eCF switches off, Payment & completion defaults to DIARIO DE VENTAS
and also offers configured CF (CONSUMIDOR FINAL) and VF (CRÉDITO FISCAL) counters
from `app_sequence`. These sales do not enter the DGII queue. Tenant
administrators retain this ordinary flow; switches belong to employees.

Test mode is available only for a single active company with `is_test: true`.
Production mode is available for either value of `is_test`. Enabling either mode
atomically disables the other; a database constraint enforces exclusivity.
Production defaults to E32 and offers configured E32/E31 only. Test defaults to
DV and also offers configured E32/E31. Both electronic modes use fiscal details,
income type 02, N/A for blank buyer addresses, rotation precedence, and the
`actionable` submission gate. Sales, payments and inventory commit in all modes.

Production reads legal name, RNC and address from the active company, and E31
uses `company.ecf_sequence_expiry` (never the test expiry). Company settings and
Users report missing data/signing files. Production checkout ignores the test
readiness flag and does not require manually supplied signing settings or a
request key. POS generates a stable request UUID; direct production requests
without a key receive a generated UUID and cannot deduplicate independent HTTP
retries unless the caller retains a request key. Signing files are resolved
automatically when the worker submits; missing files leave the sale recorded
and the document in a controlled failure state. Company fiscal data and the
production E31 expiry can be maintained in Company settings.

Each document retains its original environment for processing, status queries,
receipts and retries, even if its employee switches modes. Production batches
use purpose `pos_ecf_production` and the existing `ecf` client endpoints; test
batches remain restricted to `testecf`. No migration enables production or sends
a document. Apply `20261108050000_add_ecf_production_mode` before loading the
updated code. It adds the production employee flag, audit flag, exclusivity
constraint and company production expiry, without setting an expiry by default.

The `/pos/users` card switches update the environment flags and write a tenant
audit record. POS sessions receive the change and return to sequence/payment
review. Checkout rechecks the employee under a row lock, so a stale session
cannot cross modes while completing an invoice.

## Deployment configuration

Apply `20261108030000_remove_sale_identifier_uniqueness` before running the updated
checkout. It removes identifier uniqueness for all sales and eCF documents,
retaining ordinary search indexes. Generated identifiers remain in `sale.sequence`
for compatibility with reports, receipts and existing sale relationships.
Primary keys and `(user_id, request_id)` invoice idempotency remain unique.
Repeated identifiers must be distinguished by record ID; the DGII submission
batch still rejects duplicate eNCFs within a single batch. The POS creates a
separate batch per request, and rotation `actionable` still gates submission.
Removing database uniqueness does not change DGII's handling of reused numbers.

Checkout first looks for a rotation whose code or prefix matches the selected
sequence, preferring an exact code match. It calls `SequenceRotation.next/1`
with that row's code. If no rotation exists, it uses `app_sequence`. Invalid
rotation configuration fails checkout rather than falling back to a standard
counter. Rotation advancement commits or rolls back with the sale.

The invoice snapshot retains `sequence_source`, `sequence_code` and `actionable`.
Non-actionable rotating invoices finish as `not_submitted`: the sale, payments
and inventory still commit, but the worker does not generate or post a DGII batch.
Retries also enforce this rule. Standard eCF counters remain actionable. DV sales
continue to bypass the DGII queue regardless of their sequence source.

Apply tenant migrations `20261026000000_add_pos_ecf_test` and
`20261026010000_add_company_ecf_test_settings`, followed by
`20261026020000_default_company_ecf_test_settings` and
`20261026030000_default_company_ecf_test_ready`, through the existing deployment
process before starting this version. No migrations are run automatically.

Issuer identity comes from the single active `[tenant].company` record:
`company_name`, `rnc`, and `address`. In Company settings, save the issuer address,
`ecf_test_sequence_expiry`, and `ecf_test_sequences_ready`. Check the tenant's
`E*` counters in Sequences against previously consumed test numbers before
marking them ready. New seed counters start at zero; never reset used counters.
The existing legal name and RNC are preserved.

Missing addresses default to `AVE ITALIA 54`; missing test expiries default to
`2028-12-31`, matching the existing simulation. Existing values are preserved.
This test expiry is not a production DGII authorization. The readiness migration
sets existing companies ready for testing and defaults new companies to ready,
without modifying sequence counters. Readiness can still be disabled in Company
settings.

Credentials resolve automatically from `p12_companies/[tenant]/`, using the
existing `:fe_receivers_directory` root and a tenant credential loader following the existing reception convention.
The directory must contain exactly one `.p12` file and `credentials.txt` with
one `Password: ...` entry. There are no tenant-name mappings, issuer defaults,
or per-tenant JSON files. Local `ans` and production `evofitdb` follow the same
lookup using their authenticated tenant names.

The only optional storage setting is a shared root:
`POS_ECF_TEST_ARTIFACT_DIRECTORY`. It defaults to `data/pos-ecf-test` in the
repository root. Each invoice uses `[root]/[tenant]/[request_uuid]/`; the path is
snapshotted at creation. Production storage must be persistent and shared across
application nodes. Keep each batch and its adjacent `.source.json` together.

The existing `FE_TRUSTED_CERTIFICATES`, intermediate certificates, native tools
(OpenSSL/xmlsec1/xmllint) and runtime XSDs are reused. Signing passwords and DGII
tokens are never persisted in invoice snapshots or returned to POS.

The worker discovers queued/pending invoices across registered, migrated tenants.
It resolves credentials and the current company RNC per tenant. Already-created
invoices retain their issuer/document snapshots; changing readiness or expiry
does not prevent polling their status. Changing the issuer RNC blocks submission
of an old invoice until the identity mismatch is resolved.

HTTP destination remains explicitly `testecf`, and submission rejects POS test
manifests in other environments. Test numbering is E + type + ten-digit,
left-zero-padded counter. CF/DV/VF counters and formatting are unchanged.

## Checkout and recovery

With the switch on, Payment & completion hides CF/DV/VF and offers E31, E32,
E44, E45 and E46, defaulting to E32. Debit/credit notes remain separate document
adjustments; purchase/expense/payment types are not sale checkout options.

The fiscal form captures buyer identification kind, optional identifier/name/address
overrides (otherwise the selected customer is used), and income type. E31/E45
require domestic RNC/cédula. E32 at/above DOP250,000 requires domestic or foreign
identification. E44 supports domestic buyers and eligible foreign diplomatic
buyers and requires explicit eligibility confirmation. E45 requires government
buyer confirmation. E46 requires buyer identification, buyer/destination countries,
and export eligibility confirmation. Buyer metadata is immutable in the test
invoice snapshot; it does not change the customer record.

Per-line fields distinguish goods/services and 18%, 16%, 0%, or exempt ITBIS.
E44 forces exempt lines and `MontoExento`; E46 forces zero-rate lines and the
ITBIS3 totals. E31/E32/E45 support mixed rates. The catalog's existing prices
include 18% ITBIS: test pricing removes that embedded rate and applies the chosen
rate, rounding the unit price to cents. Original catalog/cart values are retained
and restored if test mode is turned off. Monetary discounts apply to those fiscal
prices; global discounts are allocated across lines before grouping tax totals.
Delivery is a fiscal service line (18%, or exempt for E44). E46 goods checkout
rejects service lines and separate delivery charges; invoice those services
separately. This implements DOP POS sales using ITBIS; optional foreign-currency,
customs, ISC/additional-tax and withholding workflows are not inferred from an
unclassified retail product. No buyer eligibility is fabricated or claimed to be
verified against a remote registry.

Cash/card payments are mapped to DGII's payment codes and cash change is excluded
from reported amounts. Card payments cannot exceed the invoice total. Credit
sales retain the required future due date. XSD/signature/chain checks remain in
the existing generation pipeline before any POST.

eCF Test controls are available only when the tenant's single active company has
`is_test: true`. Other companies show disabled issuer settings and hide the user
switch; the server also rejects changes to these settings and user flags.

eCF checkout locks inventory and uses the same sale, line, payment, product trace,
inventory broadcast and addon-event path as ordinary checkout. Its eCF document,
sequence reservation and operational writes commit in one transaction. Repeated
requests with the same idempotency key return the existing invoice without
repeating inventory movements or post-sale events. DGII submission remains
asynchronous and does not determine whether the sale is recorded. New invoice
snapshots retain the associated `sale_id`; historical documents remain unchanged.
Receipts linked to a sale no longer display “NO COMMERCIAL SALE”.

A small supervised scanner processes queued/pending documents from registered
tenants. PostgreSQL session advisory locks coordinate nodes without a database
transaction around HTTP. Existing generation creates signed, schema/chain-checked
artifacts. Existing submission journals persist receipt/track identity, poll
pending results and refuse blind duplicate POSTs. A restart rescans the database
and resumes the same journal. Config/known pre-upload failures can be retried
from POS; rejected or uncertain submissions require reconciliation. Sales are already recorded at checkout; later DGII status updates do not create another sale.

E32 below DOP250,000 sends RFCE. Acceptance is summary acceptance; the complete
ECF remains in its batch for the separate full-document workflow described in
`fe-generation.md`. The POS result panel displays the classification and DGII
response. Saved results are available on the eCF Test history page.

API clients use the existing `POST /api/sales` with a test sequence code and a
stable UUID `idempotency_key`. Repeating that key with the same payload returns
the existing test invoice; changing its payload is rejected. Responses have
`ecf_test: true`, a distinct `ecf-test-*` ID and `status_url`. Read status through
`GET /api/sales/ecf-tests/:id`, not the operational sale endpoints. Employees
can read only their own test documents; administrators can inspect tenant test
status. Existing sale reports/payment/cancellation endpoints do not read test
invoice tables.

A leftover filesystem `.lock` or an `unknown` result is intentionally blocked.
Inspect the immutable source, signed hashes, journal and DGII track/result before
any operator-led reconciliation; never remove locks or requeue unknown records
merely to force another POST. Attempt history is in `fe_test_submission_attempts`.

## Verification status

Implementation was reviewed statically. Compilation, tests, formatting,
migrations, signing and network submissions were not run during this change.
Deployment validation must cover ordinary checkout regression, tenant isolation,
mode-switch races, numbering, discounts/delivery/credit, duplicate UUIDs,
RFCE routing, fiscal rejection, pending/uncertain responses and restart recovery.

## History and result modal

Enabled employees can open `/pos/ecf-tests` from the desktop or mobile navigation.
The page lists their own tenant-scoped invoices, newest first, in pages of 50,
with saved DGII reports, track IDs, amounts and reception dates. The refresh icon
performs only the authenticated DGII result GET for the stored track ID and saves
the response and an attempt record. It cannot repost XML. The action is disabled
when no track ID exists (including direct RFCE responses), and concurrent worker
processing uses the same per-invoice lock. Access is rechecked against the user
record; disabling eCF Test redirects an open history session back to POS.

Test checkout opens a modal showing queued/pending status and then the returned
DGII response as processing completes. Closing it does not stop submission or
remove saved results. The modal offers receipt printing and a link to history;
normal-mode receipt prompts remain unchanged.

POS does not render an inline result card or restore a previous result on load.
Only a newly submitted test invoice opens the result modal. Closing the modal
clears that transient view and stops its UI polling; the worker and saved history
continue independently.

## Exact upload XML

History rows and the POS result modal link to `/pos/ecf-tests/:id/xml`. This view
reads the `file` selected by the persisted submission entry and verifies its
SHA-256 against that entry before displaying it. It never regenerates, re-signs,
or pretty-prints the artifact. RFCE uploads show the actual RFCE, not the full
ECF that was retained separately. The download action returns the original file
bytes unchanged. Missing or changed files are reported as unavailable rather
than replaced by a reconstructed document. Uploads without a DGII receipt are
labelled unconfirmed; known pre-send failures are explicitly identified.

The test result dialog and test printing have independent state. Printer results
only update the matching print request; they never dismiss the DGII result.
The result dialog remains open across LiveView updates until explicitly closed.

The history inspector now opens beneath the selected row as an anchored modal.
Its three-column desktop grid gives two columns to the formatted request
XML and one to the saved DGII JSON response, including the initial upload receipt.
On small screens the two panels stack. XML verification, original copy/download,
and tenant/employee access checks remain the same. The standalone XML URL remains
available for direct inspection links.

## DGII references for sales types

Implementation follows the DGII [e-CF type definitions](https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscalesElectronicosE-CF/Paginas/TipoyEstructurae-CF.aspx)
and [XML format v1.0, October 2025](https://www.dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscalesElectronicosE-CF/Documentacin%20sobre%20eCF/Formatos%20XML/Formato%20Comprobante%20Fiscal%20Electr%C3%B3nico%20(e-CF)%20v1.0.pdf):
buyer identification on pages 12–14, tax totals on pages 19–22, and item
classification on pages 34–37, together with each type's checked-in runtime XSD.

API checkout accepts the same test-only details as the UI: `ecf_buyer_kind`
(`domestic`/`foreign`), optional `ecf_buyer_id`, `ecf_buyer_name`,
`ecf_buyer_address`, `ecf_income_type` (`01`–`06`), `ecf_buyer_confirmed` for
E44/E45, and `ecf_buyer_country`, `ecf_destination_country`,
`ecf_export_confirmed` for E46. Each line accepts `ecf_tax` (`1`=18%, `2`=16%,
`3`=0%, `4`=exempt) and `ecf_kind` (`1`=goods, `2`=service). E44/E46 tax
indicators are enforced server-side. Submitted prices are never trusted; the
server derives fiscal unit prices from the tenant's catalog.

Submission/polling and manual status consultations display a CSS loading spinner
until a result or error is saved. The POS result modal is wider, has wrapping
footer actions, a readable receipt summary and an expandable DGII JSON response.
The history table groups invoice/buyer/receipt details, uses status badges and
shows loading directly on the refresh action. XML is displayed formatted only;
original bytes remain available through copy/download.

History automatically reloads its saved records while visible invoices are
queued/pending, so loading indicators stop when the worker persists a result.
This reload reads the database; it does not initiate another DGII POST.

## Disabled-mode static audit

With both environments off, normal checkout uses only CF/DV/VF and the original pricing, discount, tax,
payment, inventory-update, reporting and addon-event code. Test-only request
fields are neither sent nor cast in normal checkout. Ordinary drafts ignore
fiscal metadata and keep the original sequence fallback; normal receipt payloads
omit fiscal line markers, and the printer interprets them only on a test receipt.
Cart repricing exits immediately when test mode is off. Switching from on to off
restores the original catalog price/subtotal/tax values before the normal cart is
rendered. No-op mode saves do not broadcast or reset an active checkout.

History, XML inspection and retry actions require an enabled employee. Production
FE reception retains its original credential resolution. The company's test-range
readiness default does not enable an employee's test flag.

Shared deployment effects remain: tenant migrations are required for the new
schema fields; the background worker scans for outstanding test invoices; and
normal employee checkout locks/rechecks the mode before operational writes to
prevent a concurrent mode change. Already queued test documents keep their test
identity if their user later disables test mode. Generic checkout error messages
are now visible instead of silently hidden. This audit was static; compilation,
tests and browser regression checks were not run.

Cart summary rendering uses a tracked `checkout_state` assign derived from the
current render data. Item count, subtotal, ITBIS, discounts, total, payment balance
and completion eligibility update together on cart changes. This replaces an
untracked template `socket` alias that left the eCF summary at its initial zeros
when the ordinary client-side cart calculator was bypassed.
