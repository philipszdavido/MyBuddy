// PROPOSED Cloud Function — not deployed, not tested (no emulator run).
// Sends a push to every registered device of the recipient when a message is first created.
// Idempotent client retries overwrite the same message doc (an update), so they do not re-notify.
// Message text is deliberately NOT included in the push payload (lock-screen privacy).
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const DEAD_TOKEN_CODES = [
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
];

exports.notifyOnMessage = onDocumentCreated("chats/{chatId}/messages/{messageId}", async (event) => {
  const msg = event.data && event.data.data();
  if (!msg || !msg.recipientId || !msg.senderId) return;

  const db = getFirestore();
  const devices = await db.collection(`users/${msg.recipientId}/devices`).get();
  if (devices.empty) return;

  const sender = await db.doc(`users/${msg.senderId}`).get();
  const title = (sender.exists && sender.data().displayName) || "New message";
  const body = msg.type === "text" ? "Sent you a message" : "Sent you a photo";
  const chatId = event.params.chatId;

  const res = await getMessaging().sendEachForMulticast({
    tokens: devices.docs.map((d) => d.data().token).filter(Boolean),
    notification: { title, body },
    data: { deepLink: `mybuddy://chat/${chatId}`, chatId },
    apns: { payload: { aps: { sound: "default", "thread-id": chatId } } },
  });

  // Prune tokens that are no longer valid.
  const prune = [];
  res.responses.forEach((r, i) => {
    if (!r.success && r.error && DEAD_TOKEN_CODES.includes(r.error.code)) {
      prune.push(devices.docs[i].ref.delete());
    }
  });
  await Promise.all(prune);
});
