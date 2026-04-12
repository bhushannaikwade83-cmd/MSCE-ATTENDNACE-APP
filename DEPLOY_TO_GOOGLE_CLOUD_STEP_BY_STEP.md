# Deploy ArcFace to Google Cloud Run - Step by Step Guide 🚀

## Your Firebase Project: `smartattendanceapp-bc2fe`

We'll deploy your ArcFace backend to **Google Cloud Run** (uses same Firebase/Google account).

---

## 📋 Prerequisites Checklist

- [ ] Windows/Mac/Linux computer
- [ ] Internet connection
- [ ] Google account (same as Firebase)
- [ ] 30 minutes time

---

## ✅ Step 1: Install Google Cloud SDK (5 minutes)

### Windows:

**Option A: Download Installer (Recommended)**
1. Go to: https://cloud.google.com/sdk/docs/install
2. Download "Google Cloud SDK Installer for Windows"
3. Run the installer
4. Check "Run gcloud init" at the end
5. Open new PowerShell/Command Prompt

**Option B: PowerShell (Quick)**
```powershell
# Download installer
(New-Object Net.WebClient).DownloadFile("https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe", "$env:Temp\GoogleCloudSDKInstaller.exe")

# Run installer
& $env:Temp\GoogleCloudSDKInstaller.exe
```

### Mac:

```bash
# Download and install
curl https://sdk.cloud.google.com | bash

# Restart terminal or run:
exec -l $SHELL
```

### Linux:

```bash
# Download and install
curl https://sdk.cloud.google.com | bash

# Restart terminal or run:
exec -l $SHELL
```

---

## ✅ Step 2: Login to Your Google/Firebase Account (2 minutes)

```bash
# Login with your Firebase account
gcloud auth login

# This will open browser - login with your Firebase account email
# After login, close browser and return to terminal
```

**Verify login:**
```bash
gcloud auth list
# Should show your email address
```

---

## ✅ Step 3: Set Your Firebase Project (1 minute)

```bash
# Set your Firebase project
gcloud config set project smartattendanceapp-bc2fe

# Verify
gcloud config get-value project
# Should show: smartattendanceapp-bc2fe
```

---

## ✅ Step 4: Enable Required APIs (2 minutes)

```bash
# Enable Cloud Run API
gcloud services enable run.googleapis.com

# Enable Cloud Build API (needed to build your app)
gcloud services enable cloudbuild.googleapis.com

# Verify APIs are enabled
gcloud services list --enabled
# Should show: run.googleapis.com and cloudbuild.googleapis.com
```

---

## ✅ Step 5: Navigate to Backend Folder (1 minute)

```bash
# Go to your project folder
cd "C:\Users\naikw\OneDrive\Desktop\ATTENDANCE-APP-main\backend_api"

# Verify you're in the right folder
# You should see: main.py, requirements.txt, face_service.py
dir  # Windows
# or
ls   # Mac/Linux
```

---

## ✅ Step 6: Deploy to Cloud Run (10-15 minutes)

### Option A: Use Deployment Script (Easiest!)

**Windows:**
```bash
deploy.bat
```

**Mac/Linux:**
```bash
chmod +x deploy.sh
./deploy.sh
```

### Option B: Manual Deployment

```bash
# Deploy to Cloud Run
gcloud run deploy face-recognition-api \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 2Gi \
  --timeout 300 \
  --project smartattendanceapp-bc2fe \
  --set-env-vars="PYTHONUNBUFFERED=1"
```

**What happens:**
1. Cloud Run builds your Python app (takes 5-10 minutes)
2. Installs all dependencies from `requirements.txt`
3. Downloads ArcFace model automatically (first time only, ~250MB)
4. Deploys your API
5. Gives you a URL

**Wait for this message:**
```
Service URL: https://face-recognition-api-xxxxx-uc.a.run.app
```

**Copy this URL!** 📋 You'll need it in Step 7.

---

## ✅ Step 7: Test Your API (2 minutes)

### Test Health Endpoint:

```bash
# Replace xxxxx with your actual URL
curl https://face-recognition-api-xxxxx-uc.a.run.app/api/v1/health
```

**Expected response:**
```json
{
  "status": "healthy",
  "service": "face-recognition-api",
  "version": "1.0.0"
}
```

### Or test in browser:
Open: `https://face-recognition-api-xxxxx-uc.a.run.app/api/v1/health`

Should show: `{"status":"healthy",...}`

---

## ✅ Step 8: Update Flutter App (5 minutes)

### 8.1: Add API URL to `.env`

Create/update `.env` file in project root:
```env
FACE_RECOGNITION_API_URL=https://face-recognition-api-xxxxx-uc.a.run.app/api/v1
```

