import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_db.dart';
import '../../core/utils/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../services/geofence_service.dart';

class GpsSettingsScreen extends StatefulWidget {
  static const routeName = '/gps-settings';
  const GpsSettingsScreen({super.key});

  @override
  State<GpsSettingsScreen> createState() => _GpsSettingsScreenState();
}

class _GpsSettingsScreenState extends State<GpsSettingsScreen> {
  User? get _currentUser => appDb.auth.currentUser;
  bool _isAdmin = false;
  bool _isCheckingRole = true;
  String? _instituteId; // Store user's institute ID
  final _formKey = GlobalKey<FormState>();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _radiusController = TextEditingController(text: "30"); // Fixed default 30m
  final GeofenceService _geofenceService = GeofenceService();
  bool _isLoading = false;
  bool _isLocked = false; // Track if location is locked (after lat/lng are set)
  bool _hasLocation = false; // Track if location coordinates exist

  @override
  void initState() {
    super.initState();
    _loadUserInstituteId();
  }

  Future<void> _loadUserInstituteId() async {
    final u = _currentUser;
    if (u == null) {
      setState(() {
        _isCheckingRole = false;
        _isAdmin = false;
      });
      return;
    }

    try {
      final row = await appDb.from('profiles').select('institute_id,role').eq('id', u.id).maybeSingle();
      if (row == null) {
        setState(() {
          _isCheckingRole = false;
          _isAdmin = false;
        });
        return;
      }
      _instituteId = row['institute_id'] as String?;
      final role = (row['role'] as String?) ?? '';
      setState(() {
        _isAdmin = role == 'admin';
        _isCheckingRole = false;
      });
      if (_isAdmin && _instituteId != null) {
        _loadCurrentSettings();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error checking role: $e');
      setState(() {
        _isCheckingRole = false;
        _isAdmin = false;
      });
    }
  }

  Future<void> _loadCurrentSettings() async {
    setState(() => _isLoading = true);
    try {
      final cu = _currentUser;
      if (_instituteId != null && cu != null) {
        final row = await appDb
            .from('gps_settings')
            .select()
            .eq('institute_id', _instituteId!)
            .eq('admin_id', cu.id)
            .maybeSingle();

        if (row != null) {
          final lat = row['latitude'];
          final lng = row['longitude'];
          _hasLocation = lat != null &&
              lng != null &&
              lat.toString().isNotEmpty &&
              lng.toString().isNotEmpty &&
              (lat as num) != 0.0 &&
              (lng as num) != 0.0;
          if (_hasLocation) {
            _latController.text = lat.toString();
            _lngController.text = lng.toString();
            _isLocked = row['is_locked'] == true;
          } else {
            _isLocked = false;
          }
          _radiusController.text = '30';
          final currentRadius = (row['radius'] as num?)?.toDouble() ?? 0.0;
          if (currentRadius >= 24.9 && currentRadius <= 25.1) {
            await appDb
                .from('gps_settings')
                .update({
                  'radius': 30.0,
                  'extra': {'radiusMigrated_at': DateTime.now().toUtc().toIso8601String(), 'from': 25.0},
                })
                .eq('institute_id', _instituteId!)
                .eq('admin_id', cu.id);
          }
        } else {
          _radiusController.text = '30';
          _hasLocation = false;
          _isLocked = false;
        }
      } else {
        _radiusController.text = '30';
        _hasLocation = false;
        _isLocked = false;
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 2. Get Current Location (Auto-fill)
  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        _latController.text = position.latitude.toString();
        _lngController.text = position.longitude.toString();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Text("Location fetched successfully!"),
                ],
              ),
              backgroundColor: AppTheme.accentGreen,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Text("Location permission denied"),
                ],
              ),
              backgroundColor: AppTheme.accentRed,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 3. Save Settings to Firestore
  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_instituteId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Text("Error: Institute ID not found. Please login again."),
              ],
            ),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Save to admin-specific GPS settings (each admin has their own geo-fencing)
      if (_currentUser == null) {
        throw 'User not authenticated';
      }
      
      final cu = _currentUser;
      if (cu == null) throw 'User not authenticated';
      final existingRow = await appDb
          .from('gps_settings')
          .select()
          .eq('institute_id', _instituteId!)
          .eq('admin_id', cu.id)
          .maybeSingle();

      final existingData = existingRow;
      final existingLat = existingData?['latitude'];
      final existingLng = existingData?['longitude'];
      final hasExistingLocation = existingLat != null &&
          existingLng != null &&
          (existingLat as num) != 0.0 &&
          (existingLng as num) != 0.0;
      final isLocationLocked = existingData != null && hasExistingLocation && (existingData['is_locked'] == true);
      
      // If location is already set and locked, cannot change
      if (isLocationLocked) {
        throw 'Location is locked. Contact super admin to unlock for changes.';
      }

      // Radius is ALWAYS fixed at 30M - never changeable
      // Force radius to 30M regardless of what user entered
      final radiusToSave = 30.0;

      final ts = DateTime.now().toUtc().toIso8601String();
      final cu2 = _currentUser!;
      await appDb.from('gps_settings').upsert({
        'institute_id': _instituteId,
        'admin_id': cu2.id,
        'latitude': double.parse(_latController.text),
        'longitude': double.parse(_lngController.text),
        'radius': radiusToSave,
        'is_locked': true,
        'locked_at': ts,
        'locked_by': cu2.id,
        'extra': {'updated_at': ts},
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text("GPS Settings Saved!"),
              ],
            ),
            backgroundColor: AppTheme.accentGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        // Keep user on this screen after save; auto-pop can exit to unrelated routes
        // (e.g. institute search) when GPS settings is hosted inside navigation tabs.
        setState(() {
          _hasLocation = true;
          _isLocked = true; // Lock location after saving
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error saving: $e"),
            backgroundColor: AppTheme.accentRed,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingRole) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundGrey,
        body: const SafeArea(
          top: false,
          child: Center(
            child: CircularProgressIndicator(color: AppTheme.primaryBlue),
          ),
        ),
      );
    }

    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        // Pop already happened if didPop is true, no action needed
        // If didPop is false, pop was prevented (no previous route), also no action needed
      },
      child: Scaffold(
        backgroundColor: AppTheme.backgroundGrey,
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Info Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.info_outline, color: AppTheme.primaryBlue, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            "Set your personal attendance zone. Each admin has their own geo-fencing settings. You can only mark attendance within your configured radius.",
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: AppTheme.textGray,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

              // Radius Lock Banner (Always shown - radius is always locked)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.blue, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock, color: Colors.blue, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Radius Fixed at 30M",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Radius is permanently fixed at 30 meters for all institutes and cannot be changed.",
                            style: TextStyle(
                              color: Colors.blue.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Location Lock Banner (Only shown if location is set and locked)
              if (_isLocked)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.orange, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock, color: Colors.orange, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Location Locked",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Location coordinates are locked after being set. Contact super admin to unlock for changes.",
                              style: TextStyle(
                                color: Colors.orange.withValues(alpha: 0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (_isLocked) const SizedBox(height: 24),

              Text(
                "School Coordinates",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Latitude",
                        prefixIcon: Icon(Icons.map_outlined),
                      ),
                      validator: (v) => v!.isEmpty ? "Required" : null,
                      enabled: !_isLocked,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lngController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Longitude",
                        prefixIcon: Icon(Icons.map_outlined),
                      ),
                      validator: (v) => v!.isEmpty ? "Required" : null,
                      enabled: !_isLocked,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_isLoading || _isLocked) ? null : _getCurrentLocation,
                  icon: const Icon(Icons.my_location),
                  label: const Text("Use Current Location"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: AppTheme.primaryBlue),
                    foregroundColor: AppTheme.primaryBlue,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              Text(
                "Allowed Radius",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _radiusController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Radius in Meters",
                  prefixIcon: const Icon(Icons.radar_outlined),
                  helperText: "Radius is ALWAYS fixed at 30M for all admins. Cannot be changed, even by super admin.",
                  helperMaxLines: 2,
                ),
                validator: (v) {
                  // Always validate as 30.0 - no other value allowed
                  if (v!.isEmpty) return "Required";
                  final radius = double.tryParse(v);
                  if (radius == null) return "Invalid number";
                  if (radius != 30.0) {
                    return "Radius must be exactly 30M. This is a system-wide constant.";
                  }
                  return null;
                },
                enabled: false, // ALWAYS disabled - radius never changes
                readOnly: true, // ALWAYS read-only - radius is fixed at 30m
              ),

              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_isLoading || _isLocked) ? null : _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isLocked ? Colors.grey : AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading 
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isLocked ? "Location Locked" : "Save Configuration",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
        ),
      ),
    );
  }
}
