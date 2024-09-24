import time
import subprocess
import os

NUMBER_OF_ITERATION = 4
skip_step = 299
start_step = 0
number_of_jobs = 20

def read_iteration_file():
    if not os.path.exists("Iteration"):
        with open("Iteration", "w") as file:
            file.write("0")
        print("Iteration file created with initial value 0.")
    
    with open("Iteration", "r") as file:
        content = file.read().strip()
    
    return content

def run_job_script():
    try:
        command = ["./script_job.sh",str(skip_step),str(start_step),str(number_of_jobs)]
        subprocess.run(command,check=True,capture_output=True,text=True)
        print("script_job.sh executed successfully.")
    except subprocess.CalledProcessError as e:
        print(f"Error executing job_script.sh: {e}")
    except FileNotFoundError:
        print("script_job.sh not found. Make sure it's in the same directory and has execute permissions.")

def main():
    previous_value = None
    
    while True:
        current_value = read_iteration_file()
        print(f"Current value: {current_value}")
        
        try:
            current_value_int = int(current_value)
        except ValueError:
            print(f"Invalid value in Iteration file: {current_value}. Waiting for next check.")
            time.sleep(60)
            continue
        
        if current_value_int >= NUMBER_OF_ITERATION:
            print("Value is equals Iteration. Stopping the program.")
            break
        
        if current_value != previous_value:
            print("Value has changed. Executing job_script.sh.")
            run_job_script()
            previous_value = current_value
        else:
            print("Value hasn't changed. Doing nothing.")
        
        time.sleep(60)  # Check every minute

if __name__ == "__main__":
    main()
