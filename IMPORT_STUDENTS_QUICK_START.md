# ⚡ Import 1 Lakh Students - QUICK START (5 Minutes)

## 📝 Your Data Format

You have:
- Student full name (or fname + mname + lname)
- Subjects (up to 5+ per student)
- Student ID / Roll Number
- Institute code

## 🎯 Quick Steps

### **Step 1: Create CSV File** (2 minutes)

Save your student data as CSV with these **exact** column names:

```
instid,formserialno,fname,mname,lname,SUBJECT_1,SUBJECT_2,SUBJECT_3,SUBJECT_4,SUBJECT_5
```

**Using Python/Pandas:**
```python
import pandas as pd

# Read your Excel file
df = pd.read_excel('students.xlsx')

# Rename columns to match required format
df = df.rename(columns={
    'Institute Code': 'instid',
    'Roll/ID': 'formserialno',
    'First Name': 'fname',
    'Middle Name': 'mname',  # Can be empty
    'Last Name': 'lname',
    'Subject 1': 'SUBJECT_1',
    'Subject 2': 'SUBJECT_2',
    'Subject 3': 'SUBJECT_3',
    'Subject 4': 'SUBJECT_4',
    'Subject 5': 'SUBJECT_5',
})

# Save as CSV
df.to_csv('STUDENTS.csv', index=False)
print(f"✅ Created {len(df):,} rows")
```

**Or manually in Excel:**
1. Create columns: `instid`, `formserialno`, `fname`, `mname`, `lname`, `SUBJECT_1`-`SUBJECT_5`
2. Paste student data
3. Save as `.csv` file

### **Step 2: Get Database Connection** (1 minute)

1. Open [Supabase Dashboard](https://app.supabase.com)
2. Go: **Database** → **Connection pooling**
3. Copy **Session pooler** URL
4. Add to `.env` file:

```bash
# .env file
DATABASE_SESSION_POOL_URL="postgres://postgres.YOUR_PROJECT_REF:YOUR_PASSWORD@aws-0-YOUR_REGION.pooler.supabase.com:5432/postgres"
```

### **Step 3: Run Import Script** (2 minutes)

```bash
cd /path/to/EDUSETU-ATTENDACE-APP-main

# Make script executable
chmod +x scripts/run_bulk_student_import.sh

# Run it!
./scripts/run_bulk_student_import.sh STUDENTS.csv
```

**That's it!** The script will:
- ✅ Test database connection
- ✅ Run dry-run (show what will import)
- ✅ Ask for confirmation
- ✅ Import all students
- ✅ Verify the import
- ✅ Show summary

---

## 🏃 Expected Time & Speed

| Students | Time | Speed |
|----------|------|-------|
| 10,000 | 20 sec | ~30K/min |
| 50,000 | 1.5 min | ~30K/min |
| 100,000 | 3-4 min | ~30K/min |
| 500,000 | 15-20 min | ~25K/min |
| **1 Lakh (100,000)** | **3-5 min** | **25-30K/min** |

---

## 📊 CSV Format Examples

### **Example 1: Full Format**
```csv
instid,formserialno,fname,mname,lname,SUBJECT_1,SUBJECT_2,SUBJECT_3,SUBJECT_4,SUBJECT_5
11061,10001,KRUTIKA,SHANKAR,GOSAVI,GCC TBC ENG 30,0,GCC TBC MAR 30,0,0
11061,10002,AMIT,,SHARMA,MATH 101,PHY 102,CHEM 103,BIO 104,0
11062,20001,PRIYA,RAJESH,KULKARNI,ENG 201,MAR 202,MAT 203,0,0
```

### **Example 2: Only Names (No Subjects Yet)**
```csv
instid,formserialno,fname,mname,lname
11061,10001,KRUTIKA,SHANKAR,GOSAVI
11061,10002,AMIT,,SHARMA
```

### **Example 3: Combined Full Name**
```csv
instid,formserialno,name,SUBJECT_1
11061,10001,KRUTIKA SHANKAR GOSAVI,GCC TBC ENG
11061,10002,AMIT SHARMA,MATH 101
```

---

## 🔧 If Something Goes Wrong

### **"address not in tenant allow_list"**
```bash
# Allow your IP in Supabase:
# 1. Dashboard → Database → Network Restrictions
# 2. Add your IP or click "Allow All" temporarily
```

### **"password authentication failed"**
```bash
# Check your DATABASE_SESSION_POOL_URL format:
✅ postgres://postgres.YOUR_REF:PASSWORD@aws-0-region.pooler.supabase.com:5432/postgres
❌ NOT: postgres://postgres:PASSWORD@db.YOUR.supabase.co:5432/postgres
```

### **"Connection timeout" or "SSL bad record MAC"**
```bash
# Run with smaller chunks:
./scripts/run_bulk_student_import.sh STUDENTS.csv --copy-chunk-rows 5000
```

### **"Too many students in one import"**
```bash
# Split your CSV into multiple parts (50K each)
split -l 50000 STUDENTS.csv STUDENTS_part_

# Import each part
for f in STUDENTS_part_*; do
  ./scripts/run_bulk_student_import.sh "$f"
  sleep 5
done
```

---

## ✅ Verify Import Worked

```bash
# Check total count
psql "$DATABASE_SESSION_POOL_URL" << 'SQL'
SELECT COUNT(*) as total_students FROM students;
SQL

# Check by institute
psql "$DATABASE_SESSION_POOL_URL" << 'SQL'
SELECT institute_id, COUNT(*) 
FROM students 
GROUP BY institute_id 
ORDER BY COUNT(*) DESC;
SQL
```

---

## 💡 Pro Tips

1. **Always run without my CSV first** - Check [BULK_IMPORT_100K_STUDENTS_GUIDE.md](./BULK_IMPORT_100K_STUDENTS_GUIDE.md)
2. **Use Session Pooler** not direct connection (25x faster)
3. **Subjects field:** Use "0" or leave empty for no subject
4. **Sr No must be unique** per institute (or use matching by user_id)
5. **After import:** Run SQL in Supabase to check duplicates

---

## 📞 Full Guide

See [BULK_IMPORT_100K_STUDENTS_GUIDE.md](./BULK_IMPORT_100K_STUDENTS_GUIDE.md) for:
- Advanced options
- Troubleshooting
- Performance tuning
- Parallel imports
- Data validation

---

## 🚀 One-Liner (If you're in a hurry)

```bash
# Assume you have STUDENTS.csv ready and .env configured
cd EDUSETU-ATTENDACE-APP-main && \
pip install -q -r scripts/requirements-fast-pg-load.txt && \
./scripts/run_bulk_student_import.sh STUDENTS.csv
```

---

**Questions?** Check the detailed guide or run with `--help`:
```bash
python3 scripts/fast_load_students_pg_copy.py --help
```
