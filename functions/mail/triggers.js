const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const templates = require("./templates");
const {sendEmail} = require("./send");

const region = "us-central1";

function asDate(value) {
  if (!value) return null;
  if (value.toDate) return value.toDate();
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function daysRemaining(expiry) {
  const end = asDate(expiry);
  if (!end) return 0;
  const now = new Date();
  const endDay = new Date(end.getFullYear(), end.getMonth(), end.getDate());
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const days = Math.round((endDay - today) / 86400000);
  return days < 0 ? 0 : days;
}

function isTrialShop(shop) {
  if (!shop) return false;
  return shop.isTrial === true || shop.plan === "trial" || shop.status === "trial";
}

function isPaidActive(shop) {
  if (!shop) return false;
  return shop.isUnlocked === true &&
      shop.isTrial !== true &&
      String(shop.plan || "").toLowerCase() !== "trial" &&
      String(shop.status || "").toLowerCase() !== "locked";
}

async function loadShop(pharmacyId) {
  const id = String(pharmacyId || "").trim();
  if (!id) return null;
  const snap = await admin.firestore().collection("pharmacies").doc(id).get();
  if (!snap.exists) return null;
  return {id: snap.id, ...snap.data()};
}

async function safelySend(job) {
  try {
    await sendEmail(job);
    return true;
  } catch (error) {
    console.error("Email send failed", job.kind, job.to, error);
    return false;
  }
}

async function markUserEmail(uid, fields) {
  await admin.firestore().collection("users").doc(uid).set({
    emails: fields,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

async function markShopEmail(pharmacyId, fields) {
  await admin.firestore().collection("pharmacies").doc(pharmacyId).set({
    emails: fields,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

exports.onUserCreatedEmail = onDocumentCreated(
    {document: "users/{userId}", region},
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const user = snap.data() || {};
      const uid = event.params.userId;
      const email = String(user.email || "").trim().toLowerCase();
      const role = String(user.role || "").trim().toLowerCase();
      if (!email || role === "super_admin") return;
      if (user.emails && user.emails.welcomeSentAt) return;

      try {
        await admin.auth().updateUser(uid, {emailVerified: true, disabled: user.isActive === false});
      } catch (error) {
        console.warn("Could not mark Auth email verified", uid, error.message);
      }

      await new Promise((resolve) => setTimeout(resolve, 2500));
      const shop = await loadShop(user.pharmacyId);
      const name = String(user.displayName || "").trim() || email;
      const shopName = shop ? String(shop.name || "").trim() : "";
      const trial = isTrialShop(shop);
      const message = role === "admin"
        ? templates.welcomeAdmin({
          name,
          email,
          shopName,
          isTrial: trial,
          trialEndsAt: shop && (shop.trialEndsAt || shop.expiresAt),
        })
        : templates.welcomeStaff({name, email, shopName, role});

      const sent = await safelySend({
        to: email,
        subject: message.subject,
        html: message.html,
        text: message.text,
        kind: role === "admin" ? "welcome_admin" : "welcome_staff",
        meta: {uid, pharmacyId: user.pharmacyId || "", role},
      });
      if (sent) {
        await markUserEmail(uid, {welcomeSentAt: admin.firestore.FieldValue.serverTimestamp()});
      }
    },
);

exports.onPharmacyUpdatedEmail = onDocumentUpdated(
    {document: "pharmacies/{pharmacyId}", region},
    async (event) => {
      const before = event.data.before.data() || {};
      const after = event.data.after.data() || {};
      const pharmacyId = event.params.pharmacyId;
      if (!isPaidActive(after) || isPaidActive(before)) return;

      const expiresAt = asDate(after.expiresAt) || asDate(after.trialEndsAt);
      const expiresKey = expiresAt ? String(expiresAt.getTime()) : "active";
      if (after.emails && after.emails.activationKey === expiresKey) return;

      const email = String(after.ownerEmail || "").trim().toLowerCase();
      if (!email) return;
      let name = email;
      if (after.ownerUserId) {
        const owner = await admin.firestore().collection("users").doc(String(after.ownerUserId)).get();
        if (owner.exists) {
          name = String(owner.data().displayName || "").trim() || email;
        }
      }
      const message = templates.subscriptionActivated({
        name,
        email,
        shopName: String(after.name || "").trim(),
        plan: after.plan,
        expiresAt: after.expiresAt,
      });
      const sent = await safelySend({
        to: email,
        subject: message.subject,
        html: message.html,
        text: message.text,
        kind: "subscription_activated",
        meta: {pharmacyId, plan: after.plan || ""},
      });
      if (sent) {
        await markShopEmail(pharmacyId, {
          activationSentAt: admin.firestore.FieldValue.serverTimestamp(),
          activationKey: expiresKey,
        });
      }
    },
);

exports.trialEndingReminders = onSchedule(
    {schedule: "0 7 * * *", timeZone: "Africa/Dar_es_Salaam", region},
    async () => {
      const snapshot = await admin.firestore().collection("pharmacies").get();
      for (const doc of snapshot.docs) {
        const shop = {id: doc.id, ...doc.data()};
        if (!isTrialShop(shop) || shop.isUnlocked !== true) continue;
        const left = daysRemaining(shop.trialEndsAt || shop.expiresAt);
        if (left !== 1 && left !== 2) continue;
        const reminderKey = `${left}-${templates.formatDate(shop.trialEndsAt || shop.expiresAt)}`;
        if (shop.emails && shop.emails.trialReminderKey === reminderKey) continue;
        const email = String(shop.ownerEmail || "").trim().toLowerCase();
        if (!email) continue;
        let name = email;
        if (shop.ownerUserId) {
          const owner = await admin.firestore().collection("users").doc(String(shop.ownerUserId)).get();
          if (owner.exists) name = String(owner.data().displayName || "").trim() || email;
        }
        const message = templates.trialEnding({
          name,
          email,
          shopName: String(shop.name || "").trim(),
          trialEndsAt: shop.trialEndsAt || shop.expiresAt,
          daysLeft: left,
        });
        const sent = await safelySend({
          to: email,
          subject: message.subject,
          html: message.html,
          text: message.text,
          kind: "trial_ending",
          meta: {pharmacyId: shop.id, daysLeft: left},
        });
        if (sent) {
          await markShopEmail(shop.id, {
            trialReminderKey: reminderKey,
            trialReminderSentAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }
    },
);
