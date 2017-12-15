# -*- coding: utf-8 -*-

# Copyright 2017 Forschungszentrum Juelich

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


from __future__ import print_function, division

import argparse

import numpy as np
import nibabel as nib
from dipy.core.gradients import gradient_table_from_bvals_bvecs
from dipy.io import read_bvals_bvecs
from dipy.reconst.shm import anisotropic_power
from dipy.reconst.csdeconv import auto_response
from dipy.reconst.csdeconv import ConstrainedSphericalDeconvModel
from dipy.direction import peaks_from_model
from dipy.data import get_sphere


def anisotropic_power_map(data, mask, gtab, power=2,
                          nbr_processes=None, verbose=False):
    # compute response
    if verbose:
        print('  - computing response')
    response, _ = auto_response(gtab, data, roi_radius=10, fa_thr=0.7)

    # compute spherical harmonics from spherical deconvoluten
    if verbose:
        print('  - preparing spherical deconvolution model')
    csd_model = ConstrainedSphericalDeconvModel(gtab, response)
    sphere = get_sphere('symmetric724')
    if verbose:
        print('  - computing spherical harmonics from spherical deconvolution')
    csd_peaks = peaks_from_model(model=csd_model,
                                 data=data,
                                 mask=mask,
                                 sphere=sphere,
                                 relative_peak_threshold=.5,
                                 min_separation_angle=25,
                                 parallel=True,
                                 nbr_processes=nbr_processes)

    # compute anisotropic power map
    if verbose:
        print('  - computing anisotropic power map')
    return anisotropic_power(csd_peaks.shm_coeff, norm_factor=1e-05,
                             power=power, non_negative=True)


def main():
    # parse command line parameters
    parser = argparse.ArgumentParser(description='Compute the anisotropic \
    power map for the given dMRI data set. Computes spherical deconvolution \
    from the highest b-balue. ')
    parser.add_argument('data',   help='[IN]  4D input data volume')
    parser.add_argument('bval',
                        help='[IN]  text file with b-values (FSL format)')
    parser.add_argument('bvec',
                        help='[IN]  text file with b-vectors (FSL format)')
    parser.add_argument('mask',   help='[IN]  3D mask volume')
    parser.add_argument('--power', default=2, type=float,
                        help='[IN]  The degree to which power maps are calculated')
    parser.add_argument('out',
                        help='[OUT] name of file for anisotropic power map')
    parser.add_argument('--attenuation', '-a', action='store_true',
                        default=False,
                        help='use signal attenuation instead of full signal amplitude')
    parser.add_argument('--n_processes', '-j', default=8, type=int,
                        help='Number of parallel processes')
    parser.add_argument('--verbose', '-v', action='store_true', default=False,
                        help='be verbose')

    args = parser.parse_args()

    data_file_name = args.data
    bval_file_name = args.bval
    bvec_file_name = args.bvec
    mask_file_name = args.mask
    power = args.power
    out_file_name = args.out
    signal_attenuation = args.attenuation
    nbr_processes = args.n_processes
    verbose = args.verbose

    # load b-values and b-vectors
    if verbose:
        print('loading b-values and b-vectors')
    bvals, bvecs = read_bvals_bvecs(bval_file_name, bvec_file_name)

    # round b-values to 50s
    bvals = np.round(bvals / 50.0) * 50
    b_thresh = np.max(bvals) - 10

    selected_volumes = np.asarray([np.any(tup) for tup in zip(bvals > b_thresh,
                                                              bvals < 50)])

    gtab = gradient_table_from_bvals_bvecs(bvals[selected_volumes],
                                           bvecs[selected_volumes],
                                           atol=0.1)
    if verbose:
        print(gtab.bvals)

    # load the diffusion data
    if verbose:
        print('loading mask')
    img = nib.load(mask_file_name)
    mask = img.get_data()

    # load the diffusion data
    if verbose:
        print('loading diffusion data')
    img = nib.load(data_file_name)
    affine = img.get_affine()
    data = img.get_data(caching='unchanged')[..., selected_volumes]

    if signal_attenuation:
        # compute signal attenuation
        if verbose:
            print('computing signal attenuation')
        mean_b0 = np.mean(data[..., gtab.b0s_mask], axis=3)
        # vectorize !
        for vol in range(data.shape[3]):
            data[..., vol] = data[..., vol] / mean_b0

    if verbose:
        print('ensuring valid numbers')
    data = np.nan_to_num(data)
    data[data < 0] = 0

    # compute anisotropic power map
    if verbose:
        print('compute anisotropic power map')
    apm = anisotropic_power_map(data, mask, gtab, power=power,
                                nbr_processes=nbr_processes, verbose=verbose)

    # save anisotropic power map
    img = nib.Nifti1Image(apm, affine)
    nib.save(img, out_file_name)

if __name__ == '__main__':
    main()
