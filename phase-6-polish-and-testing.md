# Phase 6: Polish, Edge Cases & Production Readiness

## Goal
Harden the app for real-world use: tighten security rules, handle edge cases, add visual polish, and test thoroughly.

---

## Step 6.1 — Lock Down Firestore Security Rules

Replace the development rules from Phase 1 with production rules.

**Firebase Console → Firestore → Rules:**

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Users can only read/write their own user document
    match /users/{userId} {
      allow read: if request.auth != null && request.auth.uid == userId;
      allow write: if request.auth != null && request.auth.uid == userId;
    }

    // Invite codes: anyone authed can read (to join), only creator can write
    match /inviteCodes/{code} {
      allow read: if request.auth != null;
      allow create: if request.auth != null
                    && request.resource.data.createdBy == request.auth.uid;
      allow update: if request.auth != null;  // needed for marking "used"
    }

    // Pairs: only members of the pair can read
    match /pairs/{pairId} {
      allow read: if request.auth != null
                  && (resource.data.userA == request.auth.uid
                      || resource.data.userB == request.auth.uid);
      allow create: if request.auth != null;
      allow update: if request.auth != null
                    && (resource.data.userA == request.auth.uid
                        || resource.data.userB == request.auth.uid);

      // Selections: only pair members can read/write
      match /selections/{selectionId} {
        allow read: if request.auth != null;
        allow create: if request.auth != null
                      && request.resource.data.userId == request.auth.uid;
        allow delete: if request.auth != null;
        allow update: if false;  // only Cloud Functions update (matched=true)
      }
    }

    // Pending notifications: only Cloud Functions access (no client access)
    match /pendingNotifications/{notifId} {
      allow read, write: if false;
    }
  }
}
```

> **Note**: Cloud Functions use the Admin SDK, which bypasses security rules. So the `pendingNotifications` collection can be locked down completely — only the backend writes to it.

---

## Step 6.2 — Handle the "Both Select at Exact Same Time" Race Condition

If both users tap the same item within milliseconds, both Cloud Function invocations could run before either marks the selections as `matched`. This could result in duplicate pending notifications.

**Fix: Add a Firestore transaction in `functions/index.js`.**

Replace the match-detection logic inside `onSelectionCreated` with a transaction:

```javascript
// Inside the onSelectionCreated function, replace the batch write with:
await db.runTransaction(async (transaction) => {
    // Re-read the other user's selection inside the transaction
    const otherSelectionsSnapshot = await transaction.get(
        db.collection("pairs").doc(pairId)
            .collection("selections")
            .where("userId", "==", otherUserId)
            .where("itemId", "==", itemId)
            .where("matched", "==", false)
            .where("expiresAt", ">", Timestamp.now())
    );

    if (otherSelectionsSnapshot.empty) return;

    // Re-read the triggering selection to make sure it hasn't been matched
    const currentSelDoc = await transaction.get(snapshot.ref);
    if (!currentSelDoc.exists || currentSelDoc.data().matched) return;

    const otherSelDoc = otherSelectionsSnapshot.docs[0];

    // Mark both as matched
    transaction.update(snapshot.ref, { matched: true });
    transaction.update(otherSelDoc.ref, { matched: true });

    // Create pending notification
    const delayMinutes = Math.floor(Math.random() * 15) + 1;
    const sendAt = new Date(Date.now() + delayMinutes * 60 * 1000);

    const notifRef = db.collection("pendingNotifications").doc();
    transaction.set(notifRef, {
        pairId,
        itemId,
        userAId: userId,
        userBId: otherUserId,
        sendAt: Timestamp.fromDate(sendAt),
        sent: false,
        createdAt: Timestamp.now(),
    });
});
```

> **Note**: Firestore transactions with queries have limitations. If this proves problematic, an alternative is to use a distributed lock via a dedicated "matchLock" document per pair+item. For the MVP, the transaction approach works well given the low write throughput.

---

## Step 6.3 — Expired Selection Cleanup (Cloud Function)

Client-side cleanup isn't reliable (user might not open the app). Add a scheduled cleanup function.

**Add to `functions/index.js`:**

```javascript
/**
 * Runs every 15 minutes. Deletes expired, unmatched selections
 * to keep Firestore clean.
 */
