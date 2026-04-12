# Complete Figma Design Prompt: EduSetu Attendance App
## Full App UI/UX Design Specification for Figma

---

## 📱 APP OVERVIEW

### Product Identity
- **App Name**: EduSetu
- **Company**: Digitrix Media
- **Tagline**: "Smart Attendance System" / "Powered Attendance for Smart Institutes"
- **Platform**: Mobile (iOS & Android) - Flutter App
- **Target Users**: Educational Institute Administrators & Staff
- **Primary Function**: Biometric attendance management with AI face recognition

### Core Value Proposition
Secure, automated attendance tracking system that prevents fraud through:
- AI-powered face recognition
- GPS geofencing (30-meter radius)
- Entry/exit photo verification
- Real-time attendance tracking
- Comprehensive reporting

---

## 🎨 DESIGN SYSTEM

### Color Palette

#### Primary Colors
- **Primary Blue**: `#1E88E5` (RGB: 30, 136, 229)
  - Usage: Primary actions, links, headers
  - Variants: Light `#64B5F6`, Dark `#1565C0`
  
- **Primary Green**: `#4CAF50` (RGB: 76, 175, 80)
  - Usage: Success states, present attendance, positive actions
  - Variants: Light `#81C784`, Dark `#388E3C`
  
- **Accent Red**: `#F44336` (RGB: 244, 67, 54)
  - Usage: Errors, absent attendance, warnings
  - Variants: Light `#E57373`, Dark `#D32F2F`

#### Secondary Colors
- **Orange/Warning**: `#FF9800` (RGB: 255, 152, 0)
  - Usage: Warnings, medium attendance
- **Purple**: `#9C27B0` (RGB: 156, 39, 176)
  - Usage: Special features, premium
- **Teal**: `#009688` (RGB: 0, 150, 136)
  - Usage: Information, secondary actions

#### Neutral Colors
- **Background Light**: `#F5F5F5` (RGB: 245, 245, 245)
- **Background Dark**: `#121212` (RGB: 18, 18, 18)
- **Surface Light**: `#FFFFFF` (RGB: 255, 255, 255)
- **Surface Dark**: `#1E1E1E` (RGB: 30, 30, 30)
- **Text Primary**: `#212121` (Light) / `#FFFFFF` (Dark)
- **Text Secondary**: `#757575` (Light) / `#B0B0B0` (Dark)
- **Text Disabled**: `#BDBDBD` (Light) / `#424242` (Dark)
- **Divider**: `#E0E0E0` (Light) / `#424242` (Dark)

#### Glassmorphic Colors
- **Glass Background**: `rgba(255, 255, 255, 0.15)` (Light) / `rgba(0, 0, 0, 0.3)` (Dark)
- **Glass Border**: `rgba(255, 255, 255, 0.3)` (Light) / `rgba(255, 255, 255, 0.1)` (Dark)
- **Glass Shadow**: `rgba(0, 0, 0, 0.1)` - `rgba(0, 0, 0, 0.2)`

### Typography

#### Font Family
- **Primary Font**: Inter / Roboto / SF Pro Display
- **Fallback**: System default sans-serif
- **Monospace**: For numbers, codes (Roboto Mono)

#### Type Scale
- **Display Large**: 57px / 64px line height / Bold
- **Display Medium**: 45px / 52px line height / Bold
- **Display Small**: 36px / 44px line height / Bold
- **Headline Large**: 32px / 40px line height / SemiBold
- **Headline Medium**: 28px / 36px line height / SemiBold
- **Headline Small**: 24px / 32px line height / SemiBold
- **Title Large**: 22px / 28px line height / Medium
- **Title Medium**: 16px / 24px line height / Medium
- **Title Small**: 14px / 20px line height / Medium
- **Body Large**: 16px / 24px line height / Regular
- **Body Medium**: 14px / 20px line height / Regular
- **Body Small**: 12px / 16px line height / Regular
- **Label Large**: 14px / 20px line height / Medium
- **Label Medium**: 12px / 16px line height / Medium
- **Label Small**: 11px / 16px line height / Medium

