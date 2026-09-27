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

const businessCategories = <BusinessCategory>[
  BusinessCategory(
    key: 'mobile',
    label: 'Mobile shop',
    description: 'Phones and accessories, IMEI tracking',
    icon: Icons.smartphone,
    jobCards: true,
    variantFields: ['Model', 'RAM', 'Storage', 'Color'],
  ),
  BusinessCategory(
    key: 'mobile_repair',
    label: 'Mobile repair',
    description: 'Job cards, estimates, spares',
    icon: Icons.phonelink_setup,
    jobCards: true,
    variantFields: ['Model', 'Color'],
  ),
  BusinessCategory(
    key: 'garment',
    label: 'Garment shop',
    description: 'Sizes, colours, designs',
    icon: Icons.checkroom,
    variantFields: ['Size', 'Color', 'Fabric', 'Gender', 'Design'],
  ),
  BusinessCategory(
    key: 'hardware',
    label: 'Hardware shop',
    description: 'Bulk pricing, cut lengths',
    icon: Icons.hardware,
    bulkPricing: true,
    variantFields: ['Size/Weight', 'Material', 'Grade'],
  ),
  BusinessCategory(
    key: 'electrical',
    label: 'Electrical shop',
    description: 'Wires by the metre, installation jobs',
    icon: Icons.electrical_services,
    jobCards: true,
    bulkPricing: true,
    variantFields: ['Size/Rating', 'Material', 'Color'],
  ),
  BusinessCategory(
    key: 'car_workshop',
    label: 'Car workshop',
    description: 'Vehicle job cards, estimates, parts',
    icon: Icons.directions_car,
    jobCards: true,
    vehicleJobs: true,
    variantFields: ['Vehicle model', 'Brand'],
  ),
  BusinessCategory(
    key: 'bike_garage',
    label: 'Bike garage',
    description: 'Vehicle job cards, estimates, parts',
    icon: Icons.two_wheeler,
    jobCards: true,
    vehicleJobs: true,
    variantFields: ['Vehicle model', 'Brand'],
  ),
  BusinessCategory(
    key: 'other',
    label: 'Other',
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
