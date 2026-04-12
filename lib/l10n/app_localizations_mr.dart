// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Marathi (`mr`).
class AppLocalizationsMr extends AppLocalizations {
  AppLocalizationsMr([String locale = 'mr']) : super(locale);

  @override
  String get portalPrimaryLine => 'एमएससीई उपस्थिती  |  MSCE Attendance';

  @override
  String get portalSecondaryLineDefault =>
      'एमएससीई स्मार्ट उपस्थिती व्यवस्थापन प्रणाली';

  @override
  String get officialBadge => 'अधिकृत';

  @override
  String get footerOfficialUse => 'फक्त अधिकृत वापर';

  @override
  String get footerCredit => 'Digitrix Media तर्फे';

  @override
  String get mainNavSubtitleAdmin => 'प्रशासक डॅशबोर्ड  |  Admin dashboard';

  @override
  String get mainNavSubtitleBatch => 'तुकडी व्यवस्थापन  |  Batch management';

  @override
  String get mainNavSubtitleStudent => 'विद्यार्थी नोंदी  |  Student records';

  @override
  String get mainNavSubtitleGps => 'स्थान सीमा सेटिंग्ज  |  GPS geofence';

  @override
  String get mainNavSubtitleReports => 'उपस्थिती अहवाल  |  Attendance reports';

  @override
  String get splashTitle => 'एमएससीई उपस्थिती';

  @override
  String get splashSubtitle => 'एमएससीई स्मार्ट उपस्थिती व्यवस्थापन प्रणाली';

  @override
  String get splashCredit => 'Digitrix Media तर्फे';

  @override
  String get splashLoading => 'लोड होत आहे…';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageMarathi => 'मराठी';

  @override
  String get languageToggleHint => 'भाषा  |  Language';

  @override
  String get loginAppTitle => 'एमएससीई उपस्थिती';

  @override
  String get loginSubtitle => 'एमएससीई स्मार्ट उपस्थिती व्यवस्थापन प्रणाली';

  @override
  String loginCopyright(String year) {
    return '© $year एमएससीई उपस्थिती. सर्व हक्क राखीव.';
  }

  @override
  String get chipEncrypted => 'एनक्रिप्टेड';

  @override
  String get chipGovtPortal => 'सरकारी पोर्टल';

  @override
  String get chipSecure => 'सुरक्षित';

  @override
  String get badgeGovtCertified => 'सरकारी प्रमाणित  |  Govt. Certified';

  @override
  String get badgeSslSecured => 'SSL सुरक्षित  |  SSL Secured';

  @override
  String get badgeCertInCompliant => 'CERT-In अनुपालन  |  CERT-In Compliant';
}
