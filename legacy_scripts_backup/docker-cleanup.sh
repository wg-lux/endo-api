#!/usr/bin/env bash
# Docker Storage Cleanup Script - Comprehensive cleanup for storage issues
set -e

echo "=========================================="
echo "  Docker Storage Cleanup Utility"
echo "=========================================="
echo ""

# Show current storage usage
echo "📊 CURRENT DOCKER STORAGE USAGE:"
echo ""
docker system df
echo ""

# Count images by type
TOTAL_IMAGES=$(docker images -q | wc -l)
DANGLING_IMAGES=$(docker images -f "dangling=true" -q | wc -l)
TAGGED_IMAGES=$((TOTAL_IMAGES - DANGLING_IMAGES))

echo "📈 IMAGE BREAKDOWN:"
echo "  Total Images: $TOTAL_IMAGES"
echo "  Tagged Images: $TAGGED_IMAGES"
echo "  Dangling Images (<none>): $DANGLING_IMAGES"
echo ""

# Show largest images
echo "🔍 LARGEST IMAGES (Top 10):"
docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" | head -11
echo ""

# Interactive cleanup options
echo "🧹 CLEANUP OPTIONS:"
echo ""

read -p "❓ Remove all dangling images (<none> tags)? This is safe and frees up space. [y/N]: " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️ Removing dangling images..."
    if [ $DANGLING_IMAGES -gt 0 ]; then
        docker image prune -f
        echo "✅ Removed $DANGLING_IMAGES dangling images"
    else
        echo "✅ No dangling images to remove"
    fi
    echo ""
fi

read -p "❓ Remove unused images (not referenced by any container)? [y/N]: " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️ Removing unused images..."
    docker image prune -a -f
    echo "✅ Removed unused images"
    echo ""
fi

read -p "❓ Clean up build cache? This is safe and can free significant space. [y/N]: " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️ Removing build cache..."
    docker builder prune -f
    echo "✅ Removed build cache"
    echo ""
fi

# Show specific project images
echo "🏷️ PROJECT-SPECIFIC IMAGES:"
echo ""
echo "EndoReg API images:"
docker images | grep -E "(endo-api|endoreg)" || echo "  No EndoReg images found"
echo ""

echo "Other project images:"
docker images | grep -E "(lx-|annotate)" || echo "  No other project images found"
echo ""

# Advanced cleanup options
echo "🚨 ADVANCED CLEANUP OPTIONS (BE CAREFUL!):"
echo ""

read -p "❓ Remove ALL stopped containers? [y/N]: " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️ Removing stopped containers..."
    docker container prune -f
    echo "✅ Removed stopped containers"
    echo ""
fi

read -p "❓ Remove unused volumes? [y/N]: " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️ Removing unused volumes..."
    docker volume prune -f
    echo "✅ Removed unused volumes"
    echo ""
fi

read -p "❓ Remove unused networks? [y/N]: " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️ Removing unused networks..."
    docker network prune -f
    echo "✅ Removed unused networks"
    echo ""
fi

# Nuclear option
echo ""
read -p "🚨 NUCLEAR OPTION: Remove ALL images except base images (nixos/nix, python)? This will require rebuilding everything! [y/N]: " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "☢️ Removing all project images except base images..."
    
    # Keep essential base images
    docker images | grep -v -E "(nixos/nix|python|ubuntu|alpine)" | grep -v "REPOSITORY" | awk '{print $3}' | xargs -r docker rmi -f || echo "Some images couldn't be removed (in use)"
    
    echo "✅ Nuclear cleanup completed"
    echo ""
fi

# Show final storage usage
echo "📊 FINAL DOCKER STORAGE USAGE:"
echo ""
docker system df
echo ""

# Calculate space saved
echo "💾 SPACE CLEANUP SUMMARY:"
echo "Check the difference in 'RECLAIMABLE' space above"
echo ""

# Maintenance recommendations
echo "🔧 MAINTENANCE RECOMMENDATIONS:"
echo ""
echo "• Run 'docker system prune -f' regularly to remove dangling images"
echo "• Use 'docker image ls' to check for large unused images"
echo "• Consider using 'docker system df' to monitor storage usage"
echo "• For this project, keep only the current working images:"
echo "  - nixos/nix:2.18.1 (base image)"
echo "  - endo-api:dev (current development image)"
echo "  - endo-api:prod (when built)"
echo ""

# Quick maintenance command
echo "💡 QUICK CLEANUP COMMAND (for future use):"
echo "docker system prune -f && docker image prune -f && docker builder prune -f"
echo ""
echo "=========================================="
