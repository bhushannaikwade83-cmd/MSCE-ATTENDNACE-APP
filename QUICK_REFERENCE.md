# 🚀 Quick Reference Card

## Imports
```dart
import 'package:smart_attendance_app/core/theme/app_theme.dart';
import 'package:smart_attendance_app/presentation/widgets/app_button_variants.dart';
import 'package:smart_attendance_app/presentation/widgets/app_card_widgets.dart';
import 'package:smart_attendance_app/presentation/widgets/app_state_widgets.dart';
import 'package:smart_attendance_app/presentation/widgets/app_utility_widgets.dart';
```

## Spacing (Stop hardcoding!)
```dart
AppSpacing.xs    // 4px
AppSpacing.sm    // 8px
AppSpacing.md    // 12px
AppSpacing.lg    // 16px  ← Most common
AppSpacing.xl    // 24px
AppSpacing.xxl   // 32px
```

## Buttons
```dart
// Primary (Navy - main action)
AppButton(text: 'Submit', onPressed: () {})

// Secondary (Outlined - alternative)
AppButton(text: 'Cancel', variant: ButtonVariant.secondary, onPressed: () {})

// Tertiary (Saffron - less important)
AppButton(text: 'More', variant: ButtonVariant.tertiary, onPressed: () {})

// Danger (Red - destructive)
AppButton(text: 'Delete', variant: ButtonVariant.danger, onPressed: () {})

// Ghost (Minimal)
AppButton(text: 'Skip', variant: ButtonVariant.ghost, onPressed: () {})

// Mini (Toolbar)
AppMiniButton(tooltip: 'Edit', icon: Icons.edit, onPressed: () {})

// With Loading
AppButton(text: 'Save', isLoading: true, onPressed: null)
```

## Cards
```dart
// Standard
AppCard(child: Text('Content'))

// With accent (government style)
AccentCard(child: Text('Important'))

// Elevated (highlighted)
ElevatedAppCard(showTopAccent: true, child: Text('Special'))

// Data display
DataCard(label: 'Status', value: '95%', icon: Icons.trending_up)
```

## States
```dart
// Empty
EmptyStateWidget(
  icon: Icons.inbox,
  title: 'No Data',
  description: 'Start here',
  actionLabel: 'Create',
  actionCallback: () {},
)

// Error
ErrorStateWidget(
  title: 'Failed',
  message: 'Something went wrong',
  retryCallback: () => retry(),
)

// Loading
LoadingStateWidget(message: 'Loading...')

// Status badge
StatusIndicator(
  status: StatusIndicator.StatusType.success,
  label: 'Present',
)
```

## Animations
```dart
// Use these durations
AppAnimations.quickFeedback   // 100ms - button clicks
AppAnimations.standard         // 200ms - normal transitions
AppAnimations.standardPlus     // 250ms - slightly longer
AppAnimations.transition       // 300ms - page transitions
AppAnimations.delayed          // 500ms - feedback animations

// Example
duration: AppAnimations.standard,
curve: AppAnimations.easeOut,
```

## Colors
```dart
// Primary
AppTheme.primaryBlue        // #1A3C6E
AppTheme.primaryBlueDark    // #0F2547

// Accents
AppTheme.accentSaffron      // #E8871A
AppTheme.accentGreen        // #388E3C
AppTheme.accentRed          // #B71C1C

// Text
AppTheme.textDark           // #1A1A2E
AppTheme.textGray           // #5A6475

// Backgrounds
AppTheme.primaryBlueLighter // #E3F2FD
AppTheme.backgroundGrey     // #EEF2F7
```

## Lists with Animation
```dart
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => AnimatedListItem(
    index: index,
    staggerDelay: Duration(milliseconds: 50),
    child: YourCard(),
  ),
)
```

## Common Pattern (Screen with States)
```dart
@override
Widget build(BuildContext context) {
  if (_isLoading) return LoadingStateWidget();
  if (_error != null) return ErrorStateWidget(message: _error!);
  if (_items.isEmpty) return EmptyStateWidget();
  
  return ListView.builder(
    itemCount: _items.length,
    itemBuilder: (context, index) => AnimatedListItem(
      index: index,
      child: AppCard(child: Text(_items[index])),
    ),
  );
}
```

## Focus/Accessibility
```dart
AppButton(
  text: 'Save',
  focusNode: _saveFocusNode,
  onPressed: () {},
)
// Focus ring appears automatically!
```

## No More
❌ `const EdgeInsets.all(16)`  →  ✅ `AppSpacing.lg`
❌ `Color(0xFF1A3C6E)`          →  ✅ `AppTheme.primaryBlue`
❌ `Duration(ms: 200)`          →  ✅ `AppAnimations.standard`
❌ `Padding(padding: ...)`      →  ✅ Direct with `AppSpacing`

## File Locations
- Buttons: `app_button_variants.dart`
- Cards: `app_card_widgets.dart`
- States: `app_state_widgets.dart`
- Utils: `app_utility_widgets.dart`
- Theme: `app_ui.dart`

## Need Help?
1. `NEW_UI_SYSTEM_GUIDE.md` - Full reference
2. `EXAMPLE_SCREEN_REFACTOR.dart` - Working example
3. `IMPLEMENTATION_CHECKLIST.md` - Step-by-step

**That's it! You're ready to go! 🚀**
