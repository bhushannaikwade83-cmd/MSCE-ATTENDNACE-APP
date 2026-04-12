# Responsive UI Best Practices Guide

## 💡 Pro Tip (Important)
**Combine ScreenUtil + Expanded + Flexible for perfect responsive UI.**

This combination ensures your UI adapts beautifully across all screen sizes while maintaining proper layout constraints.

## Core Principles

### 1. ScreenUtil for Scaling
Use `ScreenUtil` to scale dimensions, fonts, and spacing based on screen size:

```dart
import 'package:flutter_screenutil/flutter_screenutil.dart';

// ✅ Good: Scales with screen size
Container(
  width: 100.w,        // Responsive width
  height: 50.h,        // Responsive height
  padding: EdgeInsets.all(16.w),  // Responsive padding
  child: Text(
    'Hello',
    style: TextStyle(fontSize: 16.sp),  // Responsive font
  ),
)

// ❌ Bad: Fixed sizes
Container(
  width: 100,          // Fixed - won't scale
  height: 50,          // Fixed - won't scale
  child: Text('Hello', style: TextStyle(fontSize: 16)),
)
```

### 2. Expanded for Flexible Space
Use `Expanded` when you want a widget to take available space:

```dart
Row(
  children: [
    Icon(Icons.person),           // Fixed size
    SizedBox(width: 12.w),         // Fixed spacing
    Expanded(                      // ✅ Takes remaining space
      child: Text(
        'Long text that should wrap and take available space',
        overflow: TextOverflow.ellipsis,
      ),
    ),
    Icon(Icons.arrow_forward),     // Fixed size
  ],
)
```

### 3. Flexible for Proportional Space
Use `Flexible` when you want proportional but not necessarily all available space:

```dart
Row(
  children: [
    Flexible(                       // ✅ Proportional, can shrink
      flex: 2,
      child: Container(color: Colors.blue),
    ),
    SizedBox(width: 12.w),
    Flexible(                       // ✅ Proportional, can shrink
      flex: 1,
      child: Container(color: Colors.red),
    ),
  ],
)
```

## Perfect Combination Pattern

### Pattern 1: ScreenUtil + Expanded

```dart
Row(
  children: [
    Container(
      width: 60.w,                  // ✅ ScreenUtil for fixed icon size
      height: 60.h,
      decoration: BoxDecoration(...),
      child: Icon(Icons.person),
    ),
    SizedBox(width: 16.w),          // ✅ ScreenUtil for spacing
    Expanded(                        // ✅ Expanded for flexible text
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Title',
            style: TextStyle(fontSize: 18.sp),  // ✅ ScreenUtil for font
          ),
          Text(
            'Subtitle that can be long and should wrap',
            style: TextStyle(fontSize: 14.sp),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    ),
  ],
)
```

### Pattern 2: ScreenUtil + Flexible

```dart
Row(
  children: [
    Flexible(                        // ✅ Flexible for proportional
      flex: 2,
      child: Container(
        padding: EdgeInsets.all(16.w),  // ✅ ScreenUtil for padding
        decoration: BoxDecoration(...),
        child: Text(
          'Content 1',
          style: TextStyle(fontSize: 16.sp),
        ),
      ),
    ),
    SizedBox(width: 12.w),         // ✅ ScreenUtil for spacing
    Flexible(                        // ✅ Flexible for proportional
      flex: 1,
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(...),
        child: Text(
          'Content 2',
          style: TextStyle(fontSize: 16.sp),
        ),
      ),
    ),
  ],
)
```

### Pattern 3: ScreenUtil + Expanded + Flexible (Advanced)

```dart
Row(
  children: [
    Container(
      width: 50.w,                  // ✅ Fixed with ScreenUtil
      height: 50.h,
      child: Icon(Icons.star),
    ),
    SizedBox(width: 12.w),
    Expanded(                        // ✅ Takes remaining space
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Title', style: TextStyle(fontSize: 18.sp)),
          Text('Subtitle', style: TextStyle(fontSize: 14.sp)),
        ],
      ),
    ),
    Flexible(                        // ✅ Can shrink if needed
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(...),
        child: Text('Action', style: TextStyle(fontSize: 14.sp)),
      ),
    ),
  ],
)
```

