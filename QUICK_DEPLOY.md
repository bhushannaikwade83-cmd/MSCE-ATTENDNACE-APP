# 🚀 Quick Firestore Deployment Guide

## One-Command Deployment

### Windows:
```bash
scripts\deploy_firestore.bat
```

### Mac/Linux:
```bash
./scripts/deploy_firestore.sh
```

---

## What Gets Deployed

✅ **Firestore Rules** - Security rules (active immediately)  
✅ **Firestore Indexes** - Query indexes (ready in 2-5 minutes)  
✅ **Collections** - Auto-created when app runs (no deployment needed)  

---

## Prerequisites

1. Install Firebase CLI:
   ```bash
   npm install -g firebase-tools
   ```

2. Login to Firebase:
   ```bash
   firebase login
   ```

---

## Verify Deployment

### Rules:
https://console.firebase.google.com/project/msce-attendace-app/firestore/rules

### Indexes:
https://console.firebase.google.com/project/msce-attendace-app/firestore/indexes

### Collections:
- Run your app - collections auto-create
- Check: https://console.firebase.google.com/project/msce-attendace-app/firestore/data

---

## That's It! 🎉

Your Firestore database is now fully configured and ready to use!
