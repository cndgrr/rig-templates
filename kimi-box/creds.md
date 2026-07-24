- **Creds-free by default.** The box starts with no Moonshot and no git
  credentials. If you need to authenticate, the operator runs `kimi` and
  its `/login` flow interactively (Kimi Code OAuth, or an API key). For
  git, the operator adds their own credentials (a PAT or `gh auth login`).
  Never assume credentials are present; never ask for or store secrets on
  disk beyond what the operator sets up.
