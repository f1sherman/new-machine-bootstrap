# Pi base guidance

Edit the ordered files in `base-fragments/`, then run
`bin/assemble-pi-base` from the repository root. Commit the fragments and the
resulting `AGENTS.md.d/00-base.md` together. Provisioning checks that the
assembled file matches before it installs the base guidance.

Fragments are concatenated byte for byte in filename order. Some end in the
middle of a paragraph and intentionally have no final newline. Do not add
separators: they change the guidance delivered to Pi. The existing downstream
fragment assembly and evals continue to use `AGENTS.md.d/00-base.md`.

These files split the existing base guidance only. They do not include the
additional fragments installed by downstream repositories.
