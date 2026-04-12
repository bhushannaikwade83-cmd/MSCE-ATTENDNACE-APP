// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get portalPrimaryLine => 'MSCE Attendance  |  एमएससीई उपस्थिती';

  @override
  String get portalSecondaryLineDefault =>
      'MSCE Smart Attendance Management System';

  @override
  String get officialBadge => 'OFFICIAL';

  @override
  String get footerOfficialUse => 'OFFICIAL USE ONLY';

  @override
  String get footerCredit => 'Powered by Digitrix Media';

  @override
  String get mainNavSubtitleAdmin => 'Admin dashboard  |  प्रशासक डॅशबोर्ड';

  @override
  String get mainNavSubtitleBatch => 'Batch management  |  तुकडी व्यवस्थापन';

  @override
  String get mainNavSubtitleStudent => 'Student records  |  विद्यार्थी नोंदी';

  @override
  String get mainNavSubtitleGps => 'GPS geofence  |  स्थान सीमा सेटिंग्ज';

  @override
  String get mainNavSubtitleReports => 'Attendance reports  |  उपस्थिती अहवाल';

  @override
  String get splashTitle => 'MSCE Attendance';

  @override
  String get splashSubtitle => 'MSCE Smart Attendance Management System';

  @override
  String get splashCredit => 'Powered by Digitrix Media';

  @override
  String get splashLoading => 'Loading…';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageMarathi => 'मराठी';

  @override
  String get languageToggleHint => 'Language  |  भाषा';

  @override
  String get loginAppTitle => 'MSCE Attendance';

  @override
  String get loginSubtitle => 'MSCE Smart Attendance Management System';

  @override
  String loginCopyright(String year) {
    return '© $year MSCE Attendance. All rights reserved.';
  }

  @override
  String get chipEncrypted => 'Encrypted';

  @override
  String get chipGovtPortal => 'Govt. Portal';

  @override
  String get chipSecure => 'Secure';

  @override
  String get badgeGovtCertified => 'Govt. Certified  |  सरकारी प्रमाणित';

  @override
  String get badgeSslSecured => 'SSL Secured  |  SSL सुरक्षित';

  @override
  String get badgeCertInCompliant => 'CERT-In Compliant  |  CERT-In अनुपालन';
}
