# New UI/UX System Implementation Guide

## Overview

Your app now has a complete professional UI system with:
- ✅ Enhanced theme with spacing and animation constants
- ✅ Button variants (Primary, Secondary, Tertiary, Danger, Ghost)
- ✅ Card widgets (AppCard, AccentCard, ElevatedCard, etc.)
- ✅ State widgets (Empty, Error, Loading)
- ✅ Utility widgets (Spinners, Skeletons, Animations)

---

## Quick Start

### Import the New Widgets

```dart
import 'package:smart_attendance_app/core/theme/app_theme.dart';
import 'package:smart_attendance_app/presentation/widgets/app_button_variants.dart';
import 'package:smart_attendance_app/presentation/widgets/app_card_widgets.dart';
import 'package:smart_attendance_app/presentation/widgets/app_state_widgets.dart';
import 'package:smart_attendance_app/presentation/widgets/app_utility_widgets.dart';
```

### Use Spacing & Animations Consistently

```dart
// Instead of hardcoded values
padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),

// Use the spacing system
padding: AppSpacing.cardPadding,

// For animations
Duration(milliseconds: 200),  // ❌ Don't do this

AppAnimations.standard,  // ✅ Use this
```

---

## Buttons

### Primary Button (Default - Navy Blue)

```dart
AppButton(
  text: 'Mark Attendance',
  onPressed: () => markAttendance(),
  icon: Icons.check_rounded,
)
```

### Secondary Button (Outlined)

```dart
AppButton(
  text: 'Cancel',
  onPressed: () => Navigator.pop(context),
  variant: ButtonVariant.secondary,
)
```

### Tertiary Button (Saffron - Secondary Action)

```dart
AppButton(
  text: 'More Options',
  onPressed: () => showOptions(),
  variant: ButtonVariant.tertiary,
)
```

### Danger Button (Red - Destructive Action)

```dart
AppButton(
  text: 'Delete Record',
  onPressed: () => deleteAttendance(),
  variant: ButtonVariant.danger,
)
```

### Ghost Button (Minimal)

```dart
AppButton(
  text: 'Learn More',
  onPressed: () => showInfo(),
  variant: ButtonVariant.ghost,
)
```

### With Loading State

```dart
AppButton(
  text: 'Submitting...',
  onPressed: isLoading ? null : () => submit(),
  isLoading: isLoading,
)
```

### Mini Button (Toolbar/Inline)

```dart
AppMiniButton(
  tooltip: 'Delete',
  icon: Icons.delete_rounded,
  onPressed: () => delete(),
  variant: ButtonVariant.danger,
)
```

### Compact Button (Small Spaces)

```dart
AppCompactButton(
  text: 'Save',
  onPressed: () => save(),
  variant: ButtonVariant.primary,
)
```

### With Focus Node (Keyboard Navigation)

```dart
final focusNode = FocusNode();

AppButton(
  text: 'Submit',
  onPressed: () => submit(),
  focusNode: focusNode,
)
```

---

## Cards

### Standard Card

```dart
AppCard(
  padding: AppSpacing.cardPadding,
  onTap: () => navigateToDetails(),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Attendance Status', style: textTheme.titleLarge),
      Text('Present', style: textTheme.headlineSmall),
    ],
  ),
)
```

### Card with Left Accent (Government Style)

```dart
AccentCard(
  accentColor: AppTheme.primaryBlue,
  onTap: () {},
  child: Text('Important Notice'),
)
```

### Elevated Card (Highlighted)

```dart
ElevatedAppCard(
  showTopAccent: true,
  accentColor: AppTheme.accentSaffron,
  child: Text('Special Announcement'),
)
```

### Outlined Card (Alternative Style)

```dart
OutlinedAppCard(
  backgroundColor: AppTheme.primaryBlueLighter,
  borderColor: AppTheme.primaryBlue,
  child: Text('Info Box'),
)
```

### Data Card (Statistics Display)

```dart
DataCard(
  label: 'Attendance',
  value: '95%',
  icon: Icons.trending_up_rounded,
  accentColor: AppTheme.primaryGreen,
  subtitle: 'Last 30 days',
)
```

