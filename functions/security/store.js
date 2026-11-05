const admin = require("firebase-admin");

const KEEP_DAYS = 90;

function safeId(value) {
  return String(value || "").toLowerCase().replace(/[^a-z0-9_-]+/g, "_").slice(0, 140);
}

/**
 * Saves one alert. [dedupeKey] makes repeats of the same problem collapse into a single alert,
 * so a burst never floods the super admin. Returns false when that alert already exists.
 */
async function writeAlert(alert) {
  const ref = admin.firestore().collection("security_alerts").doc(safeId(alert.dedupeKey));
  try {
    await ref.create({
      type: alert.type,
      severity: alert.severity || "warning",
      title: alert.title,
      message: alert.message || "",
      pharmacyId: alert.pharmacyId || "",
      pharmacyName: alert.pharmacyName || "",
      actorUid: alert.actorUid || "",
      actorName: alert.actorName || "",
      actorEmail: alert.actorEmail || "",
      read: false,
      emailed: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expireAt: admin.firestore.Timestamp.fromMillis(Date.now() + KEEP_DAYS * 86400000),
    });
    return ref;
  } catch (error) {
    if (error && (error.code === 6 || /already exists/i.test(String(error.message)))) return false;
    throw error;
  }
}

module.exports = {writeAlert, safeId};