### Spacing System
- **Base Unit**: 4px
- **Scale**: 4, 8, 12, 16, 20, 24, 32, 40, 48, 56, 64, 72, 80
- **Padding**: 16px (standard), 24px (large), 32px (extra large)
- **Margin**: 8px (small), 16px (medium), 24px (large), 32px (extra large)
- **Gap**: 8px (small), 16px (medium), 24px (large)

### Border Radius
- **Small**: 4px (buttons, small cards)
- **Medium**: 8px (cards, inputs)
- **Large**: 12px (large cards, modals)
- **XLarge**: 16px (hero sections)
- **Round**: 50% (avatars, pills)

### Shadows
- **Elevation 1**: `0px 1px 3px rgba(0,0,0,0.12), 0px 1px 2px rgba(0,0,0,0.24)`
- **Elevation 2**: `0px 3px 6px rgba(0,0,0,0.16), 0px 3px 6px rgba(0,0,0,0.23)`
- **Elevation 3**: `0px 10px 20px rgba(0,0,0,0.19), 0px 6px 6px rgba(0,0,0,0.23)`
- **Elevation 4**: `0px 15px 30px rgba(0,0,0,0.25), 0px 5px 10px rgba(0,0,0,0.22)`
- **Elevation 5**: `0px 20px 40px rgba(0,0,0,0.30), 0px 5px 10px rgba(0,0,0,0.22)`

### Icons
- **Style**: Material Design Rounded / Material Symbols Rounded
- **Sizes**: 16px, 20px, 24px, 32px, 40px, 48px
- **Weight**: Regular (400), Medium (500), Bold (700)

---

## 📐 COMPONENT LIBRARY

### Buttons

#### Primary Button
- **Size**: Height 56px (large), 48px (medium), 40px (small)
- **Padding**: 16px 24px (large), 12px 20px (medium), 8px 16px (small)
- **Background**: Primary Blue gradient or solid
- **Text**: White, Title Medium, SemiBold
- **Border Radius**: 12px
- **Shadow**: Elevation 2
- **States**: Default, Hover, Pressed, Disabled, Loading

#### Secondary Button
- **Size**: Same as primary
- **Background**: Transparent with border or light fill
- **Text**: Primary Blue, Title Medium, SemiBold
- **Border**: 2px solid Primary Blue
- **States**: Same as primary

#### Text Button
- **Size**: Height 40px
- **Background**: Transparent
- **Text**: Primary Blue, Body Medium, Medium
- **Underline**: On hover/press
- **States**: Default, Hover, Pressed, Disabled

#### Icon Button
- **Size**: 48x48px (standard), 40x40px (small), 56x56px (large)
- **Background**: Transparent or light fill
- **Icon**: 24px, centered
- **Border Radius**: 50% or 12px
- **States**: Default, Hover, Pressed, Disabled

### Input Fields

#### Text Input
- **Height**: 56px (large), 48px (medium)
- **Padding**: 16px (horizontal), 12px (vertical)
- **Background**: White/Dark surface
- **Border**: 1px solid Divider, 2px Primary Blue on focus
- **Border Radius**: 12px
- **Label**: Body Small, above input or floating
- **Hint**: Body Small, inside input
- **Icon**: 24px, left padding 16px
- **States**: Default, Focus, Error, Disabled

#### PIN Input
- **Height**: 64px
- **Width**: Full width or centered
- **Text**: 24px, Bold, centered, letter-spacing 8px
- **Background**: Glassmorphic or solid
- **Border**: 2px solid, Primary Blue on focus
- **Border Radius**: 12px
- **Character Limit**: 6 digits
- **Auto-submit**: After 6 digits

#### Search Input
- **Height**: 48px
- **Icon**: Search icon (24px) on left
- **Clear Button**: X icon (20px) on right when text exists
- **Background**: Light fill or glassmorphic
- **Border Radius**: 24px (pill shape)

### Cards

#### Standard Card
- **Padding**: 16px
- **Background**: Surface color
- **Border Radius**: 12px
- **Shadow**: Elevation 1
- **Spacing**: 16px gap between cards

