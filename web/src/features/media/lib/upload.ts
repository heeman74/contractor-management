import { apiUpload } from "@/lib/api-client";
import type { PendingAttachment } from "../types";

interface ImageUploadResponse {
  remote_url: string;
}

/**
 * Upload staged media through the generic image endpoint and return the
 * resulting servable URLs — for surfaces that store bare photo URL lists
 * (e.g. foreman status updates).
 */
export async function uploadPendingAsUrls(items: PendingAttachment[]): Promise<string[]> {
  const urls: string[] = [];
  for (const item of items) {
    const form = new FormData();
    form.append("file", item.file);
    const res = await apiUpload<ImageUploadResponse>("/api/v1/files/images", form);
    urls.push(res.remote_url);
  }
  return urls;
}
