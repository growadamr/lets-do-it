# Phase 4 Implementation Instructions

## IMPORTANT CONTEXT

Phase 4 creates Firebase Cloud Functions (server-side JavaScript, NOT Swift).
These run on Firebase's servers, not in Xcode.

## CRITICAL RULES

1. Do NOT modify any Swift files. Do NOT touch anything in the Herm/ folder.
2. Do NOT run `firebase deploy`. The user will deploy manually.
3. Do NOT run `firebase init`. The user will run this manually first.
4. You are ONLY writing JavaScript files in the `functions/` directory.
5. Write the code EXACTLY as shown in the phase-4 plan file.

## BEFORE YOU START

The user must first run `firebase init functions` themselves. Ask the user:
"Have you already run `firebase init functions` in /Users/adamgrow/hermGameTest? If not, please run it first (choose JavaScript, yes to ESLint, yes to install dependencies), then tell me when it's done."

If the user confirms it's done, proceed with the steps below.

## PROJECT PATH

- Functions directory: `/Users/adamgrow/hermGameTest/functions/`

## STEPS

### Step 1: Write index.js

Read the phase-4 plan file at `/Users/adamgrow/hermGameTest/phase-4-match-detection.md`.
Find the code block under "Step 4.2 — Write the Match Detection Function".
Read the existing file at `/Users/adamgrow/hermGameTest/functions/index.js` first.
Then OVERWRITE it with the EXACT code from the plan using the Write tool.

### Step 2: Install dependencies

Run this command:
```
cd /Users/adamgrow/hermGameTest/functions && npm install firebase-admin firebase-functions
```

### Step 3: Verify

Run: `cat /Users/adamgrow/hermGameTest/functions/index.js | head -10`

The first lines should show:
```
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
```

Also run: `ls /Users/adamgrow/hermGameTest/functions/node_modules/firebase-admin`

If both checks pass, say:
"Phase 4 code complete. The user must now:
1. Run: cd /Users/adamgrow/hermGameTest && firebase deploy --only functions
2. Verify both functions appear in Firebase Console → Functions
3. Create the Firestore composite index (see phase-4-match-detection.md Step 4.6)"

Do NOT run firebase deploy yourself. Do NOT modify any Swift files.