#### Glassmorphic Card
- **Padding**: 24px
- **Background**: Glass background with blur
- **Border**: 1px solid Glass border
- **Border Radius**: 16px
- **Backdrop Filter**: Blur 10-15px
- **Shadow**: Soft shadow

#### Stats Card
- **Padding**: 20px
- **Background**: Gradient or solid color
- **Border Radius**: 16px
- **Content**: Icon, Number, Label
- **Shadow**: Elevation 2

### Navigation

#### Bottom Navigation Bar
- **Height**: 72px (with safe area)
- **Background**: Surface color with elevation
- **Items**: 5 tabs (Home, Attendance, Students, Batches, Reports)
- **Icon Size**: 24px
- **Label**: Body Small
- **Active Color**: Primary Blue
- **Inactive Color**: Text Secondary
- **Indicator**: Underline or dot on active

#### App Bar
- **Height**: 56px (standard), 64px (large)
- **Background**: Surface color
- **Elevation**: Elevation 1
- **Content**: Title (Headline Small), Actions (Icon buttons)
- **Back Button**: 24px icon, left side

### Lists

#### Student List Item
- **Height**: 72px (compact), 88px (comfortable)
- **Padding**: 16px
- **Content**: Avatar (48px), Name (Title Medium), Roll Number (Body Small), Status badge
- **Action**: Tap to select, swipe actions
- **Divider**: 1px solid Divider

#### Batch List Item
- **Height**: 80px
- **Padding**: 16px
- **Content**: Batch name (Title Medium), Time range (Body Medium), Subject tags
- **Action**: Tap to view details

### Modals & Dialogs

#### Alert Dialog
- **Width**: 320px (mobile), 400px (tablet)
- **Padding**: 24px
- **Border Radius**: 16px
- **Background**: Surface color
- **Title**: Headline Small
- **Content**: Body Medium
- **Actions**: Buttons at bottom

#### Bottom Sheet
- **Height**: Auto (max 80% screen)
- **Border Radius**: 16px (top corners)
- **Background**: Surface color
- **Handle**: 4px height, 40px width, rounded
- **Content**: Scrollable

### Loading States

#### Skeleton Loader
- **Shimmer effect**: Animated gradient
- **Shape**: Matches content (text, cards, avatars)
- **Color**: Light gray with shimmer

#### Progress Indicator
- **Circular**: 24px, 32px, 48px sizes
- **Linear**: Full width, 4px height
- **Color**: Primary Blue

### Badges & Chips

#### Status Badge
- **Size**: Auto (padding 4px 8px)
- **Background**: Color based on status (Green/Present, Red/Absent, Orange/Warning)
- **Text**: Label Small, White
- **Border Radius**: 12px (pill)

#### Chip
- **Height**: 32px
- **Padding**: 8px 12px
- **Background**: Light fill
- **Text**: Body Small, Medium
- **Border Radius**: 16px (pill)
- **Icon**: 16px, optional

---

## 📱 SCREEN SPECIFICATIONS

### 1. SPLASH SCREEN

#### Purpose
First screen shown on app launch, checks authentication status

#### Layout
- **Background**: Animated gradient (Blue to Green)
- **Content**: Centered vertically
  - Logo/Icon: 120x120px, fingerprint or attendance icon
  - App Name: "EduSetu", Display Medium, Bold, White
  - Tagline: "Smart Attendance System", Body Large, White (80% opacity)
  - Company: "By Digitrix Media", Body Medium, White (60% opacity)
- **Loading**: Circular progress indicator at bottom (optional)

#### Animations
- Logo: Scale in (0.8 → 1.0) with fade
- Text: Slide up with fade
- Duration: 1.5-2 seconds

#### States
- Loading: Show spinner
- Error: Show error message (rare)

---

### 2. LOGIN SCREEN

#### Purpose
User authentication (Email/Password or PIN)

#### Layout
- **Background**: Animated gradient with glassmorphic overlay
- **Header** (Top):
  - Logo: 100x100px, glassmorphic container
  - App Name: "EduSetu", Headline Large, Bold, White
  - Tagline: "Smart Attendance System", Body Large, White
  - Company Badge: "By Digitrix Media", glassmorphic pill

