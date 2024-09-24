from ase.io.vasp import write_vasp_xdatcar
from ase.io.lammpsrun import read_lammps_dump_text

fp = open("deepmd_3/lammps/out.dump", "r")
read_data = read_lammps_dump_text(fp, index=slice(None))

fp = open("XDATCAR", "w")
write_vasp_xdatcar(fp, read_data)
