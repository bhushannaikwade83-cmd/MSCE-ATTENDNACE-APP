# Attendance App - Quick Reference Guide

## 🎯 App Purpose
Biometric attendance management system for educational institutes with face recognition, GPS geofencing, and flexible batch management.
---

## 🔑 Key Features at a Glance

| Feature | Description |
|---------|-------------|
| **🔐 Security** | IRCTC-style biometric + PIN authentication |
| **👥 Students** | Registration with photo, multiple batches, multiple subjects |
| **⏰ Batches** | Auto-generate 60-min (regular) or 120-min (late admission) batches |
| **📚 Subjects** | 8 predefined computer typing subjects (no custom subjects) |
| **📅 Semesters** | Semester 1 (Jan-Jun) or Semester 2 (Jul-Dec) with auto year |
| **✅ Attendance** | Face recognition + GPS (30m radius) + Entry/Exit photos |
| **📊 Reports** | Date range reports (max 1 month) with photos and timestamps |
| **🌙 Dark Mode** | Light/Dark theme toggle |

---

## 📱 Main Screens

```
┌─────────────────────────────────────┐
│         HOME DASHBOARD              │
│  • Quick Stats                      │
│  • Attendance Rate                  │
│  • Quick Access Buttons             │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│      ATTENDANCE MARKING             │
│  • Select Student                   │
│  • Face Recognition                 │
│  • GPS Verification (30m)           │
│  • Entry/Exit Photos                │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│      STUDENT MANAGEMENT            │
│  • View All Students               │
│  • Add/Edit/Delete                 │
│  • Search & Filter                │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│      BATCH MANAGEMENT              │
│  • Auto-Generate Batches           │
│  • 60 min or 120 min               │
│  • Multiple Subjects                │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│         REPORTS                     │
│  • Date Range (max 1 month)        │
│  • Export/Share                    │
│  • Calendar View                   │
└─────────────────────────────────────┘
```

---

## 🔄 User Flow

### Login Flow
```
App Launch
    ↓
Splash Screen
    ↓
Login Screen (Email/PIN/Biometric)
    ↓
Biometric Lock (if enabled)
    ↓
Home Dashboard
```

### Attendance Flow
```
Select Student
    ↓
Mark Entry
    ├─→ Face Recognition
    ├─→ GPS Check (30m)
    ├─→ Photo Capture
    └─→ Time Recorded
    ↓
Mark Exit
    ├─→ Face Recognition
    ├─→ GPS Check (30m)
    ├─→ Photo Capture
    └─→ Time Recorded
```

### Batch Generation Flow
```
Auto-Generate Batches
    ↓
Configure:
    • Open/Close Time (12 hours)
    • Duration (60 or 120 min)
    • Semester (1 or 2)
    • Subjects (2-3)
    ↓
Generate
    ↓
Batches Created
```

---

## 📋 Predefined Data

### Subjects (8 Fixed)
1. GCC-TBC ENGLISH 30 WPM
2. GCC-TBC ENGLISH 40 WPM
3. GCC-TBC ENGLISH 50 WPM
4. GCC-TBC ENGLISH 60 WPM
5. GCC-TBC MARATHI 30 WPM
6. GCC-TBC MARATHI 40 WPM
7. GCC-TBC HINDI 30 WPM
8. GCC-TBC HINDI 40 WPM

### Semesters
- **Semester 1**: January to June
- **Semester 2**: July to December
- **Year**: Auto-detected from device date

---

## ⏰ Batch Examples

### 60 Minutes (Regular)
**8 AM to 8 PM (12 hours)**
- Batch 1: 08:00 - 09:00
- Batch 2: 09:00 - 10:00
- Batch 3: 10:00 - 11:00
- ...
- Batch 12: 19:00 - 20:00
- **Total: 12 batches**

### 120 Minutes (Late Admission)
**8 AM to 8 PM (12 hours)**
- Batch 1: 08:00 - 10:00 - Late Admission
- Batch 2: 10:00 - 12:00 - Late Admission
- Batch 3: 12:00 - 14:00 - Late Admission
- Batch 4: 14:00 - 16:00 - Late Admission
- Batch 5: 16:00 - 18:00 - Late Admission
- Batch 6: 18:00 - 20:00 - Late Admission
- **Total: 6 batches**

---

## ✅ Attendance Rules

| Rule | Description |
|------|-------------|
| **Flexible** | Students can mark in any batch |
| **Face Recognition** | Required for entry and exit |
| **GPS Check** | Must be within 30-meter radius |
| **Photos** | Entry and exit photos with timestamps |
| **Time Tracking** | Separate entry and exit times |

---

## 🔒 Security Features

- ✅ **Biometric**: Fingerprint/Face ID
- ✅ **PIN**: 4-6 digit SHA-256 hashed
- ✅ **Auto-Lock**: App locks when minimized
- ✅ **Session Management**: Auto-logout on expiry
- ✅ **GPS Geofencing**: 30-meter radius
- ✅ **Face Recognition**: Prevents proxy attendance

---

## 📊 Reports Features

- **Date Range**: Select from/to date (max 1 month)
- **Student-wise**: Individual attendance records
- **Photos**: Entry/exit photos with timestamps
- **Export**: PDF/Excel download
- **Calendar View**: Monthly calendar with indicators
- **Trends**: Visual charts and analytics

---

## 🎨 UI Features

- Modern glassmorphic design
- Smooth animations
- Dark mode support
- Responsive layout
- Intuitive navigation
- Visual feedback

---

## 🚀 Quick Start

### For Admin
1. Login (Email/PIN/Biometric)
2. Configure GPS location (30m radius)
3. Auto-generate batches
4. Add students with photos
5. Start marking attendance

### For Users
1. Login
2. Navigate to Attendance
3. Select student
4. Mark entry/exit
5. View reports

---

## 📞 Support

- **Help Desk**: Settings → Help Desk
- **FAQ**: Common questions
- **Contact**: Support team

---

## ✅ Checklist

### Setup Checklist
- [ ] Login credentials configured
- [ ] GPS location set (30m radius)
- [ ] Batches created (auto or manual)
- [ ] Students registered with photos
- [ ] Face templates generated
- [ ] Subjects initialized (8 predefined)

### Daily Operations
- [ ] Open app (biometric/PIN)
- [ ] Navigate to Attendance
- [ ] Mark student entry
- [ ] Mark student exit
- [ ] Verify photos and timestamps
- [ ] Generate reports as needed

---

**Version**: 1.0  
**Last Updated**: January 2026
