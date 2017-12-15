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


DESCRIPTION="$(basename $SCRIPT_NAME) merges 2 dmri data sets, averages the b0 volumes + \
and corrects the second data set for a different TE. + \
The merged data set will have only a single b0.  + \
The optional masks will be combined with an AND operation."

OPTIONS[0]="dmri1     +  IN_DMRI1      +  file     +  The diffusion weighted data set                                 +  IN   +  FILE    +  1  +  none"
OPTIONS[1]="bval1     +  IN_BVAL1      +  file     +  Text file with b-values (FSL convention)                        +  IN   +  FILE    +  1  +  none"
OPTIONS[2]="bvec1     +  IN_BVEC1      +  file     +  Text file with b-vectors (FSL convention)                       +  IN   +  FILE    +  1  +  none"
OPTIONS[3]="mask1     +  IN_MASK1      +  file     +  Mask for the dMRI data                                          +  IN   +  FILE    +  0  +  none"
OPTIONS[4]="dmri2     +  IN_DMRI2      +  file     +  The diffusion weighted data set                                 +  IN   +  FILE    +  1  +  none"
OPTIONS[5]="bval2     +  IN_BVAL2      +  file     +  Text file with b-values (FSL convention)                        +  IN   +  FILE    +  1  +  none"
OPTIONS[6]="bvec2     +  IN_BVEC2      +  file     +  Text file with b-vectors (FSL convention)                       +  IN   +  FILE    +  1  +  none"
OPTIONS[7]="mask2     +  IN_MASK2      +  file     +  Mask for the dMRI data                                          +  IN   +  FILE    +  0  +  none"
OPTIONS[8]="odmri     +  OUT_DMRI      +  file     +  The merged diffusion weighted data set                          +  OUT  +  FILE    +  1  +  none"
OPTIONS[9]="obval     +  OUT_BVAL      +  file     +  Text file with merged b-values (FSL convention)                 +  OUT  +  FILE    +  1  +  none"
OPTIONS[10]="obvec    +  OUT_BVEC      +  file     +  Text file with merged b-vectors (FSL convention)                +  OUT  +  FILE    +  1  +  none"
OPTIONS[11]="omask    +  OUT_MASK      +  file     +  Mask for the dMRI data                                          +  OUT  +  FILE    +  0  +  none"
OPTIONS[12]="work     +  OUT_WORK      +  dir      +  Working directory (if exists, contents will be deleted!)        +  OUT  +  FOLDER  +  1  +  none"
OPTIONS[13]="bedpostx +  OUT_BEDPOSTX  +  dir      +  Folder for data prepared for bedpostx                           +  OUT  +  FOLDER  +  0  +  none"

. $(dirname $0)/fzj_options.source


# append underscore to name string
if [[ -n $NAME ]]; then
    NAME_STRING="${NAME}_"
else
    NAME_STRING=""
fi


if [[ -z $IN_MASK1 ]] && [[ -z $IN_MASK2 ]] && [[ -n $OUT_MASK ]]; then
    print_and_log "ERROR: Cannot create output mask without input masks"
    script_end
fi


