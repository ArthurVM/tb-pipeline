#!/bin/bash

container_list=("preprocessing" "clockwork", "vcf")

for item in ${container_list[@]}; do
    docker build -t annacprice/${item}:latest -f Dockerfile.${item} .
done

