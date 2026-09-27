import 'package:flutter_test/flutter_test.dart';
import 'package:softraxa_inventory/core/business_category.dart';

void main() {
  test('categories match the business_type values in the database', () {
    // 0001 + 0047: the enum the app's keys must stay in step with.
    const dbValues = {
      'mobile',
      'garment',
      'hardware',
      'other',
      'mobile_repair',
      'electrical',
      'car_workshop',
      'bike_garage',
    };
    expect(businessCategories.map((c) => c.key).toSet(), dbValues);
  });

  test('unknown or missing category falls back to Other', () {
    expect(categoryOf(null).key, 'other');
    expect(categoryOf('bakery').key, 'other');
  });

  test(
    'garages default to vehicle jobs; garment and hardware hide job cards',
    () {
      expect(categoryOf('bike_garage').vehicleJobs, isTrue);
      expect(categoryOf('car_workshop').vehicleJobs, isTrue);
      expect(categoryOf('garment').jobCards, isFalse);
      expect(categoryOf('hardware').jobCards, isFalse);
      expect(categoryOf('electrical').bulkPricing, isTrue);
    },
  );
}
