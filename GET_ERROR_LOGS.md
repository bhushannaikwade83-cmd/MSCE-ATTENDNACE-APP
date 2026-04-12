# 🔍 Get Error Logs - Check What Went Wrong

## 📋 Check Logs via Command Line

### Option 1: Get Recent Logs (Recommended)

```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=face-recognition-api" --project smartattendanceapp-bc2fe --limit=50 --format="table(timestamp,severity,textPayload)"
```

This shows:
- **Timestamp** - When it happened
- **Severity** - ERROR, WARNING, INFO
- **Message** - The actual error

### Option 2: Get Only Errors

```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=face-recognition-api AND severity>=ERROR" --project smartattendanceapp-bc2fe --limit=20
```

### Option 3: Get Latest Revision Logs

```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=face-recognition-api AND resource.labels.revision_name=face-recognition-api-00002-g9v" --project smartattendanceapp-bc2fe --limit=50
```

---

## 🔍 Check Service Status

```bash
gcloud run services describe face-recognition-api --region us-central1 --project smartattendanceapp-bc2fe --format="value(status.url,status.conditions)"
```

This shows:
- Service URL
- Status (Ready/Not Ready)
- Any conditions/errors

---

## 🚀 Test the Service

If the service is running, test it:

```bash
# Get the service URL first
gcloud run services describe face-recognition-api --region us-central1 --project smartattendanceapp-bc2fe --format="value(status.url)"

# Then test (replace YOUR_URL with actual URL)
curl https://YOUR_URL/api/v1/health
```

---

## 💡 Common Errors & Fixes

### Error: "ModuleNotFoundError: No module named 'X'"
**Fix**: Missing package in requirements.txt

### Error: "ImportError: cannot import name 'X'"
**Fix**: Import path issue

### Error: "AttributeError: 'NoneType' object has no attribute"
**Fix**: Object not initialized

### Error: "Connection refused" or "Timeout"
**Fix**: Service not starting properly

---

## 📝 Next Steps

1. **Run the log command** (Option 1 above)
2. **Copy the error messages** (especially ERROR level)
3. **Share them with me**
4. **I'll fix it immediately!** 🔧

**Run the command and share the output!** 🚀
