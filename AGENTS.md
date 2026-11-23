# Working instructions

- For computer use, always delegate to a GPT-6 Luna (`gpt-6-luna`) subagent. Do not perform computer use with the primary agent or another model.
- For reports, reviews, plans, and other user-facing document artifacts, use HTML rather than Markdown. Preserve explicitly requested formats, including LaTeX sources and PDF exports. Standard instruction files keep their required filename.
- Every change must update the root `VERSION` file in the same pull request. Use `MAJOR.MINOR.PATCH`: major for incompatible changes, minor for backward-compatible features, and patch for fixes, maintenance, or documentation changes. Reset lower components when incrementing a higher component. Do not add a `v` prefix, prerelease suffix, or leading zeroes.
- Keep one version for a change as it is promoted between integration branches; promotion does not require another bump when that version is already higher than the target branch's version. CI rejects changes whose version does not increase relative to the PR target or the previous push.
- The shared app footer reads `VERSION`. Keep the version check and all CI checks as dependencies of Heroku deployment. Only pushes to `dev` deploy staging; only pushes to `main` deploy production.
