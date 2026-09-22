import { useEffect } from "react";
import {
  definePluginApp,
  experimental_BranchPicker as BranchPicker,
  type PluginEnvironmentProviderInputsProps,
} from "@get-bb/plugin-sdk/app";

const providerId = "gwa-worktree";
const defaultInputs = { baseBranch: null };

function Inputs({ projectId, target, value, onChange }: PluginEnvironmentProviderInputsProps) {
  const selected =
    value && typeof value === "object" && !Array.isArray(value) && "baseBranch" in value
      ? value.baseBranch
      : null;
  useEffect(() => {
    if (value === null) onChange({ status: "ready", value: defaultInputs });
  }, [value, onChange]);
  return (
    <BranchPicker
      hostId={target.kind === "existing-host" ? target.hostId : null}
      projectId={projectId}
      label="Branch from:"
      value={typeof selected === "string" ? selected : null}
      onChange={(baseBranch) =>
        onChange({ status: "ready", value: { baseBranch } })
      }
    />
  );
}

export default definePluginApp((app) => {
  app.slots.experimental_environmentProviderInputs({
    environmentProviderId: providerId,
    component: Inputs,
  });
});
