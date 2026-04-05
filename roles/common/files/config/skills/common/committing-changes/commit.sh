#!/bin/bash
#
# commit.sh - Create a git commit with specified files and message
#
# Usage:
#   commit.sh -m "message" file1 file2 ...
#   commit.sh --force -m "message" file1 file2 ...
#
# This script creates commits WITHOUT any AI co-author attribution.
# Commits appear as if authored solely by the user.
#
# Arguments:
#   -m, --message    Commit message (required)
#   -f, --force      Force-add files that match .gitignore patterns
#   file1 file2 ...  Files to stage and commit (at least one required)
#
# Example:
#   commit.sh -m "Add user authentication" src/auth.ts src/login.tsx
#   commit.sh --force -m "Add design doc" docs/spec.md

set -e

message=""
files=()
force=false

# Parse arguments
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
        -f|--force)
            force=true
            shift
            ;;
        -h|--help)
            echo "Usage: commit.sh [-f|--force] -m \"message\" file1 file2 ..."
            echo ""
            echo "Create a git commit with specified files and message."
            echo "No AI co-author attribution is added."
            echo ""
            echo "Arguments:"
            echo "  -m, --message    Commit message (required)"
            echo "  -f, --force      Force-add files that match .gitignore patterns"
            echo "  file1 file2 ...  Files to stage and commit (at least one required)"
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

# Validate inputs
if [[ -z "$message" ]]; then
    echo "Error: Commit message is required (-m \"message\")" >&2
    exit 1
fi

if [[ ${#files[@]} -eq 0 ]]; then
    echo "Error: At least one file must be specified" >&2
    exit 1
fi

# Verify we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not in a git repository" >&2
    exit 1
fi

# Verify all files exist, are tracked, or have staged changes
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

# Pre-check: identify gitignored files
ignored_files=()
for file in "${files[@]}"; do
    if [[ -e "$file" ]] && git check-ignore -q "$file" 2>/dev/null; then
        ignored_files+=("$file")
    fi
done

# If gitignored files found without --force, fail with helpful message
if [[ ${#ignored_files[@]} -gt 0 && "$force" == "false" ]]; then
    echo "Error: The following files are gitignored and cannot be staged without --force:" >&2
    for f in "${ignored_files[@]}"; do
        echo "  $f" >&2
    done
    echo "" >&2
    echo "Use --force (-f) to commit these files anyway:" >&2
    echo "  commit.sh --force -m \"message\" file1 file2 ..." >&2
    exit 1
fi

# Stage the specified files
for file in "${files[@]}"; do
    if [[ -e "$file" ]]; then
        if [[ "$force" == "true" ]] && git check-ignore -q "$file" 2>/dev/null; then
            git add --force -- "$file"
        else
            git add -- "$file"
        fi
    else
        git rm -- "$file" 2>/dev/null || true
    fi
done

# Create the commit (no co-author attribution)
git commit -m "$message"

# Push to remote
if ! git push 2>&1; then
    echo ""
    echo "Warning: Commit created but push failed. You may need to push manually." >&2
    echo ""
    echo "Commit created (not pushed):"
    git log --oneline -n 1
    exit 1
fi

# Show the result
echo ""
echo "Commit created and pushed:"
git log --oneline -n 1
