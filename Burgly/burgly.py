#!/usr/bin/env python3

'''
Detect and quanitfy the surface depth of each glycan residue of a viral spike glycoprotein trajectory.
'''

import pymol
from pymol import cmd

import MDAnalysis as mda

import open3d as o3d

import numpy as np
import pandas as pd

def enforce_multimodel_format(traj_file: str) -> str:
    '''
    Convert input traj file to MDA-compatible multimodel format
    including MODEL and ENDMDL statements between each frame.
    
    Handles two input formats:
    1. END-delimited frames (convert to MODEL/ENDMDL)
    2. Already has MODEL/ENDMDL (return as-is or copy to new file)
    
    :param traj_file: The unformatted trajectory file
    :return: Path to multimodel-formatted file
    '''
    outfile = traj_file.replace('.pdb', '_multimodel.pdb')
    
    with open(traj_file, 'r') as f:
        lines = f.readlines()
    
    # Check if already in MODEL/ENDMDL format
    has_model = any(line.startswith('MODEL') for line in lines)
    has_endmdl = any(line.startswith('ENDMDL') for line in lines)
    
    if has_model and has_endmdl:
        # Already in proper format - but check if it's correct
        # Count MODELs and ENDMDLs
        model_count = sum(1 for line in lines if line.startswith('MODEL'))
        endmdl_count = sum(1 for line in lines if line.startswith('ENDMDL'))
        
        if model_count == endmdl_count:
            print(f"File already in MODEL/ENDMDL format with {model_count} frame(s)")
            # Just copy to output location for consistency
            with open(outfile, 'w') as f:
                f.writelines(lines)
            return outfile
    
    # Convert END-delimited format to MODEL/ENDMDL format
    multimodel_lines = []
    model_num = 1
    multimodel_lines.append(f'MODEL     {model_num:4d}\n')
    
    for i, line in enumerate(lines):
        if line.startswith('END') and not line.startswith('ENDMDL'):
            # This is an END statement (frame delimiter)
            multimodel_lines.append('ENDMDL\n')
            # Check if there's more content after this END
            if i + 1 < len(lines):
                # Check if next non-blank line has content
                remaining = lines[i+1:]
                if any(l.strip() and l.startswith('ATOM') for l in remaining):
                    model_num += 1
                    multimodel_lines.append(f'MODEL     {model_num:4d}\n')
        elif line.startswith('MODEL') or line.startswith('ENDMDL'):
            # Skip existing MODEL/ENDMDL statements (will be replaced)
            continue
        else:
            multimodel_lines.append(line)
    
    # Ensure file ends with ENDMDL if it doesn't already
    if multimodel_lines and not multimodel_lines[-1].strip().startswith('ENDMDL'):
        multimodel_lines.append('ENDMDL\n')
    
    with open(outfile, 'w') as f:
        f.writelines(multimodel_lines)
    
    return outfile

def parse_glycdat(glycdat_file: str):
    '''
    Extract glycan chain info from an input glyc.dat
    file for organizing heatmap output.

    Each glycan chain starts with a line whose second field is "NGLB".
    Each key in the dictionary is "gly_n" and its value is a list of residue numbers (integers).
    '''
    glycdat = {}
    gly_num = 0
    with open(glycdat_file, 'r') as f:
        lines = f.readlines()
        lines = [s for s in lines if s.strip()] # Remove any blank lines first
        
        # Spike protein will always be a trimer and the glyc.dat file
        # contains symmetrical data for all three trimers; we only need
        # the first third of the data since it is the same for the remaining
        # two trimers:
        trimer_len = len(lines) // 3

        for i, line in enumerate(lines):
            if i >= trimer_len:
                break
            fields = line.split()
            if len(fields) < 3:
                continue
            if fields[1] == 'NGLB':
                gly_num += 1
                glycdat[f'gly_{gly_num}'] = [i+1]
            else:
                if gly_num > 0:
                    glycdat[f'gly_{gly_num}'].append(i+1)
    return glycdat

def get_centroid(coords):
    '''
    Take a list of 3d coordinates (nx3 matrix) and 
    return the center of points or 'centroid' 
    of all coordinates in xyz format.
    
    Uses NumPy's mean function for efficiency.
    Returns None if no coordinates provided.
    '''
    if len(coords) == 0:
        return None
    
    # Use NumPy's mean function - more efficient and reliable
    return np.mean(coords, axis=0)