- **Form Card** (Center):
  - Background: Glassmorphic card
  - Tab Switcher: Login / Sign Up (horizontal tabs)
  
  **Login Form**:
  - Email Input: Full width, icon on left
  - Password/PIN Toggle: Two buttons side by side
  - Password/PIN Input: Full width, icon on left
  - Forgot PIN Link: Right-aligned (PIN mode only)
  - Change User Link: Left-aligned (PIN mode only)
  - Login Button: Full width, primary style
  - Biometric Button: Full width, secondary style (if enabled)
  - Security Badge: Small indicator showing login method

- **Footer** (Bottom):
  - Change User Account Button: Text button
  - Powered by Digitrix Media: Small text

#### States
- Default: Empty form
- Loading: Button shows spinner
- Error: Inline error message or snackbar
- Success: Navigate to next screen

#### Interactions
- PIN mode: Auto-submit after 6 digits
- Biometric: Auto-trigger if enabled
- Form validation: Real-time

---

### 3. SETUP SCREEN (First-Time Admin)

#### Purpose
Create first admin account (only shown if no admin exists)

#### Layout
- **Header**:
  - Icon: Admin panel icon, 80x80px
  - Title: "EduSetu", Headline Large
  - Subtitle: "By Digitrix Media", Body Medium
  - Tagline: "Powered Attendance for Smart Institutes", chip style

- **Form**:
  - Full Name Input
  - Admin ID Input
  - Email Input
  - Password Input
  - Create Admin Button: Full width, primary

#### Validation
- All fields required
- Email format validation
- Password min 6 characters

---

### 4. INSTITUTE SEARCH SCREEN

#### Purpose
Search and select institute for registration

#### Layout
- **App Bar**: 
  - Title: "Select Institute"
  - Back button

- **Search Bar**:
  - Full width search input
  - Search icon on left
  - Clear button on right (when text exists)

- **Institute List**:
  - Scrollable list
  - Each item:
    - Institute Name: Title Medium
    - Location: Body Small (City, State)
    - Icon: Arrow right (24px)
  - Empty state: "No institutes found"

#### Interactions
- Search: Real-time filtering
- Tap item: Navigate to registration

---

### 5. INSTITUTE REGISTRATION SCREEN

#### Purpose
Register new user account with institute

#### Layout
- **Header**: Same as login
- **Form**:
  - Name Input
  - Email Input
  - Password Input
  - Mobile Number Input
  - Send OTP Button
  - OTP Input (appears after OTP sent)
  - Verify & Register Button

#### States
- Before OTP: Show send OTP button
- After OTP: Show OTP input and verify button
- Timer: Countdown for OTP resend

---

### 6. BIOMETRIC LOCK SCREEN

#### Purpose
Quick unlock with biometric or PIN (IRCTC-style)

#### Layout
- **Background**: Blurred app screenshot or gradient
- **Content**: Centered
  - Lock Icon: 64px, centered
  - Title: "Unlock App", Headline Medium
  - Subtitle: "Use biometric or PIN", Body Medium
  - PIN Input: Always visible, centered
  - Biometric Button: Large, prominent (if enabled)
  - Change User Link: Bottom

#### Interactions
- Auto-trigger biometric on appear (500ms delay)
- PIN: Auto-submit after 6 digits
- Biometric: Show prompt overlay

---

### 7. HOME DASHBOARD

#### Purpose
Main screen with quick stats and navigation

#### Layout
- **App Bar**:
  - Title: "Dashboard" or "Home"
  - Profile icon (right)
  - Settings icon (right)

- **Stats Cards** (Top):
  - 4 cards in 2x2 grid (mobile) or 4 columns (tablet)
  - Each card:
    - Icon: 32px
    - Number: Display Small, Bold
    - Label: Body Small
    - Color: Different for each (Blue, Green, Orange, Purple)
  - Cards: Total Students, Present Today, Absent Today, Attendance Rate

- **Quick Actions** (Middle):
  - Grid of 6-8 action buttons
  - Each button:
    - Icon: 32px
    - Label: Body Small
    - Card style with elevation
  - Actions: Mark Attendance, Add Student, View Students, Batches, Reports, Settings

