# Phase 5 Implementation Instructions

## IMPORTANT CONTEXT

Phase 5 adds in-app match alerts using a Firestore listener. There are NO push notifications — we use an in-app alert instead. The Cloud Function from Phase 4 marks selections as `matched: true`, and a client-side listener detects this and shows an alert.

## CRITICAL RULES

1. Every file using @Published MUST have `import Combine`.
2. Do NOT run xcodebuild. Do NOT try to compile.
3. Do NOT modify AuthManager.swift, RootView.swift, HermApp.swift, SelectionManager.swift, PairingManager.swift, CreateCodeView.swift, JoinCodeView.swift, ActivityRow.swift.
4. Do NOT modify any files in the Models/ folder.
5. Do NOT touch the functions/ directory.
6. Do NOT create an AppDelegate.swift or NotificationManager.swift — those are NOT needed.
7. Use the Write tool for new files. Use the Edit tool for modifying existing files. You MUST Read a file before using Edit or Write to overwrite it.
8. Work through the steps IN ORDER.

## PROJECT PATHS

- Source files: `/Users/adamgrow/hermGameTest/Herm/Herm/`
- Services subfolder: `/Users/adamgrow/hermGameTest/Herm/Herm/Services/`
- Views subfolder: `/Users/adamgrow/hermGameTest/Herm/Herm/Views/`

## STEPS

### Step 1: Create MatchListener.swift

Read the phase-5 plan file at `/Users/adamgrow/hermGameTest/phase-5-push-notifications.md`.
Find the code block under "Step 5.1 — Create the Match Listener Service".
Write that EXACT code to: `/Users/adamgrow/hermGameTest/Herm/Herm/Services/MatchListener.swift`
Confirm `import Combine` is present. If not, add it after `import Foundation`.

### Step 2: Replace HomeView.swift

Read the existing file at `/Users/adamgrow/hermGameTest/Herm/Herm/Views/HomeView.swift` first.
Then from the phase-5 plan file, find the FULL updated `HomeView.swift` code block under "Step 5.2".
OVERWRITE HomeView.swift with that EXACT code using the Write tool.

### Step 3: Verify

Run: `find /Users/adamgrow/hermGameTest/Herm/Herm -name "*.swift" -type f | sort`

Expected files (12 total):
- HermApp.swift
- Models/ActivityCatalog.swift
- Models/ActivityItem.swift
- Services/AuthManager.swift
- Services/MatchListener.swift (NEW)
- Services/PairingManager.swift
- Services/SelectionManager.swift
- Views/ActivityListView.swift
- Views/ActivityRow.swift
- Views/CreateCodeView.swift
- Views/HomeView.swift (MODIFIED)
- Views/JoinCodeView.swift
- Views/RootView.swift

Also verify the match listener is wired up:
- `grep -n "MatchListener" /Users/adamgrow/hermGameTest/Herm/Herm/Views/HomeView.swift`

Should show multiple references to MatchListener.

Say "Phase 5 complete. 1 new file created, 1 file updated. Build in Xcode to verify." if everything matches.

Do NOT create any other files. Do NOT create AppDelegate.swift or NotificationManager.swift.
