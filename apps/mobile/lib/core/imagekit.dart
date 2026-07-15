import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// ImageKit media uploads (logos etc.).
///
/// The public key is safe to embed; the signature comes from the
/// `get_imagekit_auth` RPC so the private key stays server-side.
const _imageKitPublicKey = 'public_P11hw/x56/P9U8POVr73zeODHgU=';
const _imageKitUploadUrl = 'https://upload.imagekit.io/api/v1/files/upload';

Future<String> uploadToImageKit(
  SupabaseClient client,
  File file, {
  required String fileName,
  String folder = '/',
}) async {
  final auth = await client.rpc('get_imagekit_auth') as Map<String, dynamic>;

  final request = http.MultipartRequest('POST', Uri.parse(_imageKitUploadUrl))
    ..fields['publicKey'] = _imageKitPublicKey
    ..fields['token'] = auth['token'] as String
    ..fields['expire'] = auth['expire'].toString()
    ..fields['signature'] = auth['signature'] as String
    ..fields['fileName'] = fileName
    ..fields['folder'] = folder
    ..fields['useUniqueFileName'] = 'true'
    ..files.add(await http.MultipartFile.fromPath('file', file.path));

  final response = await request.send();
  final body = await response.stream.bytesToString();
  if (response.statusCode >= 300) {
    throw Exception('Image upload failed (${response.statusCode}): $body');
  }
  return (jsonDecode(body) as Map<String, dynamic>)['url'] as String;
}
