#!/bin/bash

container_list=("preprocessing" "clockwork", "vcf")

for item in ${container_list[@]}; do
    sudo singularity build ${item}.sif Singularity.${item}
done
