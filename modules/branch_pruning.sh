#!/usr/bin/env bash

# --- MODULE: Stale Branch Pruning ---
# Finds and deletes branches that haven't been updated recently.

run_branch_pruning() {
    clear
    gum style --padding "1 2" --border normal --border-foreground "$COLOR_BLUE" \
        "Welcome to Stale Branch Pruning."

    # --- 1: Get the repo ---
    local REPO_NAME
    while true; do
        REPO_NAME=$(gum input --placeholder "owner/repo" \
            --prompt.bold \
            --prompt "Enter the repository: " \
            --cursor.foreground "$COLOR_BLUE")

        if[ -z "$REPO_NAME" ]; then clear; return; fi

        if gh repo view "$REPO_NAME" &>/dev/null; then
            break
        else
            gum style --foreground "$COLOR_RED" "Error: Repository '$REPO_NAME' not found or you don't have access."
        fi
    done

    # --- 2: Ask for staleness threshold ---
    local THRESHOLD_DAYS
    while true; do
        THRESHOLD_DAYS=$(gum input --placeholder "90" \
            --value "90" \
            --prompt.bold \
            --prompt "Enter staleness threshold in days: " \
            --cursor.foreground "$COLOR_BLUE")

        if [ -z "$THRESHOLD_DAYS" ]; then clear; return; fi

        # Validate that the input is a positive integer
        if [[ "$THRESHOLD_DAYS" =~ ^[0-9]+$ ]] && [ "$THRESHOLD_DAYS" -gt 0 ]; then
            break
        else
            gum style --foreground "$COLOR_RED" "Please enter a valid positive integer."
        fi
    done

    # Calculate the cutoff date in secs since the unix upoch
    local current_epoch=$(date +%s)
    local threshold_seconds=$((THRESHOLD_DAYS * 86400))
    local cutoff_epoch=$((current_epoch - threshold_seconds))

    # --- 3: Fetch data & calculate staleness ---
    echo
    gum style --foreground "$COLOR_BORDER" "Scanning branches... (This may take a moment for large repositories)"
    
    # Build an inline script for the spinner to execute. 
    # Escape variables like \$branch so they run inside the spinner, 
    # BUT let $REPO_NAME and $cutoff_epoch evaluate immediately.
    local fetch_script=$(cat <<EOF
    # Get the default branch so we don't accidentally suggest deleting it
    DEFAULT_BRANCH=\$(gh repo view "$REPO_NAME" --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null)
    
    # Get all branches
    BRANCHES=\$(gh api "repos/$REPO_NAME/branches?per_page=100" --paginate --jq '.[].name' 2>/dev/null)

    if [ -z "\$BRANCHES" ]; then
        exit 0
    fi

    for branch in \$BRANCHES; do
        # Skip the default branch
        if [ "\$branch" = "\$DEFAULT_BRANCH" ]; then
            continue
        fi

        # Fetch the date of the last commit for this branch
        commit_date=\$(gh api "repos/$REPO_NAME/commits/\$branch" --jq '.commit.committer.date' 2>/dev/null)
        [ -z "\$commit_date" ] && continue

        # Convert the GitHub ISO 8601 date string to Unix Epoch seconds
        commit_epoch=\$(date -d "\$commit_date" +%s 2>/dev/null || echo 0)

        # Check if the commit is older than our cutoff date
        if [ "\$commit_epoch" -lt "$cutoff_epoch" ] &&[ "\$commit_epoch" -gt 0 ]; then
            diff_seconds=\$(( $current_epoch - commit_epoch ))
            days_ago=\$(( diff_seconds / 86400 ))
            # Output format: branch_name|days_ago|actual_date
            echo "\$branch|\$days_ago|\$commit_date"
        fi
    done
EOF
    )

    local STALE_BRANCHES
    STALE_BRANCHES=$(gum spin --spinner.foreground "$COLOR_BLUE" --spinner dot --title "Analyzing branch ages..." -- bash -c "$fetch_script")

    if [ -z "$STALE_BRANCHES" ]; then
        gum style --foreground "$COLOR_GREEN" "Nice! No branches older than $THRESHOLD_DAYS days found in '$REPO_NAME'."
        sleep 3
        clear
        return
    fi

    # --- 4: Present list for selection ---
    local formatted_list
    formatted_list=$(echo "$STALE_BRANCHES" | awk -F'|' '{ printf "[%s] last updated %s days ago (%s)\n", $1, $2, $3 }')

    echo
    gum style --bold "Select stale branches to delete:"
    gum style --foreground "$COLOR_BORDER" "(Space to select, 'a' to select all, Enter to confirm)"
    echo

    local selected_lines
    selected_lines=$(echo "$formatted_list" | gum choose --no-limit --height 15 \
        --cursor.foreground "$COLOR_BLUE" \
        --selected.foreground "$COLOR_BLUE")

    if [ -z "$selected_lines" ]; then
        gum style --foreground "$COLOR_BLUE" "No branches selected."
        sleep 2
        clear
        return
    fi

    # Extract just the branch names from the selection (format: [branch_name] last updated...)
    local SELECTED_BRANCHES
    SELECTED_BRANCHES=$(echo "$selected_lines" | sed 's/^\[\(.*\)\] last updated.*/\1/')
    
    local COUNT
    COUNT=$(echo "$SELECTED_BRANCHES" | grep -c . || echo "0")

    # --- 5: Confirm deletion ---
    echo
    if ! gum confirm "You are about to PERMANENTLY delete $COUNT branch(es) from '$REPO_NAME'. Proceed?" \
        --prompt.bold \
        --prompt.foreground "" \
        --selected.background "$COLOR_BLUE" \
        --selected.foreground "#FFFFFF"; then
        clear
        return
    fi

    # --- 6: Deletion loop ---
    clear
    gum style --bold --foreground "$COLOR_BLUE" -- "--- Deleting Branches ---"
    echo

    set +e
    local i=0
    local deleted_count=0

    while IFS= read -r branch; do
        [ -z "$branch" ] && continue
        branch=$(echo "$branch" | xargs)
        [ -z "$branch" ] && continue

        ((i++))
        echo "$(gum style --foreground "$COLOR_BLUE" "•") Deleting branch $i of $COUNT ($branch)..."
        
        # Use the specific git/refs/heads endpoint to delete the branch
        if gh api --method DELETE "repos/$REPO_NAME/git/refs/heads/$branch" --silent 2>/dev/null; then
            echo "  $(gum style --foreground "$COLOR_GREEN" "✔") Successfully deleted."
            ((deleted_count++))
        else
            echo "  $(gum style --foreground "$COLOR_RED" "✖") Failed to delete branch: $branch"
        fi
    done <<< "$SELECTED_BRANCHES"
    set -e

    # --- 7: SUCCESS! ---
    echo
    local line1="✨ Process Complete! ✨"
    local line2
    line2=$(gum style --foreground "$COLOR_GREEN" "Deleted $deleted_count of $COUNT stale branches from '$REPO_NAME'.")

    gum style --padding "1 2" --border normal --border-foreground "$COLOR_GREEN" \
        "$line1" \
        "$line2"

    echo
    echo "(Press any key to return to the main menu.)"
    read -n 1 -s
    clear
}