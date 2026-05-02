import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import '../../core/app_db.dart';
import '../../core/supabase_maps.dart';
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

  /// Short SnackBar text for common failures; full error still logged in debug.
  String _messageForInstitutesLoadError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('failed host lookup') ||
        s.contains('socketexception') ||
        s.contains('no address associated with hostname') ||
        s.contains('network is unreachable')) {
      return "Can't reach the server. Check internet, try another network, or turn off VPN/private DNS blocking.";
    }
    if (s.contains('timed out') || s.contains('timeout')) {
      return 'Connection timed out. Try again with a stronger signal.';
    }
    return 'Error loading institutes: $e';
  }

  @override
  void initState() {
    super.initState();
    _loadPredefinedInstitutes();
  }

  // Load all institutes from database (sorted by ID ascending)
  Future<void> _loadPredefinedInstitutes() async {
    setState(() => _isLoading = true);

    try {
      final rows = await appDb
          .from('institutes')
          .select()
          .order('id', ascending: true)
          .limit(100);
      _updateSearchResultsFromRows(rows);
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading institutes: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_messageForInstitutesLoadError(e)),
            backgroundColor: AppTheme.accentRed,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Safe fragment for PostgREST `ilike` patterns (avoid breaking `.or(...)`).
  static String _sanitizeIlikeFragment(String q) {
    var s = q.trim().replaceAll(',', ' ');
    s = s.replaceAll('%', '').replaceAll('_', '');
    return s.trim();
  }

  /// Columns searched for institute discovery (code, numeric id, name, address).
  static String _orIlikeClause(String pattern) {
    return [
      'name.ilike.$pattern',
      'institute_code.ilike.$pattern',
      'id.ilike.$pattern',
      'location.ilike.$pattern',
      'address.ilike.$pattern',
      'city.ilike.$pattern',
      'district.ilike.$pattern',
      'taluka.ilike.$pattern',
      'state.ilike.$pattern',
    ].join(',');
  }

  Future<List<Map<String, dynamic>>> _queryInstitutesIlike({
    required String pattern,
    int limit = 100,
  }) async {
    final raw = await appDb
        .from('institutes')
        .select()
        .or(_orIlikeClause(pattern))
        .order('id', ascending: true)
        .limit(limit);
    final list = raw as List;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Every token must appear somewhere on the row (any column), case-insensitive.
  static bool _rowMatchesAllTokens(
    Map<String, dynamic> row,
    List<String> tokens,
  ) {
    final blob = [
      row['name'],
      row['institute_code'],
      row['id'],
      row['location'],
      row['address'],
      row['city'],
      row['district'],
      row['taluka'],
      row['state'],
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
    for (final t in tokens) {
      final tl = t.toLowerCase();
      if (tl.isEmpty) continue;
      if (!blob.contains(tl)) return false;
    }
    return true;
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

      // Sort by institute ID in ascending order
      _searchResults.sort((a, b) {
        final idA = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
        final idB = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
        return idA.compareTo(idB);
      });

      _isLoading = false;
    });
  }

  Future<void> _searchInstitutes(String query) async {
    final safe = _sanitizeIlikeFragment(query);
    if (safe.isEmpty) {
      _loadPredefinedInstitutes();
      return;
    }

    setState(() => _isSearching = true);

    final tokens = safe
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    try {
      final phrasePattern = '%$safe%';
      var rows = await _queryInstitutesIlike(
        pattern: phrasePattern,
        limit: 120,
      );

      if (tokens.length > 1) {
        final filtered = rows
            .where((r) => _rowMatchesAllTokens(r, tokens))
            .toList();
        if (filtered.isNotEmpty) {
          rows = filtered;
        } else {
          final anchor = tokens.reduce((a, b) => a.length >= b.length ? a : b);
          rows = await _queryInstitutesIlike(pattern: '%$anchor%', limit: 280);
          rows = rows.where((r) => _rowMatchesAllTokens(r, tokens)).toList();
        }
      }

      _updateSearchResultsFromRows(rows);
      setState(() => _isSearching = false);
    } catch (e) {
      if (kDebugMode) debugPrint('Error searching institutes: $e');
      final qLower = safe.toLowerCase();
      final tokLower = tokens
          .map((t) => t.toLowerCase())
          .where((t) => t.isNotEmpty)
          .toList();
      setState(() {
        _searchResults = _searchResults.where((institute) {
          final blob = [
            institute['name'],
            institute['instituteCode'],
            institute['instituteId'],
            institute['id'],
            institute['location'],
            institute['address'],
            institute['city'],
            institute['district'],
            institute['taluka'],
            institute['state'],
          ].map((x) => (x ?? '').toString().toLowerCase()).join(' ');
          if (tokLower.length <= 1) {
            return blob.contains(qLower);
          }
          return tokLower.every(blob.contains);
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
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : AppTheme.backgroundGrey,
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
                  hintText: 'Search name, institute code, ID, or location…',
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppTheme.primaryBlue,
                  ),
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
                    borderSide: const BorderSide(
                      color: AppTheme.primaryBlue,
                      width: 2,
                    ),
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
                        return ShimmerCard().stagger(index: index);
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
                            color: isDark
                                ? Colors.white.withOpacity(0.3)
                                : Colors.grey.shade300,
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
                              color: isDark
                                  ? Colors.white70
                                  : AppTheme.textGray,
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

  Future<void> _openInstituteRegistration(
    Map<String, dynamic> institute,
  ) async {
    final instituteId = (institute['instituteId'] ?? institute['id'])
        .toString();
    final instituteCode = institute['instituteCode']?.toString().trim();
    String? inviteId;
    String? fullName;
    String? email;
    String? phone;
    try {
      Future<void> loadInvite(String key) async {
        final rows = await appDb
            .from('admin_invites')
            .select('id, full_name, phone, email')
            .eq('institute_id', key)
            .eq('claimed', false)
            .limit(1);
        final inviteRows = rows as List;
        if (inviteRows.isEmpty) return;
        final row = Map<String, dynamic>.from(inviteRows.first as Map);
        inviteId = row['id']?.toString();
        fullName = row['full_name']?.toString();
        email = row['email']?.toString();
        phone = row['phone']?.toString();
      }

      await loadInvite(instituteId);
      if (inviteId == null &&
          instituteCode != null &&
          instituteCode.isNotEmpty &&
          instituteCode != instituteId) {
        await loadInvite(instituteCode);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Invite lookup: $e');
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InstituteRegistrationScreen(
          instituteId: instituteId,
          instituteName: institute['name'] ?? 'Unknown',
          instituteLocation: institute['location'] ?? '',
          inviteId: inviteId,
          prefilledFullName: fullName,
          prefilledEmail: email,
          prefilledPhone: phone,
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
          onTap: () => _openInstituteRegistration(institute),
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
                                color: isDark
                                    ? Colors.white
                                    : AppTheme.textDark,
                              ),
                            ),
                          ),
                          if (institute['id'] != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppTheme.primaryBlue.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                [
                                  'ID: ${institute['id']}',
                                  if ((institute['instituteCode'] ?? '')
                                      .toString()
                                      .trim()
                                      .isNotEmpty)
                                    'Code: ${institute['instituteCode']}',
                                ].join(' · '),
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
                              institute['address'] ??
                                  institute['location'] ??
                                  'Address not specified',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.white70
                                    : AppTheme.textGray,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (institute['city'] != null ||
                          institute['district'] != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (institute['city'] != null) ...[
                              Text(
                                institute['city'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white70
                                      : AppTheme.textGray,
                                ),
                              ),
                            ],
                            if (institute['district'] != null &&
                                institute['district'] != institute['city']) ...[
                              if (institute['city'] != null)
                                Text(
                                  ', ',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : AppTheme.textGray,
                                  ),
                                ),
                              Text(
                                institute['district'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white70
                                      : AppTheme.textGray,
                                ),
                              ),
                            ],
                            if (institute['taluka'] != null) ...[
                              if (institute['district'] != null ||
                                  institute['city'] != null)
                                Text(
                                  ', ',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : AppTheme.textGray,
                                  ),
                                ),
                              Text(
                                'Taluka: ${institute['taluka']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white70
                                      : AppTheme.textGray,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                            if (institute['state'] != null) ...[
                              Text(
                                '${institute['city'] != null || institute['district'] != null ? ', ' : ''}${institute['state']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white70
                                      : AppTheme.textGray,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (institute['mobileNo'] != null &&
                          institute['mobileNo'].toString().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.phone_outlined,
                              size: 14,
                              color: isDark
                                  ? Colors.white70
                                  : AppTheme.textGray,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              institute['mobileNo'],
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white70
                                    : AppTheme.textGray,
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
