import { apiFetchRaw } from "@/lib/api-client";

/**
 * Downloads a binary file from a backend path (e.g. a generated PDF) and triggers
 * a browser save dialog. Routes through the authenticated proxy via apiFetchRaw so
 * the access token is never exposed to client JavaScript.
 *
 * Throws on failure — callers own the loading/toast UX.
 */
export async function downloadFileFromApi(
  path: string,
  filename: string
): Promise<void> {
  const response = await apiFetchRaw(path);
  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  try {
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = filename;
    anchor.click();
  } finally {
    URL.revokeObjectURL(url);
  }
}
