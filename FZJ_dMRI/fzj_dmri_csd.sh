#!/bin/bash

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


source $(dirname $0)/fzj_dmri_functions.source


#########################################
#
#  Obtain default number of parallel processes
#
#########################################

DEFAULT_NUM_PAR_PROC=""
if [[ -n $OMP_NUM_THREADS ]]; then
    DEFAULT_NUM_PAR_PROC=$OMP_NUM_THREADS
else
    DEFAULT_NUM_PAR_PROC=$(cat /proc/cpuinfo | grep vendor_id | wc -l)
fi




DESCRIPTION="This script computes the constrained spherical deconvolution and related index maps."

OPTIONS[0]="dmri       +  IN_DMRI       +  file    +  Name of the input dMRI data set                            +  IN   +  FILE    +  1  +  none"
OPTIONS[1]="bval       +  IN_BVAL       +  file    +  Name of the input file with b-values                       +  IN   +  FILE    +  1  +  none"
OPTIONS[2]="bvec       +  IN_BVEC       +  file    +  Name of the input file with b-vectors                      +  IN   +  FILE    +  1  +  none"
OPTIONS[3]="mask       +  IN_MASK       +  file    +  Name of the binary mask volume                             +  IN   +  FILE    +  1  +  none"
OPTIONS[4]="lmax       +  IN_LMAX       +  string  +  The maximum harmonic degree(s), comma separated, incl. b0  +  IN   +  OTHER   +  1  +  none"
OPTIONS[5]="response   +  IN_RESPONSE   +  file    +  Name of the text file with response coefficients           +  IN   +  FILE    +  0  +  none"
OPTIONS[6]="parproc    +  IN_PARPROC    +  int     +  Number of parallel processes                               +  IN   +  OTHER   +  0  +  $DEFAULT_NUM_PAR_PROC"
OPTIONS[7]="signalatt  +  IN_SIGNALATT  +  1|0     +  1 for signal attenuation, 0 for signal amplitude           +  IN   +  OTHER   +  0  +  1"
OPTIONS[8]="work       +  OUT_WORK      +  folder  +  Name for the working folder for intermediate files         +  OUT  +  FOLDER  +  1  +  none"
OPTIONS[9]="csd        +  OUT_CSD       +  file    +  Name for the file with CSD coefficients                    +  OUT  +  FILE    +  0  +  none"
OPTIONS[10]="dir       +  OUT_DIR       +  file    +  Name for the file with fiber orientations                  +  OUT  +  FILE    +  0  +  none"
OPTIONS[11]="afd       +  OUT_AFD       +  file    +  Name for the file with AFD values                          +  OUT  +  FILE    +  0  +  none"
OPTIONS[12]="disp      +  OUT_DISP      +  file    +  Name for the file with dispersion values                   +  OUT  +  FILE    +  0  +  none"
OPTIONS[13]="peak      +  OUT_PEAK      +  file    +  Name for the file with peak fiber density values           +  OUT  +  FILE    +  0  +  none"
OPTIONS[14]="fa        +  OUT_FA        +  file    +  Name for the file with FA values (diffusion tensor)        +  OUT  +  FILE    +  0  +  none"
OPTIONS[15]="oresponse +  OUT_RESPONSE  +  file    +  Name of the text file with response coefficients           +  OUT  +  FILE    +  0  +  none"
OPTIONS[16]="response-only +  IN_RESPONSE_ONLY  +  1|0    +  1 for exiting after computing the response kernel   +  OUT  +  OTHER   +  0  +  0"

. $(dirname $0)/fzj_options.source


# ensure that $OUT_CSD is defined if $IN_RESPONSE_ONLY is not set
if [[ $IN_RESPONSE_ONLY -eq 0 ]] && [[ -z $OUT_CSD ]]; then
    usage
    print_and_log
    print_and_log "------------------------------------------------------------"
    print_and_log
    print_and_log "Please specify a name for the output CSD file"
    exit 1
