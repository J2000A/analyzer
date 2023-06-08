#!/bin/bash

##############################################################
####################### USER VARIABLES #######################
##############################################################
# Variables
git_url=""          #e.g.: https://github.com/madler/zlib.git
use_cmake=true             # Choose either cmake or make
use_make=false             # Choose either cmake or make
path_to_build=""           #e.g.: "." (Relative path in repo)
path_to_execute_cil=""     #e.g.: "." (Relative path in repo)

# Functions before and after build
pre_build_commands() {
  :                        #e.g.: ./configure
}

post_build_commands() {
  :
}
##############################################################
####################### USER VARIABLES #######################
##############################################################

# Export variables so they can be used in the main script
export git_url
export use_cmake
export use_make
export path_to_build
export path_to_execute
export pre_build_commands
export post_build_commands