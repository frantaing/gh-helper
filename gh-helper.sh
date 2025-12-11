#!/usr/bin/env bash

# ---
# Welcome to gh-helper!
# A TUI for doing Github things the website won't let you do.
# ---

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Colors and Styles ---
# Github palette
COLOR_BLUE="#58a6ff"
COLOR_GREEN="#3fb950"
COLOR_RED="#f85149"
COLOR_PURPLE="#a371f7"
COLOR_BORDER="#484f58"

# --- Get the feature modules ---
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "$SCRIPT_DIR/modules/deployment_cleanup.sh"
# Add future modules here...

# --- FUNCTION: Dependency Checker ---
# Checks for required tools and offers to install them if missing.
check_dependencies() {
    local missing_deps=()
    local deps=("gh" "gum" "jq")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        gum style --border normal --border-foreground "$COLOR_RED" --padding "1 2" \
            "Warning: Required tools are missing: ${missing_deps[*]}"

        if gum confirm "Would you like to try and install them now?"; then
            # Detect package manager
            if command -v pacman &> /dev/null; then
                sudo pacman -S "${missing_deps[@]}"
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y "${missing_deps[@]}"
            elif command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y "${missing_deps[@]}"
            elif command -v brew &> /dev/null; then
                brew install "${missing_deps[@]}"
            else
                gum style --foreground "$COLOR_RED" "Could not detect a supported package manager (apt, dnf, pacman, brew)."
                echo "Please install the following manually: ${missing_deps[*]}"
                exit 1
            fi
            # Re-check after installation attempt
            check_dependencies
        else
            echo "Please install the missing dependencies to continue."
            exit 1
        fi
    fi
}

# --- FUNCTION: Welcome Screen ---
display_welcome() {
    local title
    title=$(gum style --foreground "$COLOR_BLUE" "gh-helper")

    local subtitle="A TUI for doing Github things the website won't let you do."

    gum style \
        --border double --border-foreground "$COLOR_BORDER" \
        --align center --width 50 --padding "1 2" \
        "$title" \
        "$subtitle"

    echo "" # Add a newline for spacing
}

# --- FUNCTION: Main Menu ---
display_main_menu() {
    gum style --bold "What would you like to do?"

    local choice
    choice=$(gum choose \
        "Deployment Cleanup" \
        "Actions Cache Management (coming soon)" \
        "Bulk Workflow Run Cleanup (coming soon)" \
        "Stale Branch Pruning (coming soon)" \
        "Quit" \
        --height 10 \
        --header "$header_text" \
        --cursor.foreground "$COLOR_BLUE" \
        --selected.foreground "$COLOR_BLUE")

    case "$choice" in
        "Deployment Cleanup")
            run_deployment_cleanup
            ;;
        "Actions Cache Management (coming soon)")
            gum style --foreground "$COLOR_BLUE" "This feature is planned! Check back later."
            sleep 2
            ;;
        "Bulk Workflow Run Cleanup (coming soon)")
            gum style --foreground "$COLOR_BLUE" "This feature is planned! Check back later."
            sleep 2
            ;;
        "Stale Branch Pruning (coming soon)")
            gum style --foreground "$COLOR_BLUE" "This feature is planned! Check back later."
            sleep 2
            ;;
        "Quit")
            gum style --foreground "$COLOR_GREEN" "Goodbye!"
            exit 0
            ;;
    esac
}

# --- Main ---
main() {
    clear # 1: Clear the screen first
    
    # 2: Check if all required tools are installed
    check_dependencies

    # 3: Check if the user is authenticated with gh
    # 3.5: If not, => `gh auth login`
    if ! gh auth status &>/dev/null; then
        gum style --border normal --border-foreground "$COLOR_RED" --padding "1 2" \
            "You are not authenticated with the GitHub CLI."
        if gum confirm "Would you like to run 'gh auth login' now?"; then
            gh auth login
        else
            echo "Authentication is required to use gh-helper."
            exit 1
        fi
    fi

    # 4: Show welcome screen
    display_welcome

    # 5: Loop the main menu until the user quits
    while true; do
        display_main_menu
    done
}

# Run the main function
main