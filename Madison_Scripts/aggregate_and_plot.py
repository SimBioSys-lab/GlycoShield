#!/usr/bin/env python
# coding: utf-8

# In[1]:


import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import glob

def aggregate_adjacency_matrices_sum(csv_files):
    """
    Aggregate multiple adjacency matrices by summing them.
    
    Parameters:
    -----------
    csv_files : list
        List of CSV file paths
    
    Returns:
    --------
    pandas.DataFrame : Summed matrix
    """
    matrices = []
    
    for csv_file in csv_files:
        print(f"Loading {csv_file}...")
        df = pd.read_csv(csv_file, index_col=0)
        matrices.append(df.values)
    
    # Stack and sum all matrices
    stacked = np.stack(matrices, axis=0)
    summed = np.sum(stacked, axis=0)
    
    # Create DataFrame with same index/columns as first matrix
    first_df = pd.read_csv(csv_files[0], index_col=0)
    result_df = pd.DataFrame(
        summed,
        index=first_df.index,
        columns=first_df.columns
    )
    
    return result_df

def plot_glycan_histogram(adjacency_matrix, output_file='glycan_histogram.png'):
    """
    Create histogram of glycan contact frequencies.
    
    Parameters:
    -----------
    adjacency_matrix : pandas.DataFrame
        Aggregated adjacency matrix
    output_file : str
        Output filename for the plot
    """
    # Sum contacts for each glycan (sum across rows)
    glycan_contacts = adjacency_matrix.sum(axis=1)
    
    # Create figure
    plt.figure(figsize=(12, 6))
    
    # Plot histogram
    plt.hist(glycan_contacts.values, bins=50, edgecolor='black', alpha=0.7)
    plt.xlabel('Total Number of Contacts', fontsize=12)
    plt.ylabel('Frequency', fontsize=12)
    plt.title('Distribution of Glycan Contacts (All 784 Glycans)', fontsize=14)
    plt.grid(axis='y', alpha=0.3)
    
    # Add statistics
    mean_contacts = glycan_contacts.mean()
    median_contacts = glycan_contacts.median()
    plt.axvline(mean_contacts, color='red', linestyle='--', 
                label=f'Mean: {mean_contacts:.2f}')
    plt.axvline(median_contacts, color='blue', linestyle='--', 
                label=f'Median: {median_contacts:.2f}')
    plt.legend()
    
    plt.tight_layout()
    plt.savefig(output_file, dpi=300)
    print(f"Histogram saved to {output_file}")
    
    # Print summary statistics
    print("\nGlycan Contact Statistics:")
    print(f"Total glycans: {len(glycan_contacts)}")
    print(f"Mean contacts: {mean_contacts:.2f}")
    print(f"Median contacts: {median_contacts:.2f}")
    print(f"Std Dev: {glycan_contacts.std():.2f}")
    print(f"Min contacts: {glycan_contacts.min():.2f}")
    print(f"Max contacts: {glycan_contacts.max():.2f}")

def main():
    # Get list of CSV files
    csv_files = glob.glob("*_adjacency_matrix.csv")
    
    if not csv_files:
        print("No adjacency matrix CSV files found!")
        return
    
    print(f"Found {len(csv_files)} CSV files:")
    for f in csv_files:
        print(f"  - {f}")
    
    # Aggregate matrices by sum
    print("\nAggregating matrices (sum)...")
    aggregated_matrix = aggregate_adjacency_matrices_sum(csv_files)
    
    # Save aggregated matrix
    output_csv = "aggregated_adjacency_matrix_sum.csv"
    aggregated_matrix.to_csv(output_csv)
    print(f"\nAggregated matrix saved to {output_csv}")
    print(f"Matrix shape: {aggregated_matrix.shape}")
    
    # Create histogram
    print("\nCreating histogram...")
    plot_glycan_histogram(aggregated_matrix)

if __name__ == "__main__":
    main()