- **Recent Activity** (Bottom):
  - Section title: "Recent Activity"
  - List of recent attendance marks
  - Each item: Student name, time, status

#### States
- Loading: Skeleton loaders
- Empty: Empty state message
- Error: Error message with retry

---

### 8. ATTENDANCE MARKING SCREEN

#### Purpose
Mark student entry/exit with face recognition

#### Layout
- **App Bar**:
  - Title: "Mark Attendance"
  - Batch Selector: Dropdown (optional)

- **Search Bar**:
  - Full width search input
  - Search by name or roll number

- **Student List**:
  - Scrollable list
  - Each item:
    - Avatar: 48px (student photo)
    - Name: Title Medium
    - Roll Number: Body Small
    - Status Badge: Present/Absent
    - Action Buttons: Mark Entry / Mark Exit

- **Selected Student Card** (Expanded):
  - Large avatar: 80px
  - Name: Headline Small
  - Roll Number: Body Medium
  - Batch Info: Chips
  - Entry/Exit Status: Cards with photos
  - Action Buttons: Mark Entry, Mark Exit

#### States
- Searching: Show loading
- Face Recognition: Show camera overlay
- GPS Check: Show location indicator
- Success: Show confirmation with photo
- Error: Show error message

---

### 9. STUDENT MANAGEMENT SCREEN

#### Purpose
View, search, and manage all students

#### Layout
- **App Bar**:
  - Title: "Students"
  - Search icon
  - Add Student FAB

- **Search Bar** (Collapsible):
  - Full width search input
  - Filter chips: All, Semester 1, Semester 2

- **Student List**:
  - Scrollable list
  - Each item:
    - Avatar: 56px
    - Name: Title Medium
    - Roll Number: Body Small
    - Semester: Chip
    - Batches: Chips (scrollable)
    - Menu: 3-dot menu
  - Empty state: "No students found"

- **FAB**: Add Student button (bottom right)

#### Interactions
- Tap student: View details
- Long press: Quick actions menu
- Swipe: Delete action
- Search: Real-time filtering

---

### 10. ADD STUDENT SCREEN

#### Purpose
Register new student with all details

#### Layout
- **App Bar**:
  - Title: "Add Student"
  - Back button
  - Save button (top right)

- **Form** (Scrollable):
  - Photo Section:
    - Avatar placeholder: 120x120px
    - Camera icon overlay
    - "Capture Photo" button
  
  - Basic Info:
    - Full Name Input
    - Roll Number Input
    - Contact Number Input
  
  - Academic Info:
    - Semester Dropdown: Semester 1 / Semester 2
    - Year: Auto-detected (display only)
  
  - Batch Selection:
    - Section title: "Select Batches"
    - Checkbox list of all batches
    - Each item: Batch name, time range
  
  - Subject Selection:
    - Section title: "Select Subjects (2-3)"
    - Checkbox list of 8 predefined subjects
    - Validation: Min 2, Max 3
  
  - Submit Button: Full width, primary

#### Validation
- All fields required
- Photo required
- Min 2 subjects, Max 3 subjects
- At least 1 batch selected

---

### 11. BATCH MANAGEMENT SCREEN

#### Purpose
View, create, and manage batches

#### Layout
- **App Bar**:
  - Title: "Batches"
  - Auto-Generate button (top right)
  - Add Batch FAB

- **Filter Chips**:
  - All, Semester 1, Semester 2
  - Active, Inactive

- **Batch List**:
  - Scrollable list
  - Each item:
    - Batch Name: Title Medium
    - Time Range: Body Medium (e.g., "08:00 - 09:00")
    - Subjects: Chips (scrollable)
    - Semester: Chip
    - Status: Badge (Active/Inactive)
    - Menu: 3-dot menu

- **FAB**: Add Batch button

#### Empty State
- Illustration
- Message: "No batches created"
- CTA: "Auto-Generate Batches" button

---

### 12. AUTO-GENERATE BATCHES DIALOG

#### Purpose
Configure and generate batches automatically