exports.cleanupExpiredSelections = onSchedule("every 15 minutes", async () => {
    const now = Timestamp.now();

    // Get all pairs (could be optimized with a collectionGroup query)
    const pairs = await db.collection("pairs")
        .where("active", "==", true)
        .get();

    let deletedCount = 0;

    for (const pairDoc of pairs.docs) {
        const expired = await pairDoc.ref
            .collection("selections")
            .where("matched", "==", false)
            .where("expiresAt", "<=", now)
            .get();

        for (const sel of expired.docs) {
            await sel.ref.delete();
            deletedCount++;
        }
    }

    if (deletedCount > 0) {
        console.log(`Cleaned up ${deletedCount} expired selections`);
    }
});
```

---

## Step 6.4 — Visual Polish

### 6.4.1 — App Icon

1. Create a 1024x1024 app icon (use any design tool).
2. Suggested design: two overlapping circles or a simple "H" mark.
3. In Xcode → **Assets.xcassets → AppIcon** → drag your icon in. Xcode auto-generates all sizes.

### 6.4.2 — Launch Screen

In Xcode, select the **Herm** target → **General** → **App Icons and Launch Screen**:
- Set **Launch Screen** to use a simple background color matching your design.

### 6.4.3 — Activity Row Animations

Add a subtle animation when a selection is made. The current `ActivityRow.swift` already has `.animation(.easeInOut)` — verify it looks smooth.

### 6.4.4 — Empty/Loading States

Ensure all screens handle:
- Loading state (show `ProgressView`)
- Error state (show error message with retry button)
- Empty state (show helpful text)

### 6.4.5 — Color Scheme

Support both light and dark mode. SwiftUI handles this automatically with system colors (`.primary`, `.secondary`, `Color(.systemBackground)`). Test both modes in the simulator: **Features → Toggle Appearance**.

---

## Step 6.5 — Match History (Optional Enhancement)

Show a simple list of recent matches so users can reminisce.

**File: `Views/MatchHistoryView.swift`**

```swift
import SwiftUI
import FirebaseFirestore

struct MatchHistoryView: View {
    @State private var matches: [MatchRecord] = []
    @State private var isLoading = true

