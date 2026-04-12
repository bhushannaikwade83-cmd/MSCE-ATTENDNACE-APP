# Troubleshooting: "Method Not Allowed" Error

## ❌ Error Message
```json
{"detail": "Method Not Allowed"}
```

## 🔍 Common Causes

### 1. **Using GET instead of POST**
The `/api/v1/register` endpoint **requires POST method**, not GET.

**❌ Wrong:**
```
GET https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/register
```

**✅ Correct:**
```
POST https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/register
```

---

### 2. **Wrong URL Path**
Make sure you're using the full path: `/api/v1/register`

**❌ Wrong:**
```
POST https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/register
```

**✅ Correct:**
```
POST https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/register
```

---

### 3. **Missing Content-Type Header**
The request must include `Content-Type: application/json` header.

**✅ Correct Headers:**
```
Content-Type: application/json
```

---

### 4. **CORS Preflight Issues**
If testing from a browser, make sure OPTIONS requests are allowed (already configured).

---

## ✅ Correct Request Format

### **Using cURL:**
```bash
curl -X POST \
  https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/register \
  -H "Content-Type: application/json" \
  -d '{
    "institute_id": "INS001",
    "student_id": "STU001",
    "roll_number": "ROLL001",
    "name": "Test Student",
    "image_base64": "BASE64_IMAGE_STRING"
  }'
```

### **Using Postman:**
1. Method: **POST** (not GET)
2. URL: `https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/register`
3. Headers: `Content-Type: application/json`
4. Body: JSON with required fields

### **Using JavaScript (Fetch):**
```javascript
fetch('https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/register', {
  method: 'POST',  // ← Must be POST
  headers: {
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    institute_id: 'INS001',
    student_id: 'STU001',
    roll_number: 'ROLL001',
    name: 'Test Student',
    image_base64: 'BASE64_IMAGE_STRING'
  })
})
```

### **Using Python (requests):**
```python
import requests

response = requests.post(  # ← Must be POST
    'https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/register',
    headers={'Content-Type': 'application/json'},
    json={
        'institute_id': 'INS001',
        'student_id': 'STU001',
        'roll_number': 'ROLL001',
        'name': 'Test Student',
        'image_base64': 'BASE64_IMAGE_STRING'
    }
)
```

---

## 🔧 Quick Fixes

### **If using a web browser:**
- Don't type the URL directly in the browser (browsers use GET by default)
- Use Postman, cURL, or a web form that sends POST requests

### **If using Flutter app:**
- The Flutter app already uses POST correctly
- Check the `_baseUrl` in `arcface_backend_service.dart`
- Make sure it includes `/api/v1` in the path

### **If testing with Postman:**
1. Select **POST** from the method dropdown
2. Enter URL: `https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/register`
3. Go to **Headers** tab → Add: `Content-Type: application/json`
4. Go to **Body** tab → Select **raw** → Select **JSON**
5. Paste your JSON body

---

## 🧪 Test the API

### **Step 1: Health Check (GET - this one works with GET)**
```bash
curl https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/health
```

### **Step 2: API Info (GET)**
```bash
curl https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/
```

### **Step 3: Register (POST - must use POST)**
```bash
curl -X POST \
  https://face-recognition-api-mv5fg3vmlq-uc.a.run.app/api/v1/register \
  -H "Content-Type: application/json" \
  -d '{
    "institute_id": "INS001",
    "student_id": "STU001",
    "roll_number": "ROLL001",
    "name": "Test Student",
    "image_base64": "YOUR_BASE64_IMAGE"
  }'
```

---

## 📋 All Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/health` | GET | Health check |
| `/api/v1/` | GET | API information |
| `/api/v1/register` | **POST** | Register face |
| `/api/v1/recognize` | **POST** | Recognize face |
| `/api/v1/verify` | **POST** | Verify face |

**Note:** All endpoints except `/health` and `/` require **POST** method.

---

## 🐛 Debug Steps

1. **Check the HTTP method:**
   - Is it POST? (Not GET, PUT, DELETE)

2. **Check the URL:**
   - Is it `/api/v1/register`? (Not `/register`)

3. **Check the headers:**
   - Is `Content-Type: application/json` included?

4. **Check the body:**
   - Is it valid JSON?
   - Are all required fields present?

5. **Check CORS (if from browser):**
   - Are you testing from an allowed origin?
   - CORS is configured to allow all origins (`*`)

---

## 💡 Common Mistakes

❌ **Typing URL in browser address bar** → Browser uses GET  
✅ **Use Postman or cURL with POST method**

❌ **Missing `/api/v1` prefix** → Wrong endpoint  
✅ **Use full path: `/api/v1/register`**

❌ **Using GET method** → Method Not Allowed  
✅ **Use POST method**

❌ **Missing Content-Type header** → May cause issues  
✅ **Include: `Content-Type: application/json`**

---

## 📞 Still Having Issues?

1. Check backend logs for detailed error messages
2. Verify the backend is running: `GET /api/v1/health`
3. Test with Postman using the examples above
4. Check network tab in browser DevTools for actual request details

---

## ✅ Updated Error Messages

The backend now returns more helpful error messages:

```json
{
  "detail": "Method Not Allowed. This endpoint requires POST method. You used GET. Please use POST to /api/v1/register"
}
```

This will help you identify exactly what went wrong!
