import cv2
import os
import json
import shutil
import argparse
from typing import List, Set, Tuple, Optional, TypedDict

# Define a TypedDict for the settings structure with required total_frames field
class VideoSettings(TypedDict):
    total_frames: int

def extract_frames(
    video_path: str, 
    output_dir: str, 
    settings: VideoSettings, 
    start_frame_number: int = 0
) -> int:
    """
    Extract frames from a video file based on the provided settings.
    Returns the next frame number to use.
    """
    # Create output directory if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    
    # Get the number of frames to extract from settings
    total_frames: int = settings["total_frames"]  # Now we can directly access it
    
    # Open the video file
    video: cv2.VideoCapture = cv2.VideoCapture(video_path)
    
    # Get video properties
    video_frames: int = int(video.get(cv2.CAP_PROP_FRAME_COUNT))
    fps: float = video.get(cv2.CAP_PROP_FPS)
    duration: float = video_frames / fps if fps > 0 else 0
    
    # Calculate which frames to extract
    if total_frames > video_frames:
        total_frames = video_frames  # Can't extract more frames than we have
    
    if total_frames <= 1:
        # Handle edge case of very short videos
        frame_indices: List[int] = [0]
    else:
        # Calculate frame indices to extract (evenly distributed)
        frame_indices: List[int] = [int(i * video_frames / total_frames) for i in range(total_frames)]
    
    frame_number: int = start_frame_number
    extracted_count: int = 0
    
    for _, frame_idx in enumerate(frame_indices):
        # Set video to the target frame
        video.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
        success: bool
        success, frame = video.read()
        
        if success:
            frame_path: str = os.path.join(output_dir, f"frame_{frame_number:06d}.png")
            # Use PNG for lossless quality
            cv2.imwrite(frame_path, frame)
            frame_number += 1
            extracted_count += 1
    
    video.release()
    print(f"Extracted {extracted_count} frames from {os.path.basename(video_path)}")
    print(f"Video duration: {duration:.2f} seconds, Original frames: {video_frames}")
    
    # Return the next frame number to use
    return frame_number

def load_settings(folder_path: str) -> Optional[VideoSettings]:
    """Load settings from settings.json in the folder if it exists, otherwise return default settings."""
    settings_path: str = os.path.join(folder_path, "settings.json")
    if os.path.exists(settings_path):
        try:
            with open(settings_path, 'r') as f:
                settings: VideoSettings = json.load(f)
            print(f"Loaded existing settings from {settings_path}")
            return settings
        except json.JSONDecodeError:
            print(f"Error reading settings file {settings_path}, using default settings")
            return None
    return None

def create_default_settings_file(folder_path: str, settings: VideoSettings) -> None:
    """Create a default settings.json file in the specified folder."""
    settings_path: str = os.path.join(folder_path, "settings.json")
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=4)
    print(f"Created default settings file at {settings_path}")

def is_video_file(filename: str) -> bool:
    """Check if a file is a video based on its extension."""
    video_extensions: Tuple[str, ...] = ('.mp4', '.avi', '.mov', '.mkv', '.wmv', '.flv')
    return filename.lower().endswith(video_extensions)

def organize_videos_into_subfolders(input_base_folder: str, default_settings: VideoSettings) -> None:
    """Move videos from the main directory into their own subfolders."""
    # Get all files in the main directory
    files: List[str] = [f for f in os.listdir(input_base_folder) 
             if os.path.isfile(os.path.join(input_base_folder, f))]
    
    # Filter for video files
    video_files: List[str] = [f for f in files if is_video_file(f)]
    
    if not video_files:
        print(f"No video files found in the main directory {input_base_folder}")
        return
    
    print(f"Found {len(video_files)} video files in the main directory to organize")
    
    # Move each video to its own subfolder
    for video_file in video_files:
        # Create subfolder name from video filename (without extension)
        subfolder_name: str = os.path.splitext(video_file)[0]
        subfolder_path: str = os.path.join(input_base_folder, subfolder_name)
        
        # Create the subfolder if it doesn't exist
        if not os.path.exists(subfolder_path):
            os.makedirs(subfolder_path)
            print(f"Created new subfolder: {subfolder_path}")
        
        # Source and destination paths
        source_path: str = os.path.join(input_base_folder, video_file)
        dest_path: str = os.path.join(subfolder_path, video_file)
        
        # Move the video file if it doesn't already exist in the destination
        if not os.path.exists(dest_path):
            shutil.move(source_path, dest_path)
            print(f"Moved {video_file} to {subfolder_path}")
        else:
            print(f"Skipping {video_file} - already exists in {subfolder_path}")

