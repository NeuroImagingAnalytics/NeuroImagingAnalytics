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


from concurrent.futures import ThreadPoolExecutor, wait, ALL_COMPLETED
from math import ceil, floor
import os
import subprocess
import sys
from time import gmtime, mktime, sleep, strftime, strptime
from snakemake.utils import read_job_properties


def lock(lock_file):
    # try to create lock-file
    try:
        # open jobscript master file exclusively, will fail if already exists
        with open(lock_file, 'x') as ff:
            ff.write('locked by process id: {}\n'.format(os.getpid()))
    except:
        print('Another instance is already running.', file=sys.stderr)
        sys.exit(0)


def unlock(lock_file):
    os.remove(lock_file)


def snakemake_running(pid):
    """ Check if snakemake with given pid is running. """
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    else:
        return True


def compute_node_configuration(jobscript, num_jobs):
    """
    compute and return
      * partition
      * number of nodes
      * number of paralle tasks per node
      * processing time
    """
    props = read_job_properties(jobscript=jobscript)
    job_threads = props['threads']
    job_gpus = props['resources']['gpus']
    job_mem = props['resources']['mem']
    job_time = props['resources']['time']
    partition = props['cluster']['partition']
    node_cores = props['cluster']['cores']
    node_gpus = props['cluster']['gpus']
    node_mem = props['cluster']['mem']
    node_time = props['cluster']['time']
    # convert node time to minutes
    node_time = mktime(strptime(node_time, '%H:%M:%S')) / 60.0

    # compute number of parallel tasks per node
    num_tasks = min(floor(node_cores / job_threads),
                    floor(node_mem / job_mem))

    # run more jobs on one node if compute time is very short
    overbooking = max(1, int(30 / job_time))

    # compute number of nodes
    num_nodes = ceil((num_jobs / overbooking) / num_tasks)

    # compute processing time with buffer of 10%
    proc_time = job_time * overbooking * 1.1
    print('job_time: {}'.format(job_time))
    print('proc_time: {}'.format(proc_time))
    proc_time = strftime('%H:%M:%S', gmtime(proc_time * 60))

    print('Partition: {}'.format(partition))
    print('Num Nodes: {}'.format(num_nodes))
    print('Num Tasks: {}'.format(num_tasks))
    print('Proc Time: {}'.format(proc_time))
    print('Overbooking: {}'.format(overbooking))

    return (partition, num_nodes, num_tasks, proc_time)


def submit_node(cmd):
    """
    submit a commandline to a node
    """
    subprocess.call(cmd, shell=True)


def submit(partition, num_nodes, num_tasks, proc_time, jobs):
    """
    submit a list of jobs
    """
    cmd = 'srun -n 1 '
    cmd += '--cpu_bind=none '
    cmd += '--cpus-per-task=24 '
    cmd += '--job-name="Snakemake" '
    cmd += '--nodes=1 '
    cmd += '--ntasks=1 '
    cmd += '--partition={p} '.format(p=partition)
    if partition == 'gpus':
        cmd += '--gres=gpu:{gpus} '.format(gpus=4)
    cmd += '--time={pt} '.format(pt=proc_time)
    cmd += 'parallel --jobs {nt} /bin/bash {{1}} ::: '.format(nt=num_tasks)

    tasks_per_node = ceil(len(jobs) / num_nodes)
    jobs_by_node = [jobs[i:i+tasks_per_node] for i in range(0, len(jobs), tasks_per_node)]
    for jbn in jobs_by_node:
        print(cmd + ' '.join(jbn))
    with ThreadPoolExecutor(max_workers=num_nodes) as executor:
        futures = []
        for j in jobs_by_node:
            futures.append(executor.submit(submit_node, cmd + ' '.join(j)))
        wait(futures, return_when=ALL_COMPLETED)


print('jobscript_master.py started', file=sys.stderr)

lock_file = 'jobscript_master.lock'
lock(lock_file)

print('jobscript_master.py is running', file=sys.stderr)

time_to_wait = 10
script_folder = 'scripts'
snakemake_pid = int(sys.argv[1])

jobscripts = dict()

while snakemake_running(snakemake_pid):
    sleep(time_to_wait)
    if not os.path.exists(script_folder):
        continue

    # get list of rules by checking folders in scripts folder
    rules = [r for r in os.listdir(script_folder)]
    # iterate through all rules
    for r in rules:
        # compose path for current rule
        rule_dir = os.path.join(script_folder, r)
        # get list of jobfiles
        jobs = os.listdir(rule_dir)
        # get current number of files in rule folder
        num_jobs = len(jobs)
        if num_jobs == 0:
            continue

        # check if number of files have already been computed
        if r not in jobscripts:
            # if not, set previous number of files to 0
            jobscripts[r] = 0
        else:
            if num_jobs > jobscripts[r]:
                # update number of jobs for current rule
                jobscripts[r] = num_jobs
            if num_jobs == jobscripts[r]:
                # collect scripts of all jobs
                cmds = []
                for j in jobs:
                    js_path = '{rd}/{script}'.format(script=j, rd=rule_dir)
                    # cmds.append('/bin/bash {js_path}'.format(js_path=js_path))
                    cmds.append('"{js_path}"'.format(js_path=js_path))
                partition, num_nodes, num_tasks, proc_time = \
                    compute_node_configuration(js_path, num_jobs)
                print(num_nodes, num_tasks, proc_time)
                # submit the bunch of jobs
                submit(partition=partition, num_nodes=num_nodes, num_tasks=num_tasks, proc_time=proc_time, jobs=cmds)
                # remove executed scripts
                for js in jobs:
                    print('Removing: ' + os.path.join(rule_dir, js))
                    os.remove(os.path.join(rule_dir, js))
                jobscripts[r] = 0


unlock(lock_file)
print('jobscript_master.py is terminating', file=sys.stderr)
