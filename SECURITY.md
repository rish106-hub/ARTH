# Security Policy

## Supported Branches

Security fixes target `main`. Release branches are supported only while an app
release is actively being prepared.

## Reporting a Vulnerability

Email the maintainer or open a private GitHub security advisory. Do not include
passwords, tokens, database URLs, private keys, screenshots of secrets, or user
data in public issues, pull requests, or comments.

Please include:

- affected area or endpoint
- steps to reproduce
- expected and observed behavior
- impact if known

We will acknowledge valid reports, investigate, and prioritize fixes based on
user impact and exploitability.

## Secrets

Never commit real `.env` files, signing keys, service-account JSON, database
URLs, JWT secrets, or refresh/access tokens. Rotate any secret that appears in
Git history, logs, CI output, tickets, or chat.
