import os
import subprocess
import whisper
import re
import tempfile
import argparse
import shutil

# --- Helper Function: Sanitize Filename ---
def sanitize_filename(text):
    """
    Cleans the transcribed text to create a valid filename base.
    - Converts to lowercase
    - Replaces spaces and underscores with dashes
    - Removes characters not suitable for filenames
    - Limits length to avoid issues
    """
    if not text or not text.strip():
        return "transcription-failed-or-empty"

    # Lowercase
    text = text.lower().strip()

    # Replace spaces/underscores with dashes
    text = re.sub(r'[\s_]+', '-', text)

    # Remove invalid filename characters (allow letters, numbers, dash, dot)
    text = re.sub(r'[^\w\-.]', '', text)

    # Replace multiple consecutive dashes with a single dash
    text = re.sub(r'-+', '-', text)

    # Remove leading/trailing dashes
    text = text.strip('-')

    # Limit length (e.g., 100 chars) to prevent overly long filenames
    max_len = 100
    if len(text) > max_len:
        text = text[:max_len].rsplit('-', 1)[0] # Try to cut at a dash

    # Handle empty string after sanitization
    if not text:
        return "invalid-transcription-result"

    return text

# --- Helper Function: Extract Audio ---
def extract_audio(video_file, temp_audio_path):
    """
    Extracts audio from a video file using FFmpeg.
    Returns True on success, False on failure.
    """
    print(f"  Extracting audio from: {os.path.basename(video_file)}")
    try:
        # Command to extract audio, convert to 16kHz mono WAV (good for Whisper)
        cmd = [
            'ffmpeg',
            '-i', video_file,
            '-vn',             # No video output
            '-acodec', 'pcm_s16le', # Standard WAV codec
            '-ar', '16000',    # Sample rate Whisper is trained on
            '-ac', '1',        # Mono audio
            '-y',              # Overwrite output file if it exists
            temp_audio_path
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=False) # Don't check=True here, handle below

        if result.returncode != 0:
            print(f"  FFmpeg audio extraction error: {result.stderr}")
            return False
        print(f"  Audio extracted successfully to temporary file.")
        return True
    except Exception as e:
        print(f"  Error during audio extraction: {str(e)}")
        return False

# --- Helper Function: Transcribe Audio ---
def transcribe_audio(audio_path, model):
    """
    Transcribes the given audio file using the loaded Whisper model.
    Returns the transcribed text or None if transcription fails.
    """
    print(f"  Transcribing audio...")
    try:
        result = model.transcribe(audio_path, fp16=False) # fp16=False for wider compatibility if no GPU
        transcription = result["text"]
        print(f"  Transcription successful.")
        # print(f"  Raw Transcription: '{transcription}'") # Optional: for debugging
        return transcription
    except Exception as e:
        print(f"  Error during Whisper transcription: {str(e)}")
        return None

