#!/bin/bash

#SBATCH -N 1                    # number of nodes
##SBATCH -c 12                  # 6 threads per MPI process
#SBATCH -t 72:00:00
#SBATCH -p gpu
#SBATCH --gres=gpu:1
#SBATCH -A hpc_bb_karki2
#SBATCH -o  gb_mgsion.out
#SBATCH -e  error_mgsion.out

# First, create a Python script to process OUTCAR files
cat << EOF > process_outcar.py
import dpdata
import sys

input_file = sys.argv[1]
output_dir = sys.argv[2]

dsys = dpdata.LabeledSystem(input_file)
dsys.to("deepmd/npy", output_dir, set_size=dsys.get_nframes())
EOF

# Function to process OUTCAR files in a directory
process_outcars() {
    local dir=$1
    if [ -f "$dir/OUTCAR" ]; then
        echo "Processing OUTCAR in $dir" >> log
        python process_outcar.py "$dir/OUTCAR" "$dir/deepmd_data"
    else
        echo "No OUTCAR found in $dir" >> log
    fi
}

# Process all OUTCAR files
for job in job*; do
    for try in "$job"/try*; do
        process_outcars "$try"
    done
done

# Collect and rename set.000 folders
counter=0
for job in job*; do
    for try in "$job"/try*; do
        if [ -d "$try/deepmd_data/set.000" ]; then
            new_set_name="set.$(printf "%03d" $counter)"
            mv "$try/deepmd_data/set.000" "./$new_set_name"
            mv "$try/deepmd_data/type.raw" "./type.raw"
	    mv "$try/deepmd_data/type_map.raw" "./type_map.raw"
	    echo "Moved $try/deepmd_data/set.000 to ./$new_set_name" >> log
            ((counter++))
        fi
    done
done

# Clean up
rm process_outcar.py

echo "Processed all OUTCAR files and collected $counter set folders." >> log 
