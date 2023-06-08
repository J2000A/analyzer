#!/bin/bash

# Source the input script from the provided path
if [[ -n $1 ]]; then
  source $1
else
  echo "Please give the following arguments: build_info_path output_path [--clone][--build][--path]"
  echo ""
  echo "The build_info sh file should look like this:"
  cat generate_git_build_USER_INFO_PRESET.sh
  echo ""
  exit 1
fi

# Get the output path from the provided path
if [[ -n $2 ]]; then
  output_path="$(pwd)/$2"
else
  echo "Please provide the relative path to the output as the second argument."
  exit 1
fi

if [ "$3" == "" ]; then
  echo "Please provide one of the options [--clone][--build][--path]"
  exit 1
fi

# Exit if any command fails
set -e

# Check bool variables
if { $use_cmake && $use_make ; } || { ! $use_cmake && ! $use_make ; }; then
  echo "Error: Either cmake or make should be used, but not both or neither."
  exit 1
fi

# Get the name of the repo
repo_name=$(basename "$git_url" .git)

# Export path for Mutation Generator
if [ "$3" == "--path" ]; then
  echo "$output_path/$repo_name/$path_to_build"
  exit 0
fi

# Clone repo
if [ "$3" == "--clone" ]; then
  rm -rf "$output_path/$repo_name"
  git clone $git_url "$output_path/$repo_name"
fi

# Build repo
if [ "$3" == "--build" ]; then
  cd "$output_path/$repo_name/$path_to_build"
  pre_build_commands

  if $use_cmake; then
    cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
  elif $use_make; then
    bear -- make
  fi

  post_build_commands
fi
