- **Creds-free by default.** The box starts with no xAI and no git
  credentials. If you need to authenticate, the operator runs
  `grok login` interactively (SuperGrok / X Premium+). For git, the
  operator adds their own credentials (a PAT or `gh auth login`). Never
  assume credentials are present; never ask for or store secrets on disk
  beyond what the operator sets up.
