import 'package:flutter/material.dart';
import 'package:smart_attendance_app/l10n/app_localizations.dart';
import 'admin_home_screen.dart';
import 'student_management_screen.dart';
import 'attendance_reports_screen.dart';
import 'add_student_screen.dart';
import 'batch_management_screen.dart';
import 'gps_settings_screen.dart';
import '../widgets/modern_bottom_nav_bar.dart';
import '../../core/theme/app_theme.dart';

/// Main Navigation Screen with Bottom Navigation Bar
/// Provides easy access to all features
class MainNavigationScreen extends StatefulWidget {
  static const routeName = '/main-navigation';
  
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  List<Widget> get _screens => [
    const AdminHomeScreen(),
    const BatchManagementScreen(),
    const StudentManagementScreen(), // View Students Screen
    const GpsSettingsScreen(),
    const AttendanceReportsScreen(),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNavItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final navSubtitles = <String>[
      l10n.mainNavSubtitleAdmin,
      l10n.mainNavSubtitleBatch,
      l10n.mainNavSubtitleStudent,
      l10n.mainNavSubtitleGps,
      l10n.mainNavSubtitleReports,
    ];
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        // Pop already happened if didPop is true, no action needed
        // If didPop is false, pop was prevented (no previous route), also no action needed
      },
      child: Scaffold(
        backgroundColor: AppTheme.backgroundGrey,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GovPortalHeader(
              secondaryLine: navSubtitles[_currentIndex],
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                children: _screens,
              ),
            ),
          ],
        ),
      bottomNavigationBar: ModernBottomNavBar(
        selectedIndex: _currentIndex,
        onTap: _onNavItemTapped,
      ),
      ),
    );
  }
}


/// Search Screen
class _SearchScreen extends StatefulWidget {
  const _SearchScreen();

  @override
  State<_SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<_SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        title: const Text(
          'Search',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search students, batches, attendance...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.primaryBlue),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
                ),
                filled: true,
                fillColor: AppTheme.backgroundGrey,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          
          // Search Results
          Expanded(
            child: _searchQuery.isEmpty
                ? _buildEmptyState()
                : _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Search for students, batches, or attendance',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    // In a real app, this would search through Firestore
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSearchResultItem('Students', Icons.person, 'Search students by name or roll number'),
        _buildSearchResultItem('Batches', Icons.groups, 'Find batches and subjects'),
        _buildSearchResultItem('Attendance', Icons.calendar_today, 'Search attendance records'),
        _buildSearchResultItem('Reports', Icons.bar_chart, 'View attendance reports'),
      ],
    );
  }

  Widget _buildSearchResultItem(String title, IconData icon, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primaryBlue, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey),
        ],
      ),
    );
  }
}


/// Create/Add Screen
class _CreateScreen extends StatelessWidget {
  const _CreateScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        title: const Text(
          'Create',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCreateCard(
              title: 'Add Student',
              icon: Icons.person_add,
              description: 'Register a new student',
              color: AppTheme.primaryBlue,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddStudentScreen()),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildCreateCard(
              title: 'Create Batch',
              icon: Icons.group_add,
              description: 'Open batch management to add time slots',
              color: AppTheme.accentOrange,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BatchManagementScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildCreateCard(
              title: 'Generate Report',
              icon: Icons.description,
              description: 'Create attendance report',
              color: AppTheme.accentGreen,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AttendanceReportsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateCard({
    required String title,
    required IconData icon,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
