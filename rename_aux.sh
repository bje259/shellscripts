#!/bin/bash

input_file="$1"

generated_files=()
mapfile -t generated_files < "$input_file"

rename_files() {
	for file in "${generated_files[@]}"; do
		base_name=$(basename "$file" .srt)
		dir_name=$(dirname "$file")
		new_name="$dir_name/$base_name.en.srt"
		echo "Renaming $file to $new_name"
		mv "$file" "$new_name"
	done
}

rename_files 