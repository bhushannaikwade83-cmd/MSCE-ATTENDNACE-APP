# 🔍 Check Cloud Run Logs - Find Errors

## Check Logs via Command Line

Run this command to see recent logs:

```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=face-recognition-api" --project smartattendanceapp-bc2fe --limit=50 --format=json
```

Or for a simpler text view:

```bash
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=face-recognition-api" --project smartattendanceapp-bc2fe --limit=50 --format="table(timestamp,severity,textPayload)"
```

---

## What to Look For

Common errors:
- **"ModuleNotFoundError"** → Missing Python package
- **"ImportError"** → Import issue
- **"ConnectionError"** → Network/Firebase issue
- **"AttributeError"** → Code issue
- **"Timeout"** → Request timeout

---

## Quick Check Service Status

```bash
gcloud run services describe face-recognition-api --region us-central1 --project smartattendanceapp-bc2fe
```

This shows if the service is running and the URL.

---

## Test the Service

Once you have the URL:

```bash
curl https://your-service-url/api/v1/health
```

Or in browser, just visit:
```
https://your-service-url/api/v1/health
```

**Run the log command and share the errors!** 🔧