def clean_output_folders(input_base_folder: str, output_base_folder: str) -> None:
    """Remove output folders that don't have corresponding input subfolders."""
    if not os.path.exists(output_base_folder):
        print(f"Output folder {output_base_folder} does not exist. Nothing to clean.")
        return
    
    # Get all input subfolders
    input_subfolders: Set[str] = set()
    if os.path.exists(input_base_folder):
        input_subfolders = {f for f in os.listdir(input_base_folder) 
                           if os.path.isdir(os.path.join(input_base_folder, f))}
    
    # Get all output subfolders
    output_subfolders: Set[str] = {f for f in os.listdir(output_base_folder) 
                        if os.path.isdir(os.path.join(output_base_folder, f))}
    
    # Find output subfolders that don't have corresponding input subfolders
    orphaned_folders: Set[str] = output_subfolders - input_subfolders
    
    if not orphaned_folders:
        print("No orphaned output folders found. Nothing to clean.")
        return
    
    print(f"Found {len(orphaned_folders)} orphaned output folders to remove:")
    for folder in orphaned_folders:
        folder_path: str = os.path.join(output_base_folder, folder)
        print(f"Removing: {folder_path}")
        shutil.rmtree(folder_path)
    
    print(f"Cleaned {len(orphaned_folders)} orphaned output folders.")

def should_process_subfolder(
    input_subfolder_path: str, 
    output_subfolder_path: str, 
    settings: VideoSettings,
) -> bool:
    """
    Determine if a subfolder should be processed by checking if output exists
    and if settings have changed.
    """
    # If output folder doesn't exist, we should process
    if not os.path.exists(output_subfolder_path):
        return True
    
    # Check if there are any frames in the output folder
    output_files: List[str] = [f for f in os.listdir(output_subfolder_path) 
                   if f.startswith("frame_") and f.endswith(".png")]
    
    # If no frames, we should process
    if not output_files:
        return True
    
    # Check if settings have changed by looking for a settings record
    settings_record_path: str = os.path.join(output_subfolder_path, "settings.json")
    if not os.path.exists(settings_record_path):
        return True
    
    # Compare current settings with recorded settings
    try:
        with open(settings_record_path, 'r') as f:
            recorded_settings: VideoSettings = json.load(f)
        
        # If settings are different, we should process
        if recorded_settings != settings:
            print(f"Settings have changed for {os.path.basename(input_subfolder_path)}")
            return True
    except:
        return True
    
    # If we got here, output exists and settings haven't changed
    return False

def save_settings_record(output_subfolder_path: str, settings: VideoSettings) -> None:
    """Save a record of the settings used for processing."""
    settings_record_path: str = os.path.join(output_subfolder_path, "settings.json")
    with open(settings_record_path, 'w') as f:
        json.dump(settings, f, indent=4)

