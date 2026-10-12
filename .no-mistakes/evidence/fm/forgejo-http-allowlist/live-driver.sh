#!/usr/bin/env bash
# Live validation of FM_PR_FORGEJO_HTTP_HOSTS on branch fm/forgejo-http-allowlist.
# Drives the real bin/fm-pr-check.sh, the real installed poll watcher
# (state/<id>.check.sh, byte-for-byte bin/fm-pr-poll.sh), the real
# bin/fm-pr-merge.sh, and the real parser in bin/fm-pr-lib.sh, against a
# disposable home whose only fake is the tea CLI (an external network client,
# mocked exactly the way this repository's own test style mocks it) plus the
# real jq. Nothing here touches a real FM_HOME, real fleet state, or any
# credential.
set -u
umask 022

ROOT=/home/user/.no-mistakes/worktrees/4fdebf4eeaf1/01M4RGWRKSQ4PNCPTV5GR0BWN8
BASE_COMMIT=20dcbf91520b1816663b81873ad67d0b93b3e4d6
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-live-lab.XXXXXX")
BASE_PATH=/usr/bin:/bin:/usr/sbin:/sbin
REAL_JQ=$(command -v jq) || { echo "FATAL: jq not found"; exit 1; }
unset FM_PR_FORGEJO_HTTP_HOSTS

FAILURES=0
note() { printf '\n=== %s ===\n' "$*"; }
ok()   { printf 'PASS: %s\n' "$*"; }
bad()  { printf 'FAIL: %s\n' "$*"; FAILURES=$((FAILURES+1)); }

cleanup() { rm -rf "$LAB"; }
trap cleanup EXIT

# ---------- Case CHECK: arming + poll home ----------
CK="$LAB/check"
mkdir -p "$CK/home/state" "$CK/home/data" "$CK/home/config" "$CK/wt" \
         "$CK/fakebin" "$CK/root/bin"
git -C "$CK/wt" init -q -b main
git -C "$CK/wt" -c user.name=lab -c user.email=lab@example.invalid commit -q --allow-empty -m init
git -C "$CK/wt" update-ref refs/remotes/origin/main "$(git -C "$CK/wt" rev-parse HEAD)"
printf '#!/usr/bin/env bash\nexit 0\n' > "$CK/root/bin/fm-guard.sh"
chmod +x "$CK/root/bin/fm-guard.sh"
ln -sf "$REAL_JQ" "$CK/fakebin/jq"
cat > "$CK/fakebin/tea" <<'SH'
#!/usr/bin/env bash
if [ "${1:-} ${2:-}" = "login list" ]; then
  printf '[{"name":"main","url":"%s"}]\n' "${FM_TEST_TEA_LOGIN_URL:-http://10.10.0.1:3001}"
  exit 0
fi
[ "${1:-}" = api ] || exit 0
if [ "${FM_TEST_TEA_MERGED:-}" = true ]; then
  printf '{"state":"closed","merged":true,"head":{"sha":"abc"}}\n'
else
  printf '{"state":"open","merged":false,"head":{"sha":"abc"}}\n'
fi
SH
chmod +x "$CK/fakebin/tea"

write_meta() {  # <id>
  printf 'window=firstmate:fm-%s\nendpoint_task_id=%s\nworktree=%s/wt\nproject=%s/project\nkind=ship\nmode=no-mistakes\n' \
    "$1" "$1" "$CK" "$CK" > "$CK/home/state/$1.meta"
}