fi



MIF_DMRI_ORIG="${OUT_WORK}/${NAME_}dmri.mif"
MIF_DMRI_SIGATT="${OUT_WORK}/${NAME_}dmri_sigatt.mif"
MIF_MASK="${OUT_WORK}/${NAME_}mask.mif"
MIF_CSD="${OUT_WORK}/${NAME_}csd.mif"
MSF_AFD="${OUT_WORK}/${NAME_}afd.msf"
MSF_DISP="${OUT_WORK}/${NAME_}disp.msf"
MSF_PEAK="${OUT_WORK}/${NAME_}peak.msf"
MIF_DIR="${OUT_WORK}/${NAME_}dir.mif"
MIF_AFD="${OUT_WORK}/${NAME_}afd.mif"
MIF_DISP="${OUT_WORK}/${NAME_}disp.mif"
MIF_PEAK="${OUT_WORK}/${NAME_}peak.mif"
MIF_B0="${OUT_WORK}/${NAME_}b0.mif"
MIF_TENSOR="${OUT_WORK}/${NAME_}tensor.mif"
MIF_FA="${OUT_WORK}/${NAME_}fa.mif"

RESPONSE="${OUT_WORK}/${NAME_}response.txt"
RESPONSE_TEMPLATE="${OUT_WORK}/${NAME_}response_%05d-%02d.txt"
MIF_SF_VOXELS="${OUT_WORK}/${NAME_}sf_voxels.mif"

MR_PARAMS="-quiet -force -nthreads $IN_PARPROC "
#MR_PARAMS="-force -nthreads $IN_PARPROC"



#########################################
#
#  Ensure clean working folder
#
#########################################
print_and_log "Ensuring clean working folder"
EXE="rm -fr ${OUT_WORK}/*"
print_and_log "    - $EXE"
eval "$EXE"


#########################################
#
#  Convert input files to MRtrix format
#
#########################################
print_and_log "Converting input files"

EXE="mrconvert $MR_PARAMS -fslgrad $IN_BVEC $IN_BVAL $IN_DMRI $MIF_DMRI_ORIG"
print_and_log "    - $EXE"
eval "$EXE"
verify $MIF_DMRI_ORIG

EXE="mrconvert $MR_PARAMS $IN_MASK $MIF_MASK"
print_and_log "    - $EXE"
eval "$EXE"
verify $MIF_MASK


#########################################
#
#  Compute signal attenuation
#
#########################################

if [[ $IN_SIGNALATT -eq 1 ]]; then
    print_and_log "Computing signal attenuation"
    print_and_log "  * extracting average b0"
    # check if there is more than 1 b0 volume
    if [[ $(mrinfo -shellcounts $MIF_DMRI_ORIG | cut -d ' ' -f 1) -eq 1 ]]; then
        # there is only 1 b0, no averaging required
        EXE="dwiextract $MR_PARAMS $MIF_DMRI_ORIG -shell 0 $MIF_B0"
    else
        # found multiple b0s, average them
        EXE="dwiextract $MR_PARAMS $MIF_DMRI_ORIG -shell 0 - | mrmath $MR_PARAMS -axis 3 - mean $MIF_B0"
    fi
    print_and_log "    - $EXE"
    eval "$EXE"
    verify $MIF_B0

    print_and_log "Computing mean of b0 volume"
    EXE="B0_MEAN=$(mrstats $MR_PARAMS $MIF_B0 -mask $MIF_MASK -output mean)"
    print_and_log "    - $EXE"
    eval "$EXE"

    print_and_log "Computing signal attenuation and normalizing with mean b0 intensity"
