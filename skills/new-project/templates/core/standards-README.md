# Standards

A standard is one Markdown file here: a rule about how you want work done, in a form Claude
can check against.
For example, "every screen has an empty state" or "no network calls in the UI layer".
Each file has a short rule, why it matters, how to tell it is met, and where it applies.

Run `/corecrew:new-standard` to make one: Claude asks a few questions and writes the file here.

Standards in this folder apply to every project.
A project can add its own exceptions in `<project>/docs/standards/`.
