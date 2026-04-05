# Phase 1, Step 2: Firebase Setup for Messaging — Implementation Log

**Date:** 2026-04-05
**Status:** ✅ Complete — BUILD SUCCEEDED

---

## What Was Done

### New Files Created

| File | Purpose |
|------|---------|
| `firebase/rules/firestore.rules` | Security rules for 3 new collections: `conversations`, `messages` (subcollection), `conversationMemberships`. Also covers `events`, `activityPreferences`, `customActivities`, `scheduledActivities` for future sprints |
| `firebase/rules/storage.rules` | Storage rules for `chat_images/{conversationId}/{messageId}/{filename}` — authenticated reads, writes restricted to images under 5MB, all other paths denied |
| `Sprints/Sprint 1 - Messaging/Firebase-Setup.md` | Step-by-step guide for enabling Firebase Storage in Console and deploying rules |

### Files Modified

| File | Change |
|------|--------|
| `LetsDoIt.xcodeproj/project.pbxproj` | Added `FirebaseStorage` as SPM product dependency, framework build reference, and target dependency |
| `LetsDoIt/AppDelegate.swift` | Added `import FirebaseStorage` |

### Architecture Decisions

1. **Firestore rules follow least-privilege** — Only conversation members can read messages and conversation docs. Writes require `senderUid == request.auth.uid`. `conversationMemberships` are read-only for the client except for `lastReadAt` and `muted` fields (updated client-side for read receipts).

2. **Storage rules are permissive on read** — Any authenticated user can read chat images. In practice, the app only downloads images for conversations the user is a member of, so this is safe and avoids a cross-document lookup on every image load.

3. **Rules file lives outside source tree** — `firebase/rules/` is the standard Firebase CLI convention, making `firebase deploy --only firestore:rules,storage` work without manual Console copy-paste.

4. **Future-sprint collections pre-authored** — Rules for `events`, `scheduledActivities`, `customActivities`, and `activityPreferences` are already in place so future sprints don't require a separate rules deployment step.

### Deployed Rules Summary

**Firestore:**
| Collection | Read | Write |
|---|---|---|
| `conversations/{id}` | Members only | Participants only |
| `conversations/{id}/messages/{id}` | Members only | Authenticated (sender = self) |
| `users/{uid}/conversationMemberships/{id}` | Owner only | Owner (`lastReadAt`, `muted` only) |

**Storage:**
| Path | Read | Write |
|---|---|---|
| `chat_images/{conversationId}/{messageId}/{filename}` | Authenticated | Authenticated (< 5MB, image/* only) |
| All other paths | Denied | Denied |

### Firebase Console Steps Completed (by user)
- ✅ Firebase Storage enabled in Console
- ✅ Firestore rules deployed via `firebase deploy --only firestore:rules`
- ✅ Storage rules deployed via `firebase deploy --only storage`
- ✅ IAM role for cross-service rules granted

### Build Verification
```
xcodebuild -scheme LetsDoIt -destination 'platform=iOS Simulator,name=iPhone 17' build
→ BUILD SUCCEEDED
```
