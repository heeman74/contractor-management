import { parseSSELine } from "../useIntakeChat";

describe("parseSSELine", () => {
  test("parses token event with delta", () => {
    const result = parseSSELine('event: token\ndata: {"delta":"hello"}');
    expect(result).toEqual({ event: "token", data: { delta: "hello" } });
  });

  test("parses tool_call event with create_trade_scope", () => {
    const result = parseSSELine(
      'event: tool_call\ndata: {"tool":"create_trade_scope","input":{"trade_name":"Electrical","sort_order":0},"id":"tc_1"}'
    );
    expect(result).toEqual({
      event: "tool_call",
      data: {
        tool: "create_trade_scope",
        input: { trade_name: "Electrical", sort_order: 0 },
        id: "tc_1",
      },
    });
  });

  test("parses done event", () => {
    const result = parseSSELine('event: done\ndata: {"stop_reason":"end_turn"}');
    expect(result).toEqual({
      event: "done",
      data: { stop_reason: "end_turn" },
    });
  });

  test("parses error event", () => {
    const result = parseSSELine(
      'event: error\ndata: {"message":"Something went wrong"}'
    );
    expect(result).toEqual({
      event: "error",
      data: { message: "Something went wrong" },
    });
  });

  test("returns null for empty string", () => {
    const result = parseSSELine("");
    expect(result).toBeNull();
  });

  test("returns null for comment/keep-alive line", () => {
    const result = parseSSELine(": keep-alive");
    expect(result).toBeNull();
  });

  test("handles partial data lines (data only, no event prefix) — defaults event to message", () => {
    const result = parseSSELine('data: {"delta":"world"}');
    expect(result).toEqual({ event: "message", data: { delta: "world" } });
  });

  test("returns null for whitespace-only string", () => {
    const result = parseSSELine("   ");
    expect(result).toBeNull();
  });

  test("parses token event with empty delta", () => {
    const result = parseSSELine('event: token\ndata: {"delta":""}');
    expect(result).toEqual({ event: "token", data: { delta: "" } });
  });
});
