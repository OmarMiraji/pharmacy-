const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const crypto = require("node:crypto");
const templates = require("../mail/templates");
const {sendEmail} = require("../mail/send");
const {writeAlert, safeId} = require("./store");

const region = "us-central1";
const MINUTE = 60000;

// Several destructive actions by one person in a short window look like sabotage or a stolen login.
const BURSTS = {
  "staff.deleted": {group: "staff_removed", limit: 3, label: "logins removed or disabled"},
  "staff.disabled": {group: "staff_removed", limit: 3, label: "logins removed or disabled"},
  "medicine.deleted": {group: "medicine_removed", limit: 10, label: "medicines removed"},
  "sale.voided": {group: "sale_voided", limit: 5, label: "sales cancelled"},
  "password.reset_by_admin": {group: "password_reset", limit: 5, label: "passwords reset"},
  "medicine.price_changed": {group: "price_changed", limit: 25, label: "prices changed"},
};
const BURST_WINDOW_MIN = 10;

const SIGNIN_LIMIT = 5;
const SIGNIN_WINDOW_MIN = 15;

async function superAdminEmails() {
  const snap = await admin.firestore().collection("users").where("role", "==", "super_admin").get();
  return snap.docs
      .map((doc) => doc.data() || {})
      .filter((user) => user.isActive !== false)
      .map((user) => String(user.email || "").trim().toLowerCase())
      .filter((email) => email.includes("@"));
}

async function emailSuperAdmins(content) {
  const recipients = await superAdminEmails();
  let sent = 0;
  for (const to of recipients) {
    try {
      await sendEmail({to, ...content, kind: "security_alert"});
      sent++;
    } catch (error) {
      console.warn("Security alert email failed", to, error.message);
    }
  }
  return sent;
}

/** Saves the alert and, when it is critical, emails every super admin straight away. */
async function raise(alert) {
  const ref = await writeAlert(alert);
  if (!ref || alert.severity !== "critical") return;
  const sent = await emailSuperAdmins(templates.securityAlert({
    title: alert.title,
    message: alert.message,
    severity: alert.severity,
    rows: [
      {label: "Shop", value: alert.pharmacyName},
      {label: "Done by", value: alert.actorName ? `${alert.actorName} <${alert.actorEmail}>` : alert.actorEmail},
    ],
  }));
  if (sent > 0) await ref.update({emailed: true});
}

async function countInWindow(key, windowMin) {
  const bucket = Math.floor(Date.now() / (windowMin * MINUTE));
  const ref = admin.firestore().collection("alert_counters").doc(safeId(`${key}_${bucket}`));
  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = ((snap.exists && snap.data().count) || 0) + 1;
    tx.set(ref, {
      count,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      expireAt: admin.firestore.Timestamp.fromMillis(Date.now() + 2 * 86400000),
    });
    return {count, bucket};
  });
}

function immediateAlert(log) {
  const action = log.action;
  const detail = String(log.detail || "");
  const bySuper = log.actorRole === "super_admin";
  if (action === "data.cleared") {
    return {severity: "critical", title: "Shop data was deleted", message: `${log.target || "Shop data"} was cleared (${detail}).`};
  }
  if (action === "shop.deleted") {
    return {severity: "critical", title: "A shop was deleted", message: `${log.target || "A shop"} was deleted.`};
  }
  if (action === "data.restored") {
    return {severity: "warning", title: "A backup was restored", message: `Backup ${log.target || ""} was restored (${detail}).`};
  }
  if (action === "staff.created" && detail === "super_admin") {
    return {severity: "critical", title: "New super admin login", message: `${log.target} now has full system control.`};
  }
  if (action === "staff.role_changed" && /→\s*(admin|super_admin)$/.test(detail)) {
    return {
      severity: bySuper ? "warning" : "critical",
      title: "A login was given higher access",
      message: `${log.target}: ${detail}.`,
    };
  }
  return null;
}

exports.onActivityLogged = onDocumentCreated(
    {document: "activity_logs/{logId}", region},
    async (event) => {
      const log = (event.data && event.data.data()) || {};
      const base = {
        pharmacyId: log.pharmacyId,
        pharmacyName: log.pharmacyName,
        actorUid: log.actorUid,
        actorName: log.actorName,
        actorEmail: log.actorEmail,
      };
      const now = immediateAlert(log);
      if (now) {
        await raise({...base, ...now, type: log.action, dedupeKey: `act_${event.params.logId}`});
        return;
      }
      const burst = BURSTS[log.action];
      if (!burst || log.actorRole === "super_admin" || !log.actorUid) return;
      const {count, bucket} = await countInWindow(`${log.actorUid}_${burst.group}`, BURST_WINDOW_MIN);
      if (count !== burst.limit) return;
      await raise({
        ...base,
        type: `burst_${burst.group}`,
        severity: burst.group === "price_changed" || burst.group === "password_reset" ? "warning" : "critical",
        title: `Many ${burst.label} in a short time`,
        message: `${log.actorName || log.actorEmail} made ${count}+ ${burst.label} within ${BURST_WINDOW_MIN} minutes.`,
        dedupeKey: `burst_${log.actorUid}_${burst.group}_${bucket}`,
      });
    },
);

// Called by the sign-in screen (before anyone is signed in) after a wrong password.
exports.reportSignInFailure = onCall({region}, async (request) => {
  const email = String((request.data && request.data.email) || "").trim().toLowerCase();
  if (!/^[^@\s]{1,64}@[^@\s]{1,190}\.[a-z]{2,}$/.test(email)) return {ok: true};
  const hash = crypto.createHash("sha256").update(email).digest("hex").slice(0, 24);
  const {count, bucket} = await countInWindow(`signin_${hash}`, SIGNIN_WINDOW_MIN);
  if (count !== SIGNIN_LIMIT) return {ok: true};
  const users = await admin.firestore().collection("users").where("email", "==", email).limit(1).get();
  if (users.empty) return {ok: true};
  const user = users.docs[0].data() || {};
  const role = String(user.role || "").toLowerCase();
  let shopName = "";
  if (user.pharmacyId) {
    const shop = await admin.firestore().collection("pharmacies").doc(String(user.pharmacyId)).get();
    shopName = shop.exists ? String((shop.data() || {}).name || "") : "";
  }
  await raise({
    type: "signin_failed",
    severity: role === "admin" || role === "super_admin" ? "critical" : "warning",
    title: "Repeated wrong passwords",
    message: `${SIGNIN_LIMIT} wrong password attempts for ${email} (${role || "login"}) within ${SIGNIN_WINDOW_MIN} minutes.`,
    pharmacyId: user.pharmacyId || "",
    pharmacyName: shopName,
    actorName: user.displayName || "",
    actorEmail: email,
    dedupeKey: `signin_${hash}_${bucket}`,
  });
  return {ok: true};
});

exports.securityDigest = onSchedule(
    {schedule: "0 7 * * *", timeZone: "Africa/Dar_es_Salaam", region},
    async () => {
      const since = admin.firestore.Timestamp.fromMillis(Date.now() - 86400000);
      const db = admin.firestore();
      const [alertSnap, eventCount] = await Promise.all([
        db.collection("security_alerts").where("createdAt", ">=", since).orderBy("createdAt", "desc").limit(50).get(),
        db.collection("activity_logs").where("level", "==", "security").where("createdAt", ">=", since)
            .count().get().then((snap) => snap.data().count),
      ]);
      const alerts = alertSnap.docs.map((doc) => doc.data() || {});
      if (alerts.length === 0) return;
      await emailSuperAdmins(templates.securityDigest({alerts, eventCount}));
    },
);
