import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  const AppLocalizations(this.locale);

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const supportedLocales = [Locale('en'), Locale('hi'), Locale('ta')];

  static AppLocalizations of(BuildContext context) {
    final localizations = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    return localizations ?? const AppLocalizations(Locale('en'));
  }

  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'appName': 'SafeHer',
      'welcomeTitle': 'Your intelligent safety companion',
      'login': 'Login',
      'signup': 'Sign Up',
      'logout': 'Logout',
      'dashboard': 'Dashboard',
      'monitoring': 'Monitoring',
      'incidents': 'Incidents',
      'settings': 'Settings',
      'sos': 'SOS',
      'safe': 'Safe',
      'warning': 'Warning',
      'danger': 'Danger',
      'offline': 'Offline mode enabled',
      'devicePairing': 'Device Pairing',
      'threatMonitoring': 'Threat Monitoring',
      'liveMap': 'Live Tracking Map',
      'analytics': 'Analytics',
      'contacts': 'Emergency Contacts',
      'notifications': 'Notifications',
      'profile': 'Profile',
      'privacyConsent': 'Privacy & Consent',
      'permissionsSetup': 'Permissions Setup',
    },
    'hi': {
      'appName': 'SafeHer',
      'welcomeTitle': 'आपकी स्मार्ट सुरक्षा साथी',
      'login': 'लॉगिन',
      'signup': 'साइन अप',
      'logout': 'लॉगआउट',
      'dashboard': 'डैशबोर्ड',
      'monitoring': 'निगरानी',
      'incidents': 'घटनाएं',
      'settings': 'सेटिंग्स',
      'sos': 'एसओएस',
      'safe': 'सुरक्षित',
      'warning': 'चेतावनी',
      'danger': 'खतरा',
      'offline': 'ऑफलाइन मोड चालू है',
      'devicePairing': 'डिवाइस पेयरिंग',
      'threatMonitoring': 'खतरा निगरानी',
      'liveMap': 'लाइव मैप',
      'analytics': 'एनालिटिक्स',
      'contacts': 'इमरजेंसी कॉन्टैक्ट्स',
      'notifications': 'नोटिफिकेशन्स',
      'profile': 'प्रोफाइल',
      'privacyConsent': 'गोपनीयता और सहमति',
      'permissionsSetup': 'परमिशन सेटअप',
    },
    'ta': {
      'appName': 'SafeHer',
      'welcomeTitle': 'உங்கள் புத்திசாலி பாதுகாப்பு தோழி',
      'login': 'உள்நுழை',
      'signup': 'பதிவு செய்யவும்',
      'logout': 'வெளியேறு',
      'dashboard': 'டாஷ்போர்ட்',
      'monitoring': 'கண்காணிப்பு',
      'incidents': 'சம்பவங்கள்',
      'settings': 'அமைப்புகள்',
      'sos': 'அவசரம்',
      'safe': 'பாதுகாப்பு',
      'warning': 'எச்சரிக்கை',
      'danger': 'ஆபத்து',
      'offline': 'ஆஃப்லைன் பயன்முறை இயக்கப்பட்டது',
      'devicePairing': 'சாதன இணைப்பு',
      'threatMonitoring': 'அபாய கண்காணிப்பு',
      'liveMap': 'நேரடி வரைபடம்',
      'analytics': 'பகுப்பாய்வு',
      'contacts': 'அவசர தொடர்புகள்',
      'notifications': 'அறிவிப்புகள்',
      'profile': 'சுயவிவரம்',
      'privacyConsent': 'தனியுரிமை மற்றும் ஒப்புதல்',
      'permissionsSetup': 'அனுமதி அமைப்பு',
    },
  };

  String t(String key) {
    return _localizedValues[locale.languageCode]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) {
    return false;
  }
}

extension AppLocalizationX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
