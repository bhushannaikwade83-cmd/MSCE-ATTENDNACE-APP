# Android: one more step (Command-line tools)

**ANDROID_HOME** is already set to:  
`C:\Users\pravi\AppData\Local\Android\Sdk`

Your SDK is missing the **Android SDK Command-line Tools** package. Install it once, then accept licenses.

---

## 1. Install Command-line Tools in Android Studio

1. Open **Android Studio**.
2. Go to **Settings** (or **File → Settings** on Windows).
3. Open **Languages & Frameworks → Android SDK** (or **Appearance & Behavior → System Settings → Android SDK**).
4. Open the **SDK Tools** tab.
5. Enable **Android SDK Command-line Tools (latest)**.
6. Click **Apply** and wait for the install to finish.

---

## 2. Accept Android licenses

Close and reopen your terminal (or Cursor), then run:

```bash
cd d:\Adu\col\js\project\EDUSETU-ATTENDACE-APP
flutter doctor --android-licenses
```

Press **y** and Enter for each prompt.

---

## 3. Check and build

```bash
flutter doctor -v
flutter build apk --release
```

The release APK will be at:  
`build\app\outputs\flutter-apk\app-release.apk`
