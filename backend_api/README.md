# Face Recognition Backend API for 200k+ Students

## Architecture Overview

This backend API provides fast face recognition for large-scale student databases (200,000+ students).

## Technology Stack

- **Framework**: FastAPI (Python)
- **Face Recognition**: ArcFace (InsightFace)
- **Vector Database**: FAISS (Facebook AI Similarity Search)
- **GPU**: NVIDIA GPU (optional, for faster inference)
- **Database**: Firestore (for metadata)

## Features

- ✅ ArcFace embeddings (512-dimensional vectors)
- ✅ Fast similarity search with FAISS (10-50ms for 200k vectors)
- ✅ GPU acceleration support
- ✅ Batch processing
- ✅ Caching for frequently accessed students
- ✅ RESTful API

## Performance

- **Face Embedding**: 200-400ms (with GPU: 50-100ms)
- **Vector Search**: 10-50ms (for 200k vectors)
- **Total Response Time**: 210-450ms
- **Throughput**: 100+ requests/second

## Setup Instructions

### 1. Install Dependencies

```bash
pip install fastapi uvicorn insightface onnxruntime-gpu faiss-cpu numpy pillow firebase-admin
```

### 2. Download ArcFace Model

```bash
# Download pre-trained ArcFace model
# Place in models/ directory
```

### 3. Configure Environment

```bash
# .env file
FIREBASE_CREDENTIALS_PATH=path/to/firebase-credentials.json
FAISS_INDEX_PATH=./faiss_index.bin
MODEL_PATH=./models/arcface_r100_v1.onnx
USE_GPU=true
```

### 4. Run Server

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

## API Endpoints

### POST /api/v1/recognize
Recognize a student from face photo

**Request:**
```json
{
  "image_base64": "base64_encoded_image",
  "institute_id": "institute123",
  "threshold": 0.85
}
```

**Response:**
```json
{
  "success": true,
  "match": {
    "student_id": "student123",
    "roll_number": "ROLL001",
    "name": "John Doe",
    "similarity": 0.95
  }
}
```

### POST /api/v1/register
Register a new student face

**Request:**
```json
{
  "image_base64": "base64_encoded_image",
  "institute_id": "institute123",
  "student_id": "student123",
  "roll_number": "ROLL001"
}
```

### POST /api/v1/batch-register
Register multiple students at once

### GET /api/v1/health
Health check endpoint

## Vector Database Structure

- **FAISS Index**: Flat index for exact search (best accuracy)
- **Vector Dimension**: 512 (ArcFace embedding size)
- **Index Type**: IndexFlatL2 (L2 distance) or IndexIVFFlat (faster, approximate)

## Deployment

### Option 1: Cloud Run (Google Cloud)
- Auto-scaling
- Pay per use
- GPU support available

### Option 2: AWS EC2 (with GPU)
- g4dn.xlarge or larger
- Persistent storage for FAISS index

### Option 3: Railway/Render
- Easy deployment
- May need GPU upgrade for production

## Cost Estimation (Monthly)

- **Compute**: $50-200 (depending on traffic)
- **Storage**: $10-50 (FAISS index + models)
- **Total**: ~$60-250/month for 200k students
