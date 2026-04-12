# How to Test with Your Base64 String

## ✅ Method 1: Using Swagger UI (Easiest)

1. **Open Swagger UI:**
   ```
   http://127.0.0.1:8000/docs
   ```

2. **Click on `/api/v1/recognize`** → **"Try it out"**

3. **Paste your base64 string** in the `image_base64` field:
   ```json
   {
     "image_base64": "YOUR_BASE64_STRING_HERE",
     "institute_id": "INS001",
     "threshold": 0.85
   }
   ```

4. **Click "Execute"**

---

## ✅ Method 2: Using curl (Command Line)

Replace `YOUR_BASE64_STRING_HERE` with your actual base64 string:

```bash
curl -X POST "http://127.0.0.1:8000/api/v1/recognize" \
  -H "accept: application/json" \
  -H "Content-Type: application/json" \
  -d "{\"image_base64\": \"YOUR_BASE64_STRING_HERE\", \"institute_id\": \"INS001\", \"threshold\": 0.85}"
```

**Important:** 
- The base64 string should be **very long** (at least 1000+ characters for a small image)
- It should **NOT** include the `data:image/jpeg;base64,` prefix
- It should be **pure base64** characters only

---

## ✅ Method 3: Using PowerShell (Windows)

```powershell
$base64 = "YOUR_BASE64_STRING_HERE"
$body = @{
    image_base64 = $base64
    institute_id = "INS001"
    threshold = 0.85
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://127.0.0.1:8000/api/v1/recognize" -Method POST -Body $body -ContentType "application/json"
```

---

## 🔍 How to Check if Your Base64 is Valid

A valid base64 image string:
- ✅ Is **very long** (1000+ characters for small images, 10,000+ for photos)
- ✅ Contains only: `A-Z`, `a-z`, `0-9`, `+`, `/`, `=` characters
- ✅ Ends with `=` or `==` (padding)
- ✅ Does **NOT** start with `data:image/...`

**Example of valid base64 start:**
```
/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAv/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k=
```

---

## ❌ Common Errors

### Error: "Base64 string is too short"
- **Cause:** You're using `"string"` as placeholder
- **Fix:** Use a real base64 string from an actual image

### Error: "Incorrect padding"
- **Cause:** Base64 string is corrupted or incomplete
- **Fix:** Regenerate the base64 string from the original image

### Error: "No face detected"
- **Cause:** The image doesn't contain a face, or the face is too small/blurry
- **Fix:** Use a clear photo with a visible face

---

## 🚀 Quick Test: Generate Base64 from Image

If you have an image file, run:

```bash
cd backend_api
python test_base64.py path/to/your/image.jpg
```

This will print a valid base64 string you can copy and use!
