Read every report file under `security/reports/`. These are outputs of the local
security scanners: Slither (`slither-report-*.txt`), Aderyn (`aderyn-report-*.md`),
Solhint (`solhint-report-*.txt`), and the AI runs (`ai-review-*.md`,
`ai-audit-*.md`, `skills-*.md`). If multiple timestamped reports exist for the
same tool, use only the MOST RECENT one for that tool.

Produce ONE consolidated summary of all findings across those reports:

- Group findings by severity, most severe first: CRITICAL, HIGH, MEDIUM, LOW,
  INFORMATIONAL. Omit any group that has no findings.
- Use the severity each tool already assigned. If a finding has no severity,
  assign your best-judgment severity and append "(inferred)".
- Within each group, list each finding as a single bullet in this format:
  `- <one-sentence description> — <file>:<line if known> (<source tool>)`
- De-duplicate: if multiple tools report the same issue, list it once and note
  all sources, e.g. `(slither, ai-audit)`.
- Keep every description to ONE sentence. Do NOT reproduce full finding text,
  exploit walkthroughs, or fixes — this is an index, not the report.
- End with a one-line count per severity, e.g. `Totals: 0 critical, 1 high, 3 medium, ...`.

Print the summary to STDOUT only. Do NOT write any file, create issues, post
comments, or modify the repo in any way. This repository is public and the
contracts hold real value — keep all output local to this terminal.
