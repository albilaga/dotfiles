import { experimental_defineHostEntry } from "@get-bb/plugin-sdk/host";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { gwaHostContract } from "./contract.js";

const exec = promisify(execFile);
const PATH_MARKER = "__BB_GWA_PATH__=";

function message(error: unknown): string {
  if (error && typeof error === "object") {
    const detail = ["stderr", "stdout"]
      .map((key) => key in error ? String((error as Record<string, unknown>)[key]).trim() : "")
      .find(Boolean);
    if (detail) return detail.slice(-4000);
  }
  return (error instanceof Error ? error.message : String(error)).slice(-4000);
}

export default experimental_defineHostEntry({
  contract: gwaHostContract,
  handlers: {
    async create(input, context) {
      try {
        const { stdout } = await exec(
          "/bin/zsh",
          [
            "-lic",
            'gwa "$1" "${2:-}" && print -r -- "__BB_GWA_PATH__=$PWD"',
            "--",
            input.branchName,
            input.baseBranch ?? "",
          ],
          {
            cwd: input.sourcePath,
            env: { ...process.env, HERDR_ENV: "0" },
            maxBuffer: 1024 * 1024,
            signal: context.signal,
            timeout: 15 * 60 * 1000,
          },
        );
        const path = stdout
          .split(/\r?\n/u)
          .filter((line) => line.startsWith(PATH_MARKER))
          .at(-1)
          ?.slice(PATH_MARKER.length);
        if (!path) return { status: "failed", message: "gwa did not report its worktree path" } as const;

        let baseBranch = input.baseBranch;
        if (baseBranch === null) {
          const result = await exec(
            "git",
            ["config", "--get", `git-town-branch.${input.branchName}.parent`],
            { cwd: path, signal: context.signal },
          ).catch(() => null);
          baseBranch = result?.stdout.trim() || null;
        }
        return { status: "created", path, baseBranch } as const;
      } catch (error) {
        if (context.signal.aborted) throw error;
        return { status: "failed", message: message(error) } as const;
      }
    },
    remove() {
      // gwa owns worktree lifecycle; gwrm/gwclean remove it.
      return { status: "removed" } as const;
    },
  },
});
