# Quick Guide: Convert Your Image to Base64

## Step 1: Save the Image
1. Right-click on the image you shared
2. Click "Save image as..." or "Save picture as..."
3. Save it to an easy location like:
   - `C:\Users\naikw\Desktop\test_face.jpg`
   - `C:\Users\naikw\Pictures\face.jpg`
   - Or in the `backend_api` folder: `backend_api\test_face.jpg`

## Step 2: Convert to Base64

### Option A: Using Python Script (Recommended)
```powershell
cd backend_api
python convert_image_to_base64_simple.py "C:\Users\naikw\Desktop\test_face.jpg"
```

### Option B: Using the Test Script
```powershell
cd backend_api
python test_base64.py "C:\Users\naikw\Desktop\test_face.jpg"
```

## Step 3: Copy the Base64 String
The script will print a long base64 string. Copy it!

## Step 4: Test in Swagger UI
1. Open: http://127.0.0.1:8000/docs
2. Click `/api/v1/recognize` → "Try it out"
3. Paste your base64 string in the JSON:
   ```json
   {
     "image_base64": "PASTE_YOUR_BASE64_HERE",
     "institute_id": "INS001",
     "threshold": 0.85
   }
   ```
4. Click "Execute"

---

## Alternative: Quick Python One-Liner

If you have Python installed, you can also run this directly:

```python
import base64
with open("path/to/your/image.jpg", "rb") as f:
    print(base64.b64encode(f.read()).decode())
```

Replace `path/to/your/image.jpg` with your actual image path.
