# Postman Test Guide for Face Recognition API

## 🔗 Backend API URL

**Production URL:**
```
https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1
```

**Local URL (if running locally):**
```
http://localhost:8000/api/v1
```

---

## ✅ Step 1: Health Check

**Method:** `GET`  
**URL:** `https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/health`

**Expected Response:**
```json
{
  "status": "healthy",
  "service": "face-recognition-api",
  "version": "1.0.0"
}
```

---

## 📝 Step 2: Register Face (POST)

**Method:** `POST`  
**URL:** `https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/register`

**Headers:**
```
Content-Type: application/json
```

**Body (JSON):**
```json
{
  "institute_id": "INS001",
  "student_id": "STU001",
  "roll_number": "ROLL001",
  "name": "Test Student",
  "image_base64": "BASE64_ENCODED_IMAGE_HERE"
}
```

### How to Get Base64 Image:

**Option 1: Using Online Tool**
1. Go to https://www.base64-image.de/
2. Upload your image
3. Copy the base64 string (without `data:image/jpeg;base64,` prefix)

**Option 2: Using Python**
```python
import base64

with open("face.jpg", "rb") as image_file:
    encoded = base64.b64encode(image_file.read()).decode('utf-8')
    print(encoded)
```

**Option 3: Using Node.js**
```javascript
const fs = require('fs');
const image = fs.readFileSync('face.jpg');
const base64 = image.toString('base64');
console.log(base64);
```

### Expected Success Response:
```json
{
  "success": true,
  "message": "Face registered for ROLL001"
}
```

### Expected Error Response:
```json
{
  "detail": "Registration failed: ValueError - No face detected in image..."
}
```

---

## 🔍 Step 3: Recognize Face (POST)

**Method:** `POST`  
**URL:** `https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/recognize`

**Headers:**
```
Content-Type: application/json
```

**Body (JSON):**
```json
{
  "image_base64": "BASE64_ENCODED_IMAGE_HERE",
  "institute_id": "INS001",
  "threshold": 0.85
}
```

### Expected Success Response:
```json
{
  "success": true,
  "match": {
    "student_id": "STU001",
    "roll_number": "ROLL001",
    "name": "Test Student",
    "similarity": 0.92
  },
  "processing_time_ms": 250.5
}
```

### Expected No Match Response:
```json
{
  "success": false,
  "match": null,
  "similarity": null,
  "processing_time_ms": 200.3
}
```

---

## ✅ Step 4: Verify Face (POST)

**Method:** `POST`  
**URL:** `https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/verify`

**Headers:**
```
Content-Type: application/json
```

**Body (JSON):**
```json
{
  "image_base64": "BASE64_ENCODED_IMAGE_HERE",
  "institute_id": "INS001",
  "roll_number": "ROLL001",
  "threshold": 0.70
}
```

### Expected Success Response:
```json
{
  "success": true,
  "match": true,
  "similarity": 0.88,
  "security_check_passed": true,
  "processing_time_ms": 180.2
}
```

---

## 🧪 Quick Test Image

Use this small test image (base64 encoded 1x1 pixel - will fail face detection but tests API):

```
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==
```

**Note:** This will return "No face detected" error, but confirms API is working!

---

## 📋 Postman Collection JSON

Save this as `FaceRecognitionAPI.postman_collection.json`:

```json
{
  "info": {
    "name": "Face Recognition API",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "item": [
    {
      "name": "Health Check",
      "request": {
        "method": "GET",
        "header": [],
        "url": {
          "raw": "https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/health",
          "host": ["face-recognition-api-mv5fg3vmlq-uc", "a", "run", "app"],
          "path": ["api", "v1", "health"]
        }
      }
    },
    {
      "name": "Register Face",
      "request": {
        "method": "POST",
        "header": [
          {
            "key": "Content-Type",
            "value": "application/json"
          }
        ],
        "body": {
          "mode": "raw",
          "raw": "{\n  \"institute_id\": \"INS001\",\n  \"student_id\": \"STU001\",\n  \"roll_number\": \"ROLL001\",\n  \"name\": \"Test Student\",\n  \"image_base64\": \"YOUR_BASE64_IMAGE_HERE\"\n}"
        },
        "url": {
          "raw": "https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/register",
          "host": ["face-recognition-api-mv5fg3vmlq-uc", "a", "run", "app"],
          "path": ["api", "v1", "register"]
        }
      }
    },
    {
      "name": "Recognize Face",
      "request": {
        "method": "POST",
        "header": [
          {
            "key": "Content-Type",
            "value": "application/json"
          }
        ],
        "body": {
          "mode": "raw",
          "raw": "{\n  \"image_base64\": \"YOUR_BASE64_IMAGE_HERE\",\n  \"institute_id\": \"INS001\",\n  \"threshold\": 0.85\n}"
        },
        "url": {
          "raw": "https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/recognize",
          "host": ["face-recognition-api-mv5fg3vmlq-uc", "a", "run", "app"],
          "path": ["api", "v1", "recognize"]
        }
      }
    }
  ]
}
```

---

## 🔧 Troubleshooting

### Error: "Connection refused"
- Check if backend is running
- Verify URL is correct
- Check firewall/network settings

### Error: "500 Internal Server Error"
- Check backend terminal logs
- Verify image is valid base64
- Ensure image contains a face

### Error: "No face detected"
- Use a clear face photo
- Ensure face is clearly visible
- Check image size (minimum 160x160 pixels)

### Error: "Registration failed: "
- Check backend terminal for full error
- Verify all required fields are present
- Check image format (JPEG/PNG)

---

## ✅ Success Checklist

- [ ] Health check returns 200 OK
- [ ] Register endpoint accepts request
- [ ] Image is valid base64 format
- [ ] Face is detected in image
- [ ] Registration completes successfully
- [ ] Recognize endpoint finds registered face
