# Check Build Logs via Command Line 🔍

## Since Browser Console Isn't Working

Let's use the command line to check what went wrong.

---

## Step 1: List Recent Builds

```bash
gcloud builds list --limit=5 --project smartattendanceapp-bc2fe
```

This shows the last 5 builds with their IDs.

---

## Step 2: Get Build Details

Once you have the build ID, run:

```bash
gcloud builds describe <BUILD_ID> --project smartattendanceapp-bc2fe
```

---

## Step 3: View Full Build Logs

```bash
gcloud builds log <BUILD_ID> --project smartattendanceapp-bc2fe
```

This shows the complete build output with errors.

---

## Alternative: Try Deploying Again with More Info

Sometimes the issue is temporary. Let's try deploying again with verbose output:

```bash
gcloud run deploy face-recognition-api --source . --platform managed --region us-central1 --allow-unauthenticated --memory 2Gi --timeout 300 --project smartattendanceapp-bc2fe --set-env-vars="PYTHONUNBUFFERED=1" --verbosity=debug
```

The `--verbosity=debug` flag will show more details during deployment.

---

## Quick Fix: Common Issues

If you can't access logs, let's try a simpler approach:

1. **Check if all files are present** in `backend_api/` folder
2. **Try deploying again** (sometimes it's a temporary network issue)
3. **Share any error message** you see in the terminal

---

## What to Share

If you see any error in the terminal, please share:
- The full error message
- The last few lines of output

I'll help fix it! 🔧
