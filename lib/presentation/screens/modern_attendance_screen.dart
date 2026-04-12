import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/utils/responsive.dart';
import '../../core/theme/app_theme.dart';

/// Modern Attendance Check-in Screen - Similar to the reference design
class ModernAttendanceScreen extends StatefulWidget {
  static const routeName = '/modern-attendance';
  const ModernAttendanceScreen({super.key});

  @override
  State<ModernAttendanceScreen> createState() => _ModernAttendanceScreenState();
}

class _ModernAttendanceScreenState extends State<ModernAttendanceScreen> {
  String? _currentLocation;
  bool _isLoadingLocation = true;
  String _selectedMode = 'Office'; // Home or Office
  String? _checkInTime;
  String? _checkOutTime;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      setState(() => _isLoadingLocation = true);
      final position = await Geolocator.getCurrentPosition();
      final address = await _getAddressFromLatLng(position.latitude, position.longitude);
      setState(() {
        _currentLocation = address;
        _isLoadingLocation = false;
      });
    } catch (e) {
      setState(() {
        _currentLocation = 'Location not available';
        _isLoadingLocation = false;
      });
    }
  }

  Future<String> _getAddressFromLatLng(double lat, double lng) async {
    // Simplified - in production, use geocoding service
    return '148 Rd No 12C Gulshan Dhaka-1234';
  }

  void _handleCheckIn() {
    setState(() {
      _checkInTime = DateFormat('hh:mm a').format(DateTime.now());
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Check-in successful!'),
          ],
        ),
        backgroundColor: AppTheme.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentTime = DateFormat('hh:mm a').format(now);
    final currentDate = DateFormat('EEEE, MMMM-dd, yyyy').format(now);

    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Attendance',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.description, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Location Section
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: AppTheme.accentRed, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isLoadingLocation ? 'Loading location...' : (_currentLocation ?? 'Location not available'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _getCurrentLocation,
                    child: const Text(
                      'Auto Fit',
                      style: TextStyle(color: AppTheme.primaryBlue),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Time and Date Display
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentTime,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currentDate,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Check-in Circle
            Center(
              child: GestureDetector(
                onTap: _handleCheckIn,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primaryBlue,
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.fingerprint,
                        size: 80,
                        color: AppTheme.primaryBlue,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Check in',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // Remote Mode Selection
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose your remote mode',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildModeButton(
                          'Home',
                          Icons.home,
                          _selectedMode == 'Home',
                          () => setState(() => _selectedMode = 'Home'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildModeButton(
                          'Office',
                          Icons.business,
                          _selectedMode == 'Office',
                          () => setState(() => _selectedMode = 'Office'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Clock In/Out Times
            Container(
              width: double.infinity,
              color: AppTheme.primaryBlue,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.access_time, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _checkInTime ?? '10:30 PM',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, color: Colors.white),
                    ],
                  ),
                  Row(
                    children: [
                      const Text(
                        'Out time',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, color: Colors.white),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(2), // Search icon selected
    );
  }

  Widget _buildModeButton(String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryBlue : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : AppTheme.primaryBlue,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppTheme.primaryBlue,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(int selectedIndex) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home, selectedIndex == 0),
              _buildNavItem(Icons.help_outline, selectedIndex == 1),
              _buildNavItem(Icons.search, selectedIndex == 2, isLarge: true),
              _buildNavItem(Icons.notifications_outlined, selectedIndex == 3),
              _buildNavItem(Icons.person_outline, selectedIndex == 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isSelected, {bool isLarge = false}) {
    return Container(
      width: isLarge ? 50 : 40,
      height: isLarge ? 50 : 40,
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryBlue.withOpacity(0.1) : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: isSelected ? AppTheme.primaryBlue : Colors.grey.shade600,
        size: isLarge ? 28 : 24,
      ),
    );
  }
}
