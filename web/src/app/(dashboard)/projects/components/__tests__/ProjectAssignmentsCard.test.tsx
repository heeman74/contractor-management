import React from "react";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ProjectAssignmentsCard } from "../ProjectAssignmentsCard";
import { useProjectAssignments, assignToProject } from "@/lib/api/projects";
import { apiGet } from "@/lib/api-client";

jest.mock("@/lib/api/projects", () => ({
  useProjectAssignments: jest.fn(),
  assignToProject: jest.fn(),
  unassignFromProject: jest.fn(),
}));
jest.mock("@/lib/api-client", () => ({ apiGet: jest.fn() }));
jest.mock("@/lib/hooks/usePermissions", () => ({
  usePermissions: () => ({ can: () => true, permissions: new Set(), isLoading: false }),
}));
jest.mock("sonner", () => ({ toast: { success: jest.fn(), error: jest.fn() } }));

const mockUseAssignments = useProjectAssignments as jest.Mock;
const mockAssign = assignToProject as jest.Mock;
const mockApiGet = apiGet as jest.MockedFunction<typeof apiGet>;

const USERS = [
  { id: "u1", email: "sarah@ace.com", first_name: "Sarah", last_name: "Mitchell", roles: ["admin"] },
  { id: "u2", email: "john@ace.com", first_name: "John", last_name: "Cooper", roles: ["contractor"] },
];

function renderCard() {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={client}>
      <ProjectAssignmentsCard projectId="proj-1" />
    </QueryClientProvider>
  );
}

describe("ProjectAssignmentsCard", () => {
  beforeEach(() => {
    mockAssign.mockReset();
    mockApiGet.mockReset();
    mockApiGet.mockResolvedValue(USERS as never);
  });

  test("lists existing assignments with role badges", () => {
    mockUseAssignments.mockReturnValue({
      data: [
        { id: "a1", user_name: "Sarah Mitchell", role: "project_manager" },
        { id: "a2", user_name: "John Cooper", role: "contractor" },
      ],
    });
    renderCard();
    expect(screen.getByText("Sarah Mitchell")).toBeInTheDocument();
    expect(screen.getByText("Project Manager")).toBeInTheDocument();
    expect(screen.getByText("John Cooper")).toBeInTheDocument();
    expect(screen.getByText("Contractor")).toBeInTheDocument();
  });

  test("shows empty state when no one is assigned", () => {
    mockUseAssignments.mockReturnValue({ data: [] });
    renderCard();
    expect(screen.getByText("No one assigned yet.")).toBeInTheDocument();
  });

  test("assigns a project manager with the correct payload", async () => {
    mockUseAssignments.mockReturnValue({ data: [] });
    mockAssign.mockResolvedValue({ id: "a-new" });
    const user = userEvent.setup({ pointerEventsCheck: 0 });
    renderCard();

    await waitFor(() => expect(mockApiGet).toHaveBeenCalled()); // users loaded

    await user.click(screen.getByRole("combobox", { name: /role/i }));
    await user.click(await screen.findByRole("option", { name: "Project Manager" }));

    await user.click(screen.getByRole("combobox", { name: /user/i }));
    await user.click(await screen.findByRole("option", { name: "Sarah Mitchell" }));

    await user.click(screen.getByRole("button", { name: /assign/i }));

    await waitFor(() =>
      expect(mockAssign).toHaveBeenCalledWith("proj-1", {
        user_id: "u1",
        role: "project_manager",
      })
    );
  });
});
