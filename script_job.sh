#!/bin/bash

# Check if correct number of arguments are provided
if [ $# -ne 1 ] && [ $# -ne 2 ] && [ $# -ne 3 ]; then
    echo "Usage: $0 <skip_frames> [start_frame]"
    echo "  skip_frames: Number of frames to skip between each selected frame"
    echo "  start_frame: Optional. Frame to start from (default is 0)"
    echo "  number_of_jobs: Number of Jobs"
    exit 1
fi

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

# Now you can use the variables from the "Database" section

> tmp

# Assign command line arguments to variables
skip_frames=$1
start_frame=${2:-0}  # Default to 0 if not provided
number_of_jobs=${3:-10}

# Remove the argument arg1 and arg2
shift 3

source /project/ashaky3/dpmd3/bin/activate

# Check if arguments are valid numbers
if ! [[ "$skip_frames" =~ ^[0-9]+$ ]] || ! [[ "$start_frame" =~ ^[0-9]+$ ]] || ! [[ "$number_of_jobs" =~ ^[0-9]+$ ]]; then
    echo "Error: All arguments must be positive integers."
    exit 1
fi

# Check if XDATCAR exists
if [ ! -f "XDATCAR" ]; then
    echo "Error: XDATCAR file not found in the current directory."
    exit 1
fi

mkdir -p lammps_tmp
cp XDATCAR lammps_tmp
cat << EOF > tmp_write_lmp.py

import sys
import numpy as np

def read_xdatcar(filename):
    with open(filename, 'r') as f:
        # Read system name
        system_name = f.readline().strip()
        
        # Read scaling factor
        scale = float(f.readline().strip())
        
        # Read lattice vectors
        lattice = np.array([list(map(float, f.readline().split())) for _ in range(3)])
        
        # Read atom types
        atom_types = f.readline().split()
        
        # Read atom counts
        atom_counts = list(map(int, f.readline().split()))
        
        total_atoms = sum(atom_counts)
        
        # Skip to the last configuration
        lines = f.readlines()
        last_config_start = -1
        for i in range(len(lines) - 1, -1, -1):
            if "Direct configuration=" in lines[i]:
                last_config_start = i
                break
        
        if last_config_start == -1:
            raise ValueError("No configuration found in XDATCAR")
        
        # Read coordinates of the last configuration
        coords = [list(map(float, line.split())) for line in lines[last_config_start+1:last_config_start+1+total_atoms]]
    
    return system_name, scale, lattice, atom_types, atom_counts, coords

def write_lammps_input(output_filename, system_name, scale, lattice, atom_types, atom_counts, coords):
    with open(output_filename, 'w') as f:
        f.write(f"# LAMMPS input file generated from XDATCAR: {system_name}\n\n")
        
        f.write(f"{sum(atom_counts)} atoms\n")
        f.write(f"{len(atom_types)} atom types\n\n")
        
        # Write box dimensions
        box = scale * lattice
        xlo, xhi = 0, box[0][0]
        ylo, yhi = 0, box[1][1]
        zlo, zhi = 0, box[2][2]
        xy = box[1][0]
        xz = box[2][0]
        yz = box[2][1]
        
        f.write(f"{xlo:.6f} {xhi:.6f} xlo xhi\n")
        f.write(f"{ylo:.6f} {yhi:.6f} ylo yhi\n")
        f.write(f"{zlo:.6f} {zhi:.6f} zlo zhi\n")
        f.write(f"{xy:.6f} {xz:.6f} {yz:.6f} xy xz yz\n\n")
        
        f.write("Atoms\n\n")
        
        atom_id = 1
        for atom_type, count in enumerate(atom_counts, 1):
            for _ in range(count):
                x, y, z = coords[atom_id - 1]
                # Convert fractional to Cartesian coordinates
                cart_coords = np.dot([x, y, z], scale * lattice)
                f.write(f"{atom_id} {atom_type} {cart_coords[0]:.6f} {cart_coords[1]:.6f} {cart_coords[2]:.6f}\n")
                atom_id += 1

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python script.py <input_xdatcar> <output_lmp>")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    try:
        system_name, scale, lattice, atom_types, atom_counts, coords = read_xdatcar(input_file)
        write_lammps_input(output_file, system_name, scale, lattice, atom_types, atom_counts, coords)
        print(f"Successfully converted {input_file} to {output_file}")
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

EOF
pwd >> pwd.txt
python tmp_write_lmp.py XDATCAR MgSiON.lmp
cp MgSiON.lmp in.lammps lammps_tmp
rm tmp_write_lmp.py

# Create a temporary Python script to generate POSCAR files and calculate job/try numbers
cat << EOF > temp_script.py
from ase.io import read, write
import os
import math

# Read the XDATCAR file
frames = read('XDATCAR', index=':')

total_frames = len(frames)
skip_frames = $skip_frames
start_frame = $start_frame
number_of_jobs = $number_of_jobs

# Calculate how many POSCAR files we can generate
available_poscars = (total_frames - start_frame) // (skip_frames + 1)

# Calculate num_jobs and num_tries
num_jobs = number_of_jobs
num_tries = int(available_poscars/num_jobs)
total_poscars = num_jobs * num_tries

print(f"{num_jobs},{num_tries},{total_poscars}")

# Create and write POSCAR files
for i in range(total_poscars):
    frame_index = start_frame + i * (skip_frames + 1)
    if frame_index >= total_frames:
        print(f"Warning: Reached end of XDATCAR. Only created {i} POSCAR files.")
        break
    frame = frames[frame_index]
    poscar_filename = f'POSCAR_{i+1:04d}'
    write(poscar_filename, frame, format='vasp',direct=True)
    print(f'Created {poscar_filename} from frame {frame_index}')

print(f'Created {total_poscars} POSCAR files from XDATCAR')
EOF

# Run the Python script and capture its output
output=$(python3 temp_script.py)

# Extract num_jobs, num_tries, and total_poscars from the output
IFS=',' read -r num_jobs num_tries total_poscars <<< "$(echo "$output" | head -n1)"

echo "Calculated: $num_jobs jobs, $num_tries tries, total $total_poscars POSCAR files"

# Create job and try folders
for i in $(seq 1 $num_jobs); do
    for j in $(seq 1 $num_tries); do
        mkdir -p "job$i/try$j"
    done
done

# Distribute POSCAR files
poscar_count=1
for i in $(seq 1 $num_jobs); do
    for j in $(seq 1 $num_tries); do
        if [ -f "POSCAR_$(printf "%04d" $poscar_count)" ]; then
            cp "POSCAR_$(printf "%04d" $poscar_count)" "job$i/try$j/"
	    mv "POSCAR_$(printf "%04d" $poscar_count)" "job$i/try$j/POSCAR"
            ((poscar_count++))
        else
            echo "Warning: No more POSCAR files to distribute. Stopping at job$i/try$j."
            break 2
        fi
    done
    cat << 'EOF' > job$i/run.slurm
#!/bin/bash
#SBATCH -N 1
#SBATCH -n 20
#SBATCH -t 72:00:00
#SBATCH -p checkpt
#SBATCH -A hpc_bb_karki2
#SBATCH -e  err

ncpu=60   # Total number of cpus

# The below 2 lines may not always be necessary. But have helped mitigate crashes for big jobs.
ulimit -s unlimited
export setenv I_MPI_COMPATIBILITY=4

module purge
module load intel-mpi/2021.5.1
vasp_G=/home/ashaky3/g53_impi   # Change the path to where the vasp executable is there
#vasprun="srun -n $ncpu $vasp_G"          # For cpu run

# Command to run vasp in cpu mode
#srun -N3 -n60  $vasp_G

# Count the number of directories starting with "try"
n=$(find . -maxdepth 1 -type d -name "try*" | wc -l)

# Initialize the array
dirs=()

# Populate the array with try folder names
for i in $(seq 1 $n); do
    dirs+=("try$i")
done

echo "Directories to process: ${dirs[@]}"

log_file="processing_log.txt"
echo "Processing started at $(date)" > $log_file

# Loop through each directory
for dir in "${dirs[@]}"; do
    echo "Processing $dir"
    echo "Processing $dir" | tee -a $log_file
    echo "Started at $(date)" >> $log_file

    # Copy POSCAR from the directory
    cp "$dir/POSCAR" .

    # Run VASP
    srun -N1 -n20 $vasp_G

    # Move output files back to the directory
    mv CONTCAR OUTCAR XDATCAR "$dir/"

    echo "Finished processing $dir"
    echo "------------------------"
done

echo "All calculations complete"
EOF
	cp KPOINTS POTCAR INCAR job$i
	chmod +x job$i/run.slurm
	cd job$i/
	sbatch --parsable run.slurm >> ./../tmp
	cd ..
	done

# Clean up
rm temp_script.py

echo "$total_poscars POSCAR files have been created and distributed across $num_jobs job folders, each containing $num_tries try folders."
echo "Skipped $skip_frames frames between each selected frame, starting from frame $start_frame."

# Optional: Display the directory structure
echo "Directory structure:"
tree -L 2 job*

tmp_file="tmp"

# Check if the tmp file exists
if [ ! -f "$tmp_file" ]; then
    echo "Error: $tmp_file not found."
    exit 1
fi

# Read job IDs from the tmp file
job_ids=($(cat "$tmp_file"))

# Check if any job IDs were read
if [ ${#job_ids[@]} -eq 0 ]; then
    echo "Error: No job IDs found in $tmp_file."
    exit 1
fi

# Construct the dependency string
dependency=""
for job_id in "${job_ids[@]}"; do
    if [ -z "$dependency" ]; then
        dependency="afterok:$job_id"
    else
        dependency="$dependency:$job_id"
    fi
done

echo "Submitting dependent job..."
echo "Dependency string: $dependency"

# Submit the dependent job
dependent_job_id=$(sbatch --dependency=$dependency --parsable gather_training_data.sh)

if [ $? -eq 0 ]; then
    echo "Dependent job submitted successfully with job ID: $dependent_job_id"
else
    echo "Error: Failed to submit dependent job."
    exit 1
fi

# Construct the dependency for the second dependent job
dependency_2="afterok:$dependent_job_id"

echo "Submitting second dependent job..."
echo "Dependency string: $dependency_2"

# Submit the second dependent job
dependent_job_id_2=$(sbatch --dependency=$dependency_2 --parsable add_data.sh)

if [ $? -eq 0 ]; then
    echo "Second dependent job submitted successfully with job ID: $dependent_job_id_2"
else
    echo "Error: Failed to submit second dependent job."
    exit 1
fi


# Construct the dependency for the second dependent job
dependency_3="afterok:$dependent_job_id_2"

echo "Submitting third dependent job..."
echo "Dependency string: $dependency_3"

# Submit the third dependent job (out.json to XDATCAR)
dependent_job_id_3=$(sbatch --dependency=$dependency_3 --parsable out_to_xdatcar.sh)

if [ $? -eq 0 ]; then
    echo "Third dependent job submitted successfully with job ID: $dependent_job_id_3"
else
    echo "Error: Failed to submit third dependent job."
    exit 1
fi


