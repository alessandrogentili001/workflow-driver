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

########################
### CHECKPOINT NODES ###
########################

checkpoint run_simulation_with_concurrent_check:
    input:
        "cavity/log.decomposePar"
    output:
        "cavity/logs/simulation_run_{i}.log"
    shell:
        """
        bash cavity/run_with_concurrent_check
        cp cavity/log.icoFoam {output} || touch {output}
        """

########################
### HELPER FUNCTIONS ###
########################

def check_simulation(wildcards):
    import re
    import subprocess
    import os

    i = 1
    while True:
        # get() will trigger the checkpoint to run if it hasn't already
        checkpoints.run_simulation_with_concurrent_check.get(i=i)

        remote_log = f"{config['remote_workdir']}/cavity/logs/simulation_run_{i}.log"
        remote_host = config.get('remote_host', 'leonardo')
        
        # Read log natively or via SSH
        try:
            if os.path.exists(remote_log):
                with open(remote_log, 'r') as f:
                    content = f.read()
            else:
                content = subprocess.check_output(
                    ["ssh", "-o", "BatchMode=yes", remote_host, f"cat {remote_log}"],
                    text=True
                )
        except subprocess.CalledProcessError:
            raise ValueError(f"Failed to read simulation log on cluster: {remote_log}")

        # Check for convergence condition (Ux residual < 1e-5)
        residuals = re.findall(r'smoothSolver:\s+Solving for Ux, Initial residual = [\d\.e\-]+, Final residual = ([\d\.e\-]+)', content)
        
        converged = False
        if residuals:
            final_ux = float(residuals[-1])
            if final_ux < 1e-5:
                converged = True
        
        # Max iteration safety limit (for testing workflow logic)
        if converged or i >= 3:
            return f"cavity/logs/simulation_run_{i}.log"
        else:
            # Not converged, modify parameter and loop (dummy update for workflow logic test)
            new_nu = round(0.01 + (i * 0.005), 4) 
            
            update_cmd = (
                f"cd {config['remote_workdir']} && "
                "source .env && "
                f"foamDictionary cavity/constant/transportProperties -entry nu -set {new_nu}"
            )

            if os.path.exists(remote_log):
                subprocess.run(update_cmd, shell=True, executable='/bin/bash', check=True)
            else:
                subprocess.run(
                    ["ssh", "-o", "BatchMode=yes", remote_host, update_cmd],
                    capture_output=True, text=True,
                )
            
            i += 1

######################
### FINALIZER RULE ###
######################

rule finalize_simulation:
    input:
        check_simulation
    output:
        "cavity/simulation_done.txt"
    shell:
        """
        mkdir -p $(dirname {output})
        touch {output}
        """