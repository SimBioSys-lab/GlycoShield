#!/usr/bin/env python
# coding: utf-8

# In[1]:


import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
from matplotlib.colors import LinearSegmentedColormap


# In[2]:


df = pd.read_csv('aggregated_adjacency_matrix_sum.csv', index_col=0)


# In[3]:


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


# In[4]:


glycan_counts = count_sugars_per_glycan('glyc.dat')


# In[5]:


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


# In[6]:


glycans_in_protomers = divide_data(glycan_counts)


# In[7]:


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


# In[8]:


glycan_mapping = create_glycan_mapping(glycans_in_protomers)


# In[9]:


def normalize_adjacency_matrix(avg_matrix):
    """
    Find the 98th percentile (top 2%) value
    """
    # Flatten the matrix and remove zeros to get non-zero values
    non_zero_values = avg_matrix.values.flatten()
    non_zero_values = non_zero_values[non_zero_values > 0]
    
    if len(non_zero_values) > 0:
        # Calculate the 98th percentile (top 2%)
        percentile_98 = np.percentile(non_zero_values, 98)
        return percentile_98


# In[10]:


def separate_by_protomer(adj_matrix, glycans_in_protomers):
    """
    Separate the adjacency matrix by protomer.
    Only includes glycans that actually exist in the adjacency matrix.
    
    Parameters:
    - adj_matrix: Full adjacency matrix
    - glycans_in_protomers: Dictionary mapping protomers to lists of glycan IDs
    
    Returns:
    - matrices: Dictionary of intra-protomer matrices for each protomer
    """
    # Convert the adjacency matrix indices to strings
    adj_matrix = adj_matrix.copy()
    adj_matrix.index = adj_matrix.index.astype(str)
    adj_matrix.columns = adj_matrix.columns.astype(str)
    
    # Get the actual glycans present in the adjacency matrix
    available_glycans = set(adj_matrix.index)
    
    # Create intra-protomer matrices
    matrices = {}
    for protomer, glycans in glycans_in_protomers.items():
        # Convert glycans to strings and only use glycans that are actually in the matrix
        valid_glycans = [str(g) for g in glycans if str(g) in available_glycans]
        
        if valid_glycans:
            matrices[protomer] = adj_matrix.loc[valid_glycans, valid_glycans].copy()
        else:
            # If no glycans remain after filtering, create an empty DataFrame
            matrices[protomer] = pd.DataFrame()
    
    return matrices


# In[11]:


def average_matrices(matrices):
    """
    Average matrices with same indices/columns
    """
    if not matrices:
        return pd.DataFrame()
    
    arrays = [matrix.values for matrix in matrices]
    avg_array = sum(arrays) / len(arrays)
    
    avg_matrix = pd.DataFrame(
        avg_array, 
        index=matrices[0].index, 
        columns=matrices[0].columns
    )
    
    return avg_matrix


# In[15]:


def remap_matrix_indices(matrix, glycan_mapping):
    """
    Remap matrix indices using the glycan mapping
    """
    new_index = [glycan_mapping.get(str(idx), str(idx)) for idx in matrix.index]
    new_columns = [glycan_mapping.get(str(col), str(col)) for col in matrix.columns]
    
    remapped = matrix.copy()
    remapped.index = new_index
    remapped.columns = new_columns
    
    return remapped


# In[12]:


def plot_heatmap(matrix, title, glycan_in_protomers, vmin=0, vmax=1):
    """
    Plot a heatmap from the adjacency matrix.
    
    Parameters:
    - matrix: DataFrame containing the adjacency matrix
    - title: Title for the plot
    - glycan_in_protomers: List of glycan names for axis labels
    - vmin: Minimum value for colormap
    - vmax: Maximum value for the colormap
    """
    plt.figure(figsize=(12, 11))
    
    colors = ["white", "yellow", "orange", "red", "black"]
    cmap_continuous = LinearSegmentedColormap.from_list(
        "white_yellow_orange_red_black",
        colors,
        N=256
    )
    
    # Only mask actual 0 values (not values <= 0.2, since colormap handles those)
    masked_matrix = matrix.mask(matrix == 0)
    
    # Plot heatmap
    ax = sns.heatmap(
        masked_matrix,
        cmap=cmap_continuous,
        vmin=vmin,
        vmax=vmax,
        square=True,
        linewidths=0.5,
        cbar_kws={"shrink": 0.8, "label": "Adjacency Value"},
        xticklabels=glycan_in_protomers,
        yticklabels=glycan_in_protomers
    )
    
    # Add outline around the entire plot
    for spine in ax.spines.values():
        spine.set_visible(True)
        spine.set_linewidth(1)
        spine.set_edgecolor('black')
    
    # Add outline to colorbar
    cbar = ax.collections[0].colorbar
    cbar.outline.set_linewidth(1)
    cbar.outline.set_edgecolor('black')
    
    plt.xticks(rotation=90, fontsize=8)
    plt.yticks(rotation=0, fontsize=8)
    plt.xlabel('Glycan', fontsize=20, fontweight='bold', labelpad=15)
    plt.ylabel('Glycan', fontsize=20, fontweight='bold', labelpad=15)
    plt.title(title, fontsize=24, pad=25)
    plt.tight_layout()
    
    if title:
        save_path = f"{title}.png"
        plt.savefig(save_path, dpi=300, bbox_inches='tight')
        print(f"Saved to {save_path}")
    
    plt.show()


# In[16]:


# Main workflow
def create_all_plots(adj_matrix, glycans_in_protomers, threshold_keep=0.1):
    """
    Create all required intra and inter protomer plots with separate normalization
    """
    
    # Create glycan mapping
    glycan_mapping = create_glycan_mapping(glycans_in_protomers)
    
    # 1. INTRA-PROTOMER ANALYSIS
    print("Creating intra-protomer matrices...")
    
    # Get individual intra-protomer matrices (raw, unnormalized)
    intra_matrices_raw = separate_by_protomer(adj_matrix, glycans_in_protomers)
    
    # Remap to common reference (still unnormalized)
    intra_matrices_remapped = {}
    for protomer, matrix in intra_matrices_raw.items():
        if not matrix.empty:
            intra_matrices_remapped[protomer] = remap_matrix_indices(matrix, glycan_mapping)
    
    # Calculate average intra matrix and find its maximum for normalization
    avg_intra_raw = average_matrices(list(intra_matrices_remapped.values()))
    intra_max_value = normalize_adjacency_matrix(avg_intra_raw)
    
    print(f"Intra-protomer normalization value (max of average): {intra_max_value}")
    
    # 3. NORMALIZE AND PLOT INTRA-PROTOMER MATRICES
    intra_matrices = {}
    for protomer, matrix in intra_matrices_remapped.items():
        # Normalize by intra max value
        normalized_matrix = matrix / intra_max_value if intra_max_value > 0 else matrix
        normalized_matrix[normalized_matrix < threshold_keep] = 0
        intra_matrices[protomer] = normalized_matrix
        plot_heatmap(normalized_matrix, f"{protomer} Intra-Protomer Glycan Closeness", glycans_in_protomers["CAR1"])
    
    # Plot normalized average intra-protomer
    avg_intra = avg_intra_raw / intra_max_value if intra_max_value > 0 else avg_intra_raw
    avg_intra[avg_intra < threshold_keep] = 0
    plot_heatmap(avg_intra, "Average Intra-Protomer Glycan Closeness", glycans_in_protomers["CAR1"])
    
    return intra_matrices, avg_intra


# In[17]:


intra_matrices, avg_intra = create_all_plots(df, glycans_in_protomers)