run_check() {  # <task-id> <url> <pin-value|UNSET> [tea-login-url]
  local id=$1 url=$2 pin=$3 login=${4:-http://10.10.0.1:3001}
  local envpin=()
  [ "$pin" = UNSET ] || envpin=("FM_PR_FORGEJO_HTTP_HOSTS=$pin")
  env -u FM_PR_FORGEJO_HTTP_HOSTS "${envpin[@]}" \
    FM_ROOT_OVERRIDE="$CK/root" FM_HOME="$CK/home" \
    FM_TEST_TEA_LOGIN_URL="$login" \
    PATH="$CK/fakebin:$BASE_PATH" \
    "$ROOT/bin/fm-pr-check.sh" "$id" "$url"
}

run_poll() {  # <task-id> <pin-value|UNSET> [merged] [tea-login-url]
  local id=$1 pin=$2 merged=${3:-true} login=${4:-http://10.10.0.1:3001}
  local envpin=()
  [ "$pin" = UNSET ] || envpin=("FM_PR_FORGEJO_HTTP_HOSTS=$pin")
  env -u FM_PR_FORGEJO_HTTP_HOSTS "${envpin[@]}" \
    FM_TEST_TEA_MERGED="$merged" FM_TEST_TEA_LOGIN_URL="$login" \
    PATH="$CK/fakebin:$BASE_PATH" \
    bash "$CK/home/state/$id.check.sh"
}

parse() {  # <lib> <url> -> rc; sets FM_PR_* in a subshell-printed line
  local lib=$1 url=$2
  env -u FM_PR_FORGEJO_HTTP_HOSTS FM_PR_FORGEJO_HTTP_HOSTS="${PARSE_PIN-}" \
    bash -c '. "$1"; fm_pr_url_parse "$2" && printf "provider=%s host=%s path=%s url=%s owner=%s repo=%s\n" "$FM_PR_PROVIDER" "$FM_PR_HOST" "$FM_PR_PATH" "$FM_PR_URL" "${FM_PR_OWNER-}" "${FM_PR_REPO-}"' _ "$lib" "$url" 2>/dev/null
}

# ---------- Case MG: merge home (mirrors tests/fm-pr-merge.test.sh fixtures) ----------
MG="$LAB/merge"
mkdir -p "$MG/state" "$MG/home/data" "$MG/home/config" "$MG/user-home" "$MG/fakebin" "$MG/root/bin"
git -C "$MG/wt" init -q -b main 2>/dev/null || { mkdir -p "$MG/wt"; git -C "$MG/wt" init -q -b main; }
git -C "$MG/wt" -c user.name=lab -c user.email=lab@example.invalid commit -q --allow-empty -m init
git -C "$MG/wt" update-ref refs/remotes/origin/main "$(git -C "$MG/wt" rev-parse HEAD)"
printf 'backend = "markdown"\n\n[markdown]\npath = "data/backlog.md"\narchive = "data/done-archive.md"\ndone_keep = 10\n' > "$MG/home/.tasks.toml"
printf '## In Flight\n\n## Queued\n\n## Done\n' > "$MG/home/data/backlog.md"
printf '#!/usr/bin/env bash\nexit 0\n' > "$MG/root/bin/fm-guard.sh"
chmod +x "$MG/root/bin/fm-guard.sh"
ln -sf "$REAL_JQ" "$MG/fakebin/jq"
printf 'window=fm-task-x1\nworktree=%s/wt\nproject=%s/project\nkind=ship\nmode=no-mistakes\n' "$MG" "$MG" > "$MG/state/task-x1.meta"
FJ_HEAD=cccccccccccccccccccccccccccccccccccccccc
cat > "$MG/fakebin/tea" <<'SH'
#!/usr/bin/env bash
set -u
log_dir=$(dirname "$FM_TEST_TEA_LOG")
printf '%s\n' "$*" >> "$FM_TEST_TEA_LOG"
if [ "${1:-} ${2:-}" = "login list" ]; then
  cat "$log_dir/tea-logins.json"
  exit 0
fi
[ "${1:-}" = api ] || exit 0
shift
endpoint= do_value= head_commit_id=
while [ $# -gt 0 ]; do
  case "$1" in
    -X) shift 2 ;;
    --login|--repo) shift 2 ;;
    -f)
      case "$2" in
        Do=*) do_value=${2#Do=} ;;
        head_commit_id=*) head_commit_id=${2#head_commit_id=} ;;
      esac
      shift 2
      ;;
    /repos/*) endpoint=$1; shift ;;
    *) shift ;;
  esac
done
case "$endpoint" in
  */status|*/status\?*)
    page=1
    case "$endpoint" in
      *page=*) page=${endpoint##*page=}; page=${page%%&*} ;;
    esac
    if [ "$page" = 1 ]; then
      printf '{"state":"success","total_count":1,"statuses":[{"context":"ci-1","status":"success"}]}\n'
    else
      printf '{"state":"","total_count":0,"statuses":[]}\n'
    fi
    ;;
  "/repos/{owner}/{repo}")
    printf '{"default_merge_style":"merge"}\n'
    ;;
  */merge)
    if [ -e "$log_dir/tea-expected-head" ] \
      && [ "$head_commit_id" != "$(cat "$log_dir/tea-expected-head")" ]; then
      printf '{"message":"head out of date"}\n'
    else
      : > "$log_dir/tea-merged"
      printf '{}\n'
    fi
    ;;
  *)
    if [ -e "$log_dir/tea-merged" ]; then
      printf '{"state":"closed","mergeable":false,"merged":true,"draft":false,"head":{"sha":"%s"}}\n' "$(cat "$log_dir/tea-expected-head")"
    else
      printf '{"state":"open","mergeable":true,"merged":false,"draft":false,"head":{"sha":"%s"}}\n' "$(cat "$log_dir/tea-expected-head")"
    fi
    ;;
