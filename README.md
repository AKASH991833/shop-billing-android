# Shop Billing (Android)

Shop billing and rental manager app: sale, rental and order billing with
refundable-deposit tracking, returns, stock, customers and reports.

Generic public source. Shop branding (name, contacts, motto) is injected at
build time from the BRAND_JSON Actions secret and is never committed.

## Build

CI (`.github/workflows/apk.yml`) generates the Android platform scaffolding
with `flutter create`, applies the brand config when the secret exists, and
builds `app-release.apk` as a workflow artifact.
