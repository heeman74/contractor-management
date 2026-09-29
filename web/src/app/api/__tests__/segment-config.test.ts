/**
 * @jest-environment node
 */
/**
 * Route segment config must be written as literals.
 *
 * Next evaluates `maxDuration`, `dynamic`, `revalidate` and friends statically,
 * so `export const maxDuration = SOME_CONSTANT` fails the production build with
 * "Invalid segment configuration export detected" — and nothing before that
 * build notices. tsc is happy, eslint is happy, the unit tests are happy, and
 * the deploy dies.
 *
 * This catches it in a second instead.
 */
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const SEGMENT_KEYS = [
  "dynamic",
  "dynamicParams",
  "revalidate",
  "fetchCache",
  "runtime",
  "preferredRegion",
  "maxDuration",
];

/** A literal number, string, or boolean — anything Next can read without executing it. */
const LITERAL = /^(-?\d+(\.\d+)?|"[^"]*"|'[^']*'|true|false)$/;

function routeAndPageFiles(dir: string, found: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      routeAndPageFiles(full, found);
    } else if (/^(route|page|layout)\.tsx?$/.test(entry)) {
      found.push(full);
    }
  }
  return found;
}

const APP_DIR = join(process.cwd(), "src", "app");

it("finds route files to check", () => {
  expect(routeAndPageFiles(APP_DIR).length).toBeGreaterThan(10);
});

it("declares every segment config as a literal", () => {
  const offenders: string[] = [];

  for (const file of routeAndPageFiles(APP_DIR)) {
    const source = readFileSync(file, "utf8");
    for (const key of SEGMENT_KEYS) {
      const match = source.match(
        new RegExp(`^export\\s+const\\s+${key}\\s*=\\s*([^;\\n]+);`, "m")
      );
      if (!match) continue;
      const value = match[1].trim();
      if (!LITERAL.test(value)) {
        offenders.push(
          `${file.replace(process.cwd() + "/", "")}: export const ${key} = ${value}`
        );
      }
    }
  }

  expect(offenders).toEqual([]);
});
