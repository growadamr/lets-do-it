# Let's Do It — Feature Expansion Plan

## Context
The app currently supports 2-person activity matching with a hardcoded activity list. We're expanding it into a fuller social coordination app with messaging, customizable activities, multi-person events, and scheduled activities. The user wants these shipped in the order below.

---

## Sprint 1: Messaging (3-4 weeks) — HIGH complexity

### What
Full messaging with three conversation types:
- **1-on-1 DMs** between contacts
- **Group chats** (user-created, multi-person)
- **Event threads** (auto-created from event setup — ties into Sprint 3)
- Rich messages: text + image uploads (Firebase Storage) + link previews

### Structural Change: TabView Migration
The app outgrows a single NavigationStack. Sprint 1 introduces a **TabView** with tabs: Activity, Messages, Contacts. Future sprints add tabs/sections.

### Firestore Schema
```
conversations/{conversationId}
  type: "dm" | "group" | "event"
  participants: [uid1, uid2, ...]
  createdBy, createdAt
  lastMessage: { text, senderUid, senderName, timestamp }  // denormalized
  metadata: { name, eventId? }  // group/event only
  participantNames: { uid: "Name" }

conversations/{conversationId}/messages/{messageId}
  senderUid, senderName, text, createdAt
  imageUrl?          // Firebase Storage URL
  linkPreview?: { url, title?, description?, imageUrl? }
  readBy: { uid: Timestamp }

users/{userId}/conversationMemberships/{conversationId}
  lastReadAt, muted, joinedAt
```

**Firebase Storage**: `chat_images/{conversationId}/{messageId}/{filename}`

### Cloud Functions
- **`onMessageCreated`** (trigger): Denormalize `lastMessage` on conversation doc, send FCM push to other participants
- **`onConversationCreated`** (trigger): Create `conversationMemberships` for each participant

### New Swift Files (~10)
| File | Purpose |
|------|---------|
| `Services/MessagingManager.swift` | Conversations + messages CRUD, Firestore listeners, image upload |
| `Models/Conversation.swift` | Conversation struct |
| `Models/Message.swift` | Message struct |
| `Views/Messaging/ConversationsListView.swift` | Conversation list, sorted by recency, unread badges |
| `Views/Messaging/ChatView.swift` | Message thread, text input, image attach button |
| `Views/Messaging/MessageBubbleView.swift` | Renders text/image/link preview per message |
| `Views/Messaging/NewConversationView.swift` | Create DM or group chat |
| `Views/Messaging/ImagePickerView.swift` | PHPickerViewController wrapper |
| `Views/Messaging/LinkPreviewView.swift` | Open Graph card renderer |
| `Utilities/LinkPreviewGenerator.swift` | LPMetadataProvider wrapper |

### Changes to Existing Files
- **`HomeView.swift`** → Restructure into TabView root
- **`ContactsListView.swift`** → Add "Message" button per contact
- **`AppDelegate.swift`** → Deep-link notification taps to conversations
- **Xcode project** → Add `FirebaseStorage` SPM dependency

### Key Decisions
- Message pagination: cursor-based, 50 messages per page
- Images: JPEG 0.7 quality, max 1024px longest edge
- Link previews: client-side via `LPMetadataProvider`, stored in message doc
- Build a generic deep-link router that Sprint 3 extends

---

## Sprint 2: Customizable Activities (1.5-2 weeks) — MEDIUM complexity

### What
- Toggle catalog items on/off per user
- Create custom activities (emoji + label + category)
- **Per-contact visibility**: control which contacts see each custom activity (e.g. spouse-only activities hidden from friends)
- Activity list for a contact pair = intersection of both users' enabled + mutually visible activities

### Firestore Schema
```
users/{userId}/activityPreferences/{activityId}
  enabled: Bool    // default true for catalog items

users/{userId}/customActivities/{activityId}
  id, emoji, label, category, createdAt
  visibleTo: [uid1, uid2, ...]  // which contacts can see this
```

### Cloud Functions
- **`checkForMatchesV2`** — Extend existing matcher to validate custom activity visibility for both users

### Security Rule (critical)
```
match /users/{userId}/customActivities/{activityId} {
  allow read: if request.auth.uid == userId
               || request.auth.uid in resource.data.visibleTo;
  allow write: if request.auth.uid == userId;
}
```

### New Swift Files (~6)
| File | Purpose |
|------|---------|
| `Services/ActivityManager.swift` | Preferences CRUD, custom activity CRUD, effective activity list computation |
| `Models/CustomActivity.swift` | CustomActivity struct |
| `Views/Activities/ActivitySettingsView.swift` | Toggle catalog items, manage custom activities |
| `Views/Activities/CreateCustomActivityView.swift` | Create form with emoji picker + contact visibility |
| `Views/Activities/EditCustomActivityView.swift` | Edit existing custom activity |
| `Views/Activities/EmojiPickerView.swift` | Emoji grid selector |

### Changes to Existing Files
- **`Models/ActivityItem.swift`** → Add `ActivityDisplayable` protocol for uniform rendering
- **`Views/ActivityListView.swift`** → Use `ActivityManager.getEffectiveActivities(for:)` instead of `ActivityCatalog.grouped`
- **`Views/MatchHistoryView.swift`** → Look up custom activities for `custom_*` IDs

