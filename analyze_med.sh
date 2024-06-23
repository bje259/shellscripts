#!/bin/bash

MEDIA_DIR="/mnt/c/Users/Bradl/OneDrive/CloudVids/NeedsProcessing"
# Output file for the report
REPORT_FILE="subtitle_report.csv"

# whis --output_dir ../SubsOut --output_format srt --task translate --language ja "$input"

function get_base_name() {
   local filename=$(basename -- "$1")
   echo "${filename%%.*}"
}
function process_media_files() {
   # Directory containing video files
   MEDIA_DIR="/mnt/c/Users/Bradl/OneDrive/CloudVids/NeedsProcessing"

   # Output file for the report
   REPORT_FILE="subtitle_report.csv"

   # Initialize the report file
   echo "File, Streams" >"$REPORT_FILE"

   # Loop through all files in the directory
   for file in "$MEDIA_DIR"/*; do
      if [[ -f "$file" ]]; then
         # Get subtitle stream information using ffprobe
         #subtitle_info=$(ffprobe -v error -select_streams s -show_entries stream=index,codec_name,codec_type:stream_tags=language,title -of csv=p=0 "$file" 2>&1)
         # subtitle_info=$(ffprobe -v error -select_streams s -show_entries stream=index,codec_name,codec_type:stream_tags=language,title -of csv=p=0 "$file")

         subtitle_info=$(ffprobe -v error -show_entries stream=index,codec_name,codec_type:stream_tags=language,title -of json "$file" | jq -r '.streams | map(select(.codec_type| IN("audio","subtitle")))|.[]| ""+(.["index"]|tostring) + ";"+ .codec_type+ ";"+ .tags.language ')
         # Check if ffprobe returned an error

         if [[ $? -ne 0 ]]; then
            echo "Skipping non-media file: $file"
         else
            for stream in $subtitle_info; do
               echo "$file,$stream" >>"$REPORT_FILE"
            done
            # Append file and subtitle info to the report
            # echo "$file,$subtitle_info" >>"$REPORT_FILE"
         fi
      fi
   done 2>/dev/null

   echo "Report generated: $REPORT_FILE"
}

function process_media_file() {
   file=$1
   report_file=$2
   base_name=$(basename "$file")
   subtitle_info=$(ffprobe -v error -show_entries stream=index,codec_name,codec_type:stream_tags=language,title -of json "$file" | jq -r '.streams | map(select(.codec_type| IN("audio","subtitle")))|.[]| ""+(.["index"]|tostring) + ";"+ .codec_type+ ";"+ .tags.language ')
   # Check if ffprobe returned an error

   if [[ $? -ne 0 ]]; then
      echo "Skipping non-media file: $file"
      return
   fi

   ffmpeg -y -ss 00:05:00 -i "$file" -t 00:00:30 -c copy "sample_$base_name" 2>/dev/null
   language=$(whisper --task translate --verbose False --output_format json "sample_$base_name" 2>/dev/null) && rm "sample_$base_name" && rm "sample_${base_name%.*}.json"
   lang=$(echo "${language##*language: }")
   echo "$file,$lang" >>"$report_file"

   if [[ $lang == "English" ]]; then
      echo "$file,$lang" >>"$report_file"
   else
      foundEng=false
      for stream in $subtitle_info; do
         echo "$file,$stream" >>"$report_file"
         if [[ $stream =~ "subtitle;eng" ]]; then
            foundEng=true
         fi
      done
      if [[ $foundEng == false ]]; then
         echo "Translating $file to English"
         # whis --output_dir ../SubsOut --output_format srt --task translate --language ja "$input"
         whisper --model_dir "$WHISPER_CACHE" --verbose False --output_dir "$MEDIA_DIR/SubsOut" --output_format srt --task translate --language ja "$file"
      else
         echo "found eng in embedded subs of $file"
      fi
   fi
}

function generate_media_list() {
   # Directory to search
   search_dir="$MEDIA_DIR"

   # Output files for the lists
   media_list="media_files.txt"
   subtitle_list="subtitle_files.txt"

   # Find media files and save the list
   find "$search_dir" -size +20M -type f \( -name "*.mp4" -o -name "*.avi" -o -name "*.flv" -o -name "*.m4v" -o -name "*.mkv" -o -name "*.mov" -o -name "*.ogm" -o -name "*.wmv" \) >"$media_list"

   # Find subtitle files and save the list
   # find "$search_dir" -type f \( -name "*.srt" -o -name "*.ass" -o -name "*.ssa" -o -name "*.smi" -o -name "*.sub" \) >"$subtitle_list"
   find "$search_dir" -type f \( -name "*.srt" -o -name "*.ass" -o -name "*.ssa" -o -name "*.smi" -o -name "*.sub" \) \( -iwholename "*[._]en[._]*" -o -iwholename "*[._\/]eng[._\ \/]*" -o -iwholename "*.English.*" \) >"$subtitle_list"
}

function pair_media_list() {
   # File containing the list of media files
   media_list="media_files.txt"
   # File containing the list of subtitle files
   subtitle_list="subtitle_files.txt"

   # Function to extract the base name (without extensions and optional tags)

   # Read the list of subtitle files into an associative array
   declare -A subtitles
   while IFS= read -r subfile; do
      base_name=$(get_base_name "$subfile")
      subtitles["$base_name"]="$subfile"
   done <"$subtitle_list"

   # Process each media file
   while IFS= read -r mediafile; do
      base_name=$(get_base_name "$mediafile")
      matching_subtitle="${subtitles[$base_name]}"
      if [[ -z "$matching_subtitle" ]]; then
         echo "Media: $mediafile" >&2
         echo "No matching external subtitle found for $mediafile" >&2
         echo "$mediafile,No matching external subtitle found" >>"$REPORT_FILE"
         # Run your ffprobe command or other processing logic here
         # ffprobe -v error -select_streams a,s -show_entries stream=index,codec_name,codec_type:stream_tags=language,title -of csv=p=0 "$mediafile"
         # process_media_file "$mediafile" "$REPORT_FILE"
      else
         echo "Media: $mediafile" >&2
         echo "Subtitle: $matching_subtitle" >&2
         echo "$file,$matching_subtitle" >>"$REPORT_FILE"
      fi
   done <"$media_list"

}

# process_media_files
testFile="$MEDIA_DIR/Shusaku 1.mkv"
echo "Processing media file: $testFile"
process_media_file "$testFile" "subtitle_report.csv"
# generate_media_list
# pair_media_list