#### Layout
- **Modal/Dialog**:
  - Title: "Auto-Generate Batches"
  
  - Form:
    - Institute Timing:
      - Open Time: Time picker
      - Close Time: Time picker
      - Duration Display: "12 hours" (calculated)
    
    - Batch Duration:
      - Radio buttons: 60 Minutes / 120 Minutes
      - Description below each
    
    - Semester:
      - Dropdown: Semester 1 / Semester 2
    
    - Subjects:
      - Checkbox list (select 2-3)
      - Validation message
    
    - Preview:
      - "Will generate X batches"
      - List preview (optional)
  
  - Actions:
    - Cancel button
    - Generate button (primary)

---

### 13. ATTENDANCE REPORTS SCREEN

#### Purpose
Generate and view attendance reports

#### Layout
- **App Bar**:
  - Title: "Reports"
  - Export button (top right)

- **Date Range Selector**:
  - From Date: Date picker button
  - To Date: Date picker button
  - Validation: Max 1 month range

- **Report Options**:
  - Generate Report button
  - Calendar View button
  - Trend Analysis button

- **Report Content** (After generation):
  - Summary Cards:
    - Total Students
    - Total Attendance
    - Average Percentage
  
  - Student List:
    - Each item:
      - Avatar: 40px
      - Name: Title Small
      - Roll Number: Body Small
      - Attendance: Percentage with progress bar
      - Tap to view details

- **Export Options**:
  - PDF button
  - Excel button
  - Share button

---

### 14. GPS SETTINGS SCREEN

#### Purpose
Configure institute location and geofence

#### Layout
- **App Bar**:
  - Title: "GPS Settings"
  - Back button

- **Current Location Card**:
  - Title: "Institute Location"
  - Latitude: Display (editable)
  - Longitude: Display (editable)
  - Map Preview: Small map view
  - Set Location Button: Opens map picker

- **Geofence Settings**:
  - Radius: 30 meters (display, editable)
  - Visual indicator: Circle on map
  - Description: "Attendance can only be marked within this radius"

- **Test Location**:
  - Current Location: Display
  - Status: Within/Outside radius
  - Distance: Display
  - Test Button: Check current location

- **Map View** (Full screen when opened):
  - Interactive map
  - Marker: Institute location
  - Circle: Geofence radius
  - Current location: Blue dot

---

### 15. HELP DESK SCREEN

#### Purpose
Help documentation and support

#### Layout
- **App Bar**:
  - Title: "Help & Support"
  - Back button

- **Sections**:
  - FAQ: Expandable list
  - Features Guide: List of features with descriptions
  - Contact Support: Email, phone buttons
  - About: App version, company info

---

## 🔄 USER FLOWS

### Flow 1: First-Time Setup
1. Splash Screen → Setup Screen
2. Fill admin details → Create Admin
3. Success → Login Screen
4. Login → Home Dashboard

### Flow 2: New User Registration
1. Login Screen → Tap "Sign Up"
2. Institute Search Screen → Search/Select institute
3. Institute Registration → Fill form
4. Send OTP → Enter OTP → Verify
5. Success → Login Screen

### Flow 3: Daily Login
1. Splash Screen → Login Screen
2. Enter email → Choose Password/PIN
3. Authenticate → Biometric Lock (if enabled)
4. Unlock → Home Dashboard

### Flow 4: Mark Attendance
1. Home Dashboard → Mark Attendance
2. Search student → Select student
3. Tap "Mark Entry" → Face recognition → GPS check
4. Photo captured → Entry marked
5. Later: Tap "Mark Exit" → Same process → Exit marked

### Flow 5: Add Student
1. Home Dashboard → Add Student
2. Fill form → Select batches → Select subjects
3. Capture photo → Submit
4. Success → Student added

### Flow 6: Generate Report
1. Home Dashboard → Reports
2. Select date range → Generate Report
3. View report → Export (PDF/Excel)

---

## 🎭 INTERACTIONS & ANIMATIONS

### Page Transitions
- **Push**: Slide from right (300ms)
- **Pop**: Slide to right (300ms)
- **Modal**: Fade + scale up (400ms)
- **Bottom Sheet**: Slide up from bottom (300ms)

