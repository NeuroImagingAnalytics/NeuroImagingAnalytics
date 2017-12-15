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

DESCRIPTION="This script computes the diffusion tensor and related index maps."

OPTIONS[0]="dmri    +  IN_DMRI       +  file    +  Name of the input dMRI data set                                +  IN   +  FILE    +  1  +  none"
OPTIONS[1]="bval    +  IN_BVAL       +  file    +  Name of the input file with b-values                           +  IN   +  FILE    +  1  +  none"
OPTIONS[2]="bvec    +  IN_BVEC       +  file    +  Name of the input file with b-vectors                          +  IN   +  FILE    +  1  +  none"
OPTIONS[3]="remove  +  IN_REMOVE     +  file    +  Name of text file with indices (0 based) of volumes to remove  +  IN   +  FILE    +  1  +  none"
OPTIONS[4]="work    +  OUT_WORK      +  dir     +  Folder for intermediate results                                +  OUT  +  FOLDER  +  1  +  none"
OPTIONS[5]="odmri   +  OUT_DMRI      +  file    +  Name of the output dMRI data set                               +  OUT  +  FILE    +  1  +  none"
OPTIONS[6]="obval   +  OUT_BVAL      +  file    +  Name of the output file with b-values                          +  OUT  +  FILE    +  1  +  none"
OPTIONS[7]="obvec   +  OUT_BVEC      +  file    +  Name of the output file with b-vectors                         +  OUT  +  FILE    +  1  +  none"

. $(dirname $0)/fzj_options.source


if [[ $(cat $IN_REMOVE | wc -w) -gt 0 ]]; then
    # get number of volumes in dwi file
    NUM_VOLUMES=$(${FSLDIR}/bin/fslval $IN_DMRI dim4)
    MAX_VOLUME=$(echo "$NUM_VOLUMES - 1" | bc)

    # get list of volums to keep
    REMOVE_ZERO_BASED=$(echo $(cat $IN_REMOVE))
    REMOVE_ONE_BASED=$(echo $(echo $REMOVE_ZERO_BASED | sed -e "s/ /\n/g" | awk '{print $1 + 1}') )
    KEEP_ZERO_BASED=$( seq --separator=" " 0 $MAX_VOLUME | cut -d ' ' --complement -f $(echo $REMOVE_ONE_BASED | sed -e "s/ /,/g") )
    KEEP_ONE_BASED=$(echo $(echo $KEEP_ZERO_BASED | sed -e "s/ /\n/g" | awk '{print $1 + 1}') )

    print_and_log "Removing : $(echo $REMOVE_ZERO_BASED)"
    print_and_log "Keeping  : $KEEP_ZERO_BASED"

    print_and_log "Removing b-values"
    cat $IN_BVAL | tr -s ' ' | cut -d ' ' -f $(echo $KEEP_ONE_BASED | sed -e "s/ /,/g") > ${OUT_BVAL}
    verify ${OUT_BVAL}

    print_and_log "Removing b-vectors"
    head -n 1 $IN_BVEC | tr -s ' ' | cut -d ' ' -f $(echo $KEEP_ONE_BASED | sed -e "s/ /,/g") > ${OUT_BVEC}
    verify ${OUT_BVEC}
    head -n 2 $IN_BVEC | tail -n 1 | tr -s ' ' | cut -d ' ' -f $(echo $KEEP_ONE_BASED | sed -e "s/ /,/g") >> ${OUT_BVEC}
    head -n 3 $IN_BVEC | tail -n 1 | tr -s ' ' | cut -d ' ' -f $(echo $KEEP_ONE_BASED | sed -e "s/ /,/g") >> ${OUT_BVEC}

    print_and_log "Removing volumes"
    print_and_log "  * splitting data set"
    EXE="${FSLDIR}/bin/fslsplit $IN_DMRI ${OUT_WORK}/Volume_ -t"
    print_and_log "    - $EXE"
    eval "$EXE"
    print_and_log "  * merging 'good' volumes"
    VOLUMES=$(printf "${OUT_WORK}/Volume_%04d " $KEEP_ZERO_BASED)
    EXE="${FSLDIR}/bin/fslmerge -t $OUT_DMRI $VOLUMES"
    print_and_log "    - $EXE"
    eval "$EXE"
    verify ${OUT_DMRI}
else
    print_and_log "No files to remove, copying input data"
    EXE="rsync -a $IN_DMRI $OUT_DMRI"
    print_and_log "    $EXE"
    eval "$EXE"
    verify $OUT_DMRI

    EXE="rsync -a $IN_BVAL $OUT_BVAL"
    print_and_log "    $EXE"
    eval "$EXE"
    verify $OUT_BVAL

    EXE="rsync -a $IN_BVEC $OUT_BVEC"
    print_and_log "    $EXE"
    eval "$EXE"
    verify $OUT_BVEC
fi



script_end
