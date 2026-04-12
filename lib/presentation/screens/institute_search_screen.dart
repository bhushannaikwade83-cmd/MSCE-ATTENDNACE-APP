import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/app_db.dart';
import '../../core/supabase_maps.dart';
import '../../core/utils/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/shimmer_effect.dart';
import '../widgets/enhanced_animations.dart';
import 'institute_registration_screen.dart';

class InstituteSearchScreen extends StatefulWidget {
  static const routeName = '/institute-search';
  const InstituteSearchScreen({super.key});

  @override
  State<InstituteSearchScreen> createState() => _InstituteSearchScreenState();
}

class _InstituteSearchScreenState extends State<InstituteSearchScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPredefinedInstitutes();
  }

  // Load all institutes from database
  Future<void> _loadPredefinedInstitutes() async {
    setState(() => _isLoading = true);
    
    try {
      final rows = await appDb.from('institutes').select().limit(100);
      _updateSearchResultsFromRows(rows);
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading institutes: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading institutes: ${e.toString()}'),
            backgroundColor: AppTheme.accentRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  void _updateSearchResultsFromRows(List<Map<String, dynamic>> rows) {
    setState(() {
      _searchResults = rows.map((row) {
        final m = instituteRowToMap(row);
        return {
          ...m,
          'id': row['id'],
          'instituteId': m['instituteId'],
          'instituteCode': m['instituteCode'],
          'name': m['name'] ?? 'Unknown',
          'location': m['location'] ?? '',
          'city': m['city'] ?? '',
          'state': m['state'] ?? '',
          'address': m['address'],
          'district': m['district'],
          'taluka': m['taluka'],
          'mobileNo': m['mobileNo'],
        };
      }).toList();
      _isLoading = false;
    });
  }

  Future<void> _searchInstitutes(String query) async {
    if (query.isEmpty) {
      _loadPredefinedInstitutes();
      return;
    }

    setState(() => _isSearching = true);

    try {
      final rows = await appDb.from('institutes').select().ilike('name', '%$query%').limit(50);
      _updateSearchResultsFromRows(rows);
      setState(() => _isSearching = false);
    } catch (e) {
      if (kDebugMode) debugPrint('Error searching institutes: $e');
      // Fallback: search in loaded results
      setState(() {
        _searchResults = _searchResults.where((institute) {
          final name = (institute['name'] ?? '').toString().toLowerCase();
          final location = (institute['location'] ?? '').toString().toLowerCase();
          final queryLower = query.toLowerCase();
          return name.contains(queryLower) || location.contains(queryLower);
        }).toList();
        _isSearching = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
      appBar: AppBar(
        title: const Text(
          'Find Your Institute',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            Container(
              padding: const EdgeInsets.all(16),
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search institute name or location...',
                  prefixIcon: const Icon(Icons.search, color: AppTheme.primaryBlue),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _loadPredefinedInstitutes();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
                  ),
                  filled: true,
                  fillColor: AppTheme.backgroundGrey,
                ),
                onChanged: _searchInstitutes,
              ),
            ),

            // Results List
            Expanded(
              child: _isLoading
                  ? ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: 3,
                      itemBuilder: (context, index) {
                        return ShimmerCard()
                            .stagger(index: index);
                      },
                    )
                  : _searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.school_outlined,
                                size: 80,
                                color: isDark ? Colors.white.withOpacity(0.3) : Colors.grey.shade300,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _isSearching
                                    ? 'Searching...'
                                    : 'No institutes found',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : AppTheme.textDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Try searching with a different keyword',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.white70 : AppTheme.textGray,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final institute = _searchResults[index];
                            return _buildInstituteCard(institute);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstituteCard(Map<String, dynamic> institute) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InstituteRegistrationScreen(
                  instituteId: institute['instituteId'] ?? institute['id'],
                  instituteName: institute['name'] ?? 'Unknown',
                  instituteLocation: institute['location'] ?? '',
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: AppTheme.primaryBlue,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              institute['name'] ?? 'Unknown Institute',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : AppTheme.textDark,
                              ),
                            ),
                          ),
                          if (institute['instituteCode'] != null && institute['instituteCode'].toString().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
                              ),
                              child: Text(
                                'Code: ${institute['instituteCode']}',
                                style: const TextStyle(
                                  color: AppTheme.primaryBlue,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: isDark ? Colors.white70 : AppTheme.textGray,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              institute['address'] ?? institute['location'] ?? 'Address not specified',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark ? Colors.white70 : AppTheme.textGray,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (institute['city'] != null || institute['district'] != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (institute['city'] != null) ...[
                              Text(
                                institute['city'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : AppTheme.textGray,
                                ),
                              ),
                            ],
                            if (institute['district'] != null && institute['district'] != institute['city']) ...[
                              if (institute['city'] != null) Text(', ', style: TextStyle(color: isDark ? Colors.white70 : AppTheme.textGray)),
                              Text(
                                institute['district'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : AppTheme.textGray,
                                ),
                              ),
                            ],
                            if (institute['taluka'] != null) ...[
                              if (institute['district'] != null || institute['city'] != null) 
                                Text(', ', style: TextStyle(color: isDark ? Colors.white70 : AppTheme.textGray)),
                              Text(
                                'Taluka: ${institute['taluka']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : AppTheme.textGray,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                            if (institute['state'] != null) ...[
                              Text(
                                '${institute['city'] != null || institute['district'] != null ? ', ' : ''}${institute['state']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : AppTheme.textGray,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (institute['mobileNo'] != null && institute['mobileNo'].toString().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.phone_outlined,
                              size: 14,
                              color: isDark ? Colors.white70 : AppTheme.textGray,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              institute['mobileNo'],
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : AppTheme.textGray,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios,
                    color: AppTheme.primaryBlue,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
