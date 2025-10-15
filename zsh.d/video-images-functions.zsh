# CleanShot file processor function
process_cleanshot() {
    local folder_name="$1"

    # Check if folder name is provided
    if [[ -z "$folder_name" ]]; then
        echo "Usage: process_cleanshot <folder_name>"
        echo "Example: process_cleanshot my_project"
        return 1
    fi

    # Get current date
    local current_year=$(date +%Y)
    local current_month=$(date +%m)
    local current_date=$(date +%d)

    # Create folder if it doesn't exist
    if [[ ! -d "$folder_name" ]]; then
        echo "📁 Creating folder: $folder_name"
        mkdir -p "$folder_name"
    fi

    echo "Processing CleanShot files from $(date +%Y-%m-%d) into folder: $folder_name"

    # Find all matching files using array and proper globbing
    local found_files=false

    # Enable nullglob to handle case where no files match
    setopt NULL_GLOB

    # Create arrays for different file types
    local png_files=(CleanShot\ ${current_year}-${current_month}-${current_date}\ at\ *.png)
    local mp4_files=(CleanShot\ ${current_year}-${current_month}-${current_date}\ at\ *.mp4)

    # Process PNG files
    for file in "${png_files[@]}"; do
        if [[ -f "$file" ]]; then
            found_files=true
            echo "📸 Processing PNG: $file"

            # Get image dimensions using identify (ImageMagick)
            if command -v identify >/dev/null 2>&1; then
                local dimensions=$(identify -format "%wx%h" "$file" 2>/dev/null)
                local width=$(echo "$dimensions" | cut -d'x' -f1)
                local height=$(echo "$dimensions" | cut -d'x' -f2)

                echo "   Dimensions: ${width}x${height}"

                # Function to check if dimension is within tolerance (±25%)
                local within_tolerance() {
                    local actual=$1
                    local target=$2
                    local tolerance=25  # 25% tolerance

                    local min_val=$((target * (100 - tolerance) / 100))
                    local max_val=$((target * (100 + tolerance) / 100))

                    [[ $actual -ge $min_val && $actual -le $max_val ]]
                }

                # Check dimensions and rename accordingly (with tolerance)
                if (within_tolerance $width 944 && within_tolerance $height 1844) || (within_tolerance $width 1844 && within_tolerance $height 944); then
                    echo "   → Moving to $folder_name/medium.png (matches 944x1844 ±25%)"
                    mv "$file" "$folder_name/medium.png"
                elif (within_tolerance $width 842 && within_tolerance $height 1336) || (within_tolerance $width 1336 && within_tolerance $height 842); then
                    echo "   → Moving to $folder_name/tablet.png (matches 842x1336 ±25%)"
                    mv "$file" "$folder_name/small.png"
                elif (within_tolerance $width 2682 && within_tolerance $height 1656) || (within_tolerance $width 1656 && within_tolerance $height 2682); then
                    echo "   → Moving to $folder_name/tablet.png (matches 2682x1656 ±25%)"
                    mv "$file" "$folder_name/tablet.png"
                else
                    # Use original filename without the CleanShot prefix
                    local clean_name=$(echo "$file" | sed 's/CleanShot [0-9-]* at //')
                    echo "   → Moving to $folder_name/$clean_name (no matching dimensions)"
                    mv "$file" "$folder_name/$clean_name"
                fi
            else
                echo "   ⚠️  ImageMagick not found, using original name"
                local clean_name=$(echo "$file" | sed 's/CleanShot [0-9-]* at //')
                mv "$file" "$folder_name/$clean_name"
            fi
        fi
    done

    # Process MP4 files
    for file in "${mp4_files[@]}"; do
        if [[ -f "$file" ]]; then
            found_files=true
            echo "🎥 Processing MP4: $file"
            echo "   → Moving to $folder_name/video.mp4"
            mv "$file" "$folder_name/video.mp4"
        fi
    done

    # Restore nullglob setting
    unsetopt NULL_GLOB

    if [[ "$found_files" = false ]]; then
        echo "No CleanShot files found for today ($(date +%Y-%m-%d))"
        return 0
    fi

    echo ""
    echo "🔧 Running PNG compression on files in $folder_name..."

    # Modified png_compress_all_overwrite function without confirmation
    local png_compress_auto() {
        local target_dir="$1"

        # Change to target directory
        pushd "$target_dir" >/dev/null 2>&1

        local png_files=(*.png)

        if [ ${#png_files[@]} -eq 0 ] || [ ! -f "${png_files[0]}" ]; then
            echo "No PNG files found in $target_dir"
            popd >/dev/null 2>&1
            return 1
        fi

        echo "Found ${#png_files[@]} PNG file(s) to compress (will overwrite originals)..."

        local processed=0
        local skipped=0

        for file in "${png_files[@]}"; do
            echo "🔄 Processing: $file"

            if pngquant --speed 1 --skip-if-larger --ext .png --force "$file" 2>/dev/null; then
                echo "✅ Compressed: $file (overwritten)"
                ((processed++))
            else
                echo "⚠️  Skipped: $file (no reduction possible or error)"
                ((skipped++))
            fi
        done

        echo "📊 Summary: $processed compressed, $skipped skipped"

        # Return to original directory
        popd >/dev/null 2>&1
    }

    # Run PNG compression
    png_compress_auto "$folder_name"

    # Modified compress_mp4_github function without confirmation and preserving original name
    local compress_mp4_github_auto() {
        local input="$1"

        if [ ! -f "$input" ]; then
            echo "Error: Input file '$input' not found"
            return 1
        fi

        local temp_output="${input%.*}_temp_compressed.mp4"

        echo "Compressing $input (maximum compression for GitHub)..."

        ffmpeg -i "$input" \
            -c:v libx264 \
            -preset veryslow \
            -crf 28 \
            -c:a aac \
            -b:a 64k \
            -ac 1 \
            -ar 22050 \
            -vf "scale=640:-2" \
            -r 15 \
            -movflags +faststart \
            -f mp4 \
            "$temp_output" 2>/dev/null

        if [ $? -eq 0 ]; then
            local original_size=$(stat -f%z "$input" 2>/dev/null || stat -c%s "$input" 2>/dev/null)
            local compressed_size=$(stat -f%z "$temp_output" 2>/dev/null || stat -c%s "$temp_output" 2>/dev/null)
            local reduction=$((100 - (compressed_size * 100 / original_size)))

            # Replace original with compressed version
            mv "$temp_output" "$input"

            echo "✅ Compression complete!"
            echo "Original size: $(numfmt --to=iec $original_size)B"
            echo "Compressed size: $(numfmt --to=iec $compressed_size)B"
            echo "Size reduction: ${reduction}%"
        else
            echo "❌ Compression failed"
            # Clean up temp file if it exists
            [ -f "$temp_output" ] && rm "$temp_output"
            return 1
        fi
    }

    # Compress video files if any exist
    if [[ -f "$folder_name/video.mp4" ]]; then
        echo ""
        echo "🎬 Compressing video.mp4..."
        compress_mp4_github_auto "$folder_name/video.mp4"
    fi

    echo ""
    echo "🎉 Processing complete! All files are now in the '$folder_name' folder."
}

# MP4 compression function for GitHub (maximum compression)
compress_mp4_github() {
    if [ $# -eq 0 ]; then
        echo "Usage: compress_mp4_github <input.mp4> [output.mp4]"
        echo "If no output name provided, will use input_compressed.mp4"
        return 1
    fi

    local input="$1"
    local output="${2:-${1%.*}_compressed.mp4}"

    if [ ! -f "$input" ]; then
        echo "Error: Input file '$input' not found"
        return 1
    fi

    echo "Compressing $input to $output (maximum compression for GitHub)..."

    ffmpeg -i "$input" \
        -c:v libx264 \
        -preset veryslow \
        -crf 28 \
        -c:a aac \
        -b:a 64k \
        -ac 1 \
        -ar 22050 \
        -vf "scale=640:-2" \
        -r 15 \
        -movflags +faststart \
        -f mp4 \
        "$output"

    if [ $? -eq 0 ]; then
        local original_size=$(stat -f%z "$input" 2>/dev/null || stat -c%s "$input" 2>/dev/null)
        local compressed_size=$(stat -f%z "$output" 2>/dev/null || stat -c%s "$output" 2>/dev/null)
        local reduction=$((100 - (compressed_size * 100 / original_size)))

        echo "✅ Compression complete!"
        echo "Original size: $(numfmt --to=iec $original_size)B"
        echo "Compressed size: $(numfmt --to=iec $compressed_size)B"
        echo "Size reduction: ${reduction}%"
    else
        echo "❌ Compression failed"
        return 1
    fi
}

# Alternative function with balanced quality/size for when extreme compression isn't needed
compress_mp4_balanced() {
    if [ $# -eq 0 ]; then
        echo "Usage: compress_mp4_balanced <input.mp4> [output.mp4]"
        return 1
    fi

    local input="$1"
    local output="${2:-${1%.*}_balanced.mp4}"

    if [ ! -f "$input" ]; then
        echo "Error: Input file '$input' not found"
        return 1
    fi

    echo "Compressing $input to $output (balanced quality/size)..."

    ffmpeg -i "$input" \
        -c:v libx264 \
        -preset slow \
        -crf 23 \
        -c:a aac \
        -b:a 128k \
        -vf "scale=1280:-2" \
        -r 24 \
        -movflags +faststart \
        -f mp4 \
        "$output"

    if [ $? -eq 0 ]; then
        echo "✅ Balanced compression complete!"
    else
        echo "❌ Compression failed"
        return 1
    fi
}

# Alias for quick access
alias mp4compress='compress_mp4_github'

# PNG compression functions
png_compress() {
    local input="$1"
    local basename="${input%.*}"
    pngquant --speed 1 --skip-if-larger "$input" --output "${basename}-output.png"
}
alias pngx='png_compress'

png_compress_overwrite() {
    pngquant --speed 1 --skip-if-larger --ext .png --force "$1"
}
alias pngxo='png_compress_overwrite'

# Compress all PNG files in current directory with -output.png suffix
png_compress_all() {
    local png_files=(*.png)

    if [ ${#png_files[@]} -eq 0 ] || [ ! -f "${png_files[0]}" ]; then
        echo "No PNG files found in current directory"
        return 1
    fi

    echo "Found ${#png_files[@]} PNG file(s) to compress..."

    local processed=0
    local skipped=0

    for file in "${png_files[@]}"; do
        # Skip files that already have -output suffix to avoid processing them again
        if [[ "$file" == *"-output.png" ]]; then
            echo "⏭️  Skipping $file (already processed)"
            ((skipped++))
            continue
        fi

        echo "🔄 Processing: $file"
        local basename="${file%.*}"

        if pngquant --speed 1 --skip-if-larger "$file" --output "${basename}-output.png" 2>/dev/null; then
            echo "✅ Compressed: $file → ${basename}-output.png"
            ((processed++))
        else
            echo "⚠️  Skipped: $file (no reduction possible or error)"
            ((skipped++))
        fi
    done

    echo "📊 Summary: $processed compressed, $skipped skipped"
}
alias pngxa='png_compress_all'

# Compress and overwrite all PNG files in current directory
png_compress_all_overwrite() {
    local png_files=(*.png)

    if [ ${#png_files[@]} -eq 0 ] || [ ! -f "${png_files[0]}" ]; then
        echo "No PNG files found in current directory"
        return 1
    fi

    echo "Found ${#png_files[@]} PNG file(s) to compress (will overwrite originals)..."
    echo "⚠️  WARNING: This will overwrite original files!"

    # Ask for confirmation
    echo -n "Continue? [y/N]: "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        return 0
    fi

    local processed=0
    local skipped=0

    for file in "${png_files[@]}"; do
        echo "🔄 Processing: $file"

        if pngquant --speed 1 --skip-if-larger --ext .png --force "$file" 2>/dev/null; then
            echo "✅ Compressed: $file (overwritten)"
            ((processed++))
        else
            echo "⚠️  Skipped: $file (no reduction possible or error)"
            ((skipped++))
        fi
    done

    echo "📊 Summary: $processed compressed, $skipped skipped"
}
alias pngxoa='png_compress_all_overwrite'
