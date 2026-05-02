# Quick Start: Production Migration & Testing

---

## STEP 1: Apply Database Migration (5 min)

### In Supabase SQL Editor:

1. Go to **Supabase Dashboard** → Your Project → **SQL Editor**
2. Click **+ New Query**
3. Open this file and copy all SQL:
   ```
   MERGE_NEW_INST_ADMINS.sql
   ```
4. Paste into SQL Editor and click **Run**
5. Wait for completion (should process ~2,874 records)

### Verify Migration Success:

```sql
-- Copy and run these queries to verify

-- Check how many institutes now have admin names
SELECT COUNT(*) as institutes_with_admin_name 
FROM public.institutes 
WHERE admin_full_name IS NOT NULL;
-- Expected: ~2,874

-- Check how many are missing (should be ~4)
SELECT COUNT(*) as institutes_missing_admin 
FROM public.institutes 
WHERE admin_full_name IS NULL;
-- Expected: ~4

-- Check admin_invites table
SELECT COUNT(*) as pending_admin_registrations 
FROM public.admin_invites 
WHERE claimed = false;
-- Expected: ~2,878

-- Show some examples of newly added admin details
SELECT id, name, admin_full_name, admin_email, admin_phone
FROM public.institutes 
WHERE admin_full_name IS NOT NULL 
LIMIT 5;
```

---

## STEP 2: Rebuild Flutter App (10 min)

### Update and Build:

```bash
cd /path/to/your/flutter/project

# Clean previous builds
flutter clean

# Get latest dependencies
flutter pub get

# Build for Android
flutter build apk --release
# OR build for iOS
flutter build ios --release
```

### Verify HTTP Package:

```bash
# Check pubspec.yaml has http package
grep "http:" pubspec.yaml
# Should show: http: ^1.1.0 (or similar)

# If missing, add it:
flutter pub add http
```

---

## STEP 3: Test OTP Delivery (15 min)

### Quick Test with New Admin Email:

1. **Get a test email from NEW_INST3000.csv:**
   - Open: `scripts/NEW_INST3000.csv`
   - Pick any email, e.g., `sdsamantprints@gmail.com` (from institute 110390139823)
   - Note the institute ID

2. **Install and Launch App:**
   - Install the rebuilt APK/iOS app on test device
   - Launch app

3. **Trigger OTP Send:**
   - Go to Institute Login screen
   - Enter institute ID (e.g., `110390139823`)
   - Enter the admin email (e.g., `sdsamantprints@gmail.com`)
   - Tap "Send OTP"

4. **Verify Email Received:**
   - Check inbox for email from `noreply@edusetu.com`
   - Subject should be: "Your OTP for EDUSETU"
   - Email should arrive within 2-5 seconds
   - Note the OTP code

5. **Complete Registration:**
   - Return to app
   - Enter the OTP from email
   - Set password and PIN
   - Complete registration

### Expected Success Indicators:
- ✅ Email arrives in inbox
- ✅ OTP is correct 6-digit number
- ✅ Registration completes successfully
- ✅ No "unsubscribed user" error

### If Email Doesn't Arrive:

Check app logs for:
```
✅ OTP sent via Brevo transactional API to [email]
```

If you see Brevo error, check:
1. BREVO_API_KEY is set in `.env`
2. API key is valid (log into Brevo dashboard)
3. Brevo account has sufficient credits

---

## STEP 4: Test Fallback Mechanism (Optional, 5 min)

### To test Edge Function fallback:

1. **Temporarily disable Brevo API Key:**
   - Edit `.env`
   - Comment out or clear BREVO_API_KEY
   - Rebuild app

2. **Send OTP again:**
   - Try sending OTP to another test email
   - Watch logs for message: "Brevo transactional failed, trying Edge Function..."
   - Email should still arrive (via fallback)

3. **Re-enable Brevo:**
   - Restore BREVO_API_KEY in `.env`
   - Rebuild app

---

## STEP 5: Verify System is Ready (10 min)

### Check Database Status:

