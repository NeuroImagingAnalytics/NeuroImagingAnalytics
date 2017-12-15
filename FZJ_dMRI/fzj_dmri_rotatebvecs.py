#!/usr/bin/env python
# coding: utf-8

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

import numpy as np
import argparse

description = 'Rotate b-vectors according to given affine transformation.'

parser = argparse.ArgumentParser(description=description)
parser.add_argument('bvec',
                    help='Text file with b-vectors (FSL format)')
parser.add_argument('affine',
                    help='4x4 transformation matrix (FLIRT format)')
parser.add_argument('output',
                    help='Rotated b-vectors')

args = parser.parse_args()

bvecs = np.loadtxt(args.bvec)
affine = np.loadtxt(args.affine)[:3, :3]

new_bvecs = np.dot(affine, bvecs)

np.savetxt(args.output, new_bvecs, fmt='%0.12f', delimiter=' ')
