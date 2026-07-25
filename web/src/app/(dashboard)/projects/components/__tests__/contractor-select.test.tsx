import { render, screen } from "@testing-library/react";
import type { ContractorMatch } from "@/types/projects";
import { ContractorSelect } from "../ContractorSelect";

const SPECIALTY: ContractorMatch[] = [
  { id: "c141dff9-e7ae-46bf-a5db-228787479a6f", name: "Mike Rivera", email: "mike@ace.com", has_specialty_match: true },
];
const OTHER: ContractorMatch[] = [
  { id: "d252eaa0-1234-4bcd-9999-000000000001", name: "Sarah Mitchell", email: "sarah@ace.com", has_specialty_match: false },
];

function renderSelect(value: string) {
  return render(
    <ContractorSelect
      value={value}
      onValueChange={() => {}}
      specialtyContractors={SPECIALTY}
      otherContractors={OTHER}
      hasContractors
    />
  );
}

describe("ContractorSelect", () => {
  test("shows the placeholder when nothing is selected", () => {
    renderSelect("");
    expect(screen.getByText("Select contractor...")).toBeInTheDocument();
  });

  test("shows the contractor name (not the id) for a selected specialty match", () => {
    renderSelect(SPECIALTY[0].id);
    const trigger = screen.getByTestId("contractor-select");
    expect(trigger).toHaveTextContent("Mike Rivera");
    // Regression: the raw UUID must never surface in the trigger.
    expect(trigger).not.toHaveTextContent(SPECIALTY[0].id);
  });

  test("resolves the name from the other-contractors group too", () => {
    renderSelect(OTHER[0].id);
    const trigger = screen.getByTestId("contractor-select");
    expect(trigger).toHaveTextContent("Sarah Mitchell");
    expect(trigger).not.toHaveTextContent(OTHER[0].id);
  });

  test("falls back to the placeholder when the id is not in either list", () => {
    renderSelect("00000000-0000-0000-0000-000000000000");
    expect(screen.getByText("Select contractor...")).toBeInTheDocument();
  });
});
