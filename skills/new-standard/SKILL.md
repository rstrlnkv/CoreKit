---
name: new-standard
description: Write one of your own standards (a short rule file every agent follows) into your Core. Use /coredev:new-standard [topic], or pass a knowledge line that keeps recurring.
disable-model-invocation: true
argument-hint: "[topic | knowledge line]"
---

# New standard

## Overview
A standard is a short file of rules the user wants every agent to follow, kept in their own
Core at `${user_config.core_dir}/standards/<name>.md`. The plugin ships no standards: this
skill only helps the user write theirs. **Never write into the plugin** (the folder that holds
this skill, `${CLAUDE_SKILL_DIR}/../..`); the only file this skill creates or changes is the
standard in Core.

Format: `${CLAUDE_SKILL_DIR}/references/template.md`. The shape is checked by
`${CLAUDE_SKILL_DIR}/../../scripts/check-standard.sh`. Below, `<Core>` means
`${user_config.core_dir}` (scripts expand a leading `~`).

## Language
Talk to the user in their language, in plain words; explain a term the first time you use it.
The standard on disk is **English**, and so are the commit message and file name. After the draft
is written, summarize it in 2–4 lines in the user's language.

## Start
Check that the Core is set up:
`CORE_DIR="${user_config.core_dir}" bash "${CLAUDE_SKILL_DIR}/../../scripts/lib.sh" ready`
(exit 0 = set up). If it fails, say in plain words that the Core does not exist yet and that
`/coredev:new-project` sets it up (one time); stop. Do not set it up from here.

The argument is a topic ("versioning"), a knowledge line (contains `→`: `symptom → cause →
guard`, see `${CLAUDE_SKILL_DIR}/../../reference/knowledge.md`), or empty (ask what the standard
is about, in one question). Pick `<name>`: Latin, lowercase, hyphens, 3–40 chars. If
`<Core>/standards/<name>.md` exists, read it: this is an update, and the draft starts from it.

## Steps
**1. Interview.** One question at a time, in the user's language, plain words. Cover:
what must always be true (the rules, one per line, imperative); what went wrong before (each
becomes a "Why"); which roles need it. Roles: engineer, tester, security, verifier, localizer,
designer, and `release` (the release procedure). For each rule ask how it could be checked: a
command and what it prints, or admit "no guard" and name the risk. Stop at 3–7 rules; more means
two standards. From a knowledge line, pre-fill the draft: the symptom is the "Why", the cause
the rule, the guard address the first check, and ask only what is missing.

**2. Sources.** Ask whether the user has documents to base it on (an old standard, a note, a
link). Read what they name. Nothing is used that they did not point to.

**3. Research.** Send one research subagent: the `Agent` tool, `subagent_type: general-purpose`,
told to use web search for current best practice on the topic and the user's stack, and to
return at most 300 words with links. Cite what you use in `## Sources`; the user's own
experience counts as a source. If web search is not available, say so and rely on step 2.

**4. Draft, check, save.** Fill `references/template.md`: remove every comment, keep the five
sections in order, under 120 lines. Show the draft in the user's language (the rules, why, and
how each is checked) and ask for "ok". Edit until they say ok.
- New standard: on "ok", write `<Core>/standards/<name>.md`.
- Existing standard: write the draft to a temp file first, show
  `diff -u "<Core>/standards/<name>.md" <draft>` (run `check-standard.sh` on the temp draft
  first), and overwrite only after a second "ok".

Then run `bash "${CLAUDE_SKILL_DIR}/../../scripts/check-standard.sh" "<Core>/standards/<name>.md"`.
Each `check-standard:` line is a defect: fix it, run again, until it prints nothing. Then commit
only that file, in Core (`save` is not used: it needs a project):
`git -C "<Core>" add "standards/<name>.md" && git -C "<Core>" commit -m "Add standard <name>" -- "standards/<name>.md"`
(for an update, `commit -m "Update standard <name>"`). Do not push. If git says there is nothing
to commit, the file did not change; tell the user.

**5. Report.** In the user's language: the file path, the rules in one line each, which roles
read it (agents find it by `applies-to` and read it before they work), which rules have no guard.

## Rules
- Never write into the plugin. Never overwrite a standard without the diff and an "ok".
- Never commit anything but the one standard. Never push.
- A project may override a standard with `<Core>/<project>/docs/standards/<name>.md`; that is
  the user's choice, not something to create here.
- Do not invent rules. Every rule comes from the user, their sources, or research they saw.

## Red flags — stop
| Thought | Reality |
|---------|---------|
| "I'll add a few good rules of my own" | The standard is the user's; propose, they decide. |
| "No check is fine, it is obvious" | Write `no guard — <risk>`; the gap must be visible. |
| "I'll save it with the `save` tool" | `save` needs a project; commit the one file with git. |
| "check-standard complains about a detail, I'll commit anyway" | Fix it; the agents read this shape. |
