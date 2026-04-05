# Firebase Setup Guide — Sprint 1 Messaging

## Prerequisites
- Firebase project already created (`LetsDoIt`)
- `GoogleService-Info.plist` already in project
- Firebase Auth, Firestore, and Cloud Functions already configured

---

## 1. Enable Firebase Storage

### Firebase Console Steps
1. Go to [Firebase Console](https://console.firebase.google.com/) → Select your project
2. In the left sidebar, click **Build** → **Storage**
3. Click **Get Started**
4. Choose **Start in test mode** (we'll deploy production rules next)
5. Select a location (should match your Firestore region)
6. Click **Done**

---

## 2. Deploy Firestore Security Rules

### Option A: Firebase CLI (Recommended)
```bash
# Install Firebase CLI if not already installed
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize Firestore rules in project root (if not already done)
firebase init firestore

# Select your project
firebase use --add

# Deploy rules
firebase deploy --only firestore:rules
```

### Option B: Firebase Console Manual
1. Go to **Build** → **Firestore Database** → **Rules** tab
2. Copy the contents of `firebase/rules/firestore.rules` into the editor
3. Click **Publish**

---

## 3. Deploy Storage Security Rules

### Option A: Firebase CLI (Recommended)
```bash
# Initialize Storage rules in project root (if not already done)
firebase init storage

# Deploy rules
firebase deploy --only storage
```

### Option B: Firebase Console Manual
1. Go to **Build** → **Storage** → **Rules** tab
2. Copy the contents of `firebase/rules/storage.rules` into the editor
3. Click **Publish**

---

## 4. Verify FirebaseStorage is Linked in Xcode

1. Open the Xcode project
2. Select the project root → **LetsDoIt** target → **General** tab
3. Scroll to **Frameworks, Libraries, and Embedded Content**
4. Verify `FirebaseStorage` is listed (added via SPM)
5. Build the project (`Cmd+B`) — should succeed

---

## 5. Verify Firebase Console

1. Go to **Build** → **Storage** — you should see an empty `chat_images/` folder structure once images are uploaded
2. Test by sending a test image from the app (once messaging UI is built)

---

## Rules Summary

### Firestore Rules (`firestore.rules`)
| Collection | Read | Write |
|---|---|---|
| `conversations/{id}` | Members only | Participants only |
| `conversations/{id}/messages/{id}` | Members only | Authenticated (sender = self) |
| `users/{uid}/conversationMemberships/{id}` | Owner only | Owner (lastReadAt, muted only) |
| `events/{id}` | Invitees only | Creator only |

### Storage Rules (`storage.rules`)
| Path | Read | Write |
|---|---|---|
| `chat_images/{conversationId}/{messageId}/{filename}` | Authenticated | Authenticated (< 5MB, image only) |
| All other paths | Denied | Denied |

---

## Next Steps
- **Phase 1, Step 3**: Create data models (`Conversation`, `Message`, `ConversationMembership`)
- **Phase 1, Step 4**: Build `MessagingManager` service
