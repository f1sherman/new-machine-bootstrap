#!/bin/bash
#
# commit.sh - Create a git commit with specified files and message
#
# Usage:
#   commit.sh -m "message" file1 file2 ...

set -e

message=""
files=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--message)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: --message requires a value" >&2
                exit 1
            fi
            message="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: commit.sh -m \"message\" file1 file2 ..."
            exit 0
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;
        *)
            files+=("$1")
            shift
            ;;
    esac
done

if [[ -z "$message" ]]; then
    echo "Error: Commit message is required (-m \"message\")" >&2
    exit 1
fi

if [[ ${#files[@]} -eq 0 ]]; then
    echo "Error: At least one file must be specified" >&2
    exit 1
fi

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository" >&2
    exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
normalized_requested_paths=()

for file in "${files[@]}"; do
    if [[ -e "$file" ]]; then
        file_dir="$(cd "$(dirname "$file")" && pwd -P)"
        file_name="$(basename "$file")"
        absolute_path="$file_dir/$file_name"
        case "$absolute_path" in
            "$repo_root"/*)
                normalized_requested_paths+=("${absolute_path#"$repo_root"/}")
                ;;
            "$repo_root")
                normalized_requested_paths+=(".")
                ;;
            *)
                echo "Error: File is outside repository: $file" >&2
                exit 1
                ;;
        esac
    elif git ls-files --error-unmatch "$file" > /dev/null 2>&1; then
        while IFS= read -r tracked_path; do
            normalized_requested_paths+=("$tracked_path")
        done < <(git ls-files --full-name -- "$file")
    else
        normalized_requested_paths+=("${file#./}")
    fi
done

for requested_path in "${normalized_requested_paths[@]}"; do
    if [[ "$requested_path" == "." ]]; then
        echo "Error: Refusing to commit the repository root; pass explicit files instead." >&2
        exit 1
    fi
done

reject_unrequested_staged_files() {
    local staged_file
    local requested_path
    local allowed
    local unexpected_staged_files=()

    while IFS= read -r staged_file; do
        allowed=false
        for requested_path in "${normalized_requested_paths[@]}"; do
            requested_path="${requested_path%/}"
            if [[ "$staged_file" == "$requested_path" || "$staged_file" == "$requested_path/"* ]]; then
                allowed=true
                break
            fi
        done
        if [[ "$allowed" == "false" ]]; then
            unexpected_staged_files+=("$staged_file")
        fi
    done < <(git diff --cached --name-only)

    if [[ ${#unexpected_staged_files[@]} -gt 0 ]]; then
        echo "Error: Refusing to commit staged files outside the requested path list:" >&2
        for staged_file in "${unexpected_staged_files[@]}"; do
            echo "  $staged_file" >&2
        done
        exit 1
    fi
}

for file in "${files[@]}"; do
    if [[ -e "$file" ]]; then
        continue
    fi
    if git ls-files --error-unmatch "$file" > /dev/null 2>&1; then
        continue
    fi
    if git diff --cached --name-only -- "$file" | grep -q .; then
        continue
    fi
    echo "Error: File does not exist and is not tracked by git: $file" >&2
    exit 1
done

ignored_files=()
for file in "${files[@]}"; do
    if [[ -e "$file" ]] && git check-ignore -q "$file" 2>/dev/null; then
        ignored_files+=("$file")
    fi
done

if [[ ${#ignored_files[@]} -gt 0 ]]; then
    echo "Error: The following files are gitignored and cannot be staged:" >&2
    for file in "${ignored_files[@]}"; do
        echo "  $file" >&2
    done
    exit 1
fi

reject_unrequested_staged_files

for file in "${files[@]}"; do
    if [[ -e "$file" ]]; then
        git add -- "$file"
    else
        git rm -- "$file" 2>/dev/null || true
    fi
done

reject_unrequested_staged_files

git commit -m "$message"

echo ""
echo "Commit created:"
git log --oneline -n 1
