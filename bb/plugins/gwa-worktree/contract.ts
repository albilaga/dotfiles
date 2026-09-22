import { defineRpcContract } from "@get-bb/plugin-sdk";
import { z } from "zod";

export const gwaHostContract = defineRpcContract({
  create: {
    input: z
      .object({
        sourcePath: z.string().min(1),
        branchName: z.string().min(1),
        baseBranch: z.string().min(1).nullable(),
      })
      .strict(),
    output: z.discriminatedUnion("status", [
      z
        .object({
          status: z.literal("created"),
          path: z.string().min(1),
          baseBranch: z.string().min(1).nullable(),
        })
        .strict(),
      z
        .object({ status: z.literal("failed"), message: z.string().min(1) })
        .strict(),
    ]),
  },
  remove: {
    input: z.null(),
    output: z.object({ status: z.literal("removed") }).strict(),
  },
});
