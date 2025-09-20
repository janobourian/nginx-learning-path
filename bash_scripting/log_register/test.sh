#!/bin/bash
array=( {1..10} )
for item in "${array[@]}"; do
    echo "$item"
done
