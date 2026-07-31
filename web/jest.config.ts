import type { Config } from "jest";

const config: Config = {
  testEnvironment: "jsdom",
  preset: "ts-jest",
  moduleNameMapper: {
    "^@/(.*)$": "<rootDir>/src/$1",
  },
  transform: {
    "^.+\\.tsx?$": [
      "ts-jest",
      { tsconfig: { moduleResolution: "node", jsx: "react-jsx" } },
    ],
  },
  testMatch: [
    "**/src/**/__tests__/**/*.test.ts",
    "**/src/**/__tests__/**/*.test.tsx",
  ],
  setupFilesAfterEnv: ["<rootDir>/jest.setup.ts"],
  // Jest's 5s default is not survivable for the userEvent-driven dialog suites
  // once every core is running a ts-jest worker: they take ~4s unloaded and tip
  // past 5s under contention, so the full run fails a shifting handful of tests
  // that each pass in isolation. The tests are not slow — the default is.
  testTimeout: 15000,
};

export default config;
