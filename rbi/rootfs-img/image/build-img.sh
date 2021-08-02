#! /bin/bash

source_code_dir=
rootfs_dir=
output_dir=
abs_pwd=

ARTIFEST=kata-containers.img
REPORT_FILE=report

BUILD_DIR=tools/osbuilder/image-builder
BUILD_SCRIPT=$BUILD_DIR/image_builder.sh

INFO=[INFO]
ERROR=[ERROR]

usage() {
    cat << EOT
    
    This script aims to apply a patch tokata-container's 
    image_builder.sh and run it, to build a rootfs.img 
    for kata-containers.
    
    Parameters:
        - <path/to/source_code_dir> source_code_dir means dir 
            'kata-containers'
        - <path/to/rootfs/dir> rootfs, generated by ../rootfs
        - <path/to/output_dir> 

EOT
    exit
}

exist_output_dir() {
    echo "$INFO $output_dir exists, cleaning contents..."
    rm -f $output_dir/$REPORT_FILE
    rm -f $output_dir/$ARTIFEST
    echo "$INFO Clean done."
}

no_exist_output_dir() {
    echo "$INFO $output_dir doesn't exist, creating.."
    mkdir -p $output_dir
    echo "$INFO $output_dir created."
}

patch() {
    local abs_pwd=$1
    local abs_source_code_dir=$2

    echo "$INFO Apply patch from $abs_pwd/patch --> $abs_source_code_dir/$BUILD_DIR"
    cp -rf $abs_pwd/patch/* $abs_source_code_dir/$BUILD_DIR
    echo "$INFO Apply patch done."
}

run_build() {
    local abs_source_code_dir=$1
    local abs_output_dir=$2 
    local abs_rootfs_dir=$3
    
    echo "$INFO Will began to build $abs_rootfs_dir --> $abs_output_dir"
    sudo USE_DOCKER=true IMAGE=$abs_output_dir/$ARTIFEST AGENT_INIT=yes "$abs_source_code_dir/$BUILD_SCRIPT" $abs_rootfs_dir

    [ "$?" != "0" ] && echo "$ERROR docker run failed" && exit -1 || end_notify $abs_output_dir
}

end_notify() {
    local output_dir=$1

    cat <<EOT
$INFO Build Done. Artifest is $output_dir/$ARTIFEST.
You can check for details. 
Thank you :P
EOT
}

main() {
    if [ -z $3 ]; then 
        usage
    fi

    abs_pwd=$(cd $(dirname $0); pwd)
    source_code_dir=$1
    rootfs_dir=$2
    output_dir=$3

    [ -d $output_dir ] && exist_output_dir || no_exist_output_dir

    local abs_source_code_dir=$(cd "$source_code_dir";pwd)
    local abs_output_dir=$(cd "$output_dir";pwd)
    local abs_rootfs_dir=$(cd "$rootfs_dir";pwd)
    

    patch $abs_pwd $abs_source_code_dir

    run_build $abs_source_code_dir $abs_output_dir $abs_rootfs_dir
}

main "$@"