#    EXE="mrcalc $MR_PARAMS $MIF_DMRI_ORIG $MIF_B0 -div $B0_MEAN -mult $MIF_DMRI_SIGATT"
    EXE="mrcalc $MR_PARAMS $MIF_DMRI_ORIG $MIF_B0 -div 400 -mult $MIF_DMRI_SIGATT"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify $MIF_DMRI_SIGATT

    MIF_DMRI_USE=$MIF_DMRI_SIGATT
else
    print_and_log "using signal amplitude"
    MIF_DMRI_USE=$MIF_DMRI_ORIG
fi


#########################################
#
#  Compute response
#
#########################################

print_and_log "Verifying that number of lmax and number of shells match"
SHELLS=$(mrinfo -raw_dwgrad -shells $MIF_DMRI_USE)
EXE="SHELLS_COMMA=$(echo $SHELLS | sed -e 's/ /,/g')"
print_and_log "    - $EXE"
eval "$EXE"
EXE="NUM_SHELLS=$(echo $SHELLS | wc -w)"
print_and_log "    - $EXE"
eval "$EXE"

print_and_log "  * Number of given lmax values"
LMAXS=$(echo $IN_LMAX | sed -e 's/,/ /g')
EXE="NUM_LMAX=$(echo $LMAXS | wc -w)"
print_and_log "    - $EXE"
eval "$EXE"

# verify that number of shells and lmax match
if [[ $NUM_SHELLS -ne $NUM_LMAX ]]; then
    failed "ERROR: Number of shells ($NUM_SHELLS) and number of lmax ($NUM_LMAX) must match!"
else
    print_and_log "  * ok"
fi


print_and_log "Determining the maximum SH order"
MAX_LMAX=0
for i in $(seq $NUM_SHELLS); do
    LMAX=$(echo $LMAXS | cut -d ' ' -f $i)
    if [[ $LMAX -gt $MAX_LMAX ]]; then
        MAX_LMAX=$LMAX
    fi
done
print_and_log "max(lmax) = $MAX_LMAX"


if [[ -z $IN_RESPONSE ]]; then
    print_and_log "Computing response"
    # get the first b-value greater than 100
    for i in $(seq $NUM_SHELLS); do
        SHELL=$(printf "%0.0f" $(echo $SHELLS | cut -d ' ' -f $i))
        print_and_log "  - shell: $SHELL"
        if [[ $SHELL -gt 100 ]]; then
            break
        fi
    done
    print_and_log "  * Determining single fiber voxels from shell $SHELL"
    LMAX=$(echo $LMAXS | cut -d ' ' -f $i)
    if [[ $LMAX -gt $MAX_LMAX ]]; then
        MAX_LMAX=$LMAX
    fi
    RESPONSE_FILE=$(printf $RESPONSE_TEMPLATE $SHELL $LMAX)
    EXE="dwi2response -tempdir $OUT_WORK $MR_PARAMS tournier -mask $MIF_MASK -shell $SHELL -lmax $LMAX -voxels $MIF_SF_VOXELS $MIF_DMRI_USE $RESPONSE_FILE"
    print_and_log "    - $EXE"
    eval "$EXE" # > /dev/null
    verify $RESPONSE_FILE
    verify $MIF_SF_VOXELS

    print_and_log "  * Computing response for all shells"
    EXE="dwi2response -tempdir $OUT_WORK $MR_PARAMS manual -shell $SHELLS_COMMA -lmax $IN_LMAX $MIF_DMRI_USE $MIF_SF_VOXELS $RESPONSE"
    print_and_log "    - $EXE"
    eval "$EXE" # > /dev/null
    verify $RESPONSE
else
    print_and_log "Using \"$IN_RESPONSE\" as response"
    RESPONSE=$IN_RESPONSE
fi

if [[ -n $OUT_RESPONSE ]]; then
    print_and_log "Copying response file to output folder"
    EXE="rsync -a $RESPONSE $OUT_RESPONSE"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify $OUT_RESPONSE
fi


if [[ $IN_RESPONSE_ONLY -eq 1 ]]; then
    script_end
fi

