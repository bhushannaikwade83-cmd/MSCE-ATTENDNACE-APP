# Auto-Generate Batches Feature - How It Works

## 📋 Overview

The **Auto-Generate Batches** feature automatically creates batches based on your institute's open and close times. You can choose between:
- **60 Minutes (Regular)**: Standard 1-hour batches
- **120 Minutes (Late Admission)**: 2-hour batches for late admission students

This saves you from manually creating each batch one by one. Multiple subjects (2-3) can run simultaneously in the same batch.

---

## 🎯 How It Works

### Step 1: Access the Feature
1. Go to **Batch Management** screen
2. Click the **"Auto-Generate Batches"** button (floating action button with ⚡ icon)

### Step 2: Fill in the Details

The dialog will ask for:

#### 1. **Institute Timing**
   - **Open Time**: When your institute opens (e.g., 7:00 AM, 8:00 AM, 9:00 AM)
   - **Close Time**: When your institute closes (e.g., 7:00 PM, 8:00 PM, 9:00 PM)
   - Total 12 hours: Some institutes 7-7, some 8-8, some 9-9
   - Use the clock picker to select times

#### 2. **Batch Duration**
   - **60 Minutes (Regular)**: Standard 1-hour batches (default)
   - **120 Minutes (Late Admission)**: 2-hour batches for late admission students
   - Select using radio buttons

#### 3. **Semester**
   - Select semester: **1** (Jan-Jun) or **2** (Jul-Dec)
   - Year is auto-detected from device date

#### 4. **Subjects**
   - Select 2-3 subjects (checkboxes) for simultaneous admission
   - Multiple subjects can run at the same time in the same batch
   - Each subject is 1 hour duration
   - All selected subjects will be assigned to all generated batches
   - If no subjects exist, default subjects are auto-created

### Step 3: Generate

Click **"Generate Batches"** button. The system will:

1. **Calculate time slots**: Creates batches (60 or 120 minutes) from open to close time
2. **Generate batch names**: 
   - Regular: "Batch 1 (08:00 - 09:00)"
   - Late Admission: "Batch 1 (08:00 - 10:00) - Late Admission"
3. **Assign multiple subjects**: All selected subjects (2-3) are assigned to each batch for simultaneous admission
4. **Create in Firestore**: Saves all batches to database
5. **Skip duplicates**: Won't create batches that already exist for the same year/timing

---

## 📐 Example Calculation

### Example 1: 8 AM to 8 PM (60 Minutes - Regular)

**Input:**
- Open Time: **8:00 AM**
- Close Time: **8:00 PM**
- Batch Duration: **60 Minutes (Regular)**
- Semester: **1**
- Year: **2026**
- Subjects: **GCC-TBC ENGLISH 30 WPM, GCC-TBC ENGLISH 40 WPM, GCC-TBC MARATHI 30 WPM** (3 subjects simultaneously)

**Generated Batches:**
```
Batch 1 (08:00 - 09:00) - Subjects: ENGLISH 30, ENGLISH 40, MARATHI 30
Batch 2 (09:00 - 10:00) - Subjects: ENGLISH 30, ENGLISH 40, MARATHI 30
Batch 3 (10:00 - 11:00) - Subjects: ENGLISH 30, ENGLISH 40, MARATHI 30
...
Batch 12 (19:00 - 20:00) - Subjects: ENGLISH 30, ENGLISH 40, MARATHI 30
```

**Total: 12 batches** (8 AM to 8 PM = 12 hours = 12 batches of 60 minutes each)

### Example 2: 7 AM to 7 PM (120 Minutes - Late Admission)

**Input:**
- Open Time: **7:00 AM**
- Close Time: **7:00 PM**
- Batch Duration: **120 Minutes (Late Admission)**
- Semester: **2**
- Year: **2026**
- Subjects: **GCC-TBC ENGLISH 50 WPM, GCC-TBC HINDI 30 WPM** (2 subjects simultaneously)

**Generated Batches:**
```
Batch 1 (07:00 - 09:00) - Late Admission - Subjects: ENGLISH 50, HINDI 30
Batch 2 (09:00 - 11:00) - Late Admission - Subjects: ENGLISH 50, HINDI 30
Batch 3 (11:00 - 13:00) - Late Admission - Subjects: ENGLISH 50, HINDI 30
Batch 4 (13:00 - 15:00) - Late Admission - Subjects: ENGLISH 50, HINDI 30
Batch 5 (15:00 - 17:00) - Late Admission - Subjects: ENGLISH 50, HINDI 30
Batch 6 (17:00 - 19:00) - Late Admission - Subjects: ENGLISH 50, HINDI 30
```

**Total: 6 batches** (7 AM to 7 PM = 12 hours = 6 batches of 120 minutes each)

### Example 2: 9 AM to 5 PM

**Input:**
- Open Time: **9:00 AM**
- Close Time: **5:00 PM**
- Semester: **2**
- Year: **2026**
- Subjects: **GCC TBC English 50**

**Generated Batches:**
```
Batch 1 (09:00 - 10:00)
Batch 2 (10:00 - 11:00)
Batch 3 (11:00 - 12:00)
Batch 4 (12:00 - 13:00)
Batch 5 (13:00 - 14:00)
Batch 6 (14:00 - 15:00)
Batch 7 (15:00 - 16:00)
Batch 8 (16:00 - 17:00)
```

**Total: 8 batches** (9 AM to 5 PM = 8 hours = 8 batches)

