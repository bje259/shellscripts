#!/bin/bash

# Default configuration
MEDIA_DIR="/mnt/seedbox/stash"
REPORT_FILE="subtitle_report.csv"
FINAL_REPORT_FILE="final_report.csv"
TO_PROCESS_FILE="to_process.txt"
MEDIA_LIST_FILE="media_files.txt"
SUBTITLE_LIST_FILE="subtitle_files.txt"
USE_EXISTING_MEDIA_LIST=false
SKIP_GENERATE_MEDIA_LISTS=false
SKIP_PAIR_MEDIA_LIST=false
SKIP_PROCESS_PENDING_FILES=false

echo "File---Streams" >"$REPORT_FILE"

# MEDIA_DIR="/mnt/c/Users/Bradl/OneDrive/CloudVids/NeedsProcessing" #/[rawHentai] Dorei Kaigo (奴隷介護) [Dual Audio]/isoFolder"
# "C:\Users\Bradl\OneDrive\CloudVids\NeedsProcessing\[rawHentai] Dorei Kaigo (奴隷介護) [Dual Audio]\isoFolder"
# MEDIA_DIR="/mnt/seedbox/stash"
# Output file for the report
# REPORT_FILE="subtitle_report.csv"
# FINAL_REPORT_FILE="final_report.csv"
# echo "File,Reference,SubStatus" >"$FINAL_REPORT_FILE"
# whis --output_dir ../SubsOut --output_format srt --task translate --language ja "$input"
# TO_PROCESS_FILE="to_process.txt"
# echo -n "" >"$TO_PROCESS_FILE"


#function to print usage
print_usage() {
	echo "Usage: $0 [-d MEDIA_DIR] [-r REPORT_FILE] [-f FINAL_REPORT_FILE] [-t TO_PROCESS_FILE] [-e] [-g] [-p]"
	echo "  -d MEDIA_DIR: Set the media directory"
	echo "  -r REPORT_FILE: Set the report file"
	echo "  -f FINAL_REPORT_FILE: Set the final report file"
	echo "  -t TO_PROCESS_FILE: Set the file to process"
	echo "  -e: Use existing files"
	echo "  -g: Skip generating media list"
	echo "  -p: Skip pairing media list"
	echo "  -s: Skip processing pending files"
}

#parse command line options
while getopts "d:r:f:t:egps" opt; do
	case $opt in
	d) MEDIA_DIR="$OPTARG" ;;
	r) REPORT_FILE="$OPTARG" ;;
	f) FINAL_REPORT_FILE="$OPTARG" ;;
	t) TO_PROCESS_FILE="$OPTARG" ;;
	e) USE_EXISTING_MEDIA_LIST=true ;;
	g) SKIP_GENERATE_MEDIA_LISTS=true ;;
	p) SKIP_PAIR_MEDIA_LIST=true ;;
	s) SKIP_PROCESS_PENDING_FILES=true ;;
	*)
		print_usage
		exit 1
		;;
	esac
done



# Array to track generated files
generated_files=()

function get_base_name() {
	local filename
	filename=$(basename -- "$1")
	echo "${filename%%.*}"
}

function get_base_name2() {
	local filename
	filename=$(basename -- "$1")
	echo "${filename%.*}"
}

# Function to read the final report into an array
read_final_report() {
	local final_report_file="$1"
	local -n final_report_array=$2
	while IFS=, read -r file _; do
		final_report_array+=("$file")
	done < <(tail -n +2 "$final_report_file")
}

# Function to check if an item is in an array
is_in_array() {
	local item="$1"
	local -n array=$2
	for element in "${array[@]}"; do
		if [[ "$element" == "$item" ]]; then
			return 0
		fi
	done
	return 1
}

# Function to rename generated files
rename_files() {
	for file in "${generated_files[@]}"; do
		base_name=$(basename "$file" .srt)
		dir_name=$(dirname "$file")
		new_name="$dir_name/$base_name.en.srt"
		echo "Renaming $file to $new_name"
		mv "$file" "$new_name"
	done
}

cleanup() {
	echo "Cleaning up and renaming files..."
	rename_files
}
trap cleanup EXIT

