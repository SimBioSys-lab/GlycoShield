#!/usr/bin/env python
# coding: utf-8

# In[ ]:


from MDAnalysis.analysis.distances import distance_array
import numpy as np
from itertools import combinations
import mdtraj as md
import MDAnalysis as mda
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import time
import sys


# In[ ]:


if len(sys.argv) < 2:
    print("Usage: python create_adj_matrix.py <input_file>")
    sys.exit(1)

input_file = sys.argv[1]
u = mda.Universe(input_file)


# In[ ]:


def count_sugars_per_glycan(glyc_file):
    """
    Counts the number of sugars per glycan. 

    Parameters:
    - glyc.dat: File that contains information about the glycans.

    Returns:
    - glycan_counts: Dictionary {glycan_name: number_of_sugars}
    """
    glycan_counts = {}

    # Open file
    with open(glyc_file, 'r') as file:
        current_glycan_id = None
        sugar_count = 1

        # NLGB marks the start of a new glycan. Count how many 
        # lines until a new instance of NLGB. 
        for line in file:
            if 'NGLB' in line:
                current_glycan_id = line.split()[2]
                sugar_count = 1
            else:  
                sugar_count += 1

            glycan_counts[current_glycan_id] = sugar_count
    return glycan_counts


# In[ ]:


glycan_counts = count_sugars_per_glycan('glyc.dat')


# In[ ]:


def divide_data(dict):
    """
    Generates a dictionary containing the glycans found in each protomer.

    Parameters:
    - dict: Dictionary {glycan_name: sugar_count}

    Returns:
    - glycans_in_promoters: Dictionary {protomer_name: [glycan_names]}
    """
    length = len(dict)  
    part_size = length / 3
    
    glycans_in_promoters = {'CAR1': [], 'CAR2': [], 'CAR3': []}
    
    for i, (key, value) in enumerate(dict.items()):
        if i < part_size:
            glycans_in_promoters['CAR1'].append(key)
        elif i < 2 * part_size:
            glycans_in_promoters['CAR2'].append(key)
        else:
            glycans_in_promoters['CAR3'].append(key)
    
    return glycans_in_promoters


# In[ ]:


glycans_in_protomers = divide_data(glycan_counts)


# In[ ]:


def create_glycan_mapping(glycans_in_protomers):
    """
    Create a mapping from protomer-specific IDs to common position IDs
    """
    protomers = list(glycans_in_protomers.keys())
    mapping = {}
    
    # Use first protomer as reference for numbering
    reference_protomer = protomers[0]
    num_glycans = len(glycans_in_protomers[reference_protomer])
    
    for i in range(num_glycans):
        # Use 1-based numbering: 1, 2, 3, etc.
        common_id = str(i + 1)
        for protomer in protomers:
            original_id = glycans_in_protomers[protomer][i]
            mapping[original_id] = common_id
    
    return mapping


# In[ ]:


glycan_mapping = create_glycan_mapping(glycans_in_protomers)


# In[ ]:


def get_residue_ranges(residue_dict, car_assignments):
    """
    Generates residue ID ranges for each glycan based on residue counts.

    Parameters:
    - residue_dict: Dictionary {glycan_name: sugar_count}

    Returns:
    - glycan_resid_ranges: Dictionary {glycan_name: (start_resid, end_resid)}
    """
    glycan_resid_ranges = {}

    # Create glycan ranges based on number of sugars per glycan.
    for car, glycan_ids in car_assignments.items():
        start_idx = 1

        for glycan_id in glycan_ids:
            sugar_count = residue_dict[glycan_id]
            end_idx = start_idx + sugar_count - 1
            glycan_resid_ranges[glycan_id] = (start_idx, end_idx)
            start_idx = end_idx + 1

    return glycan_resid_ranges


# In[ ]:


glycan_resid_ranges = get_residue_ranges(glycan_counts, glycans_in_protomers)


# In[ ]:


def find_protomer(glycan_id, protomer_dict):
    for protomer, glycan_list in protomer_dict.items():
        if glycan_id in glycan_list:
            return protomer
    return None

def calculate_glycan_closeness(u, glycan_resid_ranges, glycans_in_protomers, threshold=6.0):
    """
    Computes closeness between glycans based on residue ranges.

    Parameters:
    - u (MDAnalysis.Universe): The universe object.
    - glycan_resid_ranges (dict): Dictionary mapping glycan IDs ranges.
    - threshold (float): Distance threshold in Angstroms.

    Returns:
    - dict: Dictionary where keys are glycan pairs (glycanA, glycanB) and values are the number of close atom pairs.
    """
    closeness_dict = {}

    # Select atoms for each glycan
    glycan_selections = {}
    for glycan, (start, end) in glycan_resid_ranges.items():
        segid = find_protomer(glycan, glycans_in_protomers)
        selection = u.select_atoms(f"segid {segid} and resid {start}:{end}")
        glycan_selections[glycan] = selection

    # Compute closeness for all glycan pairs
    for glycanA, glycanB in combinations(glycan_selections.keys(), 2):
        atomsA = glycan_selections[glycanA]
        atomsB = glycan_selections[glycanB]

        # Get atom positions
        pos1 = atomsA.positions
        pos2 = atomsB.positions

        # Compute distance matrix
        dist_matrix = distance_array(pos1, pos2)

        # Count number of pairs within threshold Å
        num_pairs = np.sum(dist_matrix <= threshold)

        closeness_dict[(glycanA, glycanB)] = num_pairs

    return closeness_dict


# In[ ]:


closeness_results = calculate_glycan_closeness(u, glycan_resid_ranges, glycans_in_protomers)


# In[ ]:


def closeness_to_adjacency(closeness_dict, glycan_counts):
    """
    Convert closeness dictionary into an adjacency matrix.

    Parameters:
    - closeness_dict (dict): Dictionary with glycan pairs as keys and closeness as values.

    Returns:
    - df: Adjacency matrix.
    """
    # Extract unique glycans
    glycans = list(set(glycan_counts.keys()))

    # Create an empty adjacency matrix
    adj_matrix = pd.DataFrame(0, index=glycans, columns=glycans)

    # Fill the matrix with closeness values
    for (glycanA, glycanB), value in closeness_dict.items():
        adj_matrix.at[glycanA, glycanB] = value
        adj_matrix.at[glycanB, glycanA] = value
    
    return adj_matrix


# In[ ]:


adj_matrix = closeness_to_adjacency(closeness_results, glycan_counts)


# In[ ]:


# Extract base name without extension (e.g., '250_frames_clean_no_ends')
import os

base_name = os.path.splitext(os.path.basename(input_file))[0]

# Construct output filename
output_file = f"{base_name}_adjacency_matrix.csv"

# Save DataFrame to CSV
adj_matrix.to_csv(output_file)

