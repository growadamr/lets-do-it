# Phase 3 Implementation Instructions

## CRITICAL RULES

1. You are writing files to disk. Xcode auto-syncs them. Do NOT run xcodebuild. Do NOT try to compile.
2. Every file using @Published MUST have `import Combine` or the build WILL FAIL.
3. Do NOT create an Info.plist file.
4. Do NOT modify HermApp.swift, RootView.swift, AuthManager.swift, PairingManager.swift, CreateCodeView.swift, or JoinCodeView.swift.
5. Do NOT add any files beyond what is specified below.
6. Use the Write tool for new files. Use the Edit tool for modifying existing files. You MUST Read a file before using Edit or Write to overwrite it.
7. Work through the steps IN ORDER. Complete each step fully before moving on.
8. Create the Models directory if needed by just writing files to it — the directory will be created automatically.

## PROJECT PATHS

- Source files: `/Users/adamgrow/hermGameTest/Herm/Herm/`
- Models subfolder: `/Users/adamgrow/hermGameTest/Herm/Herm/Models/`
- Services subfolder: `/Users/adamgrow/hermGameTest/Herm/Herm/Services/`
- Views subfolder: `/Users/adamgrow/hermGameTest/Herm/Herm/Views/`

## STEPS

### Step 1: Create ActivityItem.swift

Read the phase-3 plan file at `/Users/adamgrow/hermGameTest/phase-3-activity-list.md`.
Find the code block under "Step 3.1 — Define the Activity Data Model".
Write that EXACT code to: `/Users/adamgrow/hermGameTest/Herm/Herm/Models/ActivityItem.swift`

### Step 2: Create ActivityCatalog.swift

From the same phase-3 plan file, find the code block under "Step 3.2 — Create the Default Activity List".
Write that EXACT code to: `/Users/adamgrow/hermGameTest/Herm/Herm/Models/ActivityCatalog.swift`

### Step 3: Create SelectionManager.swift

From the phase-3 plan file, find the code block under "Step 3.3 — Create the Selection Manager".
Write that EXACT code to: `/Users/adamgrow/hermGameTest/Herm/Herm/Services/SelectionManager.swift`
Confirm `import Combine` is present. If not, add it after `import Foundation`.

### Step 4: Create ActivityListView.swift

From the phase-3 plan file, find the code block under "Step 3.4 — Create the Activity List View".
Write that EXACT code to: `/Users/adamgrow/hermGameTest/Herm/Herm/Views/ActivityListView.swift`

IMPORTANT: After writing the file, you must ADD the timer from Step 3.7. Use the Edit tool to add these two things:
1. Add this property after the `@State private var tappedItemId` line:
   `@State private var timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()`
2. Add this modifier to the List (after `.onDisappear`):
```
.onReceive(timer) { _ in
    if let pairId = pairingManager.pairId {
        selectionManager.startListening(pairId: pairId)
    }
}
```

### Step 5: Create ActivityRow.swift

From the phase-3 plan file, find the code block under "Step 3.5 — Create the Activity Row Component".
Write that EXACT code to: `/Users/adamgrow/hermGameTest/Herm/Herm/Views/ActivityRow.swift`

### Step 6: Update HomeView.swift

Read the existing file at `/Users/adamgrow/hermGameTest/Herm/Herm/Views/HomeView.swift` first.

Then use the Edit tool to replace the ENTIRE `if pairingManager.isPaired` block. Find:
```
                if pairingManager.isPaired {
                    // Paired state — activity list goes here in Phase 3
                    VStack(spacing: 12) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("You're connected!")
                            .font(.title2.bold())

                        if let name = pairingManager.partnerName, !name.isEmpty {
                            Text("Paired with \(name)")
                               .foregroundColor(.secondary)
                        }

                        Text("Activity list coming in Phase 3...")
                            .foregroundColor(.secondary)
                            .padding(.top, 20)

                        Spacer()

                        Button("Disconnect", role: .destructive) {
                            Task { try? await pairingManager.unpair() }
                        }
                        .padding(.bottom, 40)
                    }
                }
```

Replace with:
```
                if pairingManager.isPaired {
                    VStack(spacing: 12) {
                        if let name = pairingManager.partnerName, !name.isEmpty {
                            Text("Connected with \(name)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        ActivityListView()

                        Button("Disconnect", role: .destructive) {
                            Task { try? await pairingManager.unpair() }
                        }
                        .padding(.bottom, 16)
                    }
                }
```

### Step 7: Verify

Run: `find /Users/adamgrow/hermGameTest/Herm/Herm -name "*.swift" -type f | sort`

Expected files (9 total):
- HermApp.swift
- Models/ActivityCatalog.swift (NEW)
- Models/ActivityItem.swift (NEW)
- Services/AuthManager.swift
- Services/PairingManager.swift
- Services/SelectionManager.swift (NEW)
- Views/ActivityListView.swift (NEW)
- Views/ActivityRow.swift (NEW)
- Views/CreateCodeView.swift
- Views/HomeView.swift (MODIFIED)
- Views/JoinCodeView.swift
- Views/RootView.swift

Say "Phase 3 complete. 5 new files created, 1 file updated." if the list matches.
Do NOT create any other files.
