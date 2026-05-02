# 🚀 Bulk Import 1 Lakh+ Students - Complete Guide

**Goal:** Import 100,000+ students into Supabase **FAST** using PostgreSQL COPY method  
**Speed:** ~10,000-50,000 students per minute (depends on network)  
**Recommended Method:** `fast_load_students_pg_copy.py` (25-50x faster than REST API)

---

## 📋 Step 1: Prepare Your Data

### **Required CSV Format**

Your CSV should have these columns (in any order):

```csv
instid,formserialno,fname,mname,lname,SUBJECT_1,SUBJECT_2,SUBJECT_3,SUBJECT_4,SUBJECT_5
11061,10001,KRUTIKA,SHANKAR,GOSAVI,GCC TBC ENG 30,0,GCC TBC MAR 30,0,0
11061,10002,AMIT,,SHARMA,MATH 101,PHY 102,CHEM 103,0,0
```

**Column Mapping:**
| Your Data | CSV Column | Description |
|-----------|-----------|-------------|
| Institute Code | `instid` | Institute ID (must exist in institutes table) |
| Student Roll/ID | `formserialno` | Unique identifier within institute |
| Full Name / First Name | `fname` | Student first name |
| Middle Name | `mname` | Middle name (can be blank) |
| Last Name | `lname` | Last name (can be blank) |
| Subject 1-N | `SUBJECT_1` to `SUBJECT_5+` | Subject codes (use "0" for not enrolled) |

### **Example: Convert Excel to CSV**

**In Excel/Google Sheets:**
1. Go to Sheet menu → Save as CSV
2. Or use Python:

```bash
python3 << 'EOF'
import pandas as pd

# Read Excel file
df = pd.read_excel('your_students.xlsx')

# Map your columns to required format
df_clean = df.rename(columns={
    'Your_Institute_Column': 'instid',
    'Your_Roll_Column': 'formserialno',
    'Your_First_Name': 'fname',
    'Your_Last_Name': 'lname',
})

# Save as CSV
df_clean.to_csv('STUDENTS.csv', index=False)
print(f"✅ Created STUDENTS.csv with {len(df_clean)} rows")
EOF
```

---

## 🔑 Step 2: Get Database Connection String

### **Option A: Session Pooler (RECOMMENDED - Fastest & Most Reliable)**

This is the **fastest** method for large imports.

