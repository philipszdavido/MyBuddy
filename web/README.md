# MyBuddy for the web

Placeholder: no web code yet.

When it starts, the client talks to the same backend as iOS:
- REST API `/api/v1` (contract: `backend/openapi.json`) and the Socket.IO protocol in `docs/backend/REALTIME.md`.
- Firebase Auth (Web SDK) for sign-in; send the ID token as `Authorization: Bearer <token>`.
- Add the web origin to the backend's `CORS_ORIGINS` (browsers need CORS; the mobile apps don't).
