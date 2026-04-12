# 📸 Where to Check Debug Image

The debug image is saved automatically when you make a face recognition/registration request. Here's where to find it:

---

## 🖥️ **If Running Locally (Windows)**

The debug image is saved to your Windows temp directory:

**Path:**
```
C:\Users\<YourUsername>\AppData\Local\Temp\debug_images\debug_received.jpg
```

**Quick Access:**
1. Press `Win + R`
2. Type: `%TEMP%\debug_images`
3. Press Enter
4. Open `debug_received.jpg`

**Or via Command:**
```powershell
# Open the debug images folder
explorer "$env:TEMP\debug_images"
```

---

## 🖥️ **If Running Locally (Mac/Linux)**

**Path:**
```
/tmp/debug_images/debug_received.jpg
```

**Quick Access:**
```bash
# View the image
open /tmp/debug_images/debug_received.jpg  # Mac
xdg-open /tmp/debug_images/debug_received.jpg  # Linux

# Or navigate to folder
cd /tmp/debug_images
ls -la
```

---

## ☁️ **If Deployed on Google Cloud Run**

The debug image is saved to `/tmp/debug_images/` in the container, but this is **ephemeral** (deleted when container restarts).

### Option 1: Download via API Endpoint (Easiest!)

I've added a new endpoint to download the debug image:

**URL:**
```
https://your-api-url.run.app/api/v1/debug-image
```

**How to Use:**
1. Make a face recognition/registration request first
2. Then open this URL in your browser:
   ```
   https://face-recognition-api-xxxxx-uc.a.run.app/api/v1/debug-image
   ```
3. The image will download automatically

**Or use curl:**
```bash
curl -o debug_received.jpg https://your-api-url.run.app/api/v1/debug-image
```

### Option 2: Check Cloud Run Logs

The logs will show the path where the image was saved:

```
💾 Debug image saved: /tmp/debug_images/debug_received.jpg
```

### Option 3: Use Cloud Console (Advanced)

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Navigate to **Cloud Run** → Your service
3. Click on a specific revision/instance
4. Use **Cloud Shell** to access the container (if available)

---

## 🔍 **What to Check in the Debug Image**

When you open `debug_received.jpg`, verify:

1. ✅ **Image is clear** - Not blurry or pixelated
2. ✅ **Face is visible** - Face should be clearly visible in the frame
3. ✅ **Not sideways** - Image should be upright (not rotated 90° or 180°)
4. ✅ **Good lighting** - Face should be well-lit (not too dark or overexposed)
5. ✅ **Face size** - Face should fill 30-50% of the frame
6. ✅ **Single face** - Only one face should be visible

---

## 🐛 **If Image Looks Wrong**

### Image is Rotated (Sideways)
- **Problem:** Flutter camera saved image rotated
- **Solution:** The backend automatically tries rotations (90°, 180°, 270°)
- **Check logs:** Look for "Face detected after X rotation"

### Image is Too Small
- **Problem:** Image dimensions < 160x160 pixels
- **Solution:** Backend automatically resizes to 640x640
- **Check logs:** Look for "Image too small" warning

### Image is Blurry
- **Problem:** Camera moved during capture
- **Solution:** Retake photo with steady hands

### No Face Visible
- **Problem:** Face not in frame or too far away
- **Solution:** Ensure face is clearly visible and fills 30-50% of frame

---

## 📝 **Backend Logs to Check**

When you make a request, check the backend logs for:

```
==================================================
🔍 DEBUG: Image received and decoded
Image type: <class 'numpy.ndarray'>
Image shape: (640, 480, 3)
Image dtype: uint8
Image min/max: 0/255
==================================================
💾 Debug image saved: /tmp/debug_images/debug_received.jpg
   → Check if image is clear, face visible, and not sideways!
📏 Image dimensions: 480x640
✅ Converted BGR to RGB
✅ Final image array shape: (640, 480, 3), dtype: uint8
🔍 Attempting face detection with original image...
✅ Face detected using opencv detector (strict mode)
```

---

## 🚀 **Quick Test**

1. **Make a face recognition request** from your Flutter app
2. **Check the path** shown in logs or use the API endpoint
3. **Open the image** and verify it looks correct
4. **If image is wrong**, the backend will try rotations automatically

---

## 💡 **Tip**

The debug image is **overwritten** on each new request. If you want to keep multiple debug images, the backend saves them with timestamps in the logs (but only the latest is accessible via the API endpoint).
