// ImageKit uploads from the admin panel (master product photos).
// Same account as the app (apps/mobile/lib/core/imagekit.dart): the public
// key is safe here; the signature comes from get_imagekit_auth, which signs
// with the private key kept in Supabase Vault.
import type { SupabaseClient } from "@supabase/supabase-js";

const PUBLIC_KEY = "public_K4Zyxo+kyiJX3YM2MZC3jvIuPyE=";
const UPLOAD_URL = "https://upload.imagekit.io/api/v1/files/upload";

/** Longest side of a stored product photo (same as the app). */
export const PHOTO_MAX_SIDE = 1000;

/** Shrinks a picture to a JPEG of at most PHOTO_MAX_SIDE px, upright. */
export async function shrinkPhoto(file: File): Promise<Blob> {
  let bitmap: ImageBitmap;
  try {
    bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
  } catch {
    throw new Error("That file is not a photo");
  }
  const scale = Math.min(1, PHOTO_MAX_SIDE / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  const ctx = canvas.getContext("2d")!;
  // White behind see-through PNGs, which JPEG can't keep.
  ctx.fillStyle = "#fff";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  return new Promise((resolve, reject) =>
    canvas.toBlob((b) => (b ? resolve(b) : reject(new Error("Could not prepare the photo"))), "image/jpeg", 0.8),
  );
}

/** Uploads to ImageKit and returns the photo's address. */
export async function uploadToImageKit(
  supabase: SupabaseClient,
  blob: Blob,
  fileName: string,
  folder: string,
): Promise<string> {
  const { data: auth, error } = await supabase.rpc("get_imagekit_auth");
  if (error) throw new Error(error.message);
  const form = new FormData();
  form.append("file", blob, fileName);
  form.append("fileName", fileName);
  form.append("folder", folder);
  form.append("useUniqueFileName", "true");
  form.append("publicKey", PUBLIC_KEY);
  form.append("token", auth.token);
  form.append("expire", String(auth.expire));
  form.append("signature", auth.signature);
  const res = await fetch(UPLOAD_URL, { method: "POST", body: form });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`Photo upload failed: ${body.message ?? res.status}`);
  return body.url as string;
}

/** A small copy for lists, resized by ImageKit. Other addresses unchanged. */
export function imageThumb(url: string, size: number): string {
  try {
    const u = new URL(url);
    if (u.host !== "ik.imagekit.io") return url;
    u.searchParams.set("tr", `w-${size},h-${size},c-at_max`);
    return u.toString();
  } catch {
    return url;
  }
}
