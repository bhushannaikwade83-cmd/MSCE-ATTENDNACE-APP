# Storage Cost Comparison: Firebase vs B2B for 2 Photos Daily 📸

## 📊 Your Usage: 2 Photos Per Student Per Day

**Scenario:**
- Entry photo: ~500KB
- Exit photo: ~500KB
- Total: ~1 MB per student per day
- Face registration photo: ~500KB (one-time per student)

---

## 💾 Storage Volume Calculation

### For 200,000 Students:

**Daily Storage:**
- 2 photos × 200,000 students × 500KB = **200 GB/day**

**Monthly Storage:**
- 200 GB/day × 30 days = **6,000 GB/month = 6 TB/month**

**Face Photos (One-time):**
- 200,000 students × 500KB = **100 GB**

**Total Storage Needed:**
- Monthly: **6 TB/month** (attendance photos)
- One-time: **100 GB** (face photos)
- **Total: ~6.1 TB/month** (growing monthly)

### For 300,000 Students:

**Daily Storage:**
- 2 photos × 300,000 students × 500KB = **300 GB/day**

**Monthly Storage:**
- 300 GB/day × 30 days = **9,000 GB/month = 9 TB/month**

**Face Photos (One-time):**
- 300,000 students × 500KB = **150 GB**

**Total Storage Needed:**
- Monthly: **9 TB/month** (attendance photos)
- One-time: **150 GB** (face photos)
- **Total: ~9.15 TB/month** (growing monthly)

---

## 💰 Firebase Storage Pricing

### Firebase Storage Costs:
- **First 5 GB**: FREE ✅
- **After 5 GB**: $0.026 per GB/month
- **Download**: FREE (no egress charges)
- **Upload**: FREE

### For 200,000 Students:

**Monthly Cost:**
- Storage: 6,100 GB - 5 GB (free) = 6,095 GB
- Cost: 6,095 GB × $0.026 = **$158.47/month**
- **In INR**: ₹158.47 × 83 = **₹13,153/month**
- **Annual**: **₹157,836/year**

### For 300,000 Students:

**Monthly Cost:**
- Storage: 9,150 GB - 5 GB (free) = 9,145 GB
- Cost: 9,145 GB × $0.026 = **$237.77/month**
- **In INR**: ₹237.77 × 83 = **₹19,735/month**
- **Annual**: **₹236,820/year**

---

## 💰 B2B (Backblaze B2) Storage Pricing

### B2B Storage Costs:
- **Storage**: $5 per TB/month = $0.005 per GB/month
- **Download**: $10 per TB (first 1 GB/day free)
- **Upload**: FREE

### For 200,000 Students:

**Monthly Cost:**
- Storage: 6.1 TB × $5 = **$30.50/month**
- **In INR**: ₹30.50 × 83 = **₹2,532/month**

**Download Costs** (if downloading photos):
- Assuming 10% download rate: 0.61 TB/month
- Cost: 0.61 TB × $10 = **$6.10/month**
- **In INR**: ₹6.10 × 83 = **₹506/month**

**B2B Total (200k students):**
- Storage: ₹2,532/month
- Download: ₹506/month
- **Total: ₹3,038/month**
- **Annual: ₹36,456/year**

### For 300,000 Students:

**Monthly Cost:**
- Storage: 9.15 TB × $5 = **$45.75/month**
- **In INR**: ₹45.75 × 83 = **₹3,797/month**

**Download Costs:**
- 10% download rate: 0.915 TB/month
- Cost: 0.915 TB × $10 = **$9.15/month**
- **In INR**: ₹9.15 × 83 = **₹759/month**

**B2B Total (300k students):**
- Storage: ₹3,797/month
- Download: ₹759/month
- **Total: ₹4,556/month**
- **Annual: ₹54,672/year**

---

## 📊 Cost Comparison Table

### For 200,000 Students (2 Photos Daily):

| Storage Provider | Monthly (₹) | Annual (₹) | Savings vs Firebase |
|-----------------|-------------|------------|---------------------|
| **Firebase Storage** | ₹13,153 | ₹157,836 | - |
| **B2B Storage** | ₹3,038 | ₹36,456 | **₹121,380/year** ✅ |

**B2B is 77% cheaper!** ✅

### For 300,000 Students (2 Photos Daily):

| Storage Provider | Monthly (₹) | Annual (₹) | Savings vs Firebase |
|-----------------|-------------|------------|---------------------|
| **Firebase Storage** | ₹19,735 | ₹236,820 | - |
| **B2B Storage** | ₹4,556 | ₹54,672 | **₹182,148/year** ✅ |

**B2B is 77% cheaper!** ✅

---

## 💡 Detailed Breakdown

### Firebase Storage:
- **Cost per GB**: ₹2.16/month ($0.026)
- **200k students**: ₹13,153/month
- **300k students**: ₹19,735/month
- **Pros**: Integrated with Firebase, easy setup
- **Cons**: More expensive

### B2B Storage:
- **Cost per GB**: ₹0.42/month ($0.005)
- **200k students**: ₹3,038/month
- **300k students**: ₹4,556/month
- **Pros**: Much cheaper (77% savings), reliable
- **Cons**: Separate service (but you already use it!)

---

## 🎯 Recommendation

### For 2 Photos Daily Per Student:

**Use B2B Storage** ✅

**Why?**
- ✅ **77% cheaper** than Firebase Storage
- ✅ **₹121,380-182,148/year savings**
- ✅ You already use B2B (familiar)
- ✅ Reliable and fast
- ✅ No download charges if you don't download

**Cost Savings:**
- 200k students: Save **₹121,380/year**
- 300k students: Save **₹182,148/year**

---

## 📊 Updated Total Annual Cost

### For 200,000 Students (Using B2B):

| Component | Monthly (₹) | Annual (₹) |
|-----------|-------------|------------|
| **Firebase** (Database, Auth) | 1,330 | 15,960 |
| **B2B Storage** | 3,038 | 36,456 |
| **ArcFace Backend** | 2,400 | 28,800 |
| **TOTAL** | **₹6,768/month** | **₹81,216/year** |

### For 300,000 Students (Using B2B):

| Component | Monthly (₹) | Annual (₹) |
|-----------|-------------|------------|
| **Firebase** (Database, Auth) | 2,077 | 24,924 |
| **B2B Storage** | 4,556 | 54,672 |
| **ArcFace Backend** | 4,600 | 55,200 |
| **TOTAL** | **₹11,233/month** | **₹134,796/year** |

---

## ✅ Final Recommendation

**For 200,000-300,000 students with 2 photos daily:**

**Use B2B Storage** (not Firebase Storage)

**Total Annual Cost:**
- **200k students**: ₹81,216/year (₹6,768/month)
- **300k students**: ₹134,796/year (₹11,233/month)

**This is 66-64% cheaper than using Firebase Storage!** ✅

---

## 📝 Summary

| Students | Firebase Storage | B2B Storage | Savings |
|----------|-----------------|--------------|---------|
| **200,000** | ₹157,836/year | ₹36,456/year | **₹121,380/year** |
| **300,000** | ₹236,820/year | ₹54,672/year | **₹182,148/year** |

**B2B Storage is the clear winner for your use case!** ✅

**Keep using B2B Storage** - it's much cheaper for 2 photos daily per student. 🎉
