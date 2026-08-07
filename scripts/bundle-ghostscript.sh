#!/usr/bin/env bash
set -euo pipefail

flavor="$1"
out_dir="$2"
api_url="${GHOSTSCRIPT_RELEASE_API:-https://api.github.com/repos/ArtifexSoftware/ghostpdl-downloads/releases/latest}"

case "${flavor}" in
    win32)
        asset_regex='^gs[0-9]+w32\.exe$'
        exe_name='gswin32c.exe'
        ;;
    win64)
        asset_regex='^gs[0-9]+w64\.exe$'
        exe_name='gswin64c.exe'
        ;;
    *)
        printf 'Unsupported Ghostscript flavor: %s\n' "${flavor}" >&2
        exit 2
        ;;
esac

work_dir="$(mktemp -d)"
release_json="${work_dir}/release.json"
installer="${work_dir}/ghostscript.exe"
extract_dir="${work_dir}/extract"

mkdir -p "${extract_dir}"

curl -fsSL \
    --retry 5 \
    --retry-delay 3 \
    --retry-connrefused \
    --retry-all-errors \
    -H "Accept: application/vnd.github+json" \
    -H "User-Agent: VirtualScannerBuilder" \
    "${api_url}" \
    -o "${release_json}"

download_url="$(
    python3 - "${release_json}" "${asset_regex}" <<'PY'
import json
import re
import sys

release_path, pattern = sys.argv[1], re.compile(sys.argv[2])
with open(release_path, "r", encoding="utf-8") as handle:
    release = json.load(handle)

for asset in release.get("assets", []):
    if pattern.match(asset.get("name", "")):
        print(asset["browser_download_url"])
        break
else:
    raise SystemExit(f"No Ghostscript asset matched {pattern.pattern}")
PY
)"

printf 'Downloading Ghostscript %s from %s\n' "${flavor}" "${download_url}"
curl -fL \
    --retry 5 \
    --retry-delay 3 \
    --retry-connrefused \
    --retry-all-errors \
    -H "User-Agent: VirtualScannerBuilder" \
    "${download_url}" \
    -o "${installer}"

7z x -y "-o${extract_dir}" "${installer}" >/dev/null

ghostscript_exe="$(find "${extract_dir}" -type f -name "${exe_name}" | head -n 1)"
if [[ -z "${ghostscript_exe}" ]]; then
    printf 'Could not find %s after extracting Ghostscript installer.\n' "${exe_name}" >&2
    find "${extract_dir}" -maxdepth 4 -type f | sort >&2
    exit 1
fi

ghostscript_root="$(cd "$(dirname "${ghostscript_exe}")/.." && pwd)"
mkdir -p "${out_dir}"
cp -a "${ghostscript_root}/." "${out_dir}/"

if [[ ! -f "${out_dir}/bin/${exe_name}" ]]; then
    printf 'Bundled Ghostscript is missing %s/bin/%s\n' "${out_dir}" "${exe_name}" >&2
    exit 1
fi

printf 'Bundled Ghostscript %s at %s\n' "${flavor}" "${out_dir}"