### Micro-interactions
- **Button Press**: Scale down (0.95) with feedback
- **Card Tap**: Elevation increase
- **Input Focus**: Border color change + scale (1.02)
- **Loading**: Skeleton shimmer or spinner
- **Success**: Checkmark animation
- **Error**: Shake animation

### Gestures
- **Swipe Left**: Delete action (lists)
- **Swipe Right**: Navigate back
- **Pull to Refresh**: Refresh data
- **Long Press**: Context menu

---

## 📱 RESPONSIVE DESIGN

### Breakpoints
- **Mobile Small**: 320px - 375px
- **Mobile Medium**: 375px - 414px
- **Mobile Large**: 414px - 480px
- **Tablet**: 600px - 1024px
- **Desktop**: 1024px+

### Adaptations
- **Grid**: 2 columns (mobile) → 4 columns (tablet)
- **Cards**: Full width (mobile) → Fixed width (tablet)
- **Navigation**: Bottom bar (mobile) → Sidebar (tablet)
- **Spacing**: Reduced on small screens
- **Typography**: Scales with screen size

---

## 🌓 DARK MODE

### Color Adaptations
- **Background**: Light → Dark
- **Surface**: White → Dark gray
- **Text**: Dark → Light
- **Borders**: Light gray → Dark gray
- **Shadows**: Adjusted for dark theme

### Component States
- All components have dark mode variants
- Icons: Adjusted opacity/color
- Images: Optional dark mode variants

---

## ✅ DESIGN CHECKLIST

### Visual Design
- [ ] Consistent color palette
- [ ] Typography hierarchy
- [ ] Spacing system
- [ ] Icon consistency
- [ ] Component library
- [ ] Dark mode support

### User Experience
- [ ] Clear navigation
- [ ] Intuitive interactions
- [ ] Loading states
- [ ] Error handling
- [ ] Empty states
- [ ] Success feedback

### Accessibility
- [ ] Color contrast (WCAG AA)
- [ ] Touch targets (min 48x48px)
- [ ] Text readability
- [ ] Screen reader support
- [ ] Keyboard navigation

### Technical
- [ ] Responsive layouts
- [ ] Animation specifications
- [ ] Asset exports
- [ ] Design tokens
- [ ] Component variants

---

## 📦 FIGMA FILE STRUCTURE

### Pages
1. **Design System**
   - Colors
   - Typography
   - Spacing
   - Components

2. **Authentication**
   - Splash
   - Login
   - Setup
   - Institute Search
   - Registration
   - Biometric Lock

3. **Main App**
   - Home Dashboard
   - Attendance
   - Student Management
   - Batch Management
   - Reports
   - Settings

4. **Components**
   - Buttons
   - Inputs
   - Cards
   - Navigation
   - Modals
   - Lists

5. **User Flows**
   - Flow diagrams
   - Wireframes
   - Prototypes

---

## 🎯 DESIGN PRINCIPLES

1. **Security First**: Visual indicators of security
2. **Efficiency**: Quick actions, minimal taps
3. **Clarity**: Clear labels, intuitive icons
4. **Consistency**: Same patterns throughout
5. **Feedback**: Always show loading/error/success states
6. **Accessibility**: Usable by everyone
7. **Modern**: Contemporary design trends
8. **Professional**: Trustworthy appearance

---

## 🚀 IMPLEMENTATION NOTES

### Figma Best Practices
- Use Auto Layout for all components
- Create component variants for states
- Use constraints for responsive design
- Name layers clearly
- Group related elements
- Use styles for colors and text
- Create interactive prototypes

### Export Specifications
- **Icons**: SVG (preferred) or PNG @1x, 2x, 3x
- **Images**: PNG or WebP, optimized
- **Assets**: Export as individual components
- **Spacing**: Document in design system

### Handoff Requirements
- Component specifications
- Spacing measurements
- Color codes (hex, RGB)
- Typography details
- Animation descriptions
- Interaction notes

---

**This comprehensive prompt covers the entire EduSetu app for Figma design. Use this as a reference to create pixel-perfect, user-friendly designs that align with the app's functionality and brand identity.**
