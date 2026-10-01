/**
 * The settings hub.
 *
 * Exists because breadcrumbs linked `/settings` from every settings page and
 * nothing answered it. Its own job is narrower: offer only the sections this
 * user can actually open, so the hub never shows a door onto an empty room.
 */
import { render, screen } from "@testing-library/react";

const mockCan = jest.fn();
jest.mock("@/lib/hooks/usePermissions", () => ({
  usePermissions: () => ({ can: mockCan, permissions: new Set(), isLoading: false }),
}));

import { SettingsIndex } from "../settings-index";

beforeEach(() => jest.clearAllMocks());

it("offers both sections to someone who can reach both", () => {
  mockCan.mockReturnValue(true);
  render(<SettingsIndex />);

  expect(screen.getByRole("link", { name: /Company profile/ })).toHaveAttribute(
    "href",
    "/settings/company"
  );
  expect(screen.getByRole("link", { name: /Roles & permissions/ })).toHaveAttribute(
    "href",
    "/settings/roles"
  );
});

it("hides a section the user cannot open", () => {
  mockCan.mockImplementation((key: string) => key === "company.settings.manage");
  render(<SettingsIndex />);

  expect(screen.getByRole("link", { name: /Company profile/ })).toBeInTheDocument();
  expect(
    screen.queryByRole("link", { name: /Roles & permissions/ })
  ).not.toBeInTheDocument();
});

it("says so plainly when there is nothing to configure", () => {
  // Better than an empty page that looks broken.
  mockCan.mockReturnValue(false);
  render(<SettingsIndex />);

  expect(screen.queryAllByRole("link")).toHaveLength(0);
  expect(
    screen.getByText(/do not have access to any settings/)
  ).toBeInTheDocument();
});