### Minimal Card (Subtle Container)

```dart
MinimalCard(
  backgroundColor: AppTheme.backgroundOffWhite,
  child: Text('Subtle box'),
)
```

---

## State Widgets

### Empty State

```dart
EmptyStateWidget(
  icon: Icons.inbox_rounded,
  title: 'No Attendance Records',
  description: 'Mark your attendance to get started',
  actionLabel: 'Mark Attendance',
  actionCallback: () => markAttendance(),
  iconColor: AppTheme.primaryBlue,
)
```

### Error State

```dart
ErrorStateWidget(
  title: 'Something Went Wrong',
  message: 'Failed to load attendance records',
  details: 'Error: Network timeout after 30s',
  retryCallback: () => retry(),
  dismissCallback: () => Navigator.pop(context),
  isExpandable: true,
)
```

### Loading State

```dart
LoadingStateWidget(
  message: 'Loading attendance...',
  showProgress: true,
)
```

### Status Indicator

```dart
// Success
StatusIndicator(
  status: StatusIndicator.StatusType.success,
  label: 'Present',
  showIcon: true,
)

// Error
StatusIndicator(
  status: StatusIndicator.StatusType.error,
  label: 'Absent',
)

// Warning
StatusIndicator(
  status: StatusIndicator.StatusType.warning,
  label: 'Late',
)

// Pending
StatusIndicator(
  status: StatusIndicator.StatusType.pending,
  label: 'Pending Approval',
)
```

### Info Banner

```dart
InfoBanner(
  title: 'Important Update',
  description: 'New attendance policy starts tomorrow',
  icon: Icons.info_outline_rounded,
  backgroundColor: AppTheme.yellowLight,
  textColor: AppTheme.accentYellow,
  onDismiss: () => dismiss(),
)
```

### Divider with Text

```dart
DividerWithText(text: 'OR'),
```

---

## Utility Widgets

### Custom Loading Spinner

```dart
AppLoadingSpinner(
  size: 48,
  color: AppTheme.primaryBlue,
  strokeWidth: 3,
)
```

### Skeleton Loader (Shimmer)

```dart
Column(
  children: [
    SkeletonLoader(width: double.infinity, height: 100),
    SizedBox(height: 12),
    SkeletonLoader(width: double.infinity, height: 50),
  ],
)
```

### Success Checkmark Animation

```dart
SuccessCheckmark(
  size: 64,
  color: AppTheme.primaryGreen,
  onComplete: () => Navigator.pop(context),
)
```

### Error Shake Animation

```dart
ErrorShake(
  offset: 10,
  duration: AppAnimations.delayed,
  child: Container(
    color: Colors.red,
    child: Text('Error!'),
  ),
)
```

### Animated List Items

```dart
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => AnimatedListItem(
    index: index,
    staggerDelay: Duration(milliseconds: 50),
    child: ListTile(title: Text(items[index])),
  ),
)
```

### Expandable Section

```dart
ExpandableSection(
  title: 'Advanced Options',
  initiallyExpanded: false,
  child: Column(
    children: [
      TextField(decoration: InputDecoration(labelText: 'Option 1')),
      TextField(decoration: InputDecoration(labelText: 'Option 2')),
    ],
  ),
)
```

### Page Transition

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => SmoothPageTransition(
      child: MyNewPage(),
    ),
  ),
)
```

### Badge

```dart
AppBadge(
  text: 'NEW',
  backgroundColor: AppTheme.accentSaffron,
  textColor: Colors.white,
)
```

### Tooltip

```dart
AppTooltip(
  message: 'Click to mark attendance',
  child: AppButton(
    text: 'Mark',
    onPressed: () {},
  ),
)
```

---

## Spacing System

Use these constants throughout your app for consistency:

```dart
// Inside padding
padding: AppSpacing.lg,  // 16px

// Inside margins
margin: AppSpacing.xl,   // 24px

// Gaps between widgets
SizedBox(height: AppSpacing.md),  // 12px
SizedBox(width: AppSpacing.sm),   // 8px

