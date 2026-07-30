########################
### LOAD ENVIRONMENT ###
########################

# Load the .env for all rules automatically
shell.prefix("mkdir -p cavity/logs && [ -s .env ] && source .env >> cavity/logs/env_setup.log 2>&1 || true; ")

##################
### RULE NODES ###
##################

rule all:
    input:
        "cavity/simulation_done.txt"

rule prepare_mesh:
    output:
        "cavity/log.blockMesh"
    log:
        "cavity/logs/prepare_mesh.log"
    shell:
        """
        # Run the pre script
        bash cavity/pre > {log} 2>&1
        cat cavity/log.blockMesh >> {log}
        """

rule decompose_mesh:
    input:
        "cavity/log.blockMesh"
    output:
        "cavity/log.decomposePar"
    log:
        "cavity/logs/decompose_mesh.log"
    shell:
        """
        # Decompose the mesh
        bash cavity/dec > {log} 2>&1
        cat cavity/log.decomposePar >> {log}
        """

rule run_simulation_with_concurrent_check:
    input:
        "cavity/log.decomposePar"
    output:
        "cavity/simulation_done.txt"
    shell:
        """
        # Remove old log to prevent OpenFOAM's 'already run' error
        rm -f cavity/log.icoFoam

        # Determine simulation cores from OpenFOAM config
        SIM_CORES=$(grep 'numberOfSubdomains' cavity/system/decomposeParDict | grep -o '[0-9]*')

        # Launch simulation on SIM_CORES
        srun --exclusive -n $SIM_CORES --cpus-per-task 1 \
            icoFoam -parallel > cavity/log.icoFoam 2>&1 &
        SIM_PID=$!

        # Launch checker on 1 dedicated core, passing the simulation PID so it can kill it
        srun --exclusive -n 1 --cpus-per-task 1 \
            python cavity/checker.py $SIM_PID
        
        wait $SIM_PID || true
        touch {output}
        """