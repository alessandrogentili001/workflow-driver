import os
import sys
import signal
import threading
import re
import numpy as np

def check_log(log_file, tensor_file, target_time, sim_pid, stop_event):
    while not stop_event.is_set():
        if os.path.exists(log_file):
            try:
                # 1. Read the logs
                with open(log_file, 'r') as f:
                    content = f.read()
                times = re.findall(r'^Time = ([\d\.]+)', content, re.MULTILINE)
                if times:
                    # 2. Save the array of timesteps on disk as a numpy tensor
                    time_tensor = np.array([float(t) for t in times], dtype=np.float64)
                    np.save(tensor_file, time_tensor)

                    # 3. Inspect the content of the updated tensor and look for target time
                    loaded_tensor = np.load(tensor_file)
                    if loaded_tensor.size > 0:
                        latest_time = float(loaded_tensor[-1])
                        print(f"[Checker] Tensor size: {len(loaded_tensor)}, Latest time: {latest_time} (Target: {target_time})")
                        if latest_time >= target_time:
                            print(f"[Checker] Target simulation time {target_time} reached in tensor! Stopping simulation (PID: {sim_pid})...")
                            os.kill(sim_pid, signal.SIGTERM)
                            stop_event.set()
                            break
            except Exception as e:
                print(f"[Checker] Error processing log or tensor: {e}")
        
        # Check if the process is still running
        try:
            os.kill(sim_pid, 0)
        except OSError:
            print("[Checker] Simulation process no longer running. Exiting.")
            stop_event.set()
            break
            
        stop_event.wait(5.0)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python checker.py <sim_pid>")
        sys.exit(1)
        
    sim_pid = int(sys.argv[1])
    target_time = 0.003
    tensor_file = "timesteps.npy"
    log_file = "log.icoFoam"
    
    print(f"[Checker] Started checking {log_file} for target time {target_time} (tensor: {tensor_file})...")
    
    stop_event = threading.Event()
    
    def signal_handler(sig, frame):
        print("\n[Checker] Received signal to terminate. Shutting down gracefully...")
        stop_event.set()
        
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    check_thread = threading.Thread(target=check_log, args=(log_file, tensor_file, target_time, sim_pid, stop_event))
    check_thread.start()
    
    check_thread.join()
    print("[Checker] Exited.")