## Common Use Cases

### 1. List Items with Icons

```dart
ListTile(
  leading: Container(
    width: 50.w,                    // ✅ ScreenUtil
    height: 50.h,
    decoration: BoxDecoration(...),
    child: Icon(Icons.person),
  ),
  title: Text(
    'Title',
    style: TextStyle(fontSize: 16.sp),  // ✅ ScreenUtil
  ),
  subtitle: Text(
    'Subtitle that can be long',
    style: TextStyle(fontSize: 14.sp),
    overflow: TextOverflow.ellipsis,
  ),
  trailing: Icon(Icons.arrow_forward),
)
```

### 2. Cards with Flexible Content

```dart
Card(
  child: Padding(
    padding: EdgeInsets.all(16.w),  // ✅ ScreenUtil
    child: Row(
      children: [
        Expanded(                    // ✅ Expanded for text
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Card Title',
                style: TextStyle(
                  fontSize: 18.sp,   // ✅ ScreenUtil
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8.h), // ✅ ScreenUtil
              Text(
                'Card description that can be long and should wrap properly',
                style: TextStyle(fontSize: 14.sp),
              ),
            ],
          ),
        ),
        SizedBox(width: 16.w),      // ✅ ScreenUtil
        Icon(Icons.chevron_right),
      ],
    ),
  ),
)
```

### 3. Stats Cards Grid

```dart
Row(
  children: [
    Expanded(                        // ✅ Equal width cards
      child: Container(
        padding: EdgeInsets.all(16.w),
        margin: EdgeInsets.only(right: 8.w),
        decoration: BoxDecoration(...),
        child: Column(
          children: [
            Text(
              '100',
              style: TextStyle(fontSize: 24.sp),  // ✅ ScreenUtil
            ),
            Text(
              'Total',
              style: TextStyle(fontSize: 12.sp),
            ),
          ],
        ),
      ),
    ),
    Expanded(                        // ✅ Equal width cards
      child: Container(
        padding: EdgeInsets.all(16.w),
        margin: EdgeInsets.only(left: 8.w),
        decoration: BoxDecoration(...),
        child: Column(
          children: [
            Text('50', style: TextStyle(fontSize: 24.sp)),
            Text('Present', style: TextStyle(fontSize: 12.sp)),
          ],
        ),
      ),
    ),
  ],
)
```

### 4. Form Fields

```dart
Column(
  children: [
    TextField(
      decoration: InputDecoration(
        labelText: 'Name',
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16.w,          // ✅ ScreenUtil
          vertical: 12.h,
        ),
      ),
      style: TextStyle(fontSize: 16.sp),  // ✅ ScreenUtil
    ),
    SizedBox(height: 16.h),         // ✅ ScreenUtil
    SizedBox(
      width: double.infinity,
      height: 50.h,                 // ✅ ScreenUtil
      child: ElevatedButton(
        onPressed: () {},
        child: Text(
          'Submit',
          style: TextStyle(fontSize: 16.sp),
        ),
      ),
    ),
  ],
)
```

## Best Practices

### ✅ DO:

1. **Always use ScreenUtil for dimensions:**
   ```dart
   width: 100.w, height: 50.h, fontSize: 16.sp
   ```

2. **Use Expanded for flexible content:**
   ```dart
   Expanded(child: Text('Long content'))
   ```

3. **Use Flexible for proportional layouts:**
   ```dart
   Flexible(flex: 2, child: ...)
   ```

4. **Combine them for perfect responsive UI:**
   ```dart
   Row(
     children: [
       Icon(size: 24.sp),           // ScreenUtil
       SizedBox(width: 12.w),       // ScreenUtil
       Expanded(child: Text(...)),   // Expanded
     ],
   )
   ```

### ❌ DON'T:

1. **Don't use fixed sizes:**
   ```dart
   width: 100,  // ❌ Bad
   width: 100.w // ✅ Good
   ```

