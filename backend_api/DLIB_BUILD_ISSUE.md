# dlib Build Issue - CMake Compatibility

## Problem
dlib 19.24.2 fails to build on Cloud Run due to CMake version incompatibility:
- Newer CMake (3.31.6) doesn't support old policy versions
- dlib's pybind11 submodule requires CMake 3.5 but newer CMake removed compatibility

## Solutions

### Option 1: Use Pre-built dlib Wheel (Recommended)
Try installing from a pre-built wheel source:
```dockerfile
RUN pip install --no-cache-dir https://github.com/sachadee/Dlib/releases/download/v19.22/dlib-19.22.0-cp310-cp310-linux_x86_64.whl
```

### Option 2: Use Older dlib Version
Try dlib 19.22.0 which might have better compatibility:
```txt
dlib==19.22.0
```

### Option 3: Switch to Different Face Recognition Library
Use a library that doesn't require compilation:
- `deepface` - Uses TensorFlow/Keras (pre-built wheels)
- `facenet-pytorch` - Uses PyTorch (pre-built wheels)

### Option 4: Use Pre-built Docker Base Image
Use a base image that already has dlib compiled:
```dockerfile
FROM python:3.10-slim
# Install from pre-built source
```

## Current Status
- ✅ Removed ONNX Runtime (Cloud Run incompatible)
- ✅ Switched to face_recognition library
- ❌ dlib compilation failing due to CMake issues

## Recommendation
Try Option 1 or Option 2 first. If those don't work, consider Option 3 (deepface) which is easier to deploy.
