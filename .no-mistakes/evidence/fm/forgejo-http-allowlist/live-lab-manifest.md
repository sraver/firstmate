# Live validation lab: FM_PR_FORGEJO_HTTP_HOSTS plain-http allowlist

Product driven: the real `bin/fm-pr-check.sh`, `bin/fm-pr-lib.sh`, `bin/fm-pr-poll.sh`
from branch fm/forgejo-http-allowlist (target commit 6806506), with the real
`tea` CLI v0.16.0 and the machine's real `jq`.

Disposable environment (all under /tmp/fm-lab.XXXXXX, removed after the run):
- A marked firstmate lab home (`bin/fm-lab-home.sh create`) with five task metas
  (`mode=direct-PR`, worktree = a disposable git repo whose HEAD is pushed to a
  disposable bare remote, so the named-head gate passes as for a real direct-PR task).
- Two disposable tea configs via XDG_CONFIG_HOME isolation (operator tea config untouched):
  one holding `http://127.0.0.1:3989`, one holding `https://127.0.0.1:3989`.
- A disposable local Gitea API endpoint (`gitea-api-stub.py`, python3) serving
  `/api/v1/user` and `/api/v1/repos/fmlab/fixture-repo/pulls/7` on plain HTTP :3989
  and TLS :3990 (self-signed, tea `--insecure`); the PR record's `merged` flag is
  flipped live between polls. `forge-endpoint-requests.log` is the endpoint's own
  request log proving real tea HTTP traffic.

Scenario logs: tea-login-setup.log, s1-arming.log, s1-poll-cycle.log,
s2-refusals.log, s3-scheme-pairing.log, s4-https-unchanged.log.
