# Source and modification notice

Original project: https://github.com/NdoleStudio/httpsms

Original author and project attribution: NdoleStudio / Etienne Ndole.

Upstream baseline: 8f44d83091deac7a8c6491fb3c5fa85f1ed08a53.

This independent home-receive profile is maintained in this repository under the upstream AGPL-3.0 license. Original license notices and attribution are retained. The copied upstream README is reference material; use deploy/local/README.md for this profile.

Modifications include receive-only Android permissions; removal of mobile remote logging and analytics; scoped user CA trust; persistent WorkManager uploads and acknowledgement handling; stable receive IDs; transactional message/outbox persistence; retrying PostgreSQL event delivery; privacy-preserving server logger; local endpoint restrictions; loopback web UI polling; Windows firewall, Firebase import, configurable tool paths, release signing, and login recovery scripts.

Original environment files, Firebase app configuration, deployment credentials, machine-specific recovery tests, CI publishing configuration, build artifacts and personal data are not distributed. Every deployment generates its own credentials and uses its own Firebase project and release-signing identity.
