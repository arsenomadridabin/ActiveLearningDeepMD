#!/bin/bash

#SBATCH -N 1                    # number of nodes
##SBATCH -c 12			# 6 threads per MPI process
#SBATCH -t 1:00:00
#SBATCH -p gpu
#SBATCH --gres=gpu:1
#SBATCH -A hpc_bb_karki2
#SBATCH -o  gb_mgsion.out
#SBATCH -e  error_mgsion.out

export OMP_NUM_THREADS=8
export TF_INTER_OP_PARALLELISM_THREADS=4

cd $SLURM_SUBMIT_DIR
source /project/ashaky3/dpmd3/bin/activate

PYTHONPATH=/project/ashaky3/dpmd3/bin/python
dpMD=/project/ashaky3/dpmd3/bin/dp

CONFIG_FILE="config.ini"
section="Database"

while IFS='=' read -r key value
do
    # Skip empty lines and comments
    [[ "$key" =~ ^#.* ]] && continue
    [[ -z "$key" ]] && continue

    # Detect section headers
    if [[ "$key" =~ ^\[.*\]$ ]]; then
        current_section=$(echo "$key" | sed 's/\[\(.*\)\]/\1/')
        continue
    fi

    # If inside the desired section, read key-value pairs
    if [[ "$current_section" == "$section" ]]; then
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        export "$key"="$value"
    fi
done < "$CONFIG_FILE"

iteration=$(cat Iteration)
added_iteration=$((iteration + 1))
if [ "$added_iteration" -ne 0 ]; then
	DUMP_PATH="deepmd_${added_iteration}/lammps/out.dump"

	# Create a temporary Python script
	cat << EOF > temp_convert_script.py
from ase.io.vasp import write_vasp_xdatcar
from ase.io.lammpsrun import read_lammps_dump_text

fp = open("${DUMP_PATH}", "r")
read_data = read_lammps_dump_text(fp, index=slice(None))

fp = open("XDATCAR", "w")
write_vasp_xdatcar(fp, read_data)
EOF

pwd >> log

#Remove old XDATCAR and replace it, so that we can replace with new one
rm -rf XDATCAR

python temp_convert_script.py

	echo "Conversion completed for iteration ${iteration}" >> log
else:
	echo "Skipping conversion for iteration 0" >> log
fi

file="Iteration"

if [ ! -f "$file" ]; then
    echo "1" > "$file"
else
    n=$(cat "$file")
    n=$((n + 1))
    echo "$n" > "$file"
fi

# Modify the XDATCAR
sed -i '
1s/H He Li Be/Mg Si O N/
6s/ H   He  Li  Be / Mg   Si  O  N /
' "XDATCAR"

echo "done" >> completed
