#!/bin/bash
#
# commit.sh - Create a git commit with specified files and message
#
# Usage:
#   commit.sh -m "message" file1 file2 ...
#   commit.sh --message "message" file1 file2 ...
#
# This script creates commits WITHOUT any AI co-author attribution.
# Commits appear as if authored solely by the user.
#
# Arguments:
#   -m, --message    Commit message (required)
#   file1 file2 ...  Files to stage and commit (at least one required)
#
# Example:
#   commit.sh -m "Add user authentication" src/auth.ts src/login.tsx

set -e

message=""
files=()

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
        -h|--help)
            echo "Usage: commit.sh -m \"message\" file1 file2 ..."
            echo ""
            echo "Create a git commit with specified files and message."
            echo "No AI co-author attribution is added."
            echo ""
            echo "Arguments:"
            echo "  -m, --message    Commit message (required)"
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

# Verify all files exist or are tracked
for file in "${files[@]}"; do
    if [[ ! -e "$file" ]] && ! git ls-files --error-unmatch "$file" > /dev/null 2>&1; then
        echo "Error: File does not exist: $file" >&2
        exit 1
    fi
done

# Stage the specified files
git add "${files[@]}"

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