1. Open [Supabase Dashboard](https://app.supabase.com)
2. Select your project
3. Go: **Database** → **Connection pooling**
4. Copy the **Session pooler** connection string
5. Make sure to:
   - Change `[YOUR-PASSWORD]` to your actual password
   - Look for format: `postgres://postgres.<project-ref>:password@aws-0-region.pooler.supabase.com:5432/postgres`

```bash
# Set environment variable
export DATABASE_SESSION_POOL_URL="postgres://postgres.YOUR_PROJECT_REF:PASSWORD@aws-0-YOUR_REGION.pooler.supabase.com:5432/postgres"

# Or add to .env file
echo 'DATABASE_SESSION_POOL_URL="postgres://postgres.YOUR_PROJECT_REF:PASSWORD@aws-0-YOUR_REGION.pooler.supabase.com:5432/postgres"' >> .env
```

### **Option B: Direct Connection (Slower but works)**

```bash
export DATABASE_URL="postgres://postgres:YOUR_PASSWORD@db.YOUR_PROJECT.supabase.co:5432/postgres"
```

> **⚠️ Note:** Direct connection might have IPv6 issues. Session pooler is preferred.

### **Network Restrictions Issue?**

If you see: `address not in tenant allow_list`

1. Go to Supabase Dashboard
2. **Database** → **Network Restrictions**
3. Add your public IP or temporarily **Allow all** (for testing)

---

## 📦 Step 3: Install Dependencies

```bash
# Install Python requirements for fast import
cd /path/to/EDUSETU-ATTENDACE-APP-main
pip install -r scripts/requirements-fast-pg-load.txt

# This installs: psycopg[binary], pandas, python-dotenv
```

---

## 🏃 Step 4: Run the Fast Import (Main Steps)

### **Quick Command (Recommended)**

```bash
python3 scripts/fast_load_students_pg_copy.py scripts/STUDENTS.csv \
  --match sr_no \
  --max-subjects 5 \
  --ignore-zero-subject-rows
```

### **With Full Options**

```bash
python3 scripts/fast_load_students_pg_copy.py \
  YOUR_CSV_FILE.csv \
  --match sr_no \
  --max-subjects 5 \
  --ignore-zero-subject-rows \
  --copy-chunk-rows 5000 \
  --prefer-ipv4
```

**Parameter Explanation:**

| Parameter | Meaning | Default |
|-----------|---------|---------|
| `YOUR_CSV_FILE.csv` | Path to your CSV file | Required |
| `--match sr_no` | Match students by serial number | `user_id` |
| `--max-subjects 5` | Max subjects per student | 5 |
| `--ignore-zero-subject-rows` | Skip rows with no subjects | Off |
| `--copy-chunk-rows 5000` | Process in 5,000 row chunks | 10,000 |
| `--prefer-ipv4` | Use IPv4 to avoid IPv6 timeouts | On |

### **Alternative: Use `--match user_id`**

If you're matching by existing `user_id` (updating existing students):

```bash
python3 scripts/fast_load_students_pg_copy.py scripts/STUDENTS.csv \
  --match user_id \
  --max-subjects 5
```

---

## 🧪 Step 5: DRY RUN (Test First!)

**Always test before importing 1 lakh records:**

```bash
python3 scripts/fast_load_students_pg_copy.py scripts/STUDENTS.csv \
  --match sr_no \
  --max-subjects 5 \
  --dry-run
```

✅ This shows what WILL be imported without actual database changes

---

## 📊 Step 6: Monitor Progress

During import, you'll see:

```
Reading CSV... ✓ 87,432 valid rows
Connecting to database... ✓ Connected
Starting COPY operation...

Chunk 1/18: Inserted 5,000 rows (12 sec)
Chunk 2/18: Inserted 5,000 rows (11 sec)
Chunk 3/18: Inserted 5,000 rows (13 sec)
...
✅ COMPLETE: 87,432 students imported in 2m 45s
Average: 30,895 rows/min
```

---

## ⚡ Performance Tips for 1+ Lakh Records

### **1. Use Session Pooler (25x faster than REST)**
```bash
# ❌ SLOW: REST API method
python3 scripts/import_students_csv.py STUDENTS.csv  # ~2,000 rows/min

# ✅ FAST: PostgreSQL COPY method  
python3 scripts/fast_load_students_pg_copy.py STUDENTS.csv  # ~30,000 rows/min
```

### **2. Increase Chunk Size**
```bash
# For fast networks, increase chunk size
python3 scripts/fast_load_students_pg_copy.py scripts/STUDENTS.csv \
  --copy-chunk-rows 10000  # Default
  # or even 20000 for very fast networks
```

### **3. Create Index After Import**
```bash
# After import is done, create indexes for faster queries
psql -d "your_database_url" << 'EOF'
CREATE INDEX idx_students_institute_sr_no ON students(institute_id, sr_no);
CREATE INDEX idx_students_user_id ON students(user_id);
CREATE INDEX idx_students_full_search ON students(name, first_name, last_name);
EOF
```

### **4. Disable Foreign Key Checks (Advanced)**
Only if you know what you're doing:

```sql
-- Temporarily disable constraint checks
ALTER TABLE students DISABLE TRIGGER ALL;

-- Run import...

-- Re-enable
ALTER TABLE students ENABLE TRIGGER ALL;
```

---

## 🔍 Step 7: Verify Import

### **Check Total Imported**
```bash
psql -d "your_database_url" << 'EOF'
SELECT 
  institute_id, 
  COUNT(*) as total_students,
  COUNT(DISTINCT user_id) as unique_ids,
  COUNT(DISTINCT name) as unique_names
FROM students
GROUP BY institute_id
ORDER BY total_students DESC;
EOF
```

### **Check for Duplicates**
```bash
psql -d "your_database_url" << 'EOF'
-- Find duplicate students in same institute
SELECT institute_id, sr_no, COUNT(*) as cnt
FROM students
GROUP BY institute_id, sr_no
HAVING COUNT(*) > 1
LIMIT 20;
EOF
```

### **Check Data Quality**
```bash
psql -d "your_database_url" << 'EOF'
-- Find rows with missing names
SELECT COUNT(*) FROM students WHERE name IS NULL OR name = '';

-- Find rows with no subjects
SELECT COUNT(*) FROM students WHERE subject IS NULL OR subject = '';

-- Check subject distribution
SELECT COUNT(*) FROM students WHERE subject IS NOT NULL GROUP BY subject;
EOF
```

---

## 🐛 Troubleshooting

### **Error: "address not in tenant allow_list"**
```
❌ Solution:
1. Go to Supabase Dashboard
2. Database → Network Restrictions
3. Add your IP or allow all temporarily
```

### **Error: "password authentication failed"**
```
❌ Solution: 
Ensure connection string has correct format:
✅ postgres://postgres.PROJECT_REF:PASSWORD@aws-0-region.pooler.supabase.com:5432/postgres
❌ NOT: postgres://postgres:PASSWORD@db.PROJECT.supabase.co:5432/postgres
```

### **Error: "SSL bad record MAC" or "connection is lost"**
```
❌ Solution:
The import is too fast for Wi-Fi. Options:
1. Use --copy-chunk-rows 3000 (smaller chunks)
2. Use --copy-new-connection-each-chunk (reconnect per chunk)
3. Use wired connection or faster internet
4. Run at off-peak hours
```

### **Timeout During Import**
```
❌ Solution:
For 1 lakh+ records:
1. Split into multiple files (~50K each)
2. Import in parallel OR sequentially with delays
3. Use larger chunk sizes

# Split your CSV
split -l 50000 STUDENTS.csv STUDENTS_part_

# Import each part
for f in STUDENTS_part_*; do
  python3 scripts/fast_load_students_pg_copy.py "$f" --match sr_no
  sleep 5  # Wait between imports
done
```

### **Duplicate Students Created**
```
❌ Solution:
1. Check what --match value you used
2. If sr_no based, ensure sr_no is unique per institute
3. If user_id based, ensure user_id is unique

# Delete duplicates (backup first!)
DELETE FROM students s1
WHERE ctid < (
  SELECT ctid FROM students s2 
  WHERE s1.institute_id = s2.institute_id 
    AND s1.sr_no = s2.sr_no
  LIMIT 1
);
```

---

## 📋 Full Workflow Example

```bash
#!/bin/bash
# Complete import workflow for 1 lakh students

cd /path/to/EDUSETU-ATTENDACE-APP-main

# Step 1: Prepare CSV
python3 << 'EOF'
import pandas as pd
df = pd.read_excel('master_students.xlsx')
df.to_csv('STUDENTS.csv', index=False)
print(f"✅ Prepared {len(df)} rows")
EOF

# Step 2: Install dependencies
pip install -r scripts/requirements-fast-pg-load.txt

# Step 3: Set database URL
export DATABASE_SESSION_POOL_URL="postgres://postgres.YOUR_REF:YOUR_PASS@aws-0-region.pooler.supabase.com:5432/postgres"

# Step 4: Dry run (test)
echo "🧪 Running dry-run test..."
python3 scripts/fast_load_students_pg_copy.py STUDENTS.csv \
  --match sr_no \
  --max-subjects 5 \
  --dry-run

# Step 5: Real import
echo "🚀 Starting actual import..."
time python3 scripts/fast_load_students_pg_copy.py STUDENTS.csv \
  --match sr_no \
  --max-subjects 5 \
  --ignore-zero-subject-rows \
  --copy-chunk-rows 10000

# Step 6: Verify
echo "✅ Verifying import..."
psql << 'SQL'
SELECT COUNT(*) as total_students FROM students;
SELECT COUNT(DISTINCT institute_id) as institutes FROM students;
SQL

echo "✨ Import complete!"
```

---

## 📊 Expected Performance

| File Size | Students | Time | Speed |
|-----------|----------|------|-------|
| 10 MB | 10,000 | 20 sec | 30,000/min |
| 100 MB | 100,000 | 3-5 min | 25,000/min |
| 500 MB | 500,000 | 15-20 min | 25,000/min |
| 1 GB | 1 Million | 30-40 min | 25,000/min |

⚡ **These speeds assume:**
- Session pooler connection
- 10,000 row chunks
- Stable internet connection
- Off-peak database load

---

## 🎯 Advanced: Parallel Import

For very large files (1M+), split and import in parallel:

```bash
# Split into 4 files of 250K each
split -l 250000 STUDENTS.csv STUDENTS_chunk_

# Import in parallel
for f in STUDENTS_chunk_*; do
  (python3 scripts/fast_load_students_pg_copy.py "$f" --match sr_no &)
done
wait

# All done!
echo "✅ All chunks imported"
```

---

## 📞 Quick Reference Commands

```bash
# Set connection (change values)
export DATABASE_SESSION_POOL_URL="postgres://postgres.xyz:pass@aws-0-us-east.pooler.supabase.com:5432/postgres"

# Test connection
psql "$DATABASE_SESSION_POOL_URL" -c "SELECT version();"

# Install deps
pip install -r scripts/requirements-fast-pg-load.txt

# Dry run (no changes)
python3 scripts/fast_load_students_pg_copy.py STUDENTS.csv --match sr_no --dry-run

# Real import
python3 scripts/fast_load_students_pg_copy.py STUDENTS.csv --match sr_no --max-subjects 5

# Check progress
psql "$DATABASE_SESSION_POOL_URL" -c "SELECT COUNT(*) FROM students;"

# View import speed
time python3 scripts/fast_load_students_pg_copy.py STUDENTS.csv --match sr_no
```

---

## ✅ Checklist

- [ ] CSV file prepared with correct columns
- [ ] Institutes exist in database (run `import_institutes_csv.py` first if needed)
- [ ] Database connection URL set in `.env` or environment
- [ ] Network restrictions allowed (or added your IP)
- [ ] Dependencies installed: `pip install -r scripts/requirements-fast-pg-load.txt`
- [ ] Dry-run successful: `--dry-run` flag test passed
- [ ] Real import started: monitoring console output
- [ ] Import completed: verified row count
- [ ] Duplicates checked: no unexpected duplicates
- [ ] Indexes created: for performance

---

## 📚 Related Scripts

**Other useful import scripts:**

1. **`import_institutes_csv.py`** - Import institutes first (required before students)
   ```bash
   python3 scripts/import_institutes_csv.py ALL_INSTITUTE.csv
   ```

2. **`filter_students_csv_for_import.py`** - Clean/validate CSV before import
   ```bash
   python3 scripts/filter_students_csv_for_import.py STUDENTS.csv
   ```

3. **`reconcile_institute_student_counts.sql`** - Refresh counters after bulk import
   ```bash
   psql -d "$DATABASE_URL" -f scripts/reconcile_institute_student_counts.sql
   ```

---

## 🎓 Tips for Success

1. **Always test with --dry-run first** ⚠️
2. **Start with small batches** (1,000-5,000 rows) if network is unreliable
3. **Use Session Pooler**, not direct connection 🚀
4. **Set chunk size to 10,000** for best speed/stability balance
5. **Monitor database size** (1M students ≈ 2-3 GB with indexes)
6. **Backup before importing** (just in case)
7. **Run at off-peak hours** to avoid impacting live users

---

**Last Updated:** May 1, 2026  
**For Support:** Check logs with `--verbose` flag or run `--dry-run` first