    let pairId: String

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if matches.isEmpty {
                Text("No matches yet — start tapping!")
                    .foregroundColor(.secondary)
            } else {
                List(matches) { match in
                    HStack {
                        Text(match.emoji)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(match.label)
                                .font(.body)
                            Text(match.date, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Match History")
        .task { await loadMatches() }
    }

    private func loadMatches() async {
        let db = Firestore.firestore()
        do {
            let snapshot = try await db.collection("pairs").document(pairId)
                .collection("selections")
                .whereField("matched", isEqualTo: true)
                .order(by: "createdAt", descending: true)
                .limit(to: 50)
                .getDocuments()

            // Deduplicate (two docs per match, one per user)
            var seen = Set<String>()
            var records: [MatchRecord] = []

            for doc in snapshot.documents {
                let data = doc.data()
                guard let itemId = data["itemId"] as? String,
                      let createdAt = data["createdAt"] as? Timestamp else {
                    continue
                }

                if seen.contains(itemId + createdAt.dateValue().description) {
                    continue
                }
                seen.insert(itemId + createdAt.dateValue().description)

                if let item = ActivityCatalog.items.first(where: { $0.id == itemId }) {
                    records.append(MatchRecord(
                        id: doc.documentID,
                        itemId: itemId,
                        emoji: item.emoji,
                        label: item.label,
                        date: createdAt.dateValue()
                    ))
                }
            }

            matches = records
        } catch {
            print("Failed to load matches: \(error)")
        }
        isLoading = false
    }
}

struct MatchRecord: Identifiable {
    let id: String
    let itemId: String
    let emoji: String
    let label: String
    let date: Date
}
```

Add a navigation link to this from `HomeView` when paired:
```swift
NavigationLink("Match History", destination: MatchHistoryView(pairId: pairId))
```

---

## Step 6.6 — Testing Checklist

### Functional Tests
- [ ] **Fresh install flow**: App launches → anonymous auth → home screen
- [ ] **Pairing**: Create code on device A → enter on device B → both show paired
- [ ] **Selection**: Tap item → checkmark appears → Firestore doc created
- [ ] **Deselection**: Tap again → checkmark removed → Firestore doc deleted
- [ ] **Match**: Both select same item → both selections marked `matched` → in-app alert appears
- [ ] **Alert content**: Shows correct item name and emoji
- [ ] **No false match**: Only one user selects → no alert ever appears
- [ ] **Expiry**: Selection made → wait 60 min → selection expires → no match possible after expiry
- [ ] **Unpair**: Tapping disconnect clears both users' pair state
- [ ] **Re-pair**: After disconnecting, both users can pair with someone new
- [ ] **Re-select**: After a match fires, users can select the same item again for a new match

### Edge Case Tests
- [ ] **Self-pair attempt**: Entering your own code shows an error
- [ ] **Expired code**: Code older than 10 minutes is rejected
- [ ] **Used code**: Code that's already been used is rejected
- [ ] **Already paired**: Trying to pair when already paired shows an error
- [ ] **Network loss**: Selections queue locally and sync when connection returns (Firestore offline persistence)
- [ ] **Simultaneous selection**: Both users tap same item at exact same instant → only one match fires (transaction guard)

### UI/UX Tests
- [ ] Dark mode looks correct
- [ ] No text truncation on small screens (iPhone SE)
- [ ] Large text / Dynamic Type doesn't break layout
- [ ] Haptic feedback fires on selection

---

## Step 6.7 — Deploy Final Cloud Functions

```bash
cd /Users/adamgrow/hermGameTest
firebase deploy --only functions
```

Then update Firestore rules in Firebase Console (Step 6.1).

---

## Future: Adding Push Notifications

When you upgrade to a paid Apple Developer account ($99/year), you can add real push notifications:
1. Create an APNs key in Apple Developer portal
2. Upload it to Firebase Console → Cloud Messaging
3. Add Push Notifications + Background Modes capabilities in Xcode
4. Create an AppDelegate with FCM token handling
5. Create a NotificationManager service
6. The Cloud Function infrastructure (pendingNotifications, sendPendingNotifications) is already in place from Phase 4

---

## Final File Structure

```
hermGameTest/
├── Herm/                          (Xcode project)
│   ├── Herm.xcodeproj
│   └── Herm/
│       ├── HermApp.swift
│       ├── GoogleService-Info.plist
│       ├── Assets.xcassets/
│       ├── Models/
│       │   ├── ActivityItem.swift
│       │   └── ActivityCatalog.swift
│       ├── Services/
│       │   ├── AuthManager.swift
│       │   ├── PairingManager.swift
│       │   ├── SelectionManager.swift
│       │   └── MatchListener.swift
│       └── Views/
│           ├── RootView.swift
│           ├── HomeView.swift
│           ├── CreateCodeView.swift
│           ├── JoinCodeView.swift
│           ├── ActivityListView.swift
│           ├── ActivityRow.swift
│           └── MatchHistoryView.swift
├── firebase.json
├── .firebaserc
└── functions/
    ├── index.js
    ├── package.json
    └── node_modules/
```

## Xcode 26 Reminders
- **No manual Info.plist** — Xcode auto-generates it
- **`import Combine` required** in any file using `@Published`
- **Synchronized root groups** — files in `Herm/Herm/` are auto-included in the project