function process_media_file() {
	local file="$1"
	local report_name="$2"
	local base_name=$(basename "$file")
	local base_name_no_ext=$(get_base_name2 "$base_name")

	# Probe the media file and save the stream information to an array
	local subtitle_info=()
	while IFS= read -r line; do
		subtitle_info+=("$line")
	done < <(ffprobe -v error -show_entries stream=index,codec_name,codec_type:stream_tags=language,title -of json "$file" | jq -r '.streams | map(select(.codec_type| IN("audio","subtitle")))|.[]| ""+(.["index"]|tostring) + ";" + .codec_type + ";" + .tags.language')

	# Check if ffprobe didn't find any information
	if [[ ${#subtitle_info[@]} -eq 0 ]]; then
		echo "Skipping non-media file: $file"
		echo "$file,NA,No Media" >>"$FINAL_REPORT_FILE"
		return
	fi

	# Create a sample 30 second clip of the media file
	if ! ffmpeg -y -ss 00:05:00 -i "$file" -t 00:00:30 -c copy "sample_$base_name" 2>/dev/null; then
		echo "Error creating sample clip for $file" >&2

		return
	fi

	# Translate the sample clip to English in order to detect language and delete the sample file
	if ! language=$(whisper --task translate --verbose False --output_format json "sample_$base_name" 2>/dev/null); then
		echo "Error translating sample clip for $file" >&2
		rm "sample_$base_name" "sample_${base_name%.*}.json"
		return
	fi
	rm "sample_$base_name" "sample_${base_name%.*}.json"
	lang=$(echo "${language##*language: }")
	echo "$file---$lang" >>"$report_name"
	echo $language >&2

	#If the detected language is English, stop processing
	if [[ $lang == "English" ]]; then
		echo "Halting, lang English" >>"debug.log"
		echo "$file,$lang,English Audio" >>"$FINAL_REPORT_FILE"
	else
		#If the language is not English, check if the media file has an embedded English subtitle
		foundEng=false
		for stream in "${subtitle_info[@]}"; do
			echo "$file---$stream" >>"$report_name"
			if [[ "$stream" =~ "subtitle;eng" ]]; then
				foundEng=true
			fi
		done

		#If the media file has no embedded English subtitle, translate it to English
		if [[ $foundEng == false ]]; then
			echo "Translating $file to English" >&2
			# echo "$file" >>"$TO_PROCESS_FILE"
			local dir="${file%/*}"
			if ! whisper --model_dir "$WHISPER_CACHE" --verbose False --output_dir "$dir" --output_format srt --task translate --language ja "$file"; then
				echo "Error translating $file" >&2
				return
			fi
			echo "Subtitles saved to $dir" >&2
			generated_files+=("$dir/$base_name_no_ext.srt")
			echo "$file,$dir/$base_name_no_ext.srt,Generated External Subtitle" >>"$FINAL_REPORT_FILE"
			# echo "$file,$dir/$base_name_no_ext.srt,$lang,$subtitle_info" >"$dir/$base_name_no_ext.srt"
			echo "$dir/$base_name_no_ext.srt" >&2
		else
			#If the media file has an embedded English subtitle, stop processing
			echo "found eng in embedded subs of $file" >&2
			echo "$file---Embedded English Subtitle" >>"$report_name"
			echo "$file,$lang,Embedded English Subtitle" >>"$FINAL_REPORT_FILE"
		fi

	fi
	return 0
}

# Function to generate media list
generate_media_lists() {
	if $SKIP_GENERATE_MEDIA_LISTS; then
		echo "Skipping media list generation."
		return
	fi

	# Inputs
	search_dir="$MEDIA_DIR" # Directory to search

	# Output files for the lists
	media_list="$MEDIA_LIST_FILE"
	subtitle_list="$SUBTITLE_LIST_FILE"

	# Read final report into an array
	final_report_files=()
	if [[ -f "$FINAL_REPORT_FILE" ]]; then
		read_final_report "$FINAL_REPORT_FILE" final_report_files
	fi

	# Find media files and save the list excluding already processed files
	if $USE_EXISTING_MEDIA_LIST; then
		echo "Using existing media list" >&2
	else
		echo "Generating media list" >&2
		find "$search_dir" -size +20M -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.flv" -o -name "*.m4v" -o -name "*.mkv" -o -name "*.mov" -o -name "*.ogm" -o -name "*.wmv" \) | while IFS= read -r mediafile; do
			if ! is_in_array "$mediafile" final_report_files; then
				echo "$mediafile"
			fi
		done >"$MEDIA_LIST_FILE"
	fi

	# Find subtitle files and save the list
	find "$search_dir" -type f \( -name "*.srt" -o -name "*.ass" -o -name "*.ssa" -o -name "*.smi" -o -name "*.sub" \) \( -iwholename "*[._]en[._]*" -o -iwholename "*[._/]*eng[._/]*" -o -iwholename "*.English.*" \) >"$subtitle_list"
}

function pair_media_list() {
	if $SKIP_PAIR_MEDIA_LIST; then
		echo "Skipping pairing media list."
		return
	fi

	# File containing the list of media files
	media_list="$MEDIA_LIST_FILE"
	# File containing the list of subtitle files
	subtitle_list="$SUBTITLE_LIST_FILE"

	# Function to extract the base name (without extensions and optional tags)

	# Read the list of subtitle files into an associative array
	declare -A subtitles
	while IFS= read -r subfile; do
		base_name=$(get_base_name "$subfile")
		subtitles["$base_name"]="$subfile"
	done <"$SUBTITLE_LIST_FILE"

	# echo "subtitles: ${subtitles[@]}" >>"debug.log"

	for key in "${!subtitles[@]}"; do
		echo "Key: $key" >>"debug.log"
		echo "Value: ${subtitles[$key]}" >>"debug.log"
	done

	media_files=()
	while IFS= read -r mediafile; do
		media_files+=("$mediafile")
	done <"$MEDIA_LIST_FILE"

	# Process each media file
	for mediafile in "${media_files[@]}"; do
		echo "Media file from read: $mediafile" >&2
		base_name=$(get_base_name "$mediafile")
		echo "Base name: $base_name" >&2
		matching_subtitle="${subtitles[$base_name]}"
		echo "Matching subtitle: $matching_subtitle" >&2
		if [[ -z "$matching_subtitle" ]]; then
			echo "Media: $mediafile" >&2
			echo "No matching external subtitle found for $mediafile" >&2
			echo "$mediafile---No matching external subtitle found" >>"$REPORT_FILE"
			# Run your ffprobe command or other processing logic here
			process_media_file "$mediafile" "$REPORT_FILE"
			echo "$mediafile" >"$TO_PROCESS_FILE"
		else
			echo "Media: $mediafile" >&2
			echo "Subtitle: $matching_subtitle" >&2
			echo "$mediafile---$matching_subtitle" >>"$REPORT_FILE"
			echo "$mediafile,$matching_subtitle,External Subtitle" >>"$FINAL_REPORT_FILE"
		fi
	done
}

Process_pending_files() {
	if $SKIP_PROCESS_PENDING_FILES; then
		echo "Skipping processing pending files."
		return
	fi
	pending_media_files=()
	while IFS= read -r mediafile; do
		pending_media_files+=("$mediafile")
	done <"$TO_PROCESS_FILE"

	for mediafile in "${pending_media_files[@]}"; do
		echo "Processing media file: $mediafile" >&2
		process_media_file "$mediafile" "$REPORT_FILE"
	done
}



#function to pair media list
pair_media_list_fn() {
	if $SKIP_PAIR_MEDIA_LIST; then
		echo "Skipping pairing media list."
		return
	fi

	#Inputs
	media_list="media_files.txt"       # File containing the list of media files
	subtitle_list="subtitle_files.txt" # File containing the list of subtitle files
	#Output
	to_process="to_process.txt" # File containing the list of media files to process

	# Extract the base name from the subtitle files and save them to an associative array
	declare -A subtitles
	while IFS= read -r subfile; do
		base_name=$(get_base_name "$subfile")
		subtitles["$base_name"]="$subfile"
	done <"subtitle_files.txt"

	# Read the list of media files into an array
	media_files=()
	while IFS= read -r mediafile; do
		media_files+=("$mediafile")
	done <"media_files.txt"

	# Process each media file
	for mediafile in "${media_files[@]}"; do
		base_name=$(get_base_name "$mediafile")
		matching_subtitle="${subtitles[$base_name]}"
		if [[ -z "$matching_subtitle" ]]; then
			# process_media_file "$mediafile" "$REPORT_FILE"
			echo "$mediafile" >>"$to_process"
		fi
	done
}




#Main script execution

# testFile="$MEDIA_DIR/[rawHentai] Dorei Kaigo (奴隷介護) [Dual Audio]/[rawHentai] Dorei Kaigo - 2.mkv"
# echo "Processing media file: $testFile"
# process_media_file "$testFile" "subtitle_report_process.csv"
generate_media_lists
pair_media_list
Process_pending_files
# rename_files
