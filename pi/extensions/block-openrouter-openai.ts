// Blocks OpenAI models routed through OpenRouter: they bill OpenRouter credits,
// but OpenAI models should go through the openai-codex subscription provider.
// - Replaces the openrouter catalog with the same list minus openai/* ids, so
//   they never appear in /model, Ctrl+P cycling, or subagent model resolution.
// - If a blocked model is already selected (e.g. `pi --model openrouter/openai/...`,
//   which resolves before extensions bind), reroutes to the same id on
//   openai-codex before the first request.
// ponytail: openai ids with no openai-codex equivalent (legacy/batch variants)
// are left as-is; add an allowlist-based hard error here if that ever matters.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const BLOCKED = /^~?openai\//;

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		const kept = ctx.modelRegistry
			.getAll()
			.filter((m) => m.provider === "openrouter" && !BLOCKED.test(m.id));
		if (kept.length === 0) return;
		pi.registerProvider("openrouter", { baseUrl: kept[0].baseUrl, models: kept });

		const m = ctx.model;
		if (m && m.provider === "openrouter" && BLOCKED.test(m.id)) {
			const fallback = ctx.modelRegistry.find("openai-codex", m.id.replace(BLOCKED, ""));
			if (fallback) {
				const ok = await pi.setModel(fallback);
				if (ctx.hasUI) {
					ok
						? ctx.ui.notify(`OpenAI models via OpenRouter are blocked; using openai-codex/${fallback.id}`, "warning")
						: ctx.ui.notify(`Reroute to openai-codex/${fallback.id} failed; blocked model ${m.id} is still active`, "warning");
				}
			} else if (ctx.hasUI) {
				ctx.ui.notify(`OpenAI models via OpenRouter are blocked; ${m.id} has no openai-codex equivalent`, "warning");
			}
		}
	});
}
