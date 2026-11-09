# Pi base guidance

Edit the ordered files in `base-fragments/`, then run
`bin/assemble-pi-base` from the repository root. Commit the fragments and the
resulting `AGENTS.md.d/00-base.md` together. Provisioning checks that the
assembled file matches before it installs the base guidance.

Fragments are assembled in filename order. A `.space.md` fragment ends with a
space in the assembled file, a `.blank.md` fragment ends with a blank line,
and other fragments end with one newline. The existing downstream fragment
assembly and evals continue to use `AGENTS.md.d/00-base.md`.

These files split the existing base guidance only. They do not include the
additional fragments installed by downstream repositories.
