import { getServerUser } from "@/lib/auth";
import { redirect } from "next/navigation";
import { ChatPanel } from "@/features/chat/components/ChatPanel";

interface Props {
  params: Promise<{ id: string }>;
}

/**
 * Chat panel page for a project.
 * URL: /projects/{id}/chat
 */
export default async function ProjectChatPage({ params }: Props) {
  const user = await getServerUser();
  if (!user) {
    redirect("/login");
  }

  const { id: projectId } = await params;

  return (
    <div className="flex h-[calc(100vh-4rem)] flex-col p-4">
      <ChatPanel projectId={projectId} currentUserId={user.user_id} />
    </div>
  );
}
