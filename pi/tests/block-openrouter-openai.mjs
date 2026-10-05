// Run: node pi/tests/block-openrouter-openai.mjs
import assert from "node:assert/strict";
import install from "../extensions/block-openrouter-openai.ts";

const blocked = { provider: "openrouter", id: "openai/gpt-test" };
const allowed = { provider: "openrouter", id: "other/chat" };
const image = { provider: "openrouter", type: "image", id: "openai/image" };
const classifier = { provider: "openrouter", type: "classifier", id: "other/classifier" };
let catalog = [blocked, { ...blocked, id: "~openai/gpt-test" }, allowed, image, classifier];
const provider = {
	id: "openrouter",
	getModels: () => catalog.filter((model) => !model.type),
	getAllModels: () => catalog,
	stream: () => "stream",
	streamSimple: () => "simple",
	generateImages: () => "image",
	classify: () => "classifier",
	refreshModels: () => "refresh",
};

async function check({ oauth = ["openai"], selected = blocked, succeeds = true, subscription = true } = {}) {
	let start, registered;
	const selections = [];
	install({
		on: (event, handler) => { assert.equal(event, "session_start"); start = handler; },
		registerProvider: (value) => { registered = value; },
		setModel: async (model) => { selections.push(model.provider); return succeeds; },
	});
	await start({}, {
		model: selected,
		hasUI: false,
		modelRegistry: {
			getProvider: (name) => name === "openrouter" ? provider : { auth: { oauth: { isSubscription: subscription } } },
			find: (name, id) => ({ provider: name, id }),
			isUsingOAuth: (model) => oauth.includes(model.provider),
		},
	});
	return { registered, selections };
}

const { registered, selections } = await check();
assert.deepEqual(selections, ["openai"]);
assert.deepEqual(registered.getModels(), provider.getModels());
assert.deepEqual(registered.getAllModels(), catalog);
assert.deepEqual(registered.filterModels(registered.getModels()), [allowed]);
assert.deepEqual(registered.filterAllModels(registered.getAllModels()), [allowed, image, classifier]);
assert.equal(registered.generateImages(), "image");
assert.equal(registered.classify(), "classifier");
assert.equal(registered.refreshModels(), "refresh");
for (const method of ["stream", "streamSimple"]) {
	assert.throws(() => registered[method](blocked), /OpenAI via OpenRouter is blocked/);
	assert.throws(() => registered[method]({ ...blocked, id: "~openai/gpt-test" }), /blocked/);
	assert.equal(registered[method](allowed), method === "stream" ? "stream" : "simple");
}
catalog = [...catalog, { ...allowed, id: "other/new" }];
assert.equal(registered.filterModels(registered.getModels()).length, 2);
assert.deepEqual((await check({ oauth: ["openai-codex"] })).selections, ["openai-codex"]);
assert.deepEqual((await check({ oauth: [] })).selections, []);
assert.deepEqual((await check({ subscription: false })).selections, []);
assert.deepEqual((await check({ oauth: ["openai", "openai-codex"] })).selections, ["openai"]);
assert.deepEqual((await check({ selected: allowed })).selections, []);
const failed = await check({ succeeds: false });
assert.deepEqual(failed.selections, ["openai"]);
assert.throws(() => failed.registered.streamSimple(blocked), /blocked/);
console.log("OpenRouter guard checks passed");
