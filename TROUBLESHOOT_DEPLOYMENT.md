# 🔍 Troubleshoot Deployment - Service Not Found

## ❌ Issue: Service Not in List

The `face-recognition-api` service didn't deploy. Let's find out why.

---

## Step 1: Check Build Status

Run this to see recent builds:

```bash
gcloud builds list --project smartattendanceapp-bc2fe --limit=5
```

This shows:
- Build status (SUCCESS, FAILURE, WORKING)
- Build ID
- When it ran

---

## Step 2: Get Build Logs

If you see a FAILED build, get its ID and check logs:

```bash
# Get latest build ID
gcloud builds list --project smartattendanceapp-bc2fe --limit=1 --format="value(id)"

# Then view logs (replace BUILD_ID with actual ID)
gcloud builds log BUILD_ID --project smartattendanceapp-bc2fe
```

---

## Step 3: Common Fixes

### If Build Failed:

1. **Share the error message** from logs
2. **I'll fix it immediately!**

### If No Builds Found:

The deployment might not have started. Try deploying again:

```bash
gcloud run deploy face-recognition-api --source . --platform managed --region us-central1 --allow-unauthenticated --memory 2Gi --timeout 300 --project smartattendanceapp-bc2fe --set-env-vars="PYTHONUNBUFFERED=1"
```

---

## 💡 Quick Check

Run this first to see what happened:

```bash
gcloud builds list --project smartattendanceapp-bc2fe --limit=5
```

**Share the output and I'll help fix it!** 🔧
