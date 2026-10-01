import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Where account email links (password reset, signup confirmation) land:
/// the website's /auth/callback page, which finishes them in any browser.
/// Null when WEBSITE_URL isn't set in .env: Supabase then uses its Site
/// URL, and the website's home page forwards the link to the same page.
String? get authCallbackUrl {
  final site = (dotenv.env['WEBSITE_URL'] ?? '').trim();
  if (site.isEmpty) return null;
  return '${site.replaceAll(RegExp(r'/+$'), '')}/auth/callback';
}
