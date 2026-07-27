#!/usr/bin/env bash
set -euo pipefail

repo="${1:-$HOME/dvlp/Kalaxy3}"
expected_branch="feature/kalaxy3-daux-landing-page"
expected_image_sha="b6e1fc370b51949345cf8b4cd98dca9d335fc605a0fea6f84650c5b456df4130"

cd "$repo"

branch="$(git branch --show-current)"
if [[ "$branch" != "$expected_branch" ]]; then
  printf 'ERROR: expected branch %s, found %s\n' \
    "$expected_branch" "$branch" >&2
  exit 1
fi

for path in \
  markdown/_index.md \
  markdown/config.json \
  markdown/rpi4.png
do
  if [[ ! -f "$path" ]]; then
    printf 'ERROR: required source file is missing: %s\n' "$path" >&2
    exit 1
  fi
done

if [[ -e markdown/index.md ]]; then
  echo 'ERROR: markdown/index.md still exists; expected the rename to _index.md.' >&2
  exit 1
fi

docker info >/dev/null

preview_dir="$(
  mktemp -d \
    "$HOME/Downloads/kalaxy3-daux-preview.XXXXXX"
)"

cleanup_on_failure() {
  rc=$?
  if [[ $rc -ne 0 ]]; then
    printf '\nValidation failed. Preview retained at:\n%s\n' "$preview_dir" >&2
  fi
  exit "$rc"
}
trap cleanup_on_failure EXIT

printf 'Building local Daux preview from branch %s...\n' "$branch"

docker run \
  --rm \
  --user "$(id -u):$(id -g)" \
  --env HOME=/tmp \
  --volume "$PWD:/build:ro" \
  --volume "$preview_dir:/preview" \
  --workdir /build \
  --entrypoint /bin/sh \
  daux/daux.io:latest \
  -lc '
    /daux/bin/daux generate \
      -s markdown \
      -d /preview
  '

index="$preview_dir/index.html"
test -f "$index"

image_path="$(
  find "$preview_dir" \
    -type f \
    -name rpi4.png \
    -print \
    -quit
)"
test -n "$image_path"

grep -Fq \
  'Kalaxy3 K3s Cluster' \
  "$index"

grep -Fq \
  'ARM64 and AMD64 homelab architecture, operations, and evidence' \
  "$index"

grep -Fq \
  'Kalaxy3 is a K3s-based homelab platform' \
  "$index"

grep -Fq \
  'rpi4.png' \
  "$index"

actual_image_sha="$(
  shasum -a 256 "$image_path" |
  awk '{print $1}'
)"

if [[ "$actual_image_sha" != "$expected_image_sha" ]]; then
  printf 'ERROR: generated image checksum mismatch\n' >&2
  printf 'expected=%s\nactual=%s\n' \
    "$expected_image_sha" "$actual_image_sha" >&2
  exit 1
fi

printf '\nLocal Daux validation: PASS\n'
printf 'branch=%s\n' "$branch"
printf 'preview=%s\n' "$preview_dir"
printf 'index=%s\n' "$index"
printf 'image=%s\n' "$image_path"
printf 'image_sha256=%s\n' "$actual_image_sha"

printf '\nRepository status:\n'
git status --short

trap - EXIT
open "$index"
