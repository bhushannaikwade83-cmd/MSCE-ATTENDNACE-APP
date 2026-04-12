# Hot Reload Troubleshooting Guide

## Quick Fixes for Hot Reload Not Working

### 1. Use Hot Restart Instead of Hot Reload
Some changes require a **Hot Restart** (not Hot Reload):
- Changes to `main()` function
- Changes to static/const variables
- Changes to imports
- Changes to build configuration
- Changes to theme/themeMode

**In Terminal:**
- Press `R` (capital R) for Hot Restart
- Or press `r` (lowercase r) for Hot Reload

### 2. Common Hot Reload Issues

#### Issue: Code changes not reflecting
**Solution:** Use Hot Restart (`R` in terminal)

#### Issue: App crashes after hot reload
**Solution:** 
1. Stop the app completely
2. Run `flutter clean`
3. Run `flutter pub get`
4. Run `flutter run` again

#### Issue: Hot reload button grayed out
**Solution:**
- Make sure app is running in **debug mode** (not release mode)
- Check that device is connected and authorized
- Try disconnecting and reconnecting device

### 3. When to Use Hot Reload vs Hot Restart

**Use Hot Reload (`r`):**
- UI changes (colors, text, layout)
- Widget changes
- State changes within widgets
- Most code changes

**Use Hot Restart (`R`):**
- Changes to `main()` function
- Changes to static/const variables
- Changes to imports
- Changes to build configuration
- Changes to theme initialization
- Changes to Firebase initialization
- Changes to service initialization

### 4. Force Hot Restart
If hot reload isn't working:
1. Press `R` in terminal (Hot Restart)
2. Or stop app (`q`) and run `flutter run` again

### 5. Check Debug Mode
Make sure you're running in debug mode:
```bash
flutter run --debug
```

Not release mode:
```bash
flutter run --release  # This disables hot reload!
```

### 6. Android-Specific Fixes
If hot reload still doesn't work on Android:
1. Check `android/app/build.gradle.kts` - debug buildType should have:
   - `isDebuggable = true`
   - `isMinifyEnabled = false`
   - `isShrinkResources = false`

2. Clean and rebuild:
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

### 7. Check Device Connection
- Make sure device is connected via USB
- Enable USB debugging on device
- Check `adb devices` to see if device is listed
- Try unplugging and replugging USB cable

### 8. Restart Flutter Daemon
If nothing works:
```bash
flutter pub cache repair
flutter doctor
flutter run
```

## Quick Commands Reference

| Action | Command |
|--------|---------|
| Hot Reload | Press `r` in terminal |
| Hot Restart | Press `R` in terminal |
| Stop App | Press `q` in terminal |
| Full Restart | Stop app, then `flutter run` |
| Clean Build | `flutter clean && flutter pub get && flutter run` |
