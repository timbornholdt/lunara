#!/bin/bash
# Run this from the repo root (the folder containing Lunara.xcodeproj)
# Usage: chmod +x scaffold.sh && ./scaffold.sh

set -e

SRC="Lunara"

# Create directory structure
mkdir -p "$SRC/App"
mkdir -p "$SRC/Shared/Models"
mkdir -p "$SRC/Shared/Errors"
mkdir -p "$SRC/Library/Auth"
mkdir -p "$SRC/Library/API"
mkdir -p "$SRC/Library/Store"
mkdir -p "$SRC/Library/Repo"
mkdir -p "$SRC/Library/Artwork"
mkdir -p "$SRC/Music/Engine"
mkdir -p "$SRC/Music/Queue"
mkdir -p "$SRC/Music/NowPlaying"
mkdir -p "$SRC/Music/Session"
mkdir -p "$SRC/Router"
mkdir -p "$SRC/Views/Library"
mkdir -p "$SRC/Views/Album"
mkdir -p "$SRC/Views/Artist"
mkdir -p "$SRC/Views/Collection"
mkdir -p "$SRC/Views/NowPlaying"
mkdir -p "$SRC/Views/Settings"
mkdir -p "$SRC/Views/Components"
mkdir -p "$SRC/Resources/Fonts"

echo "✓ Directories created"

# Move AGENTS.md files into place (if they exist at the output paths from Claude)
# If you already have the AGENTS.md files downloaded, place them in the repo root
# and this section will move them. Otherwise, skip — you can drop them in manually.

# Create placeholder .gitkeep files so empty directories are tracked by git
find "$SRC" -type d -empty -exec touch {}/.gitkeep \;

echo "✓ .gitkeep files added to empty directories"
echo ""
echo "Done. Directory structure:"
find "$SRC" -type f | sort
echo ""
echo "Next steps:"
echo "  1. Drop the per-directory AGENTS.md files into:"
echo "     $SRC/Shared/AGENTS.md"
echo "     $SRC/Library/AGENTS.md"
echo "     $SRC/Music/AGENTS.md"
echo "     $SRC/Router/AGENTS.md"
echo "     $SRC/Views/AGENTS.md"
echo "  2. Make sure root AGENTS.md and README.md are in the repo root (next to Lunara.xcodeproj)"
echo "  3. In Xcode, add the new folder groups to your project if they don't appear automatically"