def compute_residue_depths(centroids, surface_stl):
    '''
    Compute signed distances from glycan residue centroids to protein surface
    using Open3D raycasting.
    
    Positive values = above surface (unburied)
    Negative values = below surface (buried)
    Zero = exactly on surface
    
    :param centroids: Nx3 numpy array of residue centroid coordinates
    :param surface_stl: Path to STL file of protein surface
    :return: 1D numpy array of signed distances
    '''
    # Load the surface mesh
    mesh = o3d.io.read_triangle_mesh(surface_stl)
    
    # Create raycasting scene
    scene = o3d.t.geometry.RaycastingScene()
    _ = scene.add_triangles(o3d.t.geometry.TriangleMesh.from_legacy(mesh))
    
    # Convert centroids to Open3D tensor format
    query_points = o3d.core.Tensor(centroids.astype(np.float32))
    
    # Compute signed distances
    # Positive = outside surface, Negative = inside surface
    signed_distances = scene.compute_signed_distance(query_points).numpy()
    
    return signed_distances

def generate_stl_from_pymol(pdb_file, output_stl=None, selection="all", 
                           surface_quality=1, surface_solvent=False):
    """
    Generate STL file from PDB using PyMOL with correct coordinate frame.
    
    Args:
        pdb_file: Input PDB file
        output_stl: Output STL filename (default: input_surface.stl)
        selection: PyMOL selection for surface generation
        surface_quality: Surface quality (0-4, higher is better)
        surface_solvent: Whether to generate solvent-accessible surface
    
    Returns:
        Path to generated STL file
    """
    if output_stl is None:
        output_stl = pdb_file.replace('.pdb', '_surface.stl')
    
    try:
        # Initialize PyMOL in command-line mode
        pymol.finish_launching(['pymol', '-c'])
        
        # Load the structure
        cmd.load(pdb_file)
        
        # Set surface quality
        cmd.set("surface_quality", surface_quality)
        
        # Generate surface
        if surface_solvent:
            cmd.set("surface_mode", 1)  # Solvent accessible surface
        else:
            cmd.set("surface_mode", 0)  # Van der Waals surface
            
        cmd.show("surface", selection)
        
        # Important: Reset view to ensure coordinates are in model frame
        cmd.reset()
        cmd.center(selection)
        
        # Export as STL using model coordinates
        cmd.save(output_stl, f"({selection}) and surface", format="stl")
        cmd.delete("all")
        
        return output_stl
    
    except Exception as e:
        print(f"Error generating STL with PyMOL: {e}")
        return None

