# ARTH Document Vault + Tax OS Plan

## Goal

Turn ARTH into a taxpayer operating system: save, fix, and file-readiness support for Indian taxpayers, without pretending to be an ITR filing product before the backend can support it safely.

## Identity Policy

- One active PAN per ARTH account.
- One active ARTH account per PAN.
- PAN is optional, Profile-only, explicit-consent, encrypted at rest, and masked in the app.
- An active PAN cannot be silently replaced with another PAN. User must delete the active PAN first.

## Document Vault V1

Document upload is a separate private vault, not just checklist state.

Required backend shape:

- `tax_documents` implemented:
  - `id UUID PRIMARY KEY`
  - `user_id UUID REFERENCES app_users(id) ON DELETE CASCADE`
  - `fy TEXT NOT NULL`
  - `document_type TEXT NOT NULL`
  - `original_filename TEXT NOT NULL`
  - `mime_type TEXT NOT NULL`
  - `byte_size INT NOT NULL`
  - `sha256_fingerprint TEXT NOT NULL`
  - `ciphertext TEXT NOT NULL` (base64 AES-GCM ciphertext)
  - `iv TEXT NOT NULL`
  - `auth_tag TEXT NOT NULL`
  - `parse_status TEXT NOT NULL`
  - `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`

Security rules:

- Auth required.
- Max file size bounded.
- Allowed types only: PDF, JPEG, PNG.
- Encrypt server-side using a separate `DOCUMENT_ENCRYPTION_KEY`.
- Store only metadata and encrypted blob.
- Never log filename content, raw text, PAN, Form 16 values, or document bytes.
- No offline queue for raw documents.
- Delete-data must wipe documents and parse output.

## Non-LLM Parsing

No AI/LLM parsing in V1. Current implementation returns deterministic metadata
and document-type insights. Rich value extraction is the next parser step.

Deterministic parser route:

- Form 16 PDF text extraction.
- Pattern extraction for:
  - employer name
  - TAN
  - masked PAN match only
  - assessment year / financial year
  - gross salary
  - standard deduction
  - Chapter VI-A deductions
  - TDS
  - taxable income
- Confidence labels: high, medium, low.
- User must confirm extracted values before ARTH updates any tax profile.

Parsing limits:

- Password-protected PDFs may fail.
- Scanned images need OCR, which should be a later explicit feature.
- Parser output is assistive. It must not overwrite tax calculations without user confirmation.

## Frontend Flow

- Document Checklist remains the safe readiness layer.
- Add Upload action per document card.
- Upload sheet explains: encrypted vault, file limits, no LLM, delete anytime.
- Uploaded card shows: file name, uploaded date, parse status, extracted summary if available.
- User can delete each document.
- Tax Dossier shows document vault status and extraction confidence.

## Recommended Implementation Order

1. Done: backend migration + encrypted document storage.
2. Done: upload/list/download/delete APIs.
3. Done: Flutter file picker + upload UI.
4. Next: deterministic Form 16 field parser.
5. Next: user confirmation flow before using parsed data.
