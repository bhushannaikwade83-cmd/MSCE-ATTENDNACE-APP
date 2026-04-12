# Check Single Field Index Tab

## 🔍 You're Looking at the Wrong Tab!

You're currently viewing the **"Composite"** tab, which shows composite indexes (multiple fields).

The single-field index for `instituteCode` is in a **different tab**.

## ✅ Steps to Find the Single-Field Index:

1. **Look at the top of the page** - you should see tabs:
   - "Composite" (currently selected)
   - **"Single field"** ← Click this!

2. **Click the "Single field" tab**

3. **Look for**:
   - Collection ID: `inOut`
   - Field: `instituteCode`
   - Query scope: `Collection group`
   - Status: Should be "Building" or "Enabled"

## 📋 What You Should See:

In the Single field tab, you should see a table like:

```
Collection ID | Field          | Query scope        | Status
inOut         | instituteCode | Collection group   | Building ⏳ (or Enabled ✅)
```

## ⏳ If Status is "Building":

- Wait 2-5 minutes
- Refresh the page
- Status will change to "Enabled" (green checkmark)

## ✅ If Status is "Enabled":

- The index is ready!
- Your attendance reports should work now
- No more "Firestore index required" errors!

## 🔍 If You Don't See It:

The index might still be deploying. Wait a minute and refresh, or check the Firebase Console again.
