import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_typography.dart';
import 'sa_text_field.dart';

/// Formats a country calling code + national number into E.164
/// (`+<countrycode><number>`, digits only after the leading `+`).
String toE164(String countryCode, String nationalNumber) {
  final digits = nationalNumber.replaceAll(RegExp(r'\D'), '');
  final code = countryCode.startsWith('+') ? countryCode.substring(1) : countryCode;
  return '+$code$digits';
}

/// Phone number entry: a tappable country-code prefix (the caller supplies
/// the picker sheet via [onCountryCodeTap]) plus a digits-only national
/// number field. Exposes E.164 formatting via [toE164].
class SaPhoneField extends StatelessWidget {
  const SaPhoneField({
    required this.countryCode,
    super.key,
    this.controller,
    this.onChanged,
    this.onCountryCodeTap,
    this.errorText,
    this.label = 'Phone number',
  });

  final String countryCode;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onCountryCodeTap;
  final String? errorText;
  final String label;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SaTextField(
      label: label,
      controller: controller,
      onChanged: onChanged,
      errorText: errorText,
      keyboardType: TextInputType.phone,
      semanticsLabel: 'Phone number, country code $countryCode',
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 8, right: 4),
        child: GestureDetector(
          onTap: onCountryCodeTap,
          child: Semantics(
            label: 'Country code $countryCode',
            button: onCountryCodeTap != null,
            child: Align(
              alignment: Alignment.center,
              widthFactor: 1,
              child: Text(countryCode, style: AppTypography.bodyL.copyWith(color: onSurface)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Digits-only input formatter for phone number fields.
final phoneDigitsFormatter = FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-()]'));
