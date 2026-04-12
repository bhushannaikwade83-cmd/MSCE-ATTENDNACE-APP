# 🔍 Check Build Status - Service Not Found

## ❌ Service Not Deployed Yet

The `face-recognition-api` service is not in the list, which means:
- Either the build failed
- Or it's still building
- Or deployment didn't complete

---

## 🔍 Check Build Logs

Run these commands to see what happened:

### 1. List Recent Builds
```bash
gcloud builds list --project smartattendanceapp-bc2fe --limit=5
```

### 2. Get Latest Build ID
```bash
gcloud builds list --project smartattendanceapp-bc2fe --limit=1 --format="value(id)"
```

### 3. View Build Logs
```bash
# Replace BUILD_ID with actual ID from step 2
gcloud builds log BUILD_ID --project smartattendanceapp-bc2fe
```

---

## 🚀 Try Deploying Again

If the build failed, try deploying again:

```bash
gcloud run deploy face-recognition-api --source . --platform managed --region us-central1 --allow-unauthenticated --memory 2Gi --timeout 300 --project smartattendanceapp-bc2fe --set-env-vars="PYTHONUNBUFFERED=1"
```

---

## 💡 Common Issues

1. **Build timeout** → Increase timeout or reduce dependencies
2. **Memory error** → Increase memory allocation
3. **Dependency error** → Check requirements.txt
4. **Dockerfile error** → Check Dockerfile syntax

**Check the build logs first to see the exact error!** 🔍
