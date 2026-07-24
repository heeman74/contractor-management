import Image from "next/image";
import type { AttachmentResponse } from "@/types/api";
import { Dialog, DialogContent } from "@/components/ui/dialog";

interface PhotoLightboxProps {
  photo: AttachmentResponse | null;
  onClose: () => void;
}

export function PhotoLightbox({ photo, onClose }: PhotoLightboxProps) {
  return (
    <Dialog open={!!photo} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-3xl" showCloseButton>
        {photo?.remote_url ? (
          <Image
            src={photo.remote_url}
            width={800}
            height={600}
            unoptimized
            className="w-full object-contain"
            alt="Photo note"
          />
        ) : (
          <div className="flex items-center justify-center aspect-video bg-gray-100 rounded">
            <span className="text-xs text-gray-400">Photo unavailable</span>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