# --- Modified Compression Function ---
def compress_video(input_file, output_file, codec="hevc", crf=23, max_bitrate=None):
    """
    Compress a video file using FFmpeg. (Function signature unchanged, but usage context changes)
    :param input_file: Path to the input MOV file
    :param output_file: Path to the output MP4 file (now dynamically named)
    :param codec: Video codec to use (e.g., "hevc" for H.265 or "libx264" for H.264)
    :param crf: Quality parameter (18-28, lower is better quality)
    :param max_bitrate: Maximum bitrate in Mbps (e.g., "4M" for 4 Mbps)
    """
    print(f"  Compressing video to: {os.path.basename(output_file)}")
    try:
        # Build the command
        cmd = [
            'ffmpeg',
            '-i', input_file,
            '-c:v', codec,
            '-crf', str(crf),
            '-pix_fmt', 'yuv420p', # Common pixel format for compatibility
            '-movflags', '+faststart', # Good for web streaming
            '-c:a', 'aac',     # Standard audio codec for MP4
            '-b:a', '128k',    # Decent audio bitrate
            '-y'               # Overwrite output file if it exists
        ]

        # Add maxrate and bufsize if specified
        if max_bitrate:
            try:
                # Ensure max_bitrate is treated as a string like "4M"
                rate_str = str(max_bitrate)
                if not rate_str.endswith(('k', 'K', 'm', 'M', 'g', 'G')):
                    rate_str += 'M' # Default to Mbps if no unit

                # Calculate bufsize (typically 2x maxrate)
                rate_val = int(re.findall(r'\d+', rate_str)[0])
                rate_unit = rate_str[-1].upper()
                bufsize_str = f"{rate_val * 2}{rate_unit}"

                cmd.extend([
                    '-maxrate', rate_str,
                    '-bufsize', bufsize_str
                ])
            except (ValueError, IndexError) as e:
                 print(f"  Warning: Could not parse max_bitrate '{max_bitrate}'. Ignoring maxrate/bufsize. Error: {e}")


        # Add output file
        cmd.append(output_file)

        # Run the FFmpeg process
        # print(f"  Running FFmpeg command: {' '.join(cmd)}") # Debugging
        result = subprocess.run(cmd, capture_output=True, text=True, check=False) # Handle error below

        if result.returncode != 0:
            print(f"  FFmpeg compression error: {result.stderr}")
            # Attempt to delete potentially incomplete output file
            if os.path.exists(output_file):
                try:
                    os.remove(output_file)
                    print(f"  Deleted incomplete output file: {os.path.basename(output_file)}")
                except OSError as oe:
                    print(f"  Warning: Could not delete incomplete output file {os.path.basename(output_file)}: {oe}")
            return False

        print(f"  Video compressed successfully.")
        return True
    except Exception as e:
        print(f"  Error compressing {os.path.basename(input_file)}: {str(e)}")
        # Attempt to delete potentially incomplete output file
        if os.path.exists(output_file):
             try:
                 os.remove(output_file)
                 print(f"  Deleted incomplete output file: {os.path.basename(output_file)}")
             except OSError as oe:
                 print(f"  Warning: Could not delete incomplete output file {os.path.basename(output_file)}: {oe}")
        return False