// Common combinations
padding: AppSpacing.cardPadding,           // 16px all sides
padding: AppSpacing.paddingHorizontalLg,   // 16px left/right
padding: AppSpacing.paddingVerticalMd,     // 12px top/bottom
```

**Spacing Values:**
- `xs`: 4px (micro spacing)
- `sm`: 8px (small spacing)
- `md`: 12px (medium spacing)
- `lg`: 16px (default spacing)
- `xl`: 24px (large spacing)
- `xxl`: 32px (extra large spacing)

---

## Animation Durations

Use these for consistent feel across the app:

```dart
// Quick feedback (button press)
duration: AppAnimations.quickFeedback,  // 100ms

// Standard transition (most animations)
duration: AppAnimations.standard,       // 200ms

// Standard plus (slightly longer)
duration: AppAnimations.standardPlus,   // 250ms

// Page transition
duration: AppAnimations.transition,     // 300ms

// Delayed feedback
duration: AppAnimations.delayed,        // 500ms
```

---

## Colors Reference

### Primary Colors
- `AppTheme.primaryBlue`: #1A3C6E (Main color)
- `AppTheme.primaryBlueDark`: #0F2547 (Headers)
- `AppTheme.primaryBlueLight`: #2B5BA0 (Hover states)

### Supporting Colors (NEW)
- `AppTheme.primaryBlueLighter`: #E3F2FD (Light backgrounds)
- `AppTheme.borderLight`: #D5E8F7 (Subtle borders)
- `AppTheme.disabledGray`: #E8EAED (Disabled states)
- `AppTheme.focusRing`: #2B5BA0 (Focus indicators)

### Accent Colors
- `AppTheme.accentSaffron`: #E8871A (Secondary action)
- `AppTheme.saffronLight`: #FFF3E0 (Saffron background)
- `AppTheme.accentGreen`: #388E3C (Success)
- `AppTheme.accentRed`: #B71C1C (Error/Danger)
- `AppTheme.accentOrange`: #F57F17 (Warning)
- `AppTheme.accentYellow`: #F9A825 (Pending)

### Neutral Colors
- `AppTheme.textDark`: #1A1A2E (Primary text)
- `AppTheme.textGray`: #5A6475 (Secondary text)
- `AppTheme.textLightGray`: #9EA8B8 (Tertiary text)
- `AppTheme.dividerColor`: #DDE3EE (Dividers)
- `AppTheme.backgroundGrey`: #EEF2F7 (Page background)

---

## Migration Guide (From Old System)

### Old → New Button System

```dart
// OLD
PrimaryButton(
  text: 'Submit',
  onPressed: () {},
)

// NEW - Same result
AppButton(
  text: 'Submit',
  onPressed: () {},
)

// NEW - With variant
AppButton(
  text: 'Cancel',
  onPressed: () {},
  variant: ButtonVariant.secondary,
)
```

### Old → New Card System

```dart
// OLD
Card(
  child: Text('Content'),
)

// NEW - Better styling
AppCard(
  child: Text('Content'),
)
```

### Old → New Spacing

```dart
// OLD
padding: const EdgeInsets.all(16),

// NEW
padding: AppSpacing.lg,
```

---

## Best Practices

### 1. Always Use Spacing Constants

❌ **Don't:**
```dart
padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
```

✅ **Do:**
```dart
padding: AppSpacing.cardPadding,  // or combination of constants
```

### 2. Use Button Variants Appropriately

- **Primary**: Main actions (Submit, Save, Mark Attendance)
- **Secondary**: Alternative actions (Cancel, Go Back)
- **Tertiary**: Less important actions (More Options, View Details)
- **Danger**: Destructive actions (Delete, Remove)
- **Ghost**: Minimal style (Learn More, Skip)

### 3. Handle Loading States

Always show loading feedback:
```dart
AppButton(
  text: isLoading ? 'Saving...' : 'Save',
  onPressed: isLoading ? null : () => save(),
  isLoading: isLoading,
)
```

### 4. Provide Meaningful Empty States

Don't show blank screens:
```dart
if (items.isEmpty) {
  return EmptyStateWidget(
    icon: Icons.inbox_rounded,
    title: 'No Data',
    description: 'Start by creating your first item',
    actionLabel: 'Create New',
    actionCallback: () => create(),
  );
}
```

### 5. Show Helpful Error Messages

Always be specific about what went wrong:
```dart
ErrorStateWidget(
  title: 'Network Error',
  message: 'Failed to connect to server',
  details: 'Please check your internet connection',
  retryCallback: () => retry(),
)
```

### 6. Use Focus Nodes for Keyboard Navigation

Enable keyboard users to navigate:
```dart
FocusNode submitFocusNode = FocusNode();

