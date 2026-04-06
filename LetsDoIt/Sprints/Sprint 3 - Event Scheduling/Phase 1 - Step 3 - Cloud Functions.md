# Phase 1, Step 3: Cloud Functions (Event Triggers) — Implementation Log

**Date:** 2026-04-06
**Status:** ✅ Complete — Syntax check passed

---

## What Was Done

### Files Modified

| File | Change |
|------|--------|
| `firebase/functions/index.js` | Added `onEventCreated`, `onEventUpdated`, and `cleanupPastEvents` functions |

### Files Created

None.

---

## Function Details

### `onEventCreated`

**Trigger:** `events/{eventId}` `.onCreate` (Firestore v1)

**Behavior:**
1. Reads the newly created event document
2. Extracts `invitees` array, excludes `createdBy` UID
3. Looks up FCM tokens from `users/{uid}.fcmToken` for each remaining invitee
4. Sends FCM push notification with invitation message including event title, date, and location

| Property | Value |
|---|---|
| Trigger path | `events/{eventId}` |
| Trigger type | `functions.firestore.onCreate` |
| Notification recipients | All invitees except creator |
| FCM data payload | `{ eventId }` |
| Notification title | `"New event invitation"` |
| Notification body | `"You've been invited to \"{title}\" on {date} at {location}"` |

### `onEventUpdated`

**Trigger:** `events/{eventId}` `.onUpdate` (Firestore v1)

**Behavior — two independent detection paths:**

**RSVP changes:**
1. Compares `before.rsvps` vs `after.rsvps` to find UIDs with new/changed RSVP status
2. For each changed RSVP, looks up the user's display name
3. Sends push to **creator only**: `"{name} {accepted/declined/maybe'd} your event"`

| RSVP value | Notification verb |
|---|---|
| `"accepted"` | `"accepted your event"` |
| `"declined"` | `"declined your event"` |
| `"maybe"` | `"said maybe to your event"` |

**Event detail changes:**
1. Detects changes in `dateTime`, `location`, or `status` fields
2. Looks up FCM tokens for all invitees
3. Sends contextual push: `"Event \"{title}\" has been cancelled."` or date/location change messages

| Change detected | Notification body |
|---|---|
| `status` → `"cancelled"` | `Event "{title}" has been cancelled.` |
| `dateTime` + `location` | `Event "{title}" date and location changed.` |
| `dateTime` only | `Event "{title}" date has changed.` |
| `location` only | `Event "{title}" location has changed.` |
| Other | `Event "{title}" has been updated.` |

**FCM data payload:** `{ eventId }` on all notifications.

### `cleanupPastEvents`

**Trigger:** Pub/Sub schedule `"0 3 * * *"` (daily at 3:00 AM UTC) via `functions.pubsub.schedule()`

**Behavior:**
1. Calculates timestamp for 7 days ago
2. Queries `events` where `dateTime < sevenDaysAgo` AND `status == "active"`
3. Deletes all matching documents in a single batch
4. Throws on failure to trigger automatic retry

| Property | Value |
|---|---|
| Schedule | `"0 3 * * *"` (daily 3 AM UTC) |
| Timezone | `UTC` |
| Query | `events.where("dateTime", "<", sevenDaysAgo).where("status", "==", "active")` |
| Action | Batch delete |
| Retry | On throw (Firebase Functions automatic retry) |

---

## Architecture Decisions

1. **All three functions in the messaging functions project** — The `firebase-functions@^4.9.0` package supports v1 Firestore triggers (`onCreate`, `onUpdate`) and v1 Pub/Sub scheduling (`functions.pubsub.schedule()`). No v2 API is needed. Keeping all event functions alongside the existing messaging functions (`onMessageCreated`, `onConversationCreated`) simplifies deployment and keeps Firestore triggers co-located.

2. **RSVP notifications go to creator only, detail change notifications go to all invitees** — When an invitee RSVPs, only the event creator needs to know (the RSVPing user already sees their own choice in the UI). When the event details change, all invitees need to be notified since their plans may be affected.

3. **Individual RSVP notification messages per user** — Each RSVP change generates a separate FCM message to the creator (not a single multicast). This allows personalized notification text ("{name} accepted your event") rather than a generic bulk message. The creator's token is fetched once and reused across messages.

4. **Batch delete for cleanup** — Using `db.batch().delete()` instead of individual `delete()` calls ensures atomicity. If any deletion fails, the entire batch is retried.

5. **Graceful FCM token lookup failures** — Token lookup errors are logged but do not abort the notification flow. This matches the established pattern in `onMessageCreated` where individual token failures are tolerated.

6. **No notification on create when only creator is in invitees** — If the invitees list is empty or contains only the creator, the function returns early. This handles edge cases where a user creates an event without invitees.

---

## Build Verification
```
node --check /Users/adamgrow/hermGameTest/LetsDoIt/firebase/functions/index.js
→ Exit code 0 (no errors)
```
