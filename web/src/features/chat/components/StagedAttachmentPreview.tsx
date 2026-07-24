interface StagedAttachmentPreviewProps {
  file: File;
  previewUrl: string | null;
  onRemove: () => void;
}

export function StagedAttachmentPreview({
  file,
  previewUrl,
  onRemove,
}: StagedAttachmentPreviewProps) {
  return (
    <div className="mb-2 flex items-center gap-2 rounded-md border bg-muted p-2 text-sm">
      {previewUrl ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={previewUrl}
          alt="Attachment preview"
          className="h-10 w-10 rounded object-cover"
        />
      ) : (
        <span className="truncate">{file.name}</span>
      )}
      <button
        type="button"
        className="ml-auto text-muted-foreground hover:text-foreground"
        onClick={onRemove}
        aria-label="Remove attachment"
      >
        ×
      </button>
    </div>
  );
}
