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
};

export default config;