### Key Decisions
- Catalog items default enabled (no upfront data creation for new users)
- Custom activity IDs prefixed with `custom_` to distinguish from catalog
- Effective activity list computed client-side (requires security rule allowing cross-user reads for visible activities)
- **Reusable contact multi-select picker** built here, reused by Sprint 3 for event invitees

---

## Sprint 3: Event Scheduling (2-3 weeks) — MEDIUM-HIGH complexity

### What
- Multi-person events (title, date/time, location, description)
- Invite multiple contacts, each RSVPs independently (accept/decline/maybe)
- Real-time RSVP updates via Firestore listeners
- Optional: create group chat from event setup (requires Sprint 1)

### Firestore Schema
```
events/{eventId}
  title, description, location, dateTime
  createdBy, createdAt, updatedAt
  invitees: [uid1, uid2, ...]
  rsvps: { uid: "accepted" | "declined" | "maybe" }
  conversationId?   // links to Sprint 1 conversation (nullable)
  status: "active" | "cancelled"
```

### Cloud Functions
- **`onEventCreated`** (trigger): FCM push to all invitees
- **`onEventUpdated`** (trigger): Push on date/location/cancellation changes, push to creator on RSVP changes
- **`cleanupPastEvents`** (daily): Archive events older than 7 days

### New Swift Files (~7)
| File | Purpose |
|------|---------|
| `Services/EventManager.swift` | Events CRUD, RSVP management, real-time listener |
| `Models/Event.swift` | Event struct, RSVPStatus enum |
| `Views/Events/EventsListView.swift` | Upcoming/past segments |
| `Views/Events/EventDetailView.swift` | Full detail + RSVP buttons + attendee list + "Open Chat" |
| `Views/Events/CreateEventView.swift` | Event creation form with invitee picker |
| `Views/Events/EditEventView.swift` | Edit (creator only) |
| `Views/Events/InviteePickerView.swift` | Reuses multi-select contact picker from Sprint 2 |

### Changes to Existing Files
- **TabView root** → Add Events tab
- **`AppDelegate.swift`** → Event notification deep linking

### Key Decisions
- Top-level `events` collection (shared resource, not user-nested)
- RSVPs as map on event doc (not subcollection) — small group sizes make this efficient
- Sprint 1 dependency is **optional**: `conversationId` is nullable, chat button hidden if messaging not available

---

## Sprint 4: Scheduled Activities (1.5-2 weeks) — MEDIUM complexity

### What
- Schedule an activity to auto-activate at a future time with a specific contact
- One-time and recurring (daily, weekly, custom days)
- Cloud Function processes schedules and creates normal selection docs — existing matcher picks them up with zero changes

### Firestore Schema
```
users/{userId}/scheduledActivities/{scheduleId}
  activityId, targetContactUid
  scheduledAt: Timestamp        // next activation time
  recurrence?: { type, daysOfWeek?, intervalDays? }
  enabled: Bool                 // pause without deleting
  createdAt, lastActivatedAt?
```

### Cloud Functions
- **`processScheduledActivities`** (every 5 min): Collection group query for due schedules, creates selection docs, updates `scheduledAt` for recurring or deletes one-time
- **Requires**: Collection group index on `scheduledActivities` (`enabled`, `scheduledAt`)

### New Swift Files (~5)
| File | Purpose |
|------|---------|
| `Services/ScheduleManager.swift` | CRUD for schedules |
| `Models/ScheduledActivity.swift` | ScheduledActivity + RecurrenceRule structs |
| `Views/Scheduling/ScheduledActivitiesListView.swift` | All schedules with next activation time, enable/disable toggle |
| `Views/Scheduling/CreateScheduleView.swift` | Pick contact + activity + time + recurrence |
| `Views/Scheduling/RecurrencePickerView.swift` | Recurrence type + day selection UI |

### Changes to Existing Files
- **`Views/ActivityListView.swift`** → Add "Schedule" action per activity
- **Activity tab** → Section for accessing scheduled activities list

### Key Decisions
- Activation = normal selection creation (zero changes to matching system)
- Recurrence calculated server-side (avoids clock skew)
- `scheduledActivities` nested under users (private — contacts don't see your schedules)

---

## Sprint Dependency Map
```
Sprint 1 (Messaging)  ←── optional ── Sprint 3 (Events: group chat from event)
Sprint 2 (Activities)  ── shares ──→  Sprint 3 (Events: reusable contact picker)
Sprint 2 (Activities)  ── soft ────→  Sprint 4 (Scheduling: custom activities in picker)
```
**No hard dependencies** — each sprint can ship independently.

## Totals
- **~28 new Swift files**, 7 Cloud Functions, 6 new Firestore collections
- **Estimated total**: 8-11 weeks for one developer
- **Highest risk**: Sprint 1 (messaging is a full subsystem + TabView migration)

## Verification
Each sprint should be tested by:
1. Running the app on simulator with two test accounts (anonymous auth)
2. Verifying Firestore documents are created/updated correctly via Firebase Console
3. Testing Cloud Functions via Firebase Emulator Suite
4. Verifying push notifications once APNs is configured (use emulator logs until then)
5. Testing real-time updates (RSVP changes, new messages) across both accounts simultaneously
