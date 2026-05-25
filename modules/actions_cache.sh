#!/usr/bin/env bash

# --- MODULE: Actions Cache Management ---
# View and delete GitHub Actions caches.

run_actions_cache() {
    clear
    gum style --padding "1 2" --border normal --border-foreground "$COLOR_BLUE" \
        "Welcome to Actions Cache Management."

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

    # --- 2: Fetch Caches ---
    # Fetch ID, Key, Size, and Last Accessed time.
    local get_caches_cmd="gh api 'repos/$REPO_NAME/actions/caches?per_page=100' --paginate --jq '.actions_caches[] | {id: .id, key: .key, size: .size_in_bytes, last_accessed: .last_accessed_at}' 2>/dev/null || true"

    local CACHES_JSON
    CACHES_JSON=$(gum spin --spinner.foreground "$COLOR_BLUE" --spinner dot --title "Fetching caches for $REPO_NAME..." -- bash -c "$get_caches_cmd")

    # Check if empty
    if [ -z "$CACHES_JSON" ] || [ "$CACHES_JSON" = "null" ]; then
        gum style --foreground "$COLOR_RED" "No actions caches found for '$REPO_NAME'."
        sleep 2
        clear
        return
    fi

    # --- 3: Prepare Selection List ---
    # Use `awk`` to format bytes to human readable (MB/GB) for display
    # Produce lines like: [12345] cache-key (12.5 MB) - 2023-10-01
    local formatted_list
    formatted_list=$(echo "$CACHES_JSON" | jq -r . | jq -s . | jq -r '.[] | "\(.id)|\(.key)|\(.size)|\(.last_accessed)"' | \
    awk -F'|' 'function human(x) {
        if (x<1024) return x" B";
        x/=1024; if (x<1024) return int(x)" KB";
        x/=1024; if (x<1024) return sprintf("%.1f MB", x);
        x/=1024; return sprintf("%.1f GB", x)
    }
    { printf "[%s] %s (%s) - %s\n", $1, $2, human($3), $4 }')

    # --- 4: Select Caches to Delete ---
    echo
    gum style --bold "Select caches to delete (Space to select, Enter to confirm):"
    echo

    local selected_lines
    selected_lines=$(echo "$formatted_list" | gum choose --no-limit --height 15 \
        --cursor.foreground "$COLOR_BLUE" \
        --selected.foreground "$COLOR_BLUE")

    if [ -z "$selected_lines" ]; then
        gum style --foreground "$COLOR_BLUE" "No caches selected."
        sleep 1
        clear
        return
    fi

    # Extract IDs from the selection (format is [ID] Key...)
    local SELECTED_IDS
    SELECTED_IDS=$(echo "$selected_lines" | sed 's/^\[\([0-9]*\)\].*/\1/')
    
    local COUNT
    COUNT=$(echo "$SELECTED_IDS" | wc -l | xargs)

    # --- 5: Confirmation ---
    echo
    if ! gum confirm "You are about to delete $COUNT cache(s) from '$REPO_NAME'. This cannot be undone. Proceed?" \
        --prompt.bold \
        --prompt.foreground "" \
        --selected.background "$COLOR_BLUE" \
        --selected.foreground "#FFFFFF"; then
        clear
        return
    fi

    # --- 6: Deletion Loop ---
    clear
    gum style --bold --foreground "$COLOR_BLUE" -- "--- Deleting Caches ---"
    echo

    # !!! Temporarily disable 'set -e' so errors don't crash the script
    set +e

    local i=0
    local deleted_count=0
    
    # Read IDs line by line
    while IFS= read -r id; do
        # Skip empty lines
        [ -z "$id" ] && continue
        id=$(echo "$id" | xargs) # trim whitespace
        [ -z "$id" ] && continue

        ((i++))
        echo "$(gum style --foreground "$COLOR_BLUE" "•") Deleting cache $i of $COUNT (ID: $id)..."
        
        # Try to delete
        gh api --method DELETE "repos/$REPO_NAME/actions/caches/$id" --silent 2>/dev/null
        local delete_result=$?

        if [ $delete_result -eq 0 ]; then
            echo "  $(gum style --foreground "$COLOR_GREEN" "✔") Successfully deleted."
            ((deleted_count++))
        else
            echo "  $(gum style --foreground "$COLOR_RED" "✖") Failed to delete ID: $id"
        fi
    done <<< "$SELECTED_IDS"

    # Re-enable 'set -e'
    set -e

    # --- 7: Success Screen ---
    echo
    local line1="✨ Process Complete! ✨"
    local line2
    line2=$(gum style --foreground "$COLOR_GREEN" "Deleted $deleted_count of $COUNT caches.")

    gum style --padding "1 2" --border normal --border-foreground "$COLOR_GREEN" \
        "$line1" \
        "$line2"

    echo
    echo "(Press any key to return to the main menu.)"
    read -n 1 -s
    clear
}