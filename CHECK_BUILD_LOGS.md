# Check Build Logs - Find the Error 🔍

## 🔍 Step 1: View Build Logs

### Option A: Browser (Easiest)

1. **Click this link** (from your error message):
   ```
   https://console.cloud.google.com/cloud-build/builds;region=us-central1/bd22cfbe-18d3-4352-8d65-b6ee75e6298e?project=976619927198
   ```

2. **Or go to**: https://console.cloud.google.com
3. **Select project**: `smartattendanceapp-bc2fe`
4. **Navigate to**: Cloud Build → Builds
5. **Click on the failed build** (most recent one)
6. **Scroll down** to see the error message

### Option B: Command Line

```bash
# Get last build ID
gcloud builds list --limit=1 --format="value(id)"

# View logs
gcloud builds log $(gcloud builds list --limit=1 --format="value(id)")
```

---

## 🔧 Common Errors & Fixes

### Error 1: "ModuleNotFoundError: No module named 'insightface'"

**Fix**: Requirements.txt is correct, but might need to install from source:
```txt
# In requirements.txt, change:
insightface==0.7.3
# To:
insightface==0.7.3
onnxruntime==1.16.0
```

### Error 2: "Failed to build wheel for insightface"

**Fix**: Add build dependencies to Dockerfile (already updated!)

### Error 3: "libGL.so.1: cannot open shared object file"

**Fix**: Already fixed in updated Dockerfile ✅

### Error 4: "FileNotFoundError: vector_db.py"

**Fix**: Ensure all files are in backend_api folder

---

## 🚀 Try Deployment Again

After checking logs, I've updated the Dockerfile with all dependencies.

**Try deploying again:**

```bash
gcloud run deploy face-recognition-api --source . --platform managed --region us-central1 --allow-unauthenticated --memory 2Gi --timeout 300 --project smartattendanceapp-bc2fe --set-env-vars="PYTHONUNBUFFERED=1"
```

---

## 📝 What to Share

**Please share:**
1. The error message from build logs
2. Or screenshot of the error

**I'll fix it immediately!** 🔧

---

## 💡 Quick Fixes Applied

I've already updated:
- ✅ Dockerfile with all system dependencies
- ✅ Added missing libraries (libsm6, libxext6, etc.)
- ✅ Upgraded pip in Dockerfile

**Try deploying again!** If it still fails, share the error message. 🚀