// In form
AppButton(
  text: 'Submit',
  focusNode: submitFocusNode,
  onPressed: () => submit(),
)
```

### 7. Batch Animations for Lists

Use staggered animations for visual appeal:
```dart
ListView.builder(
  itemBuilder: (context, index) => AnimatedListItem(
    index: index,
    staggerDelay: Duration(milliseconds: 50),
    child: YourCard(),
  ),
)
```

### 8. Keyboard Accessibility

Always provide tooltips and focus indicators:
```dart
AppTooltip(
  message: 'Click to edit your profile',
  child: AppButton(
    text: 'Edit',
    onPressed: () => edit(),
  ),
)
```

---

## Common Patterns

### Form with Validation

```dart
Column(
  children: [
    TextField(
      decoration: InputDecoration(
        labelText: 'Email',
        helperText: 'example@email.com',
        errorText: _emailError,
      ),
    ),
    SizedBox(height: AppSpacing.lg),
    if (_emailError != null)
      ErrorStateWidget(
        title: 'Invalid Email',
        message: 'Please enter a valid email address',
      ),
    SizedBox(height: AppSpacing.xl),
    AppButton(
      text: 'Continue',
      onPressed: _isValid ? () => submit() : null,
    ),
  ],
)
```

### Data List with Actions

```dart
ListView.builder(
  itemCount: records.length,
  itemBuilder: (context, index) {
    final record = records[index];
    return AnimatedListItem(
      index: index,
      child: AccentCard(
        onTap: () => viewDetails(record),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.name),
                  StatusIndicator(
                    status: record.status,
                    label: record.statusLabel,
                  ),
                ],
              ),
            ),
            AppMiniButton(
              tooltip: 'Edit',
              icon: Icons.edit_rounded,
              onPressed: () => edit(record),
            ),
          ],
        ),
      ),
    );
  },
)
```

### Async Operation Flow

```dart
// Start loading
setState(() => _isLoading = true);

// Perform operation
try {
  await performAction();
  // Show success
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      content: SuccessCheckmark(
        onComplete: () => Navigator.pop(context),
      ),
    ),
  );
} catch (e) {
  // Show error
  showErrorDialog(context, error: e.toString());
} finally {
  setState(() => _isLoading = false);
}
```

---

## Troubleshooting

### Button not responding to clicks
- Check if `onPressed` is null
- Verify `isLoading` is false
- Ensure button is not disabled

### Animations not smooth
- Check animation duration (should be using `AppAnimations`)
- Verify device has sufficient resources
- Use `devtools://` to check FPS

### Colors look different
- Verify you're using the correct `AppTheme` colors
- Check if dark theme is enabled
- Test on different screen sizes

### Spacing not consistent
- Always use `AppSpacing` constants
- Don't mix hardcoded values with constants
- Use `padding` not `margin` for internal widget spacing

---

## Next Steps

1. **Gradual Migration**: Update screens one by one
2. **Test Thoroughly**: Test all states (loading, error, empty)
3. **Check Accessibility**: Verify keyboard navigation works
4. **Get Feedback**: Have users test before deploying
5. **Monitor Performance**: Use DevTools to ensure smooth animations

---

## Support

For questions or issues:
1. Check this guide for examples
2. Review widget source code for options
3. Test changes in development branch
4. Document any custom patterns you create

**The system is designed to be flexible—customize colors, spacing, and animations as needed for your specific use cases.**