2. **Don't use Expanded when you need fixed size:**
   ```dart
   Expanded(child: Icon(Icons.star))  // ❌ Bad - icon should be fixed
   Container(width: 24.w, child: Icon(Icons.star))  // ✅ Good
   ```

3. **Don't forget overflow handling:**
   ```dart
   Expanded(
     child: Text('Long text'),  // ❌ May overflow
   )
   
   Expanded(
     child: Text(
       'Long text',
       overflow: TextOverflow.ellipsis,  // ✅ Good
       maxLines: 2,
     ),
   )
   ```

## ScreenUtil Reference

### Common ScreenUtil Extensions:

```dart
// Width
100.w        // Responsive width
double.infinity  // Full width (use with Expanded)

// Height
50.h         // Responsive height
MediaQuery.of(context).size.height  // Full height

// Font Size
16.sp        // Responsive font size
18.sp        // Larger font

// Padding/Margin
EdgeInsets.all(16.w)
EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h)
EdgeInsets.only(left: 10.w, top: 5.h)

// Spacing
SizedBox(width: 12.w)
SizedBox(height: 16.h)
```

## Responsive Breakpoints

Consider different screen sizes:

```dart
// Small screens (phones)
if (MediaQuery.of(context).size.width < 600) {
  // Use smaller padding, fonts
  padding: EdgeInsets.all(12.w),
  fontSize: 14.sp,
}

// Medium screens (tablets)
else if (MediaQuery.of(context).size.width < 1200) {
  padding: EdgeInsets.all(16.w),
  fontSize: 16.sp,
}

// Large screens (desktop)
else {
  padding: EdgeInsets.all(20.w),
  fontSize: 18.sp,
}
```

## Example: Complete Responsive Card

```dart
Card(
  margin: EdgeInsets.all(16.w),     // ✅ ScreenUtil
  child: Padding(
    padding: EdgeInsets.all(16.w),  // ✅ ScreenUtil
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with icon and title
        Row(
          children: [
            Container(
              width: 50.w,          // ✅ ScreenUtil
              height: 50.h,
              decoration: BoxDecoration(...),
              child: Icon(Icons.person, size: 24.sp),
            ),
            SizedBox(width: 16.w),  // ✅ ScreenUtil
            Expanded(                // ✅ Expanded for flexible title
              child: Text(
                'Card Title That Can Be Long',
                style: TextStyle(
                  fontSize: 18.sp,  // ✅ ScreenUtil
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),     // ✅ ScreenUtil
        // Content
        Text(
          'Description that can be very long and should wrap properly',
          style: TextStyle(fontSize: 14.sp),  // ✅ ScreenUtil
        ),
        SizedBox(height: 16.h),     // ✅ ScreenUtil
        // Action buttons
        Row(
          children: [
            Expanded(                // ✅ Equal button widths
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                ),
                child: Text(
                  'Action 1',
                  style: TextStyle(fontSize: 14.sp),
                ),
              ),
            ),
            SizedBox(width: 12.w),   // ✅ ScreenUtil
            Expanded(                // ✅ Equal button widths
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                ),
                child: Text(
                  'Action 2',
                  style: TextStyle(fontSize: 14.sp),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  ),
)
```

## Quick Reference Checklist

When building responsive UI, ask yourself:

- [ ] Are all dimensions using `.w` or `.h`? (ScreenUtil)
- [ ] Are all font sizes using `.sp`? (ScreenUtil)
- [ ] Is text that can be long wrapped in `Expanded`?
- [ ] Are proportional layouts using `Flexible`?
- [ ] Is overflow handled with `TextOverflow.ellipsis`?
- [ ] Are spacing values using ScreenUtil?
- [ ] Does the layout work on different screen sizes?

## Summary

**Remember: ScreenUtil + Expanded + Flexible = Perfect Responsive UI**

- **ScreenUtil**: Scales dimensions and fonts
- **Expanded**: Takes available space
- **Flexible**: Proportional space allocation

Combine them for layouts that work beautifully on all devices! 🎨