#########################################
#
#  Compute fODF
#
#########################################

print_and_log "Computing fODF"
EXE="msdwi2fod $MR_PARAMS -bvalue_scaling true -lmax $MAX_LMAX -mask $MIF_MASK $MIF_DMRI_USE $RESPONSE $MIF_CSD"
print_and_log "    - $EXE"
eval "$EXE"
verify $MIF_CSD

print_and_log "Converting CSD file to output format"
EXE="mrconvert $MR_PARAMS $MIF_CSD $OUT_CSD"
print_and_log "    - $EXE"
eval "$EXE"
verify $OUT_CSD

#########################################
#
#  Compute index maps
#
#########################################

if [[ -n $OUT_AFD ]] || [[ -n $OUT_DISP ]] || [[ -n $OUT_PEAK ]]; then
    print_and_log "Computing index maps (fiber density, dispersion and maximal angular fiber density)"
    EXE="fod2fixel $MR_PARAMS -mask $MIF_MASK $MIF_CSD -afd $MSF_AFD -disp $MSF_DISP -peak $MSF_PEAK"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify $MSF_AFD
    verify $MSF_DISP
    verify $MSF_PEAK

    if [[ -n $OUT_DIR ]]; then
        EXE="fixel2voxel $MR_PARAMS $MSF_AFD split_dir $MIF_DIR"
        print_and_log "    - $EXE"
        eval "$EXE"
        verify $MIF_DIR

        print_and_log "Converting file with fiber direction map to output format"
        EXE="mrconvert $MR_PARAMS $MIF_DIR $OUT_DIR"
        print_and_log "    - $EXE"
        eval "$EXE"
        verify $OUT_DIR
    fi

    if [[ -n $OUT_AFD ]]; then
        EXE="fixel2voxel $MR_PARAMS $MSF_AFD split_value $MIF_AFD"
        print_and_log "    - $EXE"
        eval "$EXE"
        verify $MIF_AFD

        print_and_log "Converting file with fiber density map to output format"
        EXE="mrconvert $MR_PARAMS $MIF_AFD $OUT_AFD"
        print_and_log "    - $EXE"
        eval "$EXE"
        verify $OUT_AFD
    fi

    if [[ -n $OUT_DISP ]]; then
        EXE="fixel2voxel $MR_PARAMS $MSF_DISP split_value $MIF_DISP"
        print_and_log "    - $EXE"
        eval "$EXE"
        verify $MIF_DISP

        print_and_log "Converting file with fiber dispersion map to output format"
        EXE="mrconvert $MR_PARAMS $MIF_DISP $OUT_DISP"
        print_and_log "    - $EXE"
        eval "$EXE"
        verify $OUT_DISP
    fi

    if [[ -n $OUT_PEAK ]]; then
        EXE="fixel2voxel $MR_PARAMS $MSF_PEAK split_value $MIF_PEAK"
        print_and_log "    - $EXE"
        eval "$EXE"
        verify $MIF_PEAK

        print_and_log "Converting file with maximal angular fiber density map to output format"
        EXE="mrconvert $MR_PARAMS $MIF_PEAK $OUT_PEAK"
        print_and_log "    - $EXE"
        eval "$EXE"
        verify $OUT_PEAK
    fi
fi

if [[ -n $OUT_FA ]]; then
    print_and_log "Computing FA map"
    EXE="dwi2tensor $MR_PARAMS -mask $MIF_MASK -bvalue_scaling true $MIF_DMRI_USE $MIF_TENSOR"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify $MIF_TENSOR

    EXE="tensor2metric $MR_PARAMS -mask $MIF_MASK $MIF_TENSOR -fa $MIF_FA"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify $MIF_FA

    print_and_log "Converting file with fractional anisotropy map to out putformat"
    EXE="mrconvert $MR_PARAMS $MIF_FA $OUT_FA"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify $OUT_FA
fi


script_end
