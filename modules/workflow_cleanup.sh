#!/usr/bin/env bash

# --- MODULE: Bulk Workflow Run Cleanup ---
# Delete failed and cancelled workflow runs.

run_workflow_cleanup() {
    clear
    gum style --padding "1 2" --border normal --border-foreground "$COLOR_BLUE" \
        "Welcome to Bulk Workflow Run Cleanup."

    # --- 1: Get the repo ---
    local REPO_NAME
    while true; do
        REPO_NAME=$(gum input --placeholder "owner/repo" \
            --prompt.bold \
            --prompt "Enter the repository: " \
            --cursor.foreground "$COLOR_BLUE")

        if [ -z "$REPO_NAME" ]; then clear; return; fi

        if gh repo view "$REPO_NAME" &>/dev/null; then
            break
        else
            gum style --foreground "$COLOR_RED" "Error: Repository '$REPO_NAME' not found or you don't have access."
        fi
    done

    # --- 2: Fetch and Filter Runs ---
    # Target 'failure' and 'cancelled' runs specifically.
    local get_runs_cmd="gh api 'repos/$REPO_NAME/actions/runs?per_page=100' --paginate --jq '.workflow_runs[] | select(.conclusion == \"failure\" or .conclusion == \"cancelled\") | .id' 2>/dev/null || true"

    local RUN_IDS
    RUN_IDS=$(gum spin --spinner.foreground "$COLOR_BLUE" --spinner dot --title "Searching for failed/cancelled runs..." -- bash -c "$get_runs_cmd")

    if [ -z "$RUN_IDS" ]; then
        gum style --foreground "$COLOR_GREEN" "No failed or cancelled workflow runs found for '$REPO_NAME'!"
        sleep 2
        clear
        return
    fi

    local COUNT
    COUNT=$(echo "$RUN_IDS" | wc -l | xargs)

    # --- 3: Summary and Confirmation ---
    echo
    gum style --padding "0 1" --border normal --border-foreground "#f8e45c" \
        "Summary:" \
        "Found $COUNT workflow runs with status 'failed' or 'cancelled'."
    echo

    if ! gum confirm "Are you sure you want to PERMANENTLY delete these $COUNT runs?" \
        --prompt.bold \
        --prompt.foreground "" \
        --selected.background "$COLOR_BLUE" \
        --selected.foreground "#FFFFFF"; then
        clear
        return
    fi

    # --- 4: Deletion Loop ---
    clear
    gum style --bold --foreground "$COLOR_BLUE" -- "--- Deleting Workflow Runs ---"
    echo

    set +e
    local i=0
    local deleted_count=0
    
    while IFS= read -r id; do
        [ -z "$id" ] && continue
        id=$(echo "$id" | xargs)
        [ -z "$id" ] && continue

        ((i++))
        echo "$(gum style --foreground "$COLOR_BLUE" "•") Deleting run $i of $COUNT (ID: $id)..."
        
        if gh api --method DELETE "repos/$REPO_NAME/actions/runs/$id" --silent 2>/dev/null; then
            ((deleted_count++))
        else
            echo "  $(gum style --foreground "$COLOR_RED" "✖") Failed to delete ID: $id"
        fi
    done <<< "$RUN_IDS"
    set -e

    # --- 5: Success Screen ---
    echo
    local line1="✨ Process Complete! ✨"
    local line2
    line2=$(gum style --foreground "$COLOR_GREEN" "Successfully deleted $deleted_count workflow runs from '$REPO_NAME'.")

    gum style --padding "1 2" --border normal --border-foreground "$COLOR_GREEN" \
        "$line1" \
        "$line2"

    echo
    echo "(Press any key to return to the main menu.)"
    read -n 1 -s
    clear
}