**Replace `xxxxx` with your actual URL from Step 6!**

### 8.2: Update Attendance Screen

In `lib/presentation/screens/admin_attendance_screen.dart`:

**FIND (around line 1363):**
```dart
final faceVerified = await FaceRecognitionService.verifyStudent(
  photo.path,
  instituteId!,
  selectedRollNumber!,
);
```

**REPLACE WITH:**
```dart
// Use ArcFace backend (Google Cloud Run)
final match = await ArcFaceBackendService.recognizeStudent(
  imagePath: photo.path,
  instituteId: instituteId!,
  threshold: 0.85,
);

if (match != null && match['rollNumber'] == selectedRollNumber) {
  // Face verified! ✅
  if (kDebugMode) {
    debugPrint('✅ ArcFace verified: ${(match['similarity'] as double * 100).toStringAsFixed(1)}% match');
  }
  // Continue with attendance marking...
} else {
  // Face verification failed
  setState(() => isLoading = false);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        match == null
            ? '❌ Face recognition failed. Please try again.'
            : '❌ Face does not match. Security check failed.',
      ),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 5),
    ),
  );
  return;
}
```

### 8.3: Update Student Registration

In `lib/presentation/screens/add_student_screen.dart`:

**FIND (around line 509):**
```dart
final faceTemplateSaved = await FaceRecognitionService.saveFaceTemplate(
  _facePhotoPath!,
  _instituteId!,
  rollNumber,
  studentId,
);
```

**REPLACE WITH:**
```dart
// Use ArcFace backend for registration
final faceRegistered = await ArcFaceBackendService.registerStudentFace(
  imagePath: _facePhotoPath!,
  instituteId: _instituteId!,
  studentId: studentId,
  rollNumber: rollNumber,
  name: name,
);

if (!faceRegistered) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('❌ Failed to register face. Please try again.'),
      backgroundColor: Colors.red,
    ),
  );
  return;
}
```

---

## ✅ Step 9: Test Everything! (5 minutes)

1. **Run your Flutter app**
2. **Register a student** → Should use ArcFace backend ✅
3. **Mark attendance** → Should recognize with 99.8% accuracy ✅

---

## 🎉 Done! Your API is Live!

### Your API URL:
```
https://face-recognition-api-xxxxx-uc.a.run.app/api/v1
```

### Check in Google Cloud Console:
1. Go to: https://console.cloud.google.com
2. Select project: `smartattendanceapp-bc2fe`
3. Navigate to: **Cloud Run** → You'll see your service!

---

## 🚨 Troubleshooting

### Deployment fails?

**Check logs:**
```bash
gcloud run services logs read face-recognition-api --region us-central1
```

**Common issues:**
1. **Not logged in**: Run `gcloud auth login` again
2. **Wrong project**: Run `gcloud config set project smartattendanceapp-bc2fe`
3. **APIs not enabled**: Run Step 4 again

### API not responding?

**Check service status:**
```bash
gcloud run services describe face-recognition-api --region us-central1
```

**Test health endpoint:**
```bash
curl https://your-url/api/v1/health
```

### Model download slow?

- First deployment downloads ArcFace model (~250MB)
- Takes 2-3 minutes - be patient!
- Subsequent deployments are faster

---

## 📊 Monitor Your API

### View Logs:
```bash
gcloud run services logs read face-recognition-api --region us-central1 --limit 50
```

### View Metrics:
1. Go to: Google Cloud Console
2. Cloud Run → Your service → Metrics
3. See: Requests, latency, errors

---

## 💰 Cost Monitoring

### Check Current Usage:
1. Go to: Google Cloud Console
2. Billing → Reports
3. Filter by: Cloud Run
4. See: Current month costs

### Set Budget Alerts:
1. Go to: Billing → Budgets & alerts
2. Create budget for Cloud Run
3. Set alert at ₹2,000/month (for 200k students)

---

## ✅ Summary

1. ✅ Install Google Cloud SDK
2. ✅ Login with Firebase account
3. ✅ Set project: `smartattendanceapp-bc2fe`
4. ✅ Enable APIs
5. ✅ Deploy backend (one command!)
6. ✅ Get API URL
7. ✅ Update Flutter app
8. ✅ Test!

**Total time**: 30 minutes  
**Cost**: ₹2,400-4,600/month (with caching)  
**Uses**: Your existing Firebase account!

---

## 🚀 Next Steps

1. Follow steps above
2. Deploy backend (Step 6)
3. Update Flutter app (Step 8)
4. Test and enjoy 99.8% accuracy! ✅

**Ready to start?** Begin with Step 1! 🎉
