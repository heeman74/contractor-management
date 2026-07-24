"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { apiGet, apiPatch, apiUpload } from "@/lib/api-client";
import type { TaskAttachmentResponse } from "@/types/projects";
import type { PendingAttachment } from "@/features/media/types";

/** Photos/attachments for a task (GET /tasks/{id}/attachments). */
export function useTaskAttachments(taskId: string) {
  return useQuery<TaskAttachmentResponse[]>({
    queryKey: ["task-attachments", taskId],
    queryFn: () => apiGet<TaskAttachmentResponse[]>(`/api/v1/tasks/${taskId}/attachments`),
    enabled: Boolean(taskId),
  });
}

/**
 * Upload staged media to a task. Tasks store images under attachment_type "photo"
 * (the allowed set is photo/video/document — drawings are images, so they upload
 * as photos too).
 */
export function useUploadTaskAttachments(taskId: string) {
  const queryClient = useQueryClient();
  return useMutation<void, Error, PendingAttachment[]>({
    mutationFn: async (items) => {
      for (const item of items) {
        const form = new FormData();
        form.append("file", item.file);
        form.append("attachment_type", "photo");
        await apiUpload(`/api/v1/tasks/${taskId}/attachments`, form);
      }
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["task-attachments", taskId] }),
  });
}

/**
 * Save an annotation layer onto an existing task photo — non-destructive: the
 * original image is untouched and the annotations (annotation_data) can be
 * edited again later. PATCH /tasks/{id}/attachments/{attachmentId}.
 */
export function useUpdateTaskAnnotation(taskId: string) {
  const queryClient = useQueryClient();
  return useMutation<
    TaskAttachmentResponse,
    Error,
    { attachmentId: string; annotationData: unknown }
  >({
    mutationFn: ({ attachmentId, annotationData }) =>
      apiPatch<TaskAttachmentResponse>(
        `/api/v1/tasks/${taskId}/attachments/${attachmentId}`,
        { annotation_data: annotationData }
      ),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ["task-attachments", taskId] }),
  });
}
