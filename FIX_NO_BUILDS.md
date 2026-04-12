# 🔧 Fix: No Builds Found

## ❌ Problem: Builds Not Showing Up

No builds are listed, which means the build process didn't start properly.

---

## ✅ Step-by-Step Fix

### Step 1: Enable APIs (Make Sure They're Enabled)

```bash
gcloud services enable run.googleapis.com --project smartattendanceapp-bc2fe
gcloud services enable cloudbuild.googleapis.com --project smartattendanceapp-bc2fe
gcloud services enable artifactregistry.googleapis.com --project smartattendanceapp-bc2fe
```

### Step 2: Check Permissions

Make sure you have the right permissions:

```bash
gcloud projects get-iam-policy smartattendanceapp-bc2fe --flatten="bindings[].members" --filter="bindings.members:user:YOUR_EMAIL" --format="table(bindings.role)"
```

Replace `YOUR_EMAIL` with your Google account email.

### Step 3: Try Deploying Again (With Verbose Output)

```bash
cd C:\Users\naikw\OneDrive\Desktop\ATTENDANCE-APP-main\backend_api

gcloud run deploy face-recognition-api --source . --platform managed --region us-central1 --allow-unauthenticated --memory 2Gi --timeout 300 --project smartattendanceapp-bc2fe --set-env-vars="PYTHONUNBUFFERED=1" --verbosity=debug
```

The `--verbosity=debug` flag will show more details.

---

## 🚀 Alternative: Use the Deploy Script

Try using the deploy script:

```bash
cd C:\Users\naikw\OneDrive\Desktop\ATTENDANCE-APP-main\backend_api
deploy.bat
```

This will:
1. Set the project
2. Enable APIs
3. Deploy the service

---

## 💡 Quick Test

Try this simple test to see if Cloud Build works:

```bash
gcloud builds submit --tag gcr.io/smartattendanceapp-bc2fe/test-build --project smartattendanceapp-bc2fe
```

If this works, then Cloud Build is working. If it fails, there's a permission/API issue.

---

## 📝 What to Share

After running the commands above, share:
1. Any error messages
2. The output from the deploy command
3. Whether the APIs enabled successfully

**I'll help fix it!** 🔧
