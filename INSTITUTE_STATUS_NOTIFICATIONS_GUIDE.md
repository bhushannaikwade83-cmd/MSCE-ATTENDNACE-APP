# Institute Open/Close Notifications Guide

## Overview
This system automatically sends notifications for institute opening/closing times and handles holiday marking. It ensures attendance is not marked as absent on holidays.

## Features

### 1. **Scheduled Notifications**
- **1 Hour Before Opening**: Reminder notification
- **30 Minutes Before Opening**: Reminder notification  
- **5 Minutes Before Opening**: Final reminder notification
- **At Closing Time**: Notification to mark institute as closed
- **30 Minutes After Closing**: Auto-close if not manually closed

### 2. **Institute Status Management**
- **Open**: Institute is open for the day
- **Closed**: Institute is closed for the day
- **Holiday**: Day is marked as holiday (attendance not counted as absent)

### 3. **Auto-Close Feature**
- If institute is not marked as closed within 30 minutes after closing time
- Automatically closes the institute for that day
- Sends notification about auto-closure

## How It Works

### Notification Flow
1. **On App Start**: Notifications are scheduled based on institute timing
2. **Before Opening**: 3 notifications (1h, 30m, 5m before)
3. **At Closing**: Notification to mark as closed
4. **After Closing**: Auto-close check after 30 minutes

### Status Marking
1. **Tap Notification**: Opens app and shows status dialog
2. **Select Action**: Choose Open/Close/Holiday
3. **Save**: Status is saved to Firestore
4. **Notifications**: New notifications scheduled if opened

### Holiday Handling
- When marked as holiday:
  - Day is stored in `dailyStatus` collection
  - Attendance reports skip this day
  - Students are NOT marked as absent
  - Holiday status shown in reports

## Firestore Structure

### Daily Status Collection
**Path**: `institutes/{instituteId}/dailyStatus/{date}`

**Document Structure**:
```json
{
  "status": "open" | "closed" | "holiday",
  "date": "2026-01-15",
  "openedAt": "2026-01-15T08:00:00Z",  // If opened
  "openedBy": "user_id",
  "closedAt": "2026-01-15T22:00:00Z",  // If closed
  "closedBy": "user_id" | "system",    // "system" if auto-closed
  "autoClosed": false,                 // true if auto-closed
  "markedAt": "2026-01-15T08:00:00Z",  // If holiday
  "markedBy": "user_id",
  "reason": "National Holiday",        // Optional, for holidays
  "updatedAt": "2026-01-15T08:00:00Z"
}
```

## Usage

### For Admins

1. **Mark Institute Status**:
   - Tap the institute status icon in the app bar (Admin Home Screen)
   - Select: Open / Close / Holiday
   - Optionally add reason for holiday

2. **Notifications**:
   - Notifications are sent automatically
   - Tap notification to open app and mark status
   - Status icon in app bar shows current status

3. **Holiday Management**:
   - Mark as holiday at start of day
   - That day won't count attendance as absent
   - Holiday shown in attendance reports

### Automatic Features

- **Auto-Scheduling**: Notifications scheduled when institute loads
- **Auto-Close**: Closes automatically if not marked within 30 minutes
- **Holiday Detection**: Attendance reports automatically skip holidays

## Technical Details

### Services

1. **InstituteStatusService** (`lib/services/institute_status_service.dart`)
   - Manages open/close/holiday status
   - Stores status in Firestore
   - Provides status checking methods

2. **InstituteNotificationService** (`lib/services/institute_notification_service.dart`)
   - Schedules local notifications
   - Handles notification taps
   - Manages background tasks for auto-close

3. **NotificationHandler** (`lib/services/notification_handler.dart`)
   - Processes notification taps
   - Navigates to appropriate screen
   - Shows status dialog

### UI Components

- **InstituteStatusDialog** (`lib/presentation/widgets/institute_status_dialog.dart`)
  - Dialog to mark institute status
  - Shows current status
  - Options: Open / Close / Holiday

### Background Tasks

- **Workmanager**: Handles auto-close task
- **Task Name**: `autoCloseInstitute`
- **Trigger**: 30 minutes after closing time

## Configuration

### Institute Timing
Set in `institutes/{instituteId}` document:
```json
{
  "batchOpenTime": {
    "hour": 8,
    "minute": 0
  },
  "batchCloseTime": {
    "hour": 22,
    "minute": 0
  }
}
```

### Notification Permissions
- Android: Automatically requested on first use
- iOS: Requested on app start

## Notes

- Notifications are scheduled daily when institute loads
- Status persists in Firestore for historical tracking
- Holidays are automatically excluded from absent counts
- Auto-close prevents attendance marking after closing time
