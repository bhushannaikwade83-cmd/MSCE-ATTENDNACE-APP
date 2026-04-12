# Flutter API Call Example - Face Registration

## Correct API Call Format

```dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

// Read image file
final imageFile = File(imagePath);
final bytes = await imageFile.readAsBytes();
String base64Image = base64Encode(bytes);

// Make API call
final response = await http.post(
  Uri.parse("https://your-api/register"),
  headers: {
    "Content-Type": "application/json"
  },
  body: jsonEncode({
    "institute_id": "INS001",
    "student_id": studentId,
    "roll_number": rollNumber,
    "name": studentName,
    "image_base64": base64Image  // ✅ Always use image_base64 (single image)
  }),
);

// Handle response
if (response.statusCode == 200) {
  final data = jsonDecode(response.body);
  print("Success: ${data['success']}");
} else {
  print("Error: ${response.statusCode}");
  print("Response: ${response.body}");
}
```

## Key Points:
- ✅ Always use `image_base64` (string, not array)
- ✅ Send only the first/main image
- ✅ Do NOT use `images_base64` (this causes errors)
- ✅ Content-Type must be `application/json`
- ✅ Base64 encode the image bytes before sending
