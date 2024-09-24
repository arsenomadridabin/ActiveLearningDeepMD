#!/bin/bash

#SBATCH -N 1                    # number of nodes
##SBATCH -c 12			# 6 threads per MPI process
#SBATCH -t 72:00:00
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

lmps=/project/ashaky3/dpmd3/bin/lmp

# Function to create a new deepmd folder
create_deepmd_folder() {
    local dir=$1
    local deepmd_folders=($(find "$dir" -maxdepth 1 -type d -name "deepmd_*" -printf "%f\n" | sort -V))
    
    if [ ${#deepmd_folders[@]} -eq 0 ]; then
        new_folder="${dir}/deepmd_1"
    else
        last_folder=${deepmd_folders[-1]}
        last_number=${last_folder#deepmd_}
        new_number=$((last_number + 1))
        new_folder="${dir}/deepmd_${new_number}"
    fi
    
    mkdir -p "$new_folder/train" "$new_folder/validate"
    echo "$new_folder"
}

# Function to find the largest set number in a directory
find_largest_set_number() {
    local dir=$1
    local largest=$(find "$dir" -type d -name "set.*" | sed 's/.*set\.//' | sort -n | tail -1)
    echo "${largest:-0}"
}

# Function to create a new set name with incremented number
create_new_set_name() {
    local dest=$1
    local largest=$(find_largest_set_number "$dest")
    local new_number=$((largest + 1))
    echo "set.$new_number" 
}

# Function to copy folder with new sequential name
copy_folder_sequential() {
    local src=$1
    local dest=$2
    local new_name=$(create_new_set_name "$dest")
    cp -r "$src" "$dest/$new_name"
    echo "Copied $src to $dest/$new_name" >> log
}

export -f copy_folder_sequential
export -f create_new_set_name
export -f find_largest_set_number

# Check if a directory is provided as an argument
if [ $# -eq 0 ]; then
    dir="."
else
    dir="$1"
fi

# Create the new deepmd folder
new_folder=$(create_deepmd_folder "$dir")
echo "Created new folder: $new_folder" >> log

# Extract the number from the new folder name
new_number=$(basename "$new_folder" | sed 's/deepmd_//')

# If this is not deepmd_1, copy all set.* from the previous deepmd folder
if [ "$new_number" -gt 1 ]; then
    prev_number=$((new_number - 1))
    prev_folder="${dir}/deepmd_${prev_number}"
    if [ -d "$prev_folder" ]; then
        echo "Copying all set.* folders from $prev_folder" >> log
        find "$prev_folder/train" -type d maxdepth 1 -name "set.*" -exec bash -c 'copy_folder_sequential "$0" "'$new_folder'/train"' {} \;
        find "$prev_folder/validate" -type d maxdepth 1 -name "set.*" -exec bash -c 'copy_folder_sequential "$0" "'$new_folder'/validate"' {} \;
    else
        echo "Previous folder $prev_folder not found. Skipping copy from previous." >> log
    fi
fi

# Find all NEW folders with names starting with set.
new_set_folders=($(find "$dir" -maxdepth 1 -type d -name "set.*"))

# Check if any new set. folders were found
if [ ${#new_set_folders[@]} -eq 0 ]; then
    echo "No new set. folders found in the current directory." >> log
    exit 0
fi

echo "Found ${#new_set_folders[@]} new set. folders in the current directory." >> log

# Randomly shuffle the new set. folders
shuffled_folders=($(printf "%s\n" "${new_set_folders[@]}" | shuf))

# Calculate the number of folders for training (90%)
train_count=$((${#shuffled_folders[@]} * 90 / 100))

# Copy new folders to train and test directories
for i in "${!shuffled_folders[@]}"; do
    source_folder="${shuffled_folders[i]}"
    if [ $i -lt $train_count ]; then
        destination="$new_folder/train"
    else
        destination="$new_folder/validate"
    fi
    
    copy_folder_sequential "$source_folder" "$destination"
done

echo "Distribution of new folders complete." >> log
echo "New folders added:" >> log
echo "Training set: $train_count folders" >> log
echo "Test set: $((${#shuffled_folders[@]} - train_count)) folders" >> log

# Count total folders in train and test
train_total=$(find "$new_folder/train" -type d -name "set.*" | wc -l)
test_total=$(find "$new_folder/validate" -type d -name "set.*" | wc -l)

echo "Total folders after distribution:" >> log
echo "Training set: $train_total folders" >> log
echo "Test set: $test_total folders" >> log

# Create and run the shuffled_data.py script in the new deepmd folder
echo "Creating and running shuffled_data.py script in $new_folder..." >> log

cat << EOF > "$new_folder/shuffled_data.py"
import shutil
import os
import numpy as np

count = 0
folders_in_data = ['train','validate']
for folder in folders_in_data:
    try:
        fold_n_files = os.listdir(folder)
    except NotADirectoryError:
        continue
    for fol in fold_n_files:
        if not "set" in fol:
            continue
        else:
            if count == 0:
                energy = np.load(folder+"/"+fol+"/energy.npy")
                force  = np.load(folder+"/"+fol+"/force.npy")
                virial = np.load(folder+"/"+fol+"/virial.npy")
                box = np.load(folder+"/"+fol+"/box.npy")
                coord = np.load(folder+"/"+fol+"/coord.npy")
                count += 1
            else:
                energy = np.concatenate((energy,np.load(folder+"/"+fol+"/energy.npy")))
                force  = np.vstack((force,np.load(folder+"/"+fol+"/force.npy")))
                virial = np.vstack((virial,np.load(folder+"/"+fol+"/virial.npy")))
                box = np.vstack((box,np.load(folder+"/"+fol+"/box.npy")))
                coord = np.vstack((coord,np.load(folder+"/"+fol+"/coord.npy")))

n = energy.shape[0]
unique_random_numbers = np.random.permutation(np.arange(0, n))

x = int(0.8 * n)

training_indices = unique_random_numbers[:x]
validation_indices = unique_random_numbers[x:]

energy_training = energy[training_indices]
energy_validation = energy[validation_indices]

force_training = force[training_indices]
force_validation = force[validation_indices]

virial_training = virial[training_indices]
virial_validation = virial[validation_indices]

box_training = box[training_indices]
box_validation = box[validation_indices]

coord_training = coord[training_indices]
coord_validation = coord[validation_indices]

dir_name_1 = 'shuffled_train/set.000'
dir_name_2 = 'shuffled_validate/set.000'

if not os.path.exists(dir_name_1):
    os.makedirs(dir_name_1)

if not os.path.exists(dir_name_2):
    os.makedirs(dir_name_2)

np.save(dir_name_1+"/"+'energy.npy', energy_training)
np.save(dir_name_1+"/"+'force.npy', force_training)
np.save(dir_name_1+"/"+'virial.npy', virial_training)
np.save(dir_name_1+"/"+'box.npy', box_training)
np.save(dir_name_1+"/"+'coord.npy', coord_training)

np.save(dir_name_2+"/"+'energy.npy', energy_validation)
np.save(dir_name_2+"/"+'force.npy', force_validation)
np.save(dir_name_2+"/"+'virial.npy', virial_validation)
np.save(dir_name_2+"/"+'box.npy', box_validation)
np.save(dir_name_2+"/"+'coord.npy', coord_validation)

shutil.copy2('./../type.raw','shuffled_train/type.raw')
shutil.copy2('./../type_map.raw','shuffled_train/type_map.raw')

shutil.copy2('./../type.raw','shuffled_validate/type.raw')
shutil.copy2('./../type_map.raw','shuffled_validate/type_map.raw')

print("Data shuffling and processing complete.")
EOF

# Change to the new deepmd folder and run the Python script
cd "$new_folder"
python3 shuffled_data.py

mkdir data
mv shuffled_train shuffled_validate data

cp ./../input.json .

cd ..
#Load from config

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
echo "LAMMPS: $LAMMPS"

cd "$new_folder"

#Run DeepMD

CUDA_VISIBLE_DEVICES=0 horovodrun -np 1 $dpMD train --mpi-log=workers input.json
$dpMD freeze -o graph.pb
mkdir lammps

# Run LAMMPS

cd lammps
cp $LAMMPS/MgSiON.lmp .
cp $LAMMPS/in.lammps .
cp ./../graph.pb .

$lmps < in.lammps


echo "Script execution complete." >> log
