import mdtraj as md
import sys

# Load the PDB file using MDtraj
if len(sys.argv) < 2:
    print("Usage: python create_adj_matrix.py <input_file>")
    sys.exit(1)

input_file = sys.argv[1]
traj = md.load(input_file)

def delete_H_lines(input, output, trajectory):
    with open(input, 'r') as file:
        lines = file.readlines()

    with open(output, 'w') as new_file:
        for line in lines:
            words = line.split()
            if 'END' in line:
                new_file.write(line)
            elif 'END' not in line and not words[2].startswith('H'):
                new_file.write(line)

delete_H_lines(input_file, f"clean_{input_file}", traj)

def renumber_pdb(input_file, output_file):
    with open(input_file, 'r') as file:
        lines = file.readlines()

    with open(output_file, 'w') as new_file:
        line_number = 1
        for line in lines:
            if line.startswith('ATOM'):
                new_line = line[:6] + '{:>5}'.format(line_number) + line[11:]
                new_file.write(new_line)
                line_number += 1
            else:
                new_file.write(line)
                line_number = 1

renumber_pdb('last_250_frames_clean.pdb', 'last_250_frames_clean_renumbered.pdb')

def delete_end_lines(input, output):
    with open(input, 'r') as file:
        lines = file.readlines()

    with open(output, 'w') as new_file:
        for line in lines:
            words = line.split()
            if 'END' not in line:
                new_file.write(line)
        new_file.write('END\n')

delete_end_lines(f"clean_{input_file}", f"clean_no_ends_{input_file}")

def determine_num_subsets(n_frames, target_frames_per_subset=250):
    """
    Determine optimal number of subsets based on frame count.
    
    Parameters:
    - n_frames: Total number of frames
    - target_frames_per_subset: Ideal frames per subset (default 250)
    
    Returns:
    - Number of subsets to create
    """
    if n_frames <= target_frames_per_subset:
        return 1
    
    # Calculate ideal number of subsets
    ideal_subsets = n_frames / target_frames_per_subset
    
    # Round to nearest integer, but at least 2 if we're splitting
    num_subsets = max(2, round(ideal_subsets))
    
    # Prefer even divisions if close
    for divisor in [2, 4, 5, 8, 10]:
        if n_frames % divisor == 0:
            frames_per = n_frames // divisor
            if 100 <= frames_per <= 400:
                return divisor
    
    return num_subsets


def split_pdb_into_subsets(input_file, n_frames, num_subsets):
    """
    Split a PDB file into subsets by frame.
    
    Parameters:
    - input_file: Path to the processed PDB file
    - n_frames: Total number of frames
    - num_subsets: Number of subsets to create
    
    Returns:
    - List of output filenames
    """
    traj = md.load(input_file)
    
    frames_per_subset = n_frames // num_subsets
    remainder = n_frames % num_subsets
    
    base_name = os.path.splitext(input_file)[0]
    
    output_files = []
    start_frame = 0
    
    for i in range(num_subsets):
        extra = 1 if i < remainder else 0
        end_frame = start_frame + frames_per_subset + extra
        
        subset = traj[start_frame:end_frame]
        output_file = f"subset_{i+1}_of_{num_subsets}_{base_name}.pdb"
        
        subset.save_pdb(output_file)
        output_files.append(output_file)
        
        print(f"Created {output_file}: frames {start_frame}-{end_frame-1} ({end_frame - start_frame} frames)")
        
        start_frame = end_frame
    
    return output_files

n_frames = traj.n_frames
num_subsets = determine_num_subsets(n_frames)
