# Deploy ArcFace to Firebase (Google Cloud Run) - Simple Guide 🚀

## ✅ Yes! Use Your Existing Firebase Project

Since you already have Firebase (`smartattendanceapp-bc2fe`), deploy your ArcFace backend to **Google Cloud Run** (same Firebase project, no new account needed!).

---

## 🎯 Simple Setup (20 Minutes)

### Step 1: Install Google Cloud SDK

**Windows:**
```powershell
# Download from: https://cloud.google.com/sdk/docs/install
# Or use PowerShell:
(New-Object Net.WebClient).DownloadFile("https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe", "$env:Temp\GoogleCloudSDKInstaller.exe")
& $env:Temp\GoogleCloudSDKInstaller.exe
```

**Mac/Linux:**
```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

### Step 2: Login to Google Cloud

```bash
gcloud init
# Select your Firebase project: smartattendanceapp-bc2fe
gcloud auth login
```

### Step 3: Enable Required APIs

```bash
gcloud services enable run.googleapis.com
gcloud services enable cloudbuild.googleapis.com
```

### Step 4: Deploy Your Backend

```bash
cd backend_api

# Deploy to Cloud Run (uses your Firebase project!)
gcloud run deploy face-recognition-api \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 2Gi \
  --timeout 300 \
  --project smartattendanceapp-bc2fe
```

**That's it!** Cloud Run will:
- Build your Python app
- Install dependencies
- Deploy automatically
- Give you a URL

### Step 5: Get Your API URL

After deployment, you'll see:
```
Service URL: https://face-recognition-api-xxxxx-uc.a.run.app
```

Copy this URL!

### Step 6: Update Flutter App

Add to `.env` file:
```env
FACE_RECOGNITION_API_URL=https://face-recognition-api-xxxxx-uc.a.run.app/api/v1
```

---

## ✅ What You Get

- ✅ **Uses your existing Firebase project** - No new account!
- ✅ **Free tier**: 2 million requests/month free
- ✅ **Auto-scaling** - Handles any traffic
- ✅ **Same project** - Everything in Firebase Console
- ✅ **Easy updates** - Just redeploy

---

## 💰 Cost: $0/Month (Free Tier)

- **Cloud Run**: 2M requests/month free ✅
- **ArcFace Model**: Free (open source) ✅
- **Storage**: Uses your existing Firebase ✅
- **Total**: **$0/month** ✅

---

## 🚀 Update Your Code

### In `admin_attendance_screen.dart`:

**FIND (around line 1363):**
```dart
final faceVerified = await FaceRecognitionService.verifyStudent(...);
```

**REPLACE WITH:**
```dart
// Use ArcFace backend (Firebase Cloud Run)
final match = await ArcFaceBackendService.recognizeStudent(
  imagePath: photo.path,
  instituteId: instituteId!,
  threshold: 0.85,
);

if (match != null && match['rollNumber'] == selectedRollNumber) {
  // Face verified! ✅
  // Continue with attendance...
} else {
  // Show error
  setState(() => isLoading = false);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('❌ Face recognition failed'),
      backgroundColor: Colors.red,
    ),
  );
  return;
}
```

---

## 📝 Summary

1. **Install Google Cloud SDK** (5 min)
2. **Deploy to Cloud Run** (10 min) - Uses your Firebase project!
3. **Update Flutter app** (5 min)
4. **Done!** ✅

**Total time**: 20 minutes  
**Cost**: $0/month (free tier)  
**Uses**: Your existing Firebase project!

---

## 🎉 Benefits

1. ✅ **No new account** - Uses your Firebase
2. ✅ **Free tier** - 2M requests/month
3. ✅ **Easy deployment** - One command
4. ✅ **Auto-scaling** - Handles traffic
5. ✅ **Same project** - Everything together

**No external services needed!** Everything in your Firebase project. 🚀
