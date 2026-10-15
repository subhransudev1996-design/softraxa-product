import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// ImageKit media uploads (logos, product photos).
///
/// The public key is safe to embed; the signature comes from the
/// `get_imagekit_auth` RPC so the private key stays server-side.
const _imageKitPublicKey = 'public_K4Zyxo+kyiJX3YM2MZC3jvIuPyE=';
const _imageKitUploadUrl = 'https://upload.imagekit.io/api/v1/files/upload';

Future<String> uploadToImageKit(
  SupabaseClient client,
  File file, {
  required String fileName,
  String folder = '/',
}) async => _upload(
  client,
  await http.MultipartFile.fromPath('file', file.path),
  fileName: fileName,
  folder: folder,
);

/// Same as [uploadToImageKit], for an image already in memory (a photo
/// shrunk on the device before upload).
Future<String> uploadBytesToImageKit(
  SupabaseClient client,
  List<int> bytes, {
  required String fileName,
  String folder = '/',
}) => _upload(
  client,
  http.MultipartFile.fromBytes('file', bytes, filename: fileName),
  fileName: fileName,
  folder: folder,
);

Future<String> _upload(
  SupabaseClient client,
  http.MultipartFile file, {
  required String fileName,
  required String folder,
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
    ..files.add(file);

  final response = await request.send();
  final body = await response.stream.bytesToString();
  if (response.statusCode >= 300) {
    throw Exception('Image upload failed (${response.statusCode}): $body');
  }
  return (jsonDecode(body) as Map<String, dynamic>)['url'] as String;
}

/// A small version of an ImageKit photo for lists: ImageKit resizes it on
/// its side, so a list downloads ~10 KB per photo instead of the full one.
/// Other addresses are returned unchanged.
String imageThumb(String url, int size) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host != 'ik.imagekit.io') return url;
  return uri
      .replace(
        queryParameters: {
          ...uri.queryParameters,
          'tr': 'w-$size,h-$size,c-at_max',
        },
      )
      .toString();
}