```sql
-- Show statistics
SELECT 
  (SELECT COUNT(*) FROM institutes) as total_institutes,
  (SELECT COUNT(*) FROM institutes WHERE admin_full_name IS NOT NULL) as with_admin_details,
  (SELECT COUNT(*) FROM institutes WHERE admin_full_name IS NULL) as without_admin_details,
  (SELECT COUNT(*) FROM admin_invites) as total_pending_invites,
  (SELECT COUNT(*) FROM admin_invites WHERE claimed = true) as completed_registrations;
```

### Check App Logs:

```
✅ OTP sent via Brevo transactional API
✅ OTP stored successfully
✅ Registration completed
```

---

## STEP 6: Monitor & Deploy (Ongoing)

### Before Going Live:

- [ ] Ran database migration successfully
- [ ] Verified ~2,874 institutes have admin details
- [ ] Rebuilt Flutter app with http package
- [ ] Tested OTP delivery with 1-2 real emails
- [ ] Confirmed email arrives within 5 seconds
- [ ] Verified fallback mechanism works
- [ ] No build warnings or errors

### Post-Deployment Monitoring:

1. **First 24 hours:**
   - Monitor Brevo API logs for errors
   - Check OTP delivery success rate
   - Monitor Supabase database performance

2. **First Week:**
   - Track admin registration completion rate
   - Monitor for any email delivery issues
   - Gather feedback from institute admins

3. **Ongoing:**
   - Monitor Brevo credits/quota
   - Log all OTP sends for audit
   - Update admin contact info as needed

---

## TROUBLESHOOTING

### OTP Not Arriving?

**Check 1: Brevo API Key**
```bash
# Verify it's in .env
cat .env | grep BREVO_API_KEY
# Should show: BREVO_API_KEY=xkeysib-...
```

**Check 2: Email Format**
- Must be valid email format (contains @)
- Should be one from the database
- Check it exists: SELECT admin_email FROM institutes WHERE id = '[institute_id]'

**Check 3: Brevo Account**
- Log into brevo.com
- Check account is active
- Check API key is valid
- Check you have SMS/email credits available

**Check 4: Network**
- Verify phone has internet connection
- App logs should show POST request to Brevo API
- Should see 201 status code on success

### Build Errors?

```bash
# Clear everything and start fresh
flutter clean
rm -rf build/
rm -rf pubspec.lock
flutter pub get
flutter pub upgrade

# Then rebuild
flutter build apk --release
```

### Database Migration Failed?

If you see SQL error:
1. Check that SQL editor is in correct Supabase project
2. Try running verification queries first to understand current state
3. If needed, run UPDATE statements instead of full migration
4. Check for duplicate rows or conflicts

---

## FILES REFERENCE

| File | Purpose | Status |
|------|---------|--------|
| `MERGE_NEW_INST_ADMINS.sql` | Migrate 2,874 admin records | ✅ Ready |
| `scripts/NEW_INST3000.csv` | Source data (3,000 institutes) | ✅ Ready |
| `scripts/MISSING_ADMINS_126.csv` | Extracted missing records | ✅ Ready |
| `lib/services/auth_service.dart` | Updated with Brevo transactional API | ✅ Ready |
| `CREATE_PENDING_ALL_INSTITUTES_FINAL.sql` | Create pending registrations | ✅ Ready |
| `.env` | Configuration (BREVO_API_KEY, DATABASE_URL) | ✅ Configured |

---

## ESTIMATED TIMELINE

| Task | Time | Dependencies |
|------|------|--------------|
| Run database migration | 5 min | Supabase access |
| Verify migration | 5 min | Migration complete |
| Rebuild Flutter app | 10 min | Flutter setup |
| Test OTP delivery | 15 min | App rebuilt, email access |
| Test fallback | 5 min | App rebuilt |
| Final verification | 10 min | All tests passed |
| **Total** | **~50 min** | All clear ✅ |

---

**Last Updated:** 2026-05-02  
**App Version:** 2.0.0  
**Email Service:** Brevo (Transactional API)  
**Database:** Supabase PostgreSQL
