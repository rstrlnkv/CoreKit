# CoreModel classifier quality

Run `python3 scripts/coremodel-quality.py` with a signed-in Codex CLI. Each case makes one real OpenAI call. The offline suite checks the corpus and scorer without contacting OpenAI. To rerun individual cases, add `--case mro-en --case mro-ru`.

The corpus pairs English and Russian requests. The MRO correction comes from [CPython issue 156233](https://github.com/python/cpython/issues/156233). The temporary-directory request comes from the CoreModel change request. Each has a translation. The remaining cases are authored examples of editing, ordinary implementation, duplicate charges, choosing an offered option, adding new work and deploying with a checklist. Labels represent the intended routing under the shipped classifier policy.

The runner feeds the installed source tree’s hook a prompt event and an optional preceding reply. It offers Luna, Sol and Astra and captures the structured output from the real nested CLI. The current model is unranked to exercise all recommendations. Results score the classifier before confirmation or display. A keep decision scores only against keep. Every other case requires the exact model tier and effort. A timeout or invalid answer counts as a miss and is reported separately. Times include hook and CLI startup overhead. Repeated measurements may differ.

## Measured run

On 2026-11-25, Codex CLI 0.166.0 used an authenticated GPT-6 Luna classifier at low effort. All 16 calls returned valid structured answers. Russian matched 8 of 8 labels. English matched 7 of 8. All tier and keep decisions matched. The English temporary-directory request received Sol at low effort. Its reference label and Russian result were Sol at medium effort. Median latency was 6.7 seconds and nearest-rank p95 was 9.8 seconds. This single run covers eight distinct tasks in two languages.