# remove existing working folder
if [[ -e $OUT_WORK ]]; then
    rm -fr ${OUT_WORK}/*
fi

SPLIT_FOLDER_1="${OUT_WORK}/${NAME_STRING}Volumes_1"
SPLIT_FOLDER_2="${OUT_WORK}/${NAME_STRING}Volumes_2"

SPLIT_VOLUMES_1="${SPLIT_FOLDER_1}/vol_"
SPLIT_VOLUMES_2="${SPLIT_FOLDER_2}/vol_"

AVERAGE_B0_1="${OUT_WORK}/${NAME_STRING}1_b0_average.nii.gz"
AVERAGE_B0_2="${OUT_WORK}/${NAME_STRING}2_b0_average.nii.gz"

BATCH_FSLMATHS="${OUT_WORK}/${NAME_STRING}batch_fslmaths.txt"


DMRI="${OUT_WORK}/${NAME_STRING}dmri.nii.gz"
BVAL="${OUT_WORK}/${NAME_STRING}dmri.bval"
BVEC="${OUT_WORK}/${NAME_STRING}dmri.bvec"
MASK="${OUT_WORK}/${NAME_STRING}mask.nii.gz"

#########################################
#
# collect volume indices of unique b-values
#
#########################################

print_and_log "Collecting volume indices of b0 and b>0 b-values"
#  echo: result in one line
# cat : get content of bval file
# tr: squeeze multiple spaces into a single space character
# sed -e "s/ /\n/g" : convert spaces to newlines
# sed '/^[[:space:]]*$/d' : remove empty lines (last line might not be handled by tr
# grep : print the lines numbers, ':' and the line where '0' appears as a whole word
# cut : keep only the line number
# awk : subtract 1 to get a zero based value
#
# grep -v : gives the inverse result (all lines where '0' does not appear as a whole word
INDICES_1_0=$(echo $(cat $IN_BVAL1 | tr -s [:space:] | sed -e "s/ /\n/g" | sed '/^[[:space:]]*$/d' | grep -w --line-number 0 | cut -d ':' -f 1 | awk '{print ($1 - 1)}'))
print_and_log "  * 1 b=0 :  $INDICES_1_0"

INDICES_1_X=$(echo $(cat $IN_BVAL1 | tr -s [:space:] | sed -e "s/ /\n/g" | sed '/^[[:space:]]*$/d' | grep -v -w --line-number 0 | cut -d ':' -f 1 | awk '{print ($1 - 1)}'))
INDICES_1_X_BASE_1=$(echo $(cat $IN_BVAL1 | tr -s [:space:] | sed -e "s/ /\n/g" | sed '/^[[:space:]]*$/d' | grep -v -w --line-number 0 | cut -d ':' -f 1))
print_and_log "  * 1 b>0 :  $INDICES_1_X"

INDICES_2_0=$(echo $(cat $IN_BVAL2 | tr -s [:space:] | sed -e "s/ /\n/g" | sed '/^[[:space:]]*$/d' | grep -w --line-number 0 | cut -d ':' -f 1 | awk '{print ($1 - 1)}'))
print_and_log "  * 2 b=0 :  $INDICES_2_0"

INDICES_2_X=$(echo $(cat $IN_BVAL2 | tr -s [:space:] | sed -e "s/ /\n/g" | sed '/^[[:space:]]*$/d' | grep -v -w --line-number 0 | cut -d ':' -f 1 | awk '{print ($1 - 1)}'))
INDICES_2_X_BASE_1=$(echo $(cat $IN_BVAL2 | tr -s [:space:] | sed -e "s/ /\n/g" | sed '/^[[:space:]]*$/d' | grep -v -w --line-number 0 | cut -d ':' -f 1))
print_and_log "  * 2 b>0 :  $INDICES_2_X"



#########################################
#
# split volumes
#
#########################################

print_and_log "Splitting input data into single volumes"
EXE="mkdir -p $SPLIT_FOLDER_1"
print_and_log "    - $EXE"
eval "$EXE"
EXE="${FSLDIR}/bin/fslsplit $IN_DMRI1 $SPLIT_VOLUMES_1 -t"
print_and_log "    - $EXE"
eval "$EXE"

EXE="mkdir -p $SPLIT_FOLDER_2"
print_and_log "    - $EXE"
eval "$EXE"
EXE="${FSLDIR}/bin/fslsplit $IN_DMRI2 $SPLIT_VOLUMES_2 -t"
print_and_log "    - $EXE"
eval "$EXE"


#########################################
#
# averaging b0 volumes
#
#########################################

print_and_log "Averaging b0 volumes"
EXE="${FSLDIR}/bin/fsladd $AVERAGE_B0_1 -m"
for i in $INDICES_1_0; do
    EXE="$EXE ${SPLIT_VOLUMES_1}$(printf '%04d' $i).nii.gz"
done
print_and_log "    - $EXE"
eval "$EXE" > /dev/null
verify $AVERAGE_B0_1

EXE="${FSLDIR}/bin/fsladd $AVERAGE_B0_2 -m"
for i in $INDICES_2_0; do
    EXE="$EXE ${SPLIT_VOLUMES_2}$(printf '%04d' $i).nii.gz"
done
print_and_log "    - $EXE"
eval "$EXE" > /dev/null
verify $AVERAGE_B0_2



#########################################
#
# TE-Normalize 2nd dMRI volumes
#
#########################################

print_and_log "TE-Normalizing volumes of 2nd dMRI data set"
for i in $INDICES_2_X; do
    EXE="${FSLDIR}/bin/fslmaths ${SPLIT_VOLUMES_2}$(printf '%04d' $i).nii.gz -mul $AVERAGE_B0_1 -div $AVERAGE_B0_2 ${SPLIT_VOLUMES_2}$(printf '%04d' $i).nii.gz -odt float"
    print_and_log "    - $EXE"
    echo "$EXE" >> $BATCH_FSLMATHS
done

# execute in parallel
EXE="$(dirname $0)/fzj_parallel.sh -m $BATCH_FSLMATHS -j $FZJ_NUM_PROCS"
print_and_log "        - $EXE"
eval "$EXE"

# verify that all files have been written
for i in $INDICES_2_X; do
    verify ${SPLIT_VOLUMES_2}$(printf '%04d' $i).nii.gz
done

#########################################
#
# Combine masks
#
#########################################

if [[ -n $IN_MASK1 ]] && [[ -n $IN_MASK2 ]]; then
    print_and_log "Combining masks"
    EXE="${FSLDIR}/bin/fslmaths $IN_MASK1 -mas $IN_MASK2 $MASK -odt char"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify $MASK
elif [[ -n $IN_MASK1 ]]; then
    print_and_log "Using mask 1"
    EXE="${FSLDIR}/bin/fslmaths $IN_MASK1 $MASK -odt char"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify $MASK
elif [[ -n $IN_MASK2 ]]; then
    print_and_log "Using mask 2"
    EXE="${FSLDIR}/bin/fslmaths $IN_MASK2 $MASK -odt char"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify $MASK
fi


#########################################
#
# Merge final data set
#
#########################################

print_and_log "Merging final data set"
EXE="${FSLDIR}/bin/fslmerge -t $DMRI $AVERAGE_B0_1"
for i in $INDICES_1_X; do
    EXE="$EXE ${SPLIT_VOLUMES_1}$(printf '%04d' $i).nii.gz"
done
for i in $INDICES_2_X; do
    EXE="$EXE ${SPLIT_VOLUMES_2}$(printf '%04d' $i).nii.gz"
done
print_and_log "    - $EXE"
eval "$EXE"
verify $DMRI

if [[ -e $MASK ]]; then
    print_and_log "  * masking data"
    EXE="${FSLDIR}/bin/fslmaths $DMRI -mas $MASK $DMRI"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify $DMRI
fi

#########################################
#
# Merge final b-values
#
#########################################

print_and_log "Merging final b-value file"
NEW_BVALS="0 "
NEW_BVALS="$NEW_BVALS $(cat $IN_BVAL1 | tr -s [:space:] | cut -d ' ' -f $(echo $INDICES_1_X_BASE_1 | sed -e 's/ /,/g')) "
NEW_BVALS="$NEW_BVALS $(cat $IN_BVAL2 | tr -s [:space:] | cut -d ' ' -f $(echo $INDICES_2_X_BASE_1 | sed -e 's/ /,/g')) "
echo $NEW_BVALS > $BVAL
verify $BVAL



#########################################
#
# Merge final b-vectors
#
#########################################

print_and_log "Merging final b-value file"
NEW_BVECS_X="0 "
NEW_BVECS_Y="0 "
NEW_BVECS_Z="0 "

NEW_BVECS_X="$NEW_BVECS_X $(head -n 1 $IN_BVEC1 | tail -n 1 | tr -s [:space:] | cut -d ' ' -f $(echo $INDICES_1_X_BASE_1 | sed -e 's/ /,/g')) "
NEW_BVECS_Y="$NEW_BVECS_Y $(head -n 2 $IN_BVEC1 | tail -n 1 | tr -s [:space:] | cut -d ' ' -f $(echo $INDICES_1_X_BASE_1 | sed -e 's/ /,/g')) "
NEW_BVECS_Z="$NEW_BVECS_Z $(head -n 3 $IN_BVEC1 | tail -n 1 | tr -s [:space:] | cut -d ' ' -f $(echo $INDICES_1_X_BASE_1 | sed -e 's/ /,/g')) "

NEW_BVECS_X="$NEW_BVECS_X $(head -n 1 $IN_BVEC2 | tail -n 1 | tr -s [:space:] | cut -d ' ' -f $(echo $INDICES_2_X_BASE_1 | sed -e 's/ /,/g')) "
NEW_BVECS_Y="$NEW_BVECS_Y $(head -n 2 $IN_BVEC2 | tail -n 1 | tr -s [:space:] | cut -d ' ' -f $(echo $INDICES_2_X_BASE_1 | sed -e 's/ /,/g')) "
NEW_BVECS_Z="$NEW_BVECS_Z $(head -n 3 $IN_BVEC2 | tail -n 1 | tr -s [:space:] | cut -d ' ' -f $(echo $INDICES_2_X_BASE_1 | sed -e 's/ /,/g')) "

echo $NEW_BVECS_X > $BVEC
echo $NEW_BVECS_Y >> $BVEC
echo $NEW_BVECS_Z >> $BVEC

verify $BVEC


#########################################
#
# Copy results
#
#########################################
print_and_log "Copying results"
EXE="rsync -a $DMRI $OUT_DMRI"
print_and_log "    - $EXE"
eval "$EXE"
verify $OUT_DMRI

EXE="rsync -a $BVAL $OUT_BVAL"
print_and_log "    - $EXE"
eval "$EXE"
verify $OUT_BVAL

EXE="rsync -a $BVEC $OUT_BVEC"
print_and_log "    - $EXE"
eval "$EXE"
verify $OUT_BVEC

if [[ -e $MASK ]]; then
    EXE="rsync -a $MASK $OUT_MASK"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify $OUT_MASK
fi


#########################################
#
# Prepare BedpostX folder
#
#########################################
if [[ -n $OUT_BEDPOSTX ]]; then
    print_and_log "Preparing folder with data for BedpostX"

    # creating Directory
    EXE="mkdir -p $OUT_BEDPOSTX"
    print_and_log "    - $EXE"
    eval "$EXE"

    # unpacking and renaming dMRI data set
    EXE="${FSLDIR}/bin/fslmaths $OUT_DMRI ${OUT_BEDPOSTX}/data.nii.gz"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify "${OUT_BEDPOSTX}/data.nii.gz"

    # unpacking and renaming mask
    EXE="${FSLDIR}/bin/fslmaths $OUT_MASK ${OUT_BEDPOSTX}/nodif_brain_mask.nii.gz"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify "${OUT_BEDPOSTX}/nodif_brain_mask.nii.gz"

    # copying and renaming b-values
    EXE="rsync -a $OUT_BVAL ${OUT_BEDPOSTX}/bvals"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify "${OUT_BEDPOSTX}/bvals"

    # copying and renaming b-vectors
    EXE="rsync -a $OUT_BVEC ${OUT_BEDPOSTX}/bvecs"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify "${OUT_BEDPOSTX}/bvecs"
fi


# #########################################
# #
# # Prepare NODDI folder
# #
# #########################################
# if [[ -n $OUT_NODDI ]]; then
#     print_and_log "Preparing folder with data for NODDI"
#
#     # creating Directory
#     EXE="mkdir -p $OUT_NODDI"
#     print_and_log "    - $EXE"
#     eval "$EXE"
#
#     # unpacking and renaming dMRI data set
#     EXE="FSLOUTPUTTYPE=NIFTI ${FSLDIR}/bin/fslsplit $OUT_DMRI ${OUT_NODDI}/data -z"
#     print_and_log "    - $EXE"
#     eval "$EXE"
#
#     # unpacking and renaming mask
#     EXE="FSLOUTPUTTYPE=NIFTI ${FSLDIR}/bin/fslsplit $OUT_MASK ${OUT_NODDI}/nodif_brain_mask -z"
#     print_and_log "    - $EXE"
#     eval "$EXE"
#
#     NUM_SLICES=$(${FSLDIR}/bin/fslval $OUT_MASK dim3)
#     MAX_SLICE_ID=$(echo "$NUM_SLICES - 1" | bc)
#
#     print_and_log "  * preparing one data folder for every axial slice to be processed in parallel"
#     for i in $(seq 0 $MAX_SLICE_ID); do
#         ii = $(printf "%04d" $i)
#         mkdir -p "${OUT_NODDI}/NODDI"
#         mv "${OUT_NODDI}/data_${ii}.nii" "${OUT_NODDI}/NODDI/data.nii"
#         mv "${OUT_NODDI}/nodif_brain_mask_${ii}.nii" "${OUT_NODDI}/NODDI/nodif_brain_mask.nii"
#         cp "$OUT_BVAL" "${OUT_NODDI}/NODDI/bvals"
#         cp "$OUT_BVEC" "${OUT_NODDI}/NODDI/bvecs"
#         cp "${FZJDIR}/fzj_dmri_noddi.m" "${OUT_NODDI}/NODDI/fzj_dmri_noddi.m"
#     done
#
#     # copying and renaming b-values
#     EXE="rsync -a $OUT_BVAL ${OUT_NODDI}/bvals"
#     print_and_log "    - $EXE"
#     eval "$EXE"
#     verify "${OUT_NODDI}/bvals"
#
#     # copying and renaming b-vectors
#     EXE="rsync -a $OUT_BVEC ${OUT_NODDI}/bvecs"
#     print_and_log "    - $EXE"
#     eval "$EXE"
#     verify "${OUT_NODDI}/bvecs"
# fi
#


script_end
