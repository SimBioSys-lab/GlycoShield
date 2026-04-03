#!/usr/bin/env python3

'''
Plot residue depth data generated from burgly.
'''

import numpy as np
import pandas as pd

import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap as lsc

def main():

    import argparse
    import os

    parser = argparse.ArgumentParser(
        description='Calculate the average residue depth of each glycan residue over n frames of a viral spike glycoprotein trajectory and generate a heatmap to assess glycan burial across trimers.',
        epilog="""
Examples:
  python burgly_heatmap.py car1_depth_data.csv car2_depth_data.csv car3_depth_data.csv
  python burgly_heatmap.py car*_depth_data.csv -o results/ --outprefix spike_D --title 'SARS-CoV2 Spike D | Frames 1-100'

For any questions, contact kantorow.j@northeastern.edu
""",
        formatter_class=argparse.RawDescriptionHelpFormatter

    )
    parser.add_argument('depthdata', nargs=3, type=str, metavar=('car1dat', 'car2dat', 'car3dat'),
                        help='The three csv files output by burgly containing per-residue depth information for each glycan of each trimer of a spike glycoprotein.')
    parser.add_argument('--title', type=str, required=False,
                        help='The title of the plot if specified.')
    parser.add_argument('-o', '--outdir', default=os.getcwd(),
                        help='The directory to which the outputs should be written.')
    parser.add_argument('--outprefix', type=str, default='glycan_depth',
                        help='Prefix for output files (default: glycan_depth)')

    args = parser.parse_args()

    car1_csv, car2_csv, car3_csv = args.depthdata

    car1_depths = pd.read_csv(car1_csv, index_col=0)
    car2_depths = pd.read_csv(car2_csv, index_col=0)
    car3_depths = pd.read_csv(car3_csv, index_col=0)

    car1_heatmap_data = car1_depths.values
    car2_heatmap_data = car2_depths.values
    car3_heatmap_data = car3_depths.values

    num_glycans = car1_heatmap_data.shape[0]
    max_chain_length = car1_heatmap_data.shape[1]

    start_res_col = 0

    all_data = np.concatenate([car1_heatmap_data[:, start_res_col:].flatten(),
                               car2_heatmap_data[:, start_res_col:].flatten(),
                               car3_heatmap_data[:, start_res_col:].flatten()])

    all_data = all_data[~np.isnan(all_data)]

    vmin = np.floor(np.min(all_data))
    vmax = np.ceil(np.max(all_data))

    cmap = lsc.from_list('custom', 
                        [(0, 'darkred'), ((-vmin/(-vmin+vmax)), 'white'), (1, 'darkblue')], 
                        N=100)

    fig, axes = plt.subplots(1, 3, figsize=(22, 8))
        
    trimers = [('CAR1', car1_heatmap_data), 
                ('CAR2', car2_heatmap_data), 
                ('CAR3', car3_heatmap_data)]

    for ax, (trimer_name, data) in zip(axes, trimers):
        # Show all residue data
        plot_data = data[:, start_res_col:]
        
        im = ax.imshow(plot_data, cmap=cmap, interpolation='nearest',
                        vmin=vmin, vmax=vmax, aspect='auto',
                        extent=[start_res_col+1, max_chain_length+1, num_glycans, 0])
        
        # Set up axes
        ax.set_xticks(np.arange(start_res_col+1, max_chain_length+1) + 0.5)
        ax.set_xticklabels(range(start_res_col+1, max_chain_length+1), fontsize=12)
        ax.set_yticks(np.arange(num_glycans) + 0.5)
        ax.set_yticklabels(range(1, num_glycans+1), fontsize=12)
        
        ax.set_xlabel('Residue Position', fontsize=14)
        ax.set_ylabel('Glycan Chain', fontsize=14)
        ax.set_title(f'{trimer_name}', fontsize=16)

    # Add shared colorbar with more space and better tick marks
    fig.subplots_adjust(right=0.88)  # Leave more room on the right
    cbar_ax = fig.add_axes([0.90, 0.15, 0.015, 0.7])  # [left, bottom, width, height]
    cbar = fig.colorbar(im, cax=cbar_ax)
    cbar.ax.tick_params(labelsize=12)
    cbar.set_label(r'Distance From Protein Surface ($\AA$)', fontsize=14)
        
    # Add more tick marks to show red values better
    # Create ticks that emphasize the buried (negative) range
    if vmin < 0:
        # Include several ticks in the buried range
        buried_ticks = np.linspace(vmin, 0, 5)  # 5 ticks from most negative to 0
        exposed_ticks = np.linspace(0, vmax, 4)[1:]  # 3 ticks from 0 to most positive (exclude 0)
        tick_values = np.concatenate([buried_ticks, exposed_ticks])
    else:
        tick_values = np.linspace(vmin, vmax, 8)

    cbar.set_ticks(tick_values)
    cbar.set_ticklabels([f'{v:.1f}' for v in tick_values])

    # Overall title
    if args.title:
        fig.suptitle(f'{args.title}', fontsize=18, y=0.98)
    
    # Save figure
    output_fig = os.path.join(args.outdir, f'{args.outprefix}_heatmap.png')
    fig.savefig(output_fig, dpi=300, bbox_inches='tight')
    print(f"  Saved: {args.outprefix}_heatmap.png")

if __name__ == '__main__':
    exit(main())
