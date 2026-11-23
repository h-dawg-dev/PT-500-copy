#!/usr/bin/env bash
set -euo pipefail

: "${HEROKU_API_KEY:?Missing GitHub Actions secret HEROKU_API_KEY}"
: "${HEROKU_APP_NAME:?Missing Heroku app name}"
: "${HEROKU_APP_URL:?Missing Heroku app URL}"
: "${GITHUB_SHA:?Missing checked commit}"
: "${GITHUB_REF_NAME:?Missing deployment branch}"

case "$GITHUB_REF_NAME:$HEROKU_APP_NAME" in
  dev:tlind-pts-dev|main:tlind-pts) ;;
  *) echo 'Refusing deployment: branch and Heroku app do not match.' >&2; exit 1 ;;
esac

latest_commit=$(git ls-remote origin "refs/heads/$GITHUB_REF_NAME" | cut -f1)
if [[ "$latest_commit" != "$GITHUB_SHA" ]]; then
  echo "Skipping superseded commit $GITHUB_SHA on $GITHUB_REF_NAME."
  exit 0
fi

askpass=$(mktemp)
trap 'rm -f "$askpass"' EXIT
cat > "$askpass" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' heroku ;;
  *Password*) printf '%s\n' "$HEROKU_API_KEY" ;;
  *) exit 1 ;;
esac
ASKPASS
chmod 700 "$askpass"
export GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0

# Push precisely the commit that passed CI, rather than a moving branch name.
git -c credential.helper= push "https://git.heroku.com/$HEROKU_APP_NAME.git" "$GITHUB_SHA:refs/heads/main"

heroku_api() {
  local resource="$1"
  shift
  curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
    -H "Authorization: Bearer $HEROKU_API_KEY" \
    -H 'Accept: application/vnd.heroku+json; version=3' \
    "$@" "https://api.heroku.com/apps/$HEROKU_APP_NAME/$resource"
}

# A successful Git build can still have a failed migration/release command.
released=false
for ((attempt=1; attempt<=60; attempt++)); do
  release=$(heroku_api releases -H 'Range: version ..; max=1, order=desc' | jq -c '.[0]')
  slug_id=$(jq -r '.slug.id // empty' <<< "$release")
  if [[ -n "$slug_id" ]]; then
    commit=$(heroku_api "slugs/$slug_id" | jq -r '.commit')
    if [[ "$commit" == "$GITHUB_SHA" ]]; then
      status=$(jq -r '.status' <<< "$release")
      case "$status" in
        failed|expired) echo "Heroku release failed for $GITHUB_SHA." >&2; exit 1 ;;
        succeeded)
          if [[ $(jq -r '.current' <<< "$release") == true ]]; then
            echo "Heroku release v$(jq -r '.version' <<< "$release") is active for $GITHUB_SHA."
            released=true
            break
          fi ;;
      esac
    fi
  fi
  sleep 5
done
if [[ "$released" != true ]]; then
  echo "Timed out waiting for $GITHUB_SHA to become the active release." >&2
  exit 1
fi

version=$(tr -d '\r\n' < VERSION)
for ((attempt=1; attempt<=24; attempt++)); do
  if curl --fail --silent --show-error --connect-timeout 10 --max-time 20 "$HEROKU_APP_URL/up" > /dev/null && \
     page=$(curl --fail --silent --show-error --connect-timeout 10 --max-time 20 "$HEROKU_APP_URL/") && \
     grep -Fq "data-app-version=\"$version\"" <<< "$page"; then
    echo "$HEROKU_APP_NAME is healthy and serving version $version."
    exit 0
  fi
  sleep 5
done
echo "Health/version check failed for $HEROKU_APP_NAME (expected $version)." >&2
exit 1
