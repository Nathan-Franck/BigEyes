import os
import subprocess
import sys

# --- Configuration ---

# Path to the Meshroom batch executable
MESHROOM_BATCH_EXE = r"Meshroom-2023.3.0/meshroom_batch.exe"

# Main folder containing the subfolders with images
INPUT_BASE_DIR = r"extracted_frames"

# Main folder where the output subfolders will be created
OUTPUT_BASE_DIR = r"meshes"

# Path to your Meshroom template pipeline file (.mg)
PIPELINE_TEMPLATE_MG = r"meshroom-template.mg"

# Base directory for Meshroom cache files (subfolders will be created here)
CACHE_BASE_DIR = r"MeshroomCache"

# Base directory to save the specific .mg project file for each run (Optional)
SAVE_PROJECT_BASE_DIR = r"project-files"

# Meshroom verbosity level (e.g., info, debug, warning, error)
VERBOSITY = "info"

# --- End Configuration ---

def run_meshroom_for_subfolder(
    subfolder_name, input_dir, output_dir, cache_dir, save_dir
):
    """Runs meshroom_batch for a single subfolder using absolute paths."""
    # --- Convert all paths to absolute paths ---
    abs_input_subfolder_path = os.path.abspath(
        os.path.join(input_dir, subfolder_name)
    )
    abs_output_subfolder_path = os.path.abspath(
        os.path.join(output_dir, subfolder_name)
    )
    abs_cache_subfolder_path = os.path.abspath(
        os.path.join(cache_dir, subfolder_name)
    )
    abs_save_project_dir = os.path.abspath(save_dir) # Base save dir
    abs_save_project_file = os.path.abspath(
        os.path.join(save_dir, f"{subfolder_name}_project.mg")
    )
    abs_pipeline_template_mg = os.path.abspath(PIPELINE_TEMPLATE_MG)
    abs_meshroom_batch_exe = os.path.abspath(MESHROOM_BATCH_EXE)
    # --- End Path Conversion ---

    # Create output, cache, and save directories if they don't exist
    # Use absolute paths here too for consistency, though relative might work
    os.makedirs(abs_output_subfolder_path, exist_ok=True)
    os.makedirs(abs_cache_subfolder_path, exist_ok=True)
    os.makedirs(abs_save_project_dir, exist_ok=True) # Ensure base save dir exists

    print(f"--- Processing Subfolder: {subfolder_name} ---")
    print(f"  Input:  {abs_input_subfolder_path}")
    print(f"  Output: {abs_output_subfolder_path}")
    print(f"  Cache:  {abs_cache_subfolder_path}")
    print(f"  Save:   {abs_save_project_file}")
    print(f"  Pipeline: {abs_pipeline_template_mg}")

    # Construct the command line arguments using absolute paths
    cmd = [
        abs_meshroom_batch_exe,
        "-i", abs_input_subfolder_path,
        "-p", abs_pipeline_template_mg,
        "-o", abs_output_subfolder_path,
        "--cache", abs_cache_subfolder_path,
        "--save", abs_save_project_file,
        "-v", VERBOSITY,
        # Add any other constant flags you need here
        # Example: "--forceCompute"
    ]

    print(f"  Running command: {' '.join(cmd)}")

    try:
        # Execute the command
        # Run from the directory containing the executable for potentially
        # better relative path resolution *within* Meshroom if needed,
        # although absolute paths in args should be sufficient.
        process = subprocess.run(
            cmd,
            check=True, # Raise an exception if Meshroom returns an error
            capture_output=True, # Capture stdout and stderr
            text=True, # Decode stdout/stderr as text
            # cwd=os.path.dirname(abs_meshroom_batch_exe) # Optional: Set working directory
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
        print(f"!!! Error: Meshroom executable not found at '{abs_meshroom_batch_exe}'", file=sys.stderr)
        print("Please check the MESHROOM_BATCH_EXE path in the script.", file=sys.stderr)
        sys.exit(1) # Exit script if executable is not found
    except Exception as e:
        print(f"!!! An unexpected error occurred processing {subfolder_name}: {e}", file=sys.stderr)
        return False

# --- Keep the main() function as it was before ---
def main():
    """Main function to find subfolders and process them."""
    print("Starting Meshroom Batch Processing Script")
    print("=" * 40)

    # --- Input Validations ---
    # Use abspath here too for early checking
    abs_meshroom_exe = os.path.abspath(MESHROOM_BATCH_EXE)
    abs_input_base = os.path.abspath(INPUT_BASE_DIR)
    abs_pipeline_mg = os.path.abspath(PIPELINE_TEMPLATE_MG)
    abs_output_base = os.path.abspath(OUTPUT_BASE_DIR) # Get absolute path for check

    if not os.path.isfile(abs_meshroom_exe):
        print(f"Error: Meshroom executable not found: {abs_meshroom_exe}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isdir(abs_input_base):
        print(f"Error: Input base directory not found: {abs_input_base}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(abs_pipeline_mg):
        print(f"Error: Pipeline template file not found: {abs_pipeline_mg}", file=sys.stderr)
        sys.exit(1)
    if not os.path.exists(os.path.dirname(abs_output_base)):
         print(f"Warning: Parent directory for output base directory does not exist: {os.path.dirname(abs_output_base)}", file=sys.stderr)
         # We'll let makedirs handle creating OUTPUT_BASE_DIR later

    # --- Find Subfolders ---
    try:
        subfolders = [
            f
            for f in os.listdir(abs_input_base) # Use absolute path
            if os.path.isdir(os.path.join(abs_input_base, f))
        ]
    except OSError as e:
        print(f"Error accessing input directory {abs_input_base}: {e}", file=sys.stderr)
        sys.exit(1)


    if not subfolders:
        print(f"No subfolders found in {abs_input_base}. Exiting.")
        sys.exit(0)

    print(f"Found {len(subfolders)} subfolders to process:")
    for sf in subfolders:
        print(f"  - {sf}")
    print("-" * 40)

    # --- Process Subfolders ---
    success_count = 0
    fail_count = 0
    # Pass the original base directories, conversion happens inside the function
    for subfolder_name in subfolders:
        if run_meshroom_for_subfolder(
            subfolder_name,
            INPUT_BASE_DIR, # Pass original base dir
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
