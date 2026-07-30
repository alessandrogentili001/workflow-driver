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
        bash cavity/run_with_concurrent_check
        touch {output}
        """