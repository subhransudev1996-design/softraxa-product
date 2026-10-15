import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/i18n.dart';
import '../../core/imagekit.dart';
import '../../core/platform.dart';
import '../../core/theme.dart';

/// Longest side of a stored product photo. Enough for the detail screen;
/// lists ask ImageKit for a smaller copy (imageThumb).
const productPhotoMaxSide = 1000;

/// A camera photo (3-5 MB) shrunk to a ~80 KB JPEG, turned the right way
/// up. Throws if [bytes] is not an image.
Uint8List shrinkProductPhoto(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    // Broken or unknown files can throw instead of returning null.
  }
  if (decoded == null) throw 'That file is not a photo';
  var photo = img.bakeOrientation(decoded);
  final longest = photo.width > photo.height ? photo.width : photo.height;
  if (longest > productPhotoMaxSide) {
    photo = photo.width >= photo.height
        ? img.copyResize(photo, width: productPhotoMaxSide)
        : img.copyResize(photo, height: productPhotoMaxSide);
  }
  return Uint8List.fromList(img.encodeJpg(photo, quality: 78));
}

/// Asks camera or gallery (phones; the PC opens a file picker), then
/// shrinks the photo. Null when nothing was picked.
Future<Uint8List?> pickProductPhoto(BuildContext context) async {
  var source = ImageSource.gallery;
  if (!isDesktopPlatform) {
    final picked = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(t('Take a photo')),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(t('Choose from gallery')),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return null;
    source = picked;
  }
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 2000,
    imageQuality: 90,
  );
  if (file == null) return null;
  try {
    return await compute(shrinkProductPhoto, await file.readAsBytes());
  } catch (_) {
    // Shrunk in the background, where translations aren't loaded.
    throw t('That file is not a photo');
  }
}

/// Uploads a shrunk photo to the shop's folder; returns its address.
Future<String> uploadProductPhoto(
  SupabaseClient client,
  Uint8List jpeg, {
  required String businessId,
}) => uploadBytesToImageKit(
  client,
  jpeg,
  fileName: '${const Uuid().v4()}.jpg',
  folder: '/products/$businessId',
);

/// The photo box on the product form: the new photo, else the saved (or
/// shared-list) one, else an empty box. Tap to add or change.
class ProductPhotoField extends StatelessWidget {
  const ProductPhotoField({
    super.key,
    required this.url,
    required this.picked,
    required this.onPick,
    required this.onRemove,
    this.fromList = false,
  });

  final String? url;
  final Uint8List? picked;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  /// The photo came with a product from the shared list.
  final bool fromList;

  @override
  Widget build(BuildContext context) {
    final has = picked != null || (url ?? '').isNotEmpty;
    final Widget image = picked != null
        ? Image.memory(picked!, fit: BoxFit.cover)
        : has
        ? CachedNetworkImage(
            key: ValueKey(url),
            imageUrl: imageThumb(url!, 240),
            fit: BoxFit.cover,
            errorWidget: (_, _, _) =>
                Icon(Icons.broken_image_outlined, color: AppColors.inkSoft),
          )
        : const Icon(
            Icons.add_a_photo_outlined,
            color: AppColors.primary,
            size: 30,
          );
    return Row(
      children: [
        InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 96,
            height: 96,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.35),
              ),
              color: AppColors.primary.withValues(alpha: 0.05),
            ),
            child: Center(child: SizedBox.expand(child: image)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('Product photo'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                has
                    ? (fromList && picked == null
                          ? t(
                              'From the product list. Take your own to replace it.',
                            )
                          : t('Shown in your product list and while billing.'))
                    : t(
                        'Optional. Shown in your product list and while billing.',
                      ),
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: onPick,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(has ? t('Change photo') : t('Add photo')),
                  ),
                  if (has)
                    TextButton.icon(
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(t('Remove')),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A product's photo as a small square, or [fallback] when it has none
/// (or it can't be loaded).
class ProductThumb extends StatelessWidget {
  const ProductThumb({
    super.key,
    required this.url,
    required this.size,
    required this.fallback,
  });

  final String? url;
  final double size;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    if ((url ?? '').isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: CachedNetworkImage(
        key: ValueKey(url),
        imageUrl: imageThumb(url!, (size * 3).round()),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}
