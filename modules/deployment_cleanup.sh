#!/usr/bin/env bash

# --- MODULE: Deployment Cleanup ---
# => The deployment cleanup feature.

run_deployment_cleanup() {
    gum spin --spinner dot --title "Launching Deployment Cleanup..." -- sleep 1

    clear # Clear the screen when running module

    # Logic
    gum style --padding "1 2" --border normal --border-foreground "$COLOR_BLUE" \
        "Welcome to the Deployment Cleanup Module." \
        "Here, we will ask for the repo and environment to clean."

    echo
    echo "(This feature is under construction. Press any key to return to the menu.)"
    read -n 1 -s # Silent keypress
    
    clear # Clear the screen when exiting
}