esac
exit 0
SH
chmod +x "$MG/fakebin/tea"
# Two logins: an unrelated https instance and the operator-pinned http one.
cat > "$MG/tea-logins.json" <<'JSON'
[
  {
    "name": "other",
    "url": "https://elsewhere.example",
    "ssh_host": "",
    "user": "",
    "default": "false"
  },
  {
    "name": "fm-fixture",
    "url": "http://10.10.0.1:3001",
    "ssh_host": "",
    "user": "",
    "default": "false"
  }
]
JSON
printf '%s\n' "$FJ_HEAD" > "$MG/tea-expected-head"
: > "$MG/tea.log"

run_merge() {  # <task-id> <url> <pin-value|UNSET>
  local id=$1 url=$2 pin=$3
  local envpin=()
  [ "$pin" = UNSET ] || envpin=("FM_PR_FORGEJO_HTTP_HOSTS=$pin")
  env -u FM_PR_FORGEJO_HTTP_HOSTS "${envpin[@]}" \
    FM_ROOT_OVERRIDE="$ROOT" FM_HOME="$MG/home" FM_STATE_OVERRIDE="$MG/state" \
    FM_TEST_TEA_LOG="$MG/tea.log" \
    HOME="$MG/user-home" \
    PATH="$MG/fakebin:$PATH" \
    "$ROOT/bin/fm-pr-merge.sh" "$id" "$url"
}

# ---------- base-commit contrast export ----------
mkdir -p "$LAB/base"
git -C "$ROOT" archive "$BASE_COMMIT" bin/fm-pr-lib.sh | tar -x -C "$LAB/base"

PIN='10.10.0.1:3001,internal.git.local'
HTTP_URL=http://10.10.0.1:3001/o/r/pulls/7

# ================= scenarios =================

note 'S0 regression contrast: at base commit the pin does not exist; pinned http URL must be refused there'
out=$(PARSE_PIN=$PIN parse "$LAB/base/bin/fm-pr-lib.sh" "$HTTP_URL"); rc=$?
if [ $rc -ne 0 ] && [ -z "$out" ]; then ok "base commit refuses pinned http URL (feature absent: rc=$rc)"; else bad "base commit accepted pinned http URL: rc=$rc out=$out"; fi

note 'S1 parser: pinned http host:port and bare host accepted, fields exact'
out=$(PARSE_PIN=$PIN parse "$ROOT/bin/fm-pr-lib.sh" "$HTTP_URL"); rc=$?
if [ $rc -eq 0 ] && [ "$out" = "provider=forgejo host=10.10.0.1:3001 path=o/r url=$HTTP_URL owner=o repo=r" ]; then ok "pinned host:port parses: $out"; else bad "pinned host:port parse: rc=$rc out=$out"; fi
out=$(PARSE_PIN=$PIN parse "$ROOT/bin/fm-pr-lib.sh" http://internal.git.local/team/repo/pulls/9); rc=$?
if [ $rc -eq 0 ] && [ "$out" = "provider=forgejo host=internal.git.local path=team/repo url=http://internal.git.local/team/repo/pulls/9 owner=team repo=repo" ]; then ok "pinned bare host parses: $out"; else bad "bare host parse: rc=$rc out=$out"; fi

note 'S2 parser adversarial: exact-match only; lookalikes, wrong shapes, malformed/empty pins refused'
for row in \
  'http://10.10.0.1:3001.evil.com/o/r/pulls/7' \
  'http://10.10.0.1:300/o/r/pulls/7' \
  'http://10.10.0.1/o/r/pulls/7' \
  'http://internal.git.local:3001/o/r/pulls/7' \
  'http://10.10.0.1:3001.evil.com:3001/o/r/pulls/7' \
  'http://elsewhere.example/o/r/pulls/7'
do
  out=$(PARSE_PIN=$PIN parse "$ROOT/bin/fm-pr-lib.sh" "$row"); rc=$?
  if [ $rc -ne 0 ]; then ok "refused lookalike $row"; else bad "accepted lookalike $row: $out"; fi
done
for pin in '' '10.10.0.1:3001.evil.com' ' http://10.10.0.1:3001' '10.10.0.1:3001:' 'http://10.10.0.1:3001,10.10.0.1:3001:'; do
  out=$(PARSE_PIN=$pin parse "$ROOT/bin/fm-pr-lib.sh" "$HTTP_URL"); rc=$?
  if [ $rc -ne 0 ]; then ok "refused with pin list '$pin'"; else bad "accepted with pin list '$pin'"; fi
done
out=$(env -u FM_PR_FORGEJO_HTTP_HOSTS bash -c '. "$1"; fm_pr_url_parse "$2"' _ "$ROOT/bin/fm-pr-lib.sh" "$HTTP_URL" 2>/dev/null); rc=$?
if [ $rc -ne 0 ]; then ok "refused with pin unset"; else bad "accepted with pin unset"; fi
out=$(PARSE_PIN=,,10.10.0.1:3001,, parse "$ROOT/bin/fm-pr-lib.sh" "$HTTP_URL"); rc=$?
if [ $rc -eq 0 ]; then ok "empty entries around the real pin do not hide it"; else bad "empty entries hid the real pin"; fi

note 'S3 https unchanged: https URL parses as before; https-with-port still refused'
out=$(PARSE_PIN=$PIN parse "$ROOT/bin/fm-pr-lib.sh" https://git.example.com/o/r/pulls/1); rc=$?
if [ $rc -eq 0 ] && [ "$out" = "provider=forgejo host=git.example.com path=o/r url=https://git.example.com/o/r/pulls/1 owner=o repo=r" ]; then ok "https URL unchanged: $out"; else bad "https URL changed: rc=$rc out=$out"; fi
out=$(PARSE_PIN=$PIN parse "$ROOT/bin/fm-pr-lib.sh" https://10.10.0.1:3001/o/r/pulls/7); rc=$?
if [ $rc -ne 0 ]; then ok "https-with-port still refused"; else bad "https-with-port accepted: $out"; fi

note 'S4 arming live: pinned http PR arms; unpinned refused as invalid; https-only login for pinned http host refused'
write_meta task-a
run_check task-a "$HTTP_URL" "$PIN" >"$LAB/arm-a.out" 2>&1; rc=$?
if [ $rc -eq 0 ]; then ok "arming pinned http PR succeeded (rc=0)"; else bad "arming pinned http PR rc=$rc: $(cat "$LAB/arm-a.out")"; fi
grep -qxF "pr=$HTTP_URL" "$CK/home/state/task-a.meta" && ok "meta records pr=$HTTP_URL" || bad "meta missing pr= line: $(grep '^pr=' "$CK/home/state/task-a.meta" 2>/dev/null)"
[ "$(sed -n 3p "$CK/home/state/task-a.pr-poll")" = "10.10.0.1:3001" ] && ok "poll sidecar carries pinned host:port" || bad "sidecar host line: $(sed -n 3p "$CK/home/state/task-a.pr-poll")"
[ -f "$CK/home/state/task-a.check.sh" ] && cmp -s "$CK/home/state/task-a.check.sh" "$ROOT/bin/fm-pr-poll.sh" && ok "watcher armed byte-for-byte from bin/fm-pr-poll.sh" || bad "watcher not armed or not byte-identical"

write_meta task-b
run_check task-b "$HTTP_URL" '' >"$LAB/arm-b.out" 2>&1; rc=$?
if [ $rc -eq 2 ] && grep -q "error: invalid PR check request" "$LAB/arm-b.out" && [ ! -e "$CK/home/state/task-b.check.sh" ]; then
  ok "empty pin: arming refused as invalid request, nothing armed"
else
  bad "empty pin arming: rc=$rc out=$(cat "$LAB/arm-b.out")"
fi

write_meta task-c
run_check task-c "$HTTP_URL" "$PIN" https://10.10.0.1:3001 >"$LAB/arm-c.out" 2>&1; rc=$?
if [ $rc -eq 1 ] && grep -q "requires exactly one 'tea login' registered for that host" "$LAB/arm-c.out" && [ ! -e "$CK/home/state/task-c.check.sh" ]; then
  ok "https-only login on pinned host:port refused, names the missing login, nothing armed"
else
  bad "https-login arming: rc=$rc out=$(cat "$LAB/arm-c.out")"
fi

note 'S5 poll live (real installed watcher): wakes only behind the pin and the pinned host'
out=$(run_poll task-a "$PIN" true); [ "$out" = merged ] && ok "poll wakes 'merged' for merged pinned http PR" || bad "poll behind pin: out='$out'"
out=$(run_poll task-a UNSET true); [ -z "$out" ] && ok "poll stays silent when the pin is absent from its environment" || bad "poll without pin: out='$out'"
out=$(run_poll task-a "$PIN" true https://elsewhere.example); [ -z "$out" ] && ok "poll stays silent when the only login is https on another host" || bad "poll through wrong login: out='$out'"
out=$(run_poll task-a "$PIN" false); [ -z "$out" ] && ok "poll stays silent for an open (unmerged) PR" || bad "poll for open PR: out='$out'"
printf '%s\n%s\n%s\n%s\n%s\n' forgejo http://10.10.0.1:9999/o/r/pulls/7 10.10.0.1:9999 o/r 7 > "$CK/home/state/task-a.pr-poll"
out=$(run_poll task-a "$PIN" true); [ -z "$out" ] && ok "doctored sidecar host:port (9999) cannot ride the 3001 pin" || bad "doctored sidecar woke: out='$out'"

note 'S6 merge live: unpinned http refused as invalid; pinned merges through the pinned http login only'
: > "$MG/tea.log"; rm -f "$MG/tea-merged" "$MG/state/task-x1.check.sh"
run_merge task-x1 "$HTTP_URL" '' >"$LAB/mg-b.out" 2>&1; rc=$?
if [ $rc -eq 2 ] && grep -q "error: invalid PR merge request" "$LAB/mg-b.out" && [ ! -e "$MG/state/task-x1.check.sh" ]; then
  ok "unpinned http merge refused as invalid, nothing armed"
else
  bad "unpinned merge: rc=$rc out=$(tail -3 "$LAB/mg-b.out")"; fi

: > "$MG/tea.log"; rm -f "$MG/tea-merged" "$MG/state/task-x1.check.sh"
grep -q '^pr=' "$MG/state/task-x1.meta" && sed -i '/^pr=/d' "$MG/state/task-x1.meta"
run_merge task-x1 "$HTTP_URL" '10.10.0.1:3001' >"$LAB/mg-a.out" 2>&1; rc=$?
if [ $rc -eq 0 ]; then ok "pinned http merge succeeded (rc=0)"; else bad "pinned merge rc=$rc: $(tail -5 "$LAB/mg-a.out")"; fi
grep -q "pr=$HTTP_URL" "$MG/state/task-x1.meta" && ok "merge recorded pr=$HTTP_URL before merging" || bad "merge did not record pr= line"
grep -q -- "--login fm-fixture --repo o/r /repos/{owner}/{repo}/pulls/7$" "$MG/tea.log" && ok "PR read through the pinned http login fm-fixture" || bad "PR read invocation: $(grep pulls/7 "$MG/tea.log" | head -2)"
grep -q -- "--login fm-fixture --repo o/r -X POST /repos/{owner}/{repo}/pulls/7/merge" "$MG/tea.log" && ok "merge POST through the pinned http login" || bad "merge invocation: $(grep '/merge' "$MG/tea.log")"
if grep -q -- '--login other' "$MG/tea.log"; then bad "unrelated 'other' login leaked into tea invocation"; else ok "unrelated https login never used"; fi

note 'SUMMARY'
if [ "$FAILURES" -eq 0 ]; then echo "ALL LIVE CHECKS PASSED"; else echo "$FAILURES LIVE CHECK(S) FAILED"; fi
exit $((FAILURES > 0))
