// R1 shop categories — the `business_type` values in the database
// (migrations 0001, 0047 and 0066). Keep in step with the app's
// lib/core/business_category.dart.
export const BUSINESS_TYPES = [
  { value: "grocery", label: "Grocery / kirana store" },
  { value: "stationery", label: "Stationery & gift shop" },
  { value: "cosmetics", label: "Cosmetics & general store" },
  { value: "mobile", label: "Mobile shop" },
  { value: "mobile_repair", label: "Mobile repair" },
  { value: "garment", label: "Garment shop" },
  { value: "hardware", label: "Hardware shop" },
  { value: "electrical", label: "Electrical shop" },
  { value: "car_workshop", label: "Car workshop" },
  { value: "bike_garage", label: "Bike garage" },
  { value: "other", label: "Other" },
] as const;

export function businessTypeLabel(value: string | null | undefined): string {
  return BUSINESS_TYPES.find((t) => t.value === value)?.label ?? "Other";
}
