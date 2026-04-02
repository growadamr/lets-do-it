# Phase 6 Implementation Instructions

## IMPORTANT CONTEXT

Phase 6 is polish and hardening. Most of this phase is manual (Firebase Console rules, testing, app icon). You write/update a few code files.

## CRITICAL RULES

1. Do NOT modify any Swift files unless explicitly told to below.
2. Do NOT run firebase deploy. The user will deploy manually.
3. Do NOT run xcodebuild.
4. You MUST Read a file before using Edit or Write to overwrite it.
5. Work through the steps IN ORDER.

## STEPS

### Step 1: Update functions/index.js with race condition fix

Read the phase-6 plan file at `/Users/adamgrow/hermGameTest/phase-6-polish-and-testing.md`.
Read the existing file at `/Users/adamgrow/hermGameTest/functions/index.js` first.

In the `onSelectionCreated` function, you need to replace the batch write with a transaction. Find the section starting from `// MATCH FOUND!` through `await batch.commit();` and the `console.log` after it.

Specifically find and replace this block:
```
        // MATCH FOUND!
        const otherSelectionDoc = otherSelections.docs[0];

        // Mark both selections as matched
        const batch = db.batch();
        batch.update(snapshot.ref, { matched: true });
        batch.update(otherSelectionDoc.ref, { matched: true });

        // Calculate random delay: 1 to 15 minutes from now
        const delayMinutes = Math.floor(Math.random() * 15) + 1;
        const sendAt = new Date(Date.now() + delayMinutes * 60 * 1000);

        // Create pending notification
        batch.set(db.collection("pendingNotifications").doc(), {
            pairId: pairId,
            itemId: itemId,
            userAId: userId,
            userBId: otherUserId,
            sendAt: Timestamp.fromDate(sendAt),
            sent: false,
            createdAt: FieldValue.serverTimestamp(),
        });

        await batch.commit();

        console.log(
            `Match found! Item: ${itemId}, Users: ${userId} & ${otherUserId}. ` +
            `Notification scheduled for ${sendAt.toISOString()} (${delayMinutes}min delay)`
        );
```

Replace with the transaction code from Step 6.2 of the phase-6 plan file. Copy it EXACTLY. Add a console.log after the transaction call:
```
        console.log(`Match found! Item: ${itemId}, Users: ${userId} & ${otherUserId}`);
```

### Step 2: Add cleanup function to functions/index.js

From the phase-6 plan file, find the code block under "Step 6.3 — Expired Selection Cleanup".
Use the Edit tool to APPEND that entire `exports.cleanupExpiredSelections` function to the END of `/Users/adamgrow/hermGameTest/functions/index.js`.

### Step 3: Create MatchHistoryView.swift

From the phase-6 plan file, find the code block under "Step 6.5 — Match History".
Write the ENTIRE code block (both `MatchHistoryView` and `MatchRecord` structs) to:
`/Users/adamgrow/hermGameTest/Herm/Herm/Views/MatchHistoryView.swift`

### Step 4: Update HomeView.swift to add Match History link

Read the existing file at `/Users/adamgrow/hermGameTest/Herm/Herm/Views/HomeView.swift` first.

Use the Edit tool to add a NavigationLink to Match History. Find:
```
                        Button("Disconnect", role: .destructive) {
                            Task { try? await pairingManager.unpair() }
                        }
                        .padding(.bottom, 16)
```

Replace with:
```
                        if let pairId = pairingManager.pairId {
                            NavigationLink("Match History") {
                                MatchHistoryView(pairId: pairId)
                            }
                            .padding(.top, 8)
                        }

                        Button("Disconnect", role: .destructive) {
                            Task { try? await pairingManager.unpair() }
                        }
                        .padding(.bottom, 16)
```

### Step 5: Verify

Run: `find /Users/adamgrow/hermGameTest/Herm/Herm -name "*.swift" -type f | sort`

Expected to see `Views/MatchHistoryView.swift` added.

Also run:
- `grep -c "cleanupExpiredSelections" /Users/adamgrow/hermGameTest/functions/index.js` (should be 1)
- `grep -c "runTransaction" /Users/adamgrow/hermGameTest/functions/index.js` (should be 1)
- `grep -n "MatchHistoryView" /Users/adamgrow/hermGameTest/Herm/Herm/Views/HomeView.swift` (should show the NavigationLink)

If all checks pass, say:
"Phase 6 code complete. The user must now:
1. Run: cd /Users/adamgrow/hermGameTest && firebase deploy --only functions
2. Update Firestore security rules in Firebase Console (see phase-6-polish-and-testing.md Step 6.1)
3. Add an app icon in Xcode (optional)
4. Test all flows from the Phase 6 testing checklist"

Do NOT run firebase deploy. Do NOT modify Firestore rules.
