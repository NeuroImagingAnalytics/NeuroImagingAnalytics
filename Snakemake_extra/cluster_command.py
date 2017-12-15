#!/usr/bin/env python3

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


import subprocess
import sys
from snakemake.utils import read_job_properties

jobscript = sys.argv[1]
job_properties = read_job_properties(jobscript)

script_folder = 'scripts'
rule_name = job_properties['rule']

# copy current run script to scripts folder
cmd = 'mkdir -p {scripts}/{rn} && cp {script} {scripts}/{rn}/' \
        .format(script=jobscript, rn=rule_name, scripts=script_folder)
print(cmd, file=sys.stderr)
subprocess.call(cmd, shell=True)

sys.exit(0)
