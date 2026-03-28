import { logger } from "../logger";

describe("Logger", () => {
  let consoleSpy: {
    log: jest.SpiedFunction<typeof console.log>;
    warn: jest.SpiedFunction<typeof console.warn>;
    error: jest.SpiedFunction<typeof console.error>;
  };

  beforeEach(() => {
    consoleSpy = {
      log: jest.spyOn(console, "log").mockImplementation(),
      warn: jest.spyOn(console, "warn").mockImplementation(),
      error: jest.spyOn(console, "error").mockImplementation(),
    };
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  test("logger.info calls console.log", () => {
    logger.info("TestTag", "test message");
    expect(consoleSpy.log).toHaveBeenCalled();
  });

  test("logger.warn calls console.warn", () => {
    logger.warn("TestTag", "warning message");
    expect(consoleSpy.warn).toHaveBeenCalled();
  });

  test("logger.error calls console.error", () => {
    logger.error("TestTag", "error message");
    expect(consoleSpy.error).toHaveBeenCalled();
  });

  test("logger.debug calls console.log in non-production", () => {
    logger.debug("TestTag", "debug message");
    expect(consoleSpy.log).toHaveBeenCalled();
  });

  test("logger includes tag and message in output", () => {
    logger.info("MyComponent", "something happened");
    const callArgs = consoleSpy.log.mock.calls[0];
    const output = callArgs[0] as string;
    expect(output).toContain("MyComponent");
    expect(output).toContain("something happened");
  });

  test("logger includes data when provided", () => {
    const data = { userId: "123" };
    logger.info("TestTag", "with data", data);
    const callArgs = consoleSpy.log.mock.calls[0];
    // In dev mode, data is passed as second argument
    expect(callArgs[1]).toEqual(data);
  });
});
