# MyBuddy for Android

Placeholder: no Android code yet.

When it starts, the app talks to the same backend as iOS:
- REST API `/api/v1` (contract: `backend/openapi.json`) and the Socket.IO protocol in `docs/backend/REALTIME.md`.
- Firebase Auth for sign-in (send the ID token as `Authorization: Bearer <token>`) and FCM for push.
- Deep links: `mybuddy://chat|profile|post/{id}`.
