import type { AttachmentType } from "@/types/api";

/** A media item staged in the composer, ready to upload. */
export interface PendingAttachment {
  id: string;
  file: File;
  /** Object URL for the thumbnail preview (revoked on remove). */
  previewUrl: string;
  attachmentType: AttachmentType;
}
