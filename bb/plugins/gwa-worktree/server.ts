import type { BbPluginApi } from "@get-bb/plugin-sdk";
import { z } from "zod";
import { gwaHostContract } from "./contract.js";

export const GWA_ENVIRONMENT_PROVIDER_ID = "gwa-worktree";

export const gwaInputsSchema = z
  .object({ baseBranch: z.string().min(1).nullable().default(null) })
  .default({ baseBranch: null });

export default function plugin(bb: BbPluginApi): void {
  const host = bb.hosts.experimental_client({ contract: gwaHostContract });

  bb.experimental_environments.register({
    id: GWA_ENVIRONMENT_PROVIDER_ID,
    displayName: "GWA worktree",
    description: "Create or attach a worktree with your gwa shell function.",
    icon: "FolderGit",
    requires: { gitCheckout: true },
    inputs: gwaInputsSchema,
    async create(context) {
      context.report.step("Running gwa");
      try {
        const result = await host.call(
          "create",
          {
            sourcePath: context.projectCheckout.path,
            branchName: context.rebuild
              ? (context.previous?.environment.branchName ?? context.suggestedBranchName)
              : context.suggestedBranchName,
            baseBranch: context.inputs.baseBranch,
          },
          { hostId: context.host.id, signal: context.signal, timeoutMs: 15 * 60 * 1000 },
        );
        if (result.status === "failed") return result;
        return {
          status: "created",
          path: result.path,
          ownsPath: false,
          ...(result.baseBranch === null ? {} : { mergeBaseBranch: result.baseBranch }),
        };
      } catch (error) {
        if (context.signal.aborted) throw error;
        return {
          status: "failed",
          message: error instanceof Error ? error.message : String(error),
        };
      }
    },
    async remove(context) {
      if (context.hostId !== null) {
        await host.call("remove", null, {
          hostId: context.hostId,
          signal: context.signal,
        });
      }
      return { status: "removed" };
    },
  });
}
