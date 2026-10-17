# ADR-008: Push notifications

Status: proposed. Requirements: FR-ANN-002.3, FR-VAC-004.4, FR-BRF-003, A-15, PRIV-001.

## Context
Opt-in reminders for new announcements and vacation decisions. The Monday 07:00 briefing reminder is local because
Work IQ output cannot be generated unattended (U-03). Notification Hubs is available in Switzerland North, with
zone redundancy forced on there.

## Decision
- Azure Notification Hubs (Standard tier for the SLA) in Switzerland North; APNs token-based auth.
- The APNs auth key (.p8) is a human-only secret, uploaded to the namespace by the human.
- The app registers an installation (not a registration) only after the user opts in, asked in context.
- Installation tags use `HMAC(oid)` with a Key Vault key, never the oid or email.
- Payloads are generic ("New announcement", "Your request was decided") with no title, body, name or audience hint.
  The app fetches content over REST on open, so existence is never leaked through push (FR-ANN-002.3).
- `api/` sends per recipient tag after commit; send failures never fail the business write.
- Opt-out and sign-out delete the installation.
- Monday 07:00 briefing stays a local notification (FR-BRF-003).

## Consequences
- Device tokens are personal data: add to the inventory entry `push-and-notification-state` (cosmos only if push is built).
- Extra cost from forced zone redundancy; one hub per app per environment (separate dev hub, Apple sandbox vs production).
- **Cut line:** if push slips, polling on app open satisfies every Must requirement.
- Apple receives the device token and a generic alert.

## Alternatives
- Direct APNs from `api/`: no extra Azure service, but we would own token auth, retries, and invalid-token cleanup.
- Local-only notifications: cannot notify about new announcements while the app is closed.

## Sources
- learn.microsoft.com/azure/reliability/reliability-notification-hubs
- learn.microsoft.com/azure/notification-hubs/notification-hubs-push-notification-faq
