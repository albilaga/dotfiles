import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const BLOCKED = /^~?openai\//;

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		const provider = ctx.modelRegistry.getProvider("openrouter");
		if (!provider) return;

		// Keep the complete catalog for API dispatch; filter availability, not media operations.
		pi.registerProvider({
			...provider,
			filterModels: (models, credential) => (provider.filterModels?.(models, credential) ?? models)
				.filter((model) => !BLOCKED.test(model.id)),
			filterAllModels: (models, credential) => (provider.filterAllModels?.(models, credential) ?? models)
				.filter((model) => (model.type && model.type !== "chat") || !BLOCKED.test(model.id)),
			stream(model, context, options) {
				if (BLOCKED.test(model.id)) throw new Error(`OpenAI via OpenRouter is blocked: ${model.id}`);
				return provider.stream(model, context, options);
			},
			streamSimple(model, context, options) {
				if (BLOCKED.test(model.id)) throw new Error(`OpenAI via OpenRouter is blocked: ${model.id}`);
				return provider.streamSimple(model, context, options);
			},
		});

		const model = ctx.model;
		if (!model || model.provider !== "openrouter" || !BLOCKED.test(model.id)) return;

		const id = model.id.replace(BLOCKED, "");
		for (const name of ["openai", "openai-codex"]) {
			const fallback = ctx.modelRegistry.find(name, id);
			// API-key credentials must not silently turn a subscription reroute into paid API usage.
			if (!fallback || !ctx.modelRegistry.isUsingOAuth(fallback) ||
				!ctx.modelRegistry.getProvider(name)?.auth.oauth?.isSubscription) continue;
			if (await pi.setModel(fallback)) {
				if (ctx.hasUI) ctx.ui.notify(`OpenAI via OpenRouter is blocked; using ${name}/${id}`, "warning");
				return;
			}
		}
		if (ctx.hasUI) ctx.ui.notify(`OpenAI via OpenRouter is blocked; sign in with ChatGPT via /login openai and select ${id}`, "warning");
	});
}
