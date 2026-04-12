# ONNX Runtime Cloud Run Compatibility Issue

## 🔴 Problem

The deployment is failing with this error:
```
ImportError: /usr/local/lib/python3.10/site-packages/onnxruntime/capi/onnxruntime_pybind11_state.cpython-310-x86_64-linux-gnu.so: cannot enable executable stack as shared object requires: Invalid argument
```

This is a **security restriction** in Google Cloud Run that prevents libraries from using executable stacks.

## ✅ Solutions

### Option 1: Use Alternative Face Recognition (Recommended)

Instead of InsightFace (which requires ONNX Runtime), use a library that doesn't need ONNX:

**Option 1A: Use `face_recognition` library (dlib-based)**
```python
# requirements.txt
face-recognition==1.3.0
dlib==19.24.2
```

**Option 1B: Use TensorFlow Lite (works on Cloud Run)**
- Use MobileNet-based face recognition
- No ONNX Runtime dependency

### Option 2: Use Different Deployment Platform

Deploy to:
- **Google Cloud Compute Engine** (VM) - allows executable stacks
- **AWS Lambda** with custom runtime
- **Azure Container Instances**

### Option 3: Build Custom ONNX Runtime

Build ONNX Runtime from source without executable stack requirement (complex).

## 🚀 Recommended: Switch to face_recognition Library

The `face_recognition` library uses dlib and doesn't require ONNX Runtime. It's:
- ✅ Free and open source
- ✅ Works on Cloud Run
- ✅ Good accuracy (99.38% on LFW)
- ✅ Easy to use

Would you like me to:
1. **Convert the code to use `face_recognition` library?** (Recommended)
2. **Try deploying to Compute Engine instead?**
3. **Try a different ONNX Runtime version/workaround?**

Let me know which option you prefer! 🎯
