- **Creds-free by default.** The box starts with no OpenAI and no git
  credentials. If you need to authenticate Codex, the operator runs the
  login flow (`codex`) interactively. For git, the operator adds their own
  credentials (a PAT or `gh auth login`). Never assume credentials are
  present; never ask for or store secrets on disk beyond what the operator
  sets up.
