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
