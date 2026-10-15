import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:softraxa_inventory/core/imagekit.dart';
import 'package:softraxa_inventory/features/products/product_photo.dart';

Uint8List _photo(int w, int h, {int orientation = 1}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(200, 120, 40));
  image.exif.imageIfd.orientation = orientation;
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

void main() {
  test('a big camera photo is shrunk to 1000 px on its longest side', () {
    final out = img.decodeJpg(shrinkProductPhoto(_photo(4000, 3000)))!;
    expect(out.width, productPhotoMaxSide);
    expect(out.height, 750);
  });

  test('a tall photo keeps its shape', () {
    final out = img.decodeJpg(shrinkProductPhoto(_photo(1500, 3000)))!;
    expect(out.height, productPhotoMaxSide);
    expect(out.width, 500);
  });

  test('a small photo is not enlarged', () {
    final out = img.decodeJpg(shrinkProductPhoto(_photo(600, 400)))!;
    expect([out.width, out.height], [600, 400]);
  });

  test('a phone photo taken sideways is turned upright', () {
    // EXIF 6 = the camera was turned 90°: stored 2000x1000, shown 1000x2000.
    final out = img.decodeJpg(
      shrinkProductPhoto(_photo(2000, 1000, orientation: 6)),
    )!;
    expect(out.height > out.width, isTrue);
  });

  test('something that is not a photo is refused', () {
    expect(
      () => shrinkProductPhoto(Uint8List.fromList([1, 2, 3, 4])),
      throwsA('That file is not a photo'),
    );
  });

  test('lists ask ImageKit for a small copy; other addresses unchanged', () {
    expect(
      imageThumb('https://ik.imagekit.io/abc/products/x.jpg', 120),
      'https://ik.imagekit.io/abc/products/x.jpg?tr=w-120%2Ch-120%2Cc-at_max',
    );
    expect(
      imageThumb('https://example.com/x.jpg', 120),
      'https://example.com/x.jpg',
    );
  });
}
