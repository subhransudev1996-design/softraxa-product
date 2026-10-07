import 'i18n.dart';
import 'package:flutter/material.dart';

/// R1 shop categories (LAUNCH_SPECIFICATION D01, D03, D06). The key is the
/// `business_type` value in the database. The category picks which
/// modules and product fields the app shows; the database sets the
/// matching defaults when setup finishes (migration 0047).
class BusinessCategory {
  const BusinessCategory({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    this.jobCards = false,
    this.vehicleJobs = false,
    this.bulkPricing = false,
    this.variantFields = const ['Option'],
  });

  final String key;
  final String label;
  final String description;
  final IconData icon;

  /// Services and job cards in the menus.
  final bool jobCards;

  /// New job cards default to a vehicle (registration, odometer, fuel).
  final bool vehicleJobs;

  /// Wholesale price with a minimum quantity on the product form.
  final bool bulkPricing;

  /// Attribute names suggested for product variants.
  final List<String> variantFields;
}

// A getter, not a const: labels are translated (t()) when read.
List<BusinessCategory> get businessCategories => [
  BusinessCategory(
    key: 'grocery',
    label: t('Grocery / kirana store'),
    description: 'Packed foods, loose items by weight, daily needs',
    icon: Icons.local_grocery_store,
    variantFields: ['Size/Weight', 'Flavour', 'Brand'],
  ),
  BusinessCategory(
    key: 'stationery',
    label: t('Stationery & gift shop'),
    description: 'Books, pens, school and office supplies, gifts',
    icon: Icons.edit_note,
    variantFields: ['Size', 'Color', 'Brand'],
  ),
  BusinessCategory(
    key: 'cosmetics',
    label: t('Cosmetics & general store'),
    description: 'Beauty, personal care, daily-use items',
    icon: Icons.spa,
    variantFields: ['Shade', 'Size/Weight', 'Brand'],
  ),
  BusinessCategory(
    key: 'mobile',
    label: t('Mobile shop'),
    description: 'Phones and accessories, IMEI tracking',
    icon: Icons.smartphone,
    jobCards: true,
    variantFields: ['Model', 'RAM', 'Storage', 'Color'],
  ),
  BusinessCategory(
    key: 'mobile_repair',
    label: t('Mobile repair'),
    description: 'Job cards, estimates, spares',
    icon: Icons.phonelink_setup,
    jobCards: true,
    variantFields: ['Model', 'Color'],
  ),
  BusinessCategory(
    key: 'garment',
    label: t('Garment shop'),
    description: 'Sizes, colours, designs',
    icon: Icons.checkroom,
    variantFields: ['Size', 'Color', 'Fabric', 'Gender', 'Design'],
  ),
  BusinessCategory(
    key: 'hardware',
    label: t('Hardware shop'),
    description: 'Bulk pricing, cut lengths',
    icon: Icons.hardware,
    bulkPricing: true,
    variantFields: ['Size/Weight', 'Material', 'Grade'],
  ),
  BusinessCategory(
    key: 'electrical',
    label: t('Electrical shop'),
    description: 'Wires by the metre, installation jobs',
    icon: Icons.electrical_services,
    jobCards: true,
    bulkPricing: true,
    variantFields: ['Size/Rating', 'Material', 'Color'],
  ),
  BusinessCategory(
    key: 'car_workshop',
    label: t('Car workshop'),
    description: 'Vehicle job cards, estimates, parts',
    icon: Icons.directions_car,
    jobCards: true,
    vehicleJobs: true,
    variantFields: ['Vehicle model', 'Brand'],
  ),
  BusinessCategory(
    key: 'bike_garage',
    label: t('Bike garage'),
    description: 'Vehicle job cards, estimates, parts',
    icon: Icons.two_wheeler,
    jobCards: true,
    vehicleJobs: true,
    variantFields: ['Vehicle model', 'Brand'],
  ),
  BusinessCategory(
    key: 'other',
    label: t('Other'),
    description: 'Everything switched on',
    icon: Icons.storefront,
    jobCards: true,
    bulkPricing: true,
  ),
];

BusinessCategory categoryOf(String? key) => businessCategories.firstWhere(
  (c) => c.key == key,
  orElse: () => businessCategories.last,
);