def main():

    import argparse
    import os

    parser = argparse.ArgumentParser(
        description='Calculate the average residue depth of each glycan residue over n frames of a viral spike glycoprotein trajectory and generate a heatmap to assess glycan burial across trimers.',
        epilog="""
Examples:
  python burgly.py trajectory.pdb
  python burgly.py trajectory.pdb -gly glyc.dat -o ./output_dir
  python burgly.py trajectory.pdb --frame-range 0 100 --outprefix mydepths
  python burgly.py trajectory.pdb --use-multimodel trajectory_multimodel.pdb --use-surface surface.stl

For any questions, contact kantorow.j@northeastern.edu
""",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument('trajectory', type=str,
                        help='Trajectory file in PDB format containing glycans partitioned by trimer via the segid column designated "CAR1", "CAR2", and "CAR3".')
    parser.add_argument('-gly', '--glycan-data', type=str, default='glyc.dat',
                        help='A text file detailing which groups of carbohydrate residues equate to which glycan structures. Looks for a file named "glyc.dat" in the current working directory if not specified.')
    parser.add_argument('-o', '--outdir', default=os.getcwd(),
                        help='The directory to which the outputs should be written.')
    parser.add_argument('-fr', '--frame-range', nargs=2, type=int, metavar=('framestart', 'framestop'), required=False,
                        help='The range of trajectory frames over which to calculate average glycan residue depth per each residue. Calculated over all frames if not specified.')
    parser.add_argument('--outprefix', type=str, default='glycan_depth',
                        help='Prefix for output files (default: glycan_depth)')
    parser.add_argument('--use-multimodel', type=str, default=None,
                        help='Use existing multimodel PDB file instead of converting the input trajectory (saves time on reruns).')
    parser.add_argument('--use-surface', type=str, default=None,
                        help='Use existing surface STL file instead of generating from first frame (saves time on reruns).')
    
    args = parser.parse_args()
    
    # Ensure output directory exists
    os.makedirs(args.outdir, exist_ok=True)

    # Parse glycan data file and create map of glycan residue numbers
    # corresponding to individual glycan chains for later processing.
    # Note- this data extracts glycan ids for a single trimer assuming
    # each trimer's glycosylation is symmetrical:
    print(f"Parsing glycan data from {args.glycan_data}...")
    glycdat = parse_glycdat(args.glycan_data)
    all_glyres_ids = [idx for glychain in glycdat.values() for idx in glychain]
    num_glycans = len(glycdat)
    num_residues = len(all_glyres_ids)
    
    print(f"Found {num_glycans} glycan chains with {num_residues} total residues")

    # Convert input trajectory to multimodel format if needed:
    if args.use_multimodel:
        print(f"Using existing multimodel trajectory: {args.use_multimodel}")
        traj_multimodel = args.use_multimodel
    else:
        print(f"Processing trajectory {args.trajectory}...")
        traj_multimodel = enforce_multimodel_format(args.trajectory)
        print(f'Trajectory converted to multimodel and saved as {traj_multimodel}')

    # Generate an MDA universe from the multimodel trajectory:
    universe = mda.Universe(traj_multimodel)
    
    # Determine frame range to process
    if args.frame_range:
        frame_start, frame_stop = args.frame_range
        trajectory_slice = universe.trajectory[frame_start:frame_stop]
        num_frames = frame_stop - frame_start
        print(f"Processing frames {frame_start} to {frame_stop} ({num_frames} frames)")
    else:
        trajectory_slice = universe.trajectory
        num_frames = len(universe.trajectory)
        print(f"Processing all {num_frames} frames")

    # Generate or use existing surface STL file:
    if args.use_surface:
        print(f"Using existing surface STL: {args.use_surface}")
        _temp_frame1_surface_stl = args.use_surface
        _temp_frame1_atoms_pdb = None  # Not needed if using existing surface
    else:
        # Write protein heavy atoms from the first frame to a temporary pdb
        # file for surface calculation:
        universe.trajectory[0]  # Move to first frame
        _temp_frame1_atoms_pdb = f'_temp_{os.path.basename(args.trajectory).replace(".pdb", "")}_frame1.pdb'
        frame_1_protein_atoms = universe.select_atoms('segid CH* and not name *H*')
        frame_1_protein_atoms.write(_temp_frame1_atoms_pdb)
        print(f'Wrote temporary frame 1 protein coordinates for surface calculation as {_temp_frame1_atoms_pdb}')

        # Generate an open3d-readable stl file of the first frame's surface:
        _temp_frame1_surface_stl = generate_stl_from_pymol(_temp_frame1_atoms_pdb)
        print(f'Wrote temporary protein surface geometry in stl format from frame 1 coordinates as {_temp_frame1_surface_stl}')

    # Pre-allocate arrays to store residue depth data
    # Shape: (num_frames, num_residues)
    car1_data = np.zeros((num_frames, num_residues))
    car2_data = np.zeros((num_frames, num_residues))
    car3_data = np.zeros((num_frames, num_residues))

    # Step through each frame of the trajectory:
    print(f"\nCalculating residue depths...")
    for frame_idx, ts in enumerate(trajectory_slice):
        if frame_idx % 10 == 0:
            print(f"  Processing frame {frame_idx + 1}/{num_frames}")
        
        # Pre-allocate arrays for centroids
        car1_residue_centroids = np.zeros((num_residues, 3))
        car2_residue_centroids = np.zeros((num_residues, 3))
        car3_residue_centroids = np.zeros((num_residues, 3))

        # Calculate the centroid of each residue from its heavy atom coordinates
        for res_idx, resnum in enumerate(all_glyres_ids):
            car1_res_n_atoms = universe.select_atoms(f'segid CAR1 and resnum {resnum} and not name *H*')
            car2_res_n_atoms = universe.select_atoms(f'segid CAR2 and resnum {resnum} and not name *H*')
            car3_res_n_atoms = universe.select_atoms(f'segid CAR3 and resnum {resnum} and not name *H*')

            centroid1 = get_centroid(car1_res_n_atoms.positions)
            centroid2 = get_centroid(car2_res_n_atoms.positions)
            centroid3 = get_centroid(car3_res_n_atoms.positions)
            
            if centroid1 is None or centroid2 is None or centroid3 is None:
                print(f"  Warning: Residue {resnum} not found in one or more segids, skipping...")
                continue
                
            car1_residue_centroids[res_idx] = centroid1
            car2_residue_centroids[res_idx] = centroid2
            car3_residue_centroids[res_idx] = centroid3

        # Compute signed distances using raycasting
        car1_data[frame_idx, :] = compute_residue_depths(car1_residue_centroids, _temp_frame1_surface_stl)
        car2_data[frame_idx, :] = compute_residue_depths(car2_residue_centroids, _temp_frame1_surface_stl)
        car3_data[frame_idx, :] = compute_residue_depths(car3_residue_centroids, _temp_frame1_surface_stl)

    print(f"\nCalculating frame-averaged depths...")
    # Compute the average depth of each residue across the frame range:
    car1_avg_res_depths = np.mean(car1_data, axis=0)
    car2_avg_res_depths = np.mean(car2_data, axis=0)
    car3_avg_res_depths = np.mean(car3_data, axis=0)

    # Reshape depth data into 2D arrays organized by glycan chain
    # Find the maximum glycan chain length for padding
    max_chain_length = max(len(chain) for chain in glycdat.values())
    
    # Create 2D arrays: rows = glycan chains, columns = residue positions
    # Fill with NaN for missing positions (variable chain lengths)
    car1_heatmap_data = np.full((num_glycans, max_chain_length), np.nan)
    car2_heatmap_data = np.full((num_glycans, max_chain_length), np.nan)
    car3_heatmap_data = np.full((num_glycans, max_chain_length), np.nan)
    
    # Map residue depths to glycan chains
    res_idx = 0
    for gly_idx in range(num_glycans):
        chain_length = len(glycdat[f'gly_{gly_idx + 1}'])
        for pos_idx in range(chain_length):
            car1_heatmap_data[gly_idx, pos_idx] = car1_avg_res_depths[res_idx]
            car2_heatmap_data[gly_idx, pos_idx] = car2_avg_res_depths[res_idx]
            car3_heatmap_data[gly_idx, pos_idx] = car3_avg_res_depths[res_idx]
            res_idx += 1

    # Save raw depth data to CSV files
    print(f"\nSaving depth data to CSV files...")
    car1_df = pd.DataFrame(car1_heatmap_data, 
                           index=[f'Glycan {i+1}' for i in range(num_glycans)],
                           columns=[f'Res {i+1}' for i in range(max_chain_length)])
    car2_df = pd.DataFrame(car2_heatmap_data,
                           index=[f'Glycan {i+1}' for i in range(num_glycans)],
                           columns=[f'Res {i+1}' for i in range(max_chain_length)])
    car3_df = pd.DataFrame(car3_heatmap_data,
                           index=[f'Glycan {i+1}' for i in range(num_glycans)],
                           columns=[f'Res {i+1}' for i in range(max_chain_length)])
    
    car1_df.to_csv(os.path.join(args.outdir, f'{args.outprefix}_CAR1.csv'))
    car2_df.to_csv(os.path.join(args.outdir, f'{args.outprefix}_CAR2.csv'))
    car3_df.to_csv(os.path.join(args.outdir, f'{args.outprefix}_CAR3.csv'))
    
    print(f"  Saved: {args.outprefix}_CAR1.csv")
    print(f"  Saved: {args.outprefix}_CAR2.csv")
    print(f"  Saved: {args.outprefix}_CAR3.csv")
    print(f"\nDepth calculations complete!")
    print(f"To generate heatmap visualizations, use burgly_heatmap.py with the CSV files.")
    
    # Clean up temporary files
    print(f"\nCleaning up temporary files...")
    if not args.use_multimodel and os.path.exists(traj_multimodel):
        # Remove multimodel file to save space
        os.remove(traj_multimodel)
        print(f"  Removed multimodel trajectory: {traj_multimodel}")
    if not args.use_surface and _temp_frame1_atoms_pdb and os.path.exists(_temp_frame1_atoms_pdb):
        os.remove(_temp_frame1_atoms_pdb)
        print(f"  Removed temporary frame 1 PDB")
    if not args.use_surface and os.path.exists(_temp_frame1_surface_stl):
        # Remove temporary surface file to save space
        os.remove(_temp_frame1_surface_stl)
        print(f"  Removed temporary surface STL: {_temp_frame1_surface_stl}")
    
    print(f"\nDone! Results saved to {args.outdir}")

if __name__ == '__main__':
    exit(main())
