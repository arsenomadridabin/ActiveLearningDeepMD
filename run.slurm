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

CUDA_VISIBLE_DEVICES=0 horovodrun -np 1 $dpMD train --mpi-log=workers MgSiON_input.json
