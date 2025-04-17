import os
import subprocess
import sys

# --- Configuration ---

# Path to the Meshroom batch executable
MESHROOM_BATCH_EXE = r"Meshroom-2023.3.0/meshroom_batch.exe" # <-- CHANGE THIS

# Main folder containing the subfolders with images
INPUT_BASE_DIR = r"extracted_frames" # <-- CHANGE THIS

# Main folder where the output subfolders will be created
OUTPUT_BASE_DIR = r"meshes" # <-- CHANGE THIS

# Path to your Meshroom template pipeline file (.mg)
PIPELINE_TEMPLATE_MG = r"meshroom-template.mg" # <-- CHANGE THIS

# Base directory for Meshroom cache files (subfolders will be created here)
CACHE_BASE_DIR = r"meshroom-cache" # <-- CHANGE THIS (Optional, but recommended)

# Base directory to save the specific .mg project file for each run (Optional)
SAVE_PROJECT_BASE_DIR = r"project-files" # <-- CHANGE THIS (Optional)

# Meshroom verbosity level (e.g., info, debug, warning, error)
VERBOSITY = "info"

# --- End Configuration ---

def run_meshroom_for_subfolder(
    subfolder_name, input_dir, output_dir, cache_dir, save_dir
):
    """Runs meshroom_batch for a single subfolder."""
    input_subfolder_path = os.path.join(input_dir, subfolder_name)
    output_subfolder_path = os.path.join(output_dir, subfolder_name)
    cache_subfolder_path = os.path.join(cache_dir, subfolder_name)
    save_project_file = os.path.join(
        save_dir, f"{subfolder_name}_project.mg"
    )

    # Create output, cache, and save directories if they don't exist
    os.makedirs(output_subfolder_path, exist_ok=True)
    os.makedirs(cache_subfolder_path, exist_ok=True)
    os.makedirs(save_dir, exist_ok=True) # Ensure base save dir exists

    print(f"--- Processing Subfolder: {subfolder_name} ---")
    print(f"  Input:  {input_subfolder_path}")
    print(f"  Output: {output_subfolder_path}")
    print(f"  Cache:  {cache_subfolder_path}")
    print(f"  Save:   {save_project_file}")
    print(f"  Pipeline: {PIPELINE_TEMPLATE_MG}")

    # Construct the command line arguments
    cmd = [
        MESHROOM_BATCH_EXE,
        "-i", input_subfolder_path,
        "-p", PIPELINE_TEMPLATE_MG,
        "-o", output_subfolder_path,
        "--cache", cache_subfolder_path,
        "--save", save_project_file,
        "-v", VERBOSITY,
        # Add any other constant flags you need here
        # Example: "--forceCompute"
    ]

    print(f"  Running command: {' '.join(cmd)}")

    try:
        # Execute the command
        process = subprocess.run(
            cmd,
            check=True, # Raise an exception if Meshroom returns an error
            capture_output=True, # Capture stdout and stderr
            text=True, # Decode stdout/stderr as text
        )
        print(f"  Meshroom STDOUT:\n{process.stdout}")
        if process.stderr:
            print(f"  Meshroom STDERR:\n{process.stderr}")
        print(f"--- Finished Subfolder: {subfolder_name} ---")
        return True

    except subprocess.CalledProcessError as e:
        print(f"!!! Error processing {subfolder_name} !!!", file=sys.stderr)
        print(f"  Return Code: {e.returncode}", file=sys.stderr)
        print(f"  Command: {' '.join(e.cmd)}", file=sys.stderr)
        print(f"  Stdout:\n{e.stdout}", file=sys.stderr)
        print(f"  Stderr:\n{e.stderr}", file=sys.stderr)
        return False
    except FileNotFoundError:
        print(f"!!! Error: Meshroom executable not found at '{MESHROOM_BATCH_EXE}'", file=sys.stderr)
        print("Please check the MESHROOM_BATCH_EXE path in the script.", file=sys.stderr)
        sys.exit(1) # Exit script if executable is not found
    except Exception as e:
        print(f"!!! An unexpected error occurred processing {subfolder_name}: {e}", file=sys.stderr)
        return False


def main():
    """Main function to find subfolders and process them."""
    print("Starting Meshroom Batch Processing Script")
    print("=" * 40)

    # --- Input Validations ---
    if not os.path.isfile(MESHROOM_BATCH_EXE):
        print(f"Error: Meshroom executable not found: {MESHROOM_BATCH_EXE}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isdir(INPUT_BASE_DIR):
        print(f"Error: Input base directory not found: {INPUT_BASE_DIR}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(PIPELINE_TEMPLATE_MG):
        print(f"Error: Pipeline template file not found: {PIPELINE_TEMPLATE_MG}", file=sys.stderr)
        sys.exit(1)
    if not os.path.exists(os.path.dirname(OUTPUT_BASE_DIR)):
         print(f"Warning: Parent directory for output base directory does not exist: {os.path.dirname(OUTPUT_BASE_DIR)}", file=sys.stderr)
         # We'll let makedirs handle creating OUTPUT_BASE_DIR later

    # --- Find Subfolders ---
    try:
        subfolders = [
            f
            for f in os.listdir(INPUT_BASE_DIR)
            if os.path.isdir(os.path.join(INPUT_BASE_DIR, f))
        ]
    except OSError as e:
        print(f"Error accessing input directory {INPUT_BASE_DIR}: {e}", file=sys.stderr)
        sys.exit(1)


    if not subfolders:
        print(f"No subfolders found in {INPUT_BASE_DIR}. Exiting.")
        sys.exit(0)

    print(f"Found {len(subfolders)} subfolders to process:")
    for sf in subfolders:
        print(f"  - {sf}")
    print("-" * 40)

    # --- Process Subfolders ---
    success_count = 0
    fail_count = 0
    for subfolder_name in subfolders:
        if run_meshroom_for_subfolder(
            subfolder_name,
            INPUT_BASE_DIR,
            OUTPUT_BASE_DIR,
            CACHE_BASE_DIR,
            SAVE_PROJECT_BASE_DIR,
        ):
            success_count += 1
        else:
            fail_count += 1
        print("-" * 40) # Separator between folders

    # --- Summary ---
    print("=" * 40)
    print("Batch Processing Summary:")
    print(f"  Successfully processed: {success_count}")
    print(f"  Failed to process:    {fail_count}")
    print("=" * 40)

if __name__ == "__main__":
    main()