def process_video_folders(
    input_base_folder: str, 
    output_base_folder: str, 
    default_settings: Optional[VideoSettings] = None, 
    clean: bool = False
) -> None:
    """Process all video folders, extracting frames from videos based on folder settings."""
    # Set default settings if none provided
    if default_settings is None:
        default_settings = {"total_frames": 30}
    
    # Clean orphaned output folders if requested
    if clean:
        clean_output_folders(input_base_folder, output_base_folder)
    
    # First, organize any videos in the main directory into subfolders
    organize_videos_into_subfolders(input_base_folder, default_settings)
    
    # Create the base output folder if it doesn't exist
    if not os.path.exists(output_base_folder):
        os.makedirs(output_base_folder)
    
    # Get all subfolders in the input base folder
    subfolders: List[str] = [f for f in os.listdir(input_base_folder) 
                 if os.path.isdir(os.path.join(input_base_folder, f))]
    
    if not subfolders:
        print(f"No subfolders found in {input_base_folder}")
        return
    
    print(f"Found {len(subfolders)} subfolders to process")
    
    # Process each subfolder
    for subfolder in subfolders:
        input_subfolder_path: str = os.path.join(input_base_folder, subfolder)
        output_subfolder_path: str = os.path.join(output_base_folder, subfolder)
        
        # Load settings for this subfolder or use defaults
        settings = load_settings(input_subfolder_path)
        if (settings is None):
            settings = default_settings
            create_default_settings_file(input_subfolder_path, settings)
        print(f"Processing subfolder: {subfolder}")
        print(f"Using settings: {settings}")
        
        # Check if we need to process this subfolder
        if not should_process_subfolder(input_subfolder_path, output_subfolder_path, settings):
            print(f"Skipping {subfolder} - output already exists with same settings")
            continue
        
        # If output folder exists but we're reprocessing, clear it first
        if os.path.exists(output_subfolder_path):
            print(f"Clearing existing output folder: {output_subfolder_path}")
            for file in os.listdir(output_subfolder_path):
                file_path: str = os.path.join(output_subfolder_path, file)
                if os.path.isfile(file_path):
                    os.remove(file_path)
        else:
            # Create output subfolder if it doesn't exist
            os.makedirs(output_subfolder_path)
        
        # Get all video files in the subfolder
        video_files: List[str] = [f for f in os.listdir(input_subfolder_path) 
                      if is_video_file(f) and 
                      os.path.isfile(os.path.join(input_subfolder_path, f))]
        
        if not video_files:
            print(f"No video files found in {input_subfolder_path}")
            continue
        
        print(f"Found {len(video_files)} video files in {subfolder}")
        
        # First, calculate the total duration of all videos
        total_duration: float = 0.0
        video_durations: List[float] = []
        
        for video_file in video_files:
            video_path: str = os.path.join(input_subfolder_path, video_file)
            video: cv2.VideoCapture = cv2.VideoCapture(video_path)
            
            # Get video properties
            video_frames: int = int(video.get(cv2.CAP_PROP_FRAME_COUNT))
            fps: float = video.get(cv2.CAP_PROP_FPS)
            duration: float = video_frames / fps if fps > 0 else 0
            
            video_durations.append(duration)
            total_duration += duration
            video.release()
        
        # Process each video in the subfolder
        next_frame_number: int = 0
        for i, video_file in enumerate(video_files):
            video_path: str = os.path.join(input_subfolder_path, video_file)
            
            print(f"Processing: {video_file} -> {output_subfolder_path}")
            print(f"Starting at frame number: {next_frame_number}")

            # Calculate frames for this video based on its duration ratio
            per_video_settings = settings.copy()
            if total_duration > 0:
                duration_ratio = video_durations[i] / total_duration
                print(f'Video duration: {video_durations[i]:.2f} seconds ({duration_ratio:.2%} of total)')
                frames_for_video = max(1, int(settings['total_frames'] * duration_ratio))
            else:
                # Fallback if durations couldn't be calculated
                frames_for_video = max(1, settings['total_frames'] // len(video_files))
                
            per_video_settings['total_frames'] = frames_for_video
            
            print(f'Frames allocated for this video: {per_video_settings["total_frames"]}')
            
            # Extract frames using the settings, and get the next frame number
            next_frame_number = extract_frames(
                video_path, 
                output_subfolder_path, 
                per_video_settings, 
                start_frame_number=next_frame_number
            )
        
        # Save a record of the settings used
        save_settings_record(output_subfolder_path, settings)
        
        print(f"Completed processing subfolder: {subfolder}")
        print(f"Total frames extracted: {next_frame_number}")

def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments."""
    parser: argparse.ArgumentParser = argparse.ArgumentParser(
        description='Extract frames from videos organized in subfolders.'
    )
    
    parser.add_argument('--input', '-i', type=str, default="raw_videos",
                        help='Base input folder containing video subfolders')
    
    parser.add_argument('--output', '-o', type=str, default="extracted_frames",
                        help='Base output folder for extracted frames')
    
    parser.add_argument('--frames', '-f', type=int, default=180,
                        help='Default number of frames to extract per subfolder')
    
    parser.add_argument('--clean', action='store_true',
                        help='Remove output folders that don\'t have corresponding input subfolders')
    
    return parser.parse_args()

def main() -> None:
    """Main function to run the script."""
    # Parse command line arguments
    args: argparse.Namespace = parse_arguments()
    
    # Define default settings
    default_settings: VideoSettings = {
        "total_frames": args.frames,
    }
    
    # Process all video subfolders
    process_video_folders(args.input, args.output, default_settings, args.clean)

if __name__ == "__main__":
    main()
