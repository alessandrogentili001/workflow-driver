import os
import sys
import signal
import threading
import re

def check_log(log_file, target_time, sim_pid, stop_event):
    while not stop_event.is_set():
        if os.path.exists(log_file):
            try:
                with open(log_file, 'r') as f:
                    content = f.read()
                times = re.findall(r'^Time = ([\d\.]+)', content, re.MULTILINE)
                if times:
                    latest_time = float(times[-1])
                    print(f"[Checker] Latest time: {latest_time} (Target: {target_time})")
                    if latest_time >= target_time:
                        print(f"[Checker] Target simulation time {target_time} reached! Stopping simulation (PID: {sim_pid})...")
                        os.kill(sim_pid, signal.SIGTERM)
                        stop_event.set()
                        break
            except Exception as e:
                print(f"[Checker] Error reading log: {e}")
        
        # Check if the process is still running
        try:
            os.kill(sim_pid, 0)
        except OSError:
            print("[Checker] Simulation process no longer running. Exiting.")
            stop_event.set()
            break
            
        stop_event.wait(120.0)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python checker.py <sim_pid>")
        sys.exit(1)
        
    sim_pid = int(sys.argv[1])
    log_file = "log.icoFoam"
    target_time = 0.003
    
    print(f"[Checker] Started checking {log_file} for target time {target_time}...")
    
    stop_event = threading.Event()
    
    def signal_handler(sig, frame):
        print("\n[Checker] Received signal to terminate. Shutting down gracefully...")
        stop_event.set()
        
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    check_thread = threading.Thread(target=check_log, args=(log_file, target_time, sim_pid, stop_event))
    check_thread.start()
    
    check_thread.join()
    print("[Checker] Exited.")