# --- Modified Batch Processing Function ---
def batch_process_recursive(root_directory, codec="hevc", crf=23, whisper_model_name="base"):
    """
    Recursively search for MOV files, extract audio, transcribe, generate filename,
    and compress to MP4 format.

    :param root_directory: The root directory to start the search
    :param codec: Video codec to use
    :param crf: Quality parameter
    :param whisper_model_name: Name of the Whisper model to load (e.g., "tiny", "base", "small", "medium", "large")
    """
    # Check if FFmpeg is available
    if shutil.which("ffmpeg") is None:
        print("Error: FFmpeg not found. Please install FFmpeg and ensure it's in your system's PATH.")
        return

    # Load Whisper model
    print(f"Loading Whisper model: {whisper_model_name}...")
    try:
        model = whisper.load_model(whisper_model_name)
        print("Whisper model loaded successfully.")
    except Exception as e:
        print(f"Error loading Whisper model '{whisper_model_name}': {str(e)}")
        print("Please ensure the model name is correct and dependencies are installed.")
        return

    # Count for statistics
    total_files = 0
    successful_processing = 0
    failed_processing = 0

    # Walk through all directories and files
    for dirpath, dirnames, filenames in os.walk(root_directory):
        # Filter out directories starting with '.' to avoid hidden ones like .git
        dirnames[:] = [d for d in dirnames if not d.startswith('.')]

        for filename in filenames:
            # Case-insensitive check for .mov extension
            if filename.lower().endswith('.mov'):
                total_files += 1
                input_file = os.path.join(dirpath, filename)
                print(f"\nProcessing: {input_file}")

                temp_audio_file = None
                transcribed_text = None
                output_file = None
                success = False

                try:
                    # 1. Create a temporary file for audio extraction
                    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_f:
                        temp_audio_file = temp_f.name

                    # 2. Extract Audio
                    if not extract_audio(input_file, temp_audio_file):
                        print(f"  Skipping file due to audio extraction failure.")
                        failed_processing += 1
                        continue # Move to the next file

                    # 3. Transcribe Audio
                    transcribed_text = transcribe_audio(temp_audio_file, model)
                    if transcribed_text is None:
                        print(f"  Skipping file due to transcription failure.")
                        failed_processing += 1
                        continue # Move to the next file

                    # 4. Generate Filename
                    base_output_name = sanitize_filename(transcribed_text)
                    output_file = os.path.join(dirpath, f"{base_output_name}.mp4")

                    # Check for potential filename collision (optional but recommended)
                    counter = 1
                    original_output_file = output_file
                    while os.path.exists(output_file):
                         print(f"  Warning: Output file '{os.path.basename(output_file)}' already exists.")
                         output_file = os.path.join(dirpath, f"{base_output_name}-{counter}.mp4")
                         print(f"  Attempting new name: '{os.path.basename(output_file)}'")
                         counter += 1
                         if counter > 10: # Safety break to prevent infinite loop
                             print("  Too many filename collisions. Skipping this file.")
                             failed_processing += 1
                             output_file = None # Ensure we don't try to compress
                             break
                    if output_file is None: # Check if skipped due to collisions
                        continue

                    # 5. Compress Video
                    if compress_video(input_file, output_file, codec, crf):
                        successful_processing += 1
                        success = True

                        # Calculate size reduction
                        try:
                            original_size = os.path.getsize(input_file)
                            compressed_size = os.path.getsize(output_file)
                            reduction_percent = ((original_size - compressed_size) / original_size) * 100 if original_size > 0 else 0

                            print(f"Successfully processed: {filename} -> {os.path.basename(output_file)}")
                            print(f"  Original size: {original_size / (1024 * 1024):.2f} MB")
                            print(f"  Compressed size: {compressed_size / (1024 * 1024):.2f} MB")
                            print(f"  Reduction: {reduction_percent:.2f}%")
                        except FileNotFoundError:
                             print("  Error calculating file sizes (file might have been moved or deleted).")
                        except ZeroDivisionError:
                             print("  Original file size is zero. Cannot calculate reduction.")

                    else:
                        failed_processing += 1
                        print(f"  Compression failed for: {filename}")

                except Exception as e:
                    print(f"  An unexpected error occurred processing {filename}: {str(e)}")
                    failed_processing += 1
                finally:
                    # 6. Cleanup Temporary Audio File
                    if temp_audio_file and os.path.exists(temp_audio_file):
                        try:
                            os.remove(temp_audio_file)
                            # print(f"  Cleaned up temporary audio file: {temp_audio_file}")
                        except OSError as oe:
                            print(f"  Warning: Could not delete temporary audio file {temp_audio_file}: {oe}")


    # Print summary
    print("\n--- Processing Summary ---")
    print(f"Total MOV files found: {total_files}")
    print(f"Successfully processed & compressed: {successful_processing}")
    print(f"Failed processing/compression: {failed_processing}")
    # print(f"Skipped files (e.g., extraction/transcription errors): {skipped_files}") # Redundant if counted in failed

# --- Main Execution Block ---
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Compress MOV files to MP4 format recursively, naming based on speech.")
    parser.add_argument("directory", help="Root directory to search for MOV files")
    parser.add_argument("--codec", default="hevc", choices=["hevc", "libx264"], help="Video codec (default: hevc)")
    parser.add_argument("--crf", type=int, default=23, help="Quality parameter (default: 23, lower is better quality, 18-28 typical range)")
    parser.add_argument("--whisper-model", default="base", choices=["tiny", "base", "small", "medium", "large"], help="Whisper model size (default: base)")
    # parser.add_argument("--max-bitrate", default=None, help="Maximum video bitrate (e.g., '4M' for 4 Mbps, optional)") # Example if you want max bitrate back

    args = parser.parse_args()

    if not os.path.isdir(args.directory):
        print(f"Error: Directory not found: {args.directory}")
    else:
        print(f"Starting recursive processing in: {args.directory}")
        print(f"Using codec: {args.codec}, CRF: {args.crf}")
        print(f"Using Whisper model: {args.whisper_model}")
        # print(f"Max bitrate: {args.max_bitrate if args.max_bitrate else 'Not set'}")

        batch_process_recursive(args.directory, args.codec, args.crf, args.whisper_model)

        print("\nProcessing finished.")