---

## 🔧 Technical Details

### Algorithm:
1. **Convert times to minutes**: 
   - Open time: `8:00 AM` → `480 minutes`
   - Close time: `8:00 PM` → `1200 minutes`

2. **Generate batches (60 or 120 minutes)**:
   - Start at open time
   - Create batch: `startTime` to `startTime + batchDurationMinutes`
   - Move to next slot: `startTime += batchDurationMinutes`
   - Repeat until `startTime >= closeTime`
   - For 60 minutes: Creates 12 batches (12 hours)
   - For 120 minutes: Creates 6 batches (12 hours)

3. **Format timing string**:
   - Format: `"HH:MM - HH:MM"`
   - Example: `"08:00 - 09:00"`

4. **Create batch name**:
   - Format: `"Batch {number} ({timing})"`
   - Example: `"Batch 1 (08:00 - 09:00)"`

5. **Save to Firestore**:
   - Each batch includes:
     - `name`: Batch name (includes "- Late Admission" for 120-minute batches)
     - `timing`: Timing string (e.g., "08:00 - 09:00" or "08:00 - 10:00")
     - `startTime`: `{hour: 8, minute: 0}`
     - `endTime`: `{hour: 9, minute: 0}` (or `{hour: 10, minute: 0}` for 120 minutes)
     - `batchDurationMinutes`: `60` or `120`
     - `year`: "2026"
     - `semester`: "1" or "2"
     - `subjects`: Array of selected subjects (2-3 subjects for simultaneous admission)
     - `isAutoGenerated`: `true`
     - `studentCount`: `0` (initial)

### Duplicate Prevention:
- Before creating, checks if a batch with the same `year` and `timing` already exists
- If exists, skips that batch
- Only creates new batches

---

## ✅ Benefits

1. **Time Saving**: Create 12 batches (60 min) or 6 batches (120 min) in seconds
2. **Flexibility**: Choose between 60-minute (regular) or 120-minute (late admission) batches
3. **Multiple Subjects**: Support for 2-3 subjects running simultaneously in the same batch
4. **Consistency**: All batches are exactly the selected duration (60 or 120 minutes)
5. **No Gaps**: Covers entire institute operating hours (12 hours total)
6. **Same Subjects**: All batches get the same subjects automatically
7. **No Duplicates**: Won't create batches that already exist

---

## ⚠️ Important Notes

1. **Batch Duration**: Choose 60 minutes (regular) or 120 minutes (late admission)
2. **No Overlap**: Batches don't overlap (e.g., 8-9, 9-10, 10-11 for 60 min or 8-10, 10-12, 12-14 for 120 min)
3. **No Gaps**: Covers entire time range from open to close (12 hours total)
4. **Multiple Subjects**: 2-3 subjects can run simultaneously in the same batch
5. **Same Subjects**: All generated batches get the same subjects
6. **Institute Timings**: Supports different timings (7-7, 8-8, 9-9)
7. **Can Edit Later**: You can edit individual batches after generation
8. **Can Delete**: You can delete unwanted batches manually

---

## 🎨 UI Flow

```
Batch Management Screen
    ↓
Click "Auto-Generate Batches" (FAB)
    ↓
Dialog Opens
    ↓
Select Open Time (clock picker)
    ↓
Select Close Time (clock picker)
    ↓
Select Semester (dropdown)
    ↓
Select Subjects (checkboxes - multiple)
    ↓
Click "Generate Batches"
    ↓
Loading... (creates batches)
    ↓
Success Message: "X batches generated successfully"
    ↓
Dialog Closes
    ↓
Batch List Refreshes (shows new batches)
```

---

## 🔍 Verification

After generating, check:

1. **Batch Management Screen**: Should show all new batches
2. **Firestore Console**: 
   - Go to `institutes/{instituteId}/batches`
   - Should see new batch documents
   - Check `isAutoGenerated: true` field
3. **Batch Details**: 
   - Each batch should have correct timing
   - All batches should have selected subjects
   - Year and semester should match

---

## 🆘 Troubleshooting

**Problem**: "No batches generated"
- **Solution**: Check if batches already exist for that year/timing. The system skips duplicates.

**Problem**: "Close time must be after open time"
- **Solution**: Make sure close time is later than open time (e.g., 8 AM to 10 PM, not 10 PM to 8 AM).

**Problem**: "At least one subject is required"
- **Solution**: Select at least one subject before generating.

**Problem**: "Subjects not loading"
- **Solution**: Subjects are auto-created on first use. Wait a moment and try again.

---

## 💡 Tips

1. **Generate Once**: Generate all batches at the start of the semester
2. **Edit Later**: You can edit individual batches if needed (change subjects, timing, etc.)
3. **Multiple Semesters**: Generate separately for Semester 1 and Semester 2
4. **Different Years**: Generate separately for different years
5. **Subject Changes**: You can add/remove subjects from batches after generation

---

## 📊 Example Use Case

**Scenario**: Institute operates 8 AM to 10 PM, has 2 semesters per year, offers 3 subjects.

**Steps:**
1. Generate batches for Semester 1 (Jan-Jun 2026) with all 3 subjects → 14 batches created
2. Generate batches for Semester 2 (Jul-Dec 2026) with all 3 subjects → 14 batches created
3. Total: 28 batches created in 2 clicks!

**Manual Alternative**: Would take 28+ clicks and lots of typing! 😅
