import ffmpeg
import os
import subprocess

def compress_video(input_file, output_file, codec="hevc", crf=23, max_bitrate=None):
    """
    Compress a video file using FFmpeg.
    :param input_file: Path to the input MOV file
    :param output_file: Path to the output MP4 file
    :param codec: Video codec to use (e.g., "hevc" for H.265 or "libx264" for H.264)
    :param crf: Quality parameter (18-28, lower is better quality)
    :param max_bitrate: Maximum bitrate in Mbps (e.g., "4M" for 4 Mbps)
    """
    try:
        # Build the command
        cmd = [
            'ffmpeg',
            '-i', input_file,
            '-c:v', codec,
            '-crf', str(crf),
            '-pix_fmt', 'yuv420p',
            '-movflags', '+faststart',
            '-c:a', 'aac',
            '-b:a', '128k'
        ]
        
        # Add maxrate and bufsize if specified
        if max_bitrate:
            cmd.extend([
                '-maxrate', max_bitrate,
                '-bufsize', f"{int(max_bitrate.rstrip('M'))*2}M"
            ])
            
        # Add output file
        cmd.append(output_file)
        
        # Run the FFmpeg process
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"FFmpeg error: {result.stderr}")
            return False
        return True
    except Exception as e:
        print(f"Error compressing {input_file}: {str(e)}")
        return False

def batch_compress_recursive(root_directory, codec="hevc", crf=18):
    """
    Recursively search for MOV files in the given directory and its subdirectories,
    then compress them to MP4 format.
    
    :param root_directory: The root directory to start the search
    :param codec: Video codec to use
    :param crf: Quality parameter
    """
    # Count for statistics
    total_files = 0
    successful_compressions = 0
    failed_compressions = 0
    
    # Walk through all directories and files
    for dirpath, dirnames, filenames in os.walk(root_directory):
        for filename in filenames:
            # Case-insensitive check for .mov extension
            if filename.lower().endswith('.mov'):
                total_files += 1
                
                # Construct full paths
                input_file = os.path.join(dirpath, filename)
                output_file = os.path.join(dirpath, f"{os.path.splitext(filename)[0]}_compressed.mp4")
                
                print(f"Processing: {input_file}")
                
                # Compress the video
                if compress_video(input_file, output_file, codec, crf):
                    successful_compressions += 1
                    
                    # Calculate size reduction
                    original_size = os.path.getsize(input_file)
                    compressed_size = os.path.getsize(output_file)
                    reduction_percent = ((original_size - compressed_size) / original_size) * 100
                    
                    print(f"Compressed: {filename}")
                    print(f"  Original size: {original_size / (1024 * 1024):.2f} MB")
                    print(f"  Compressed size: {compressed_size / (1024 * 1024):.2f} MB")
                    print(f"  Reduction: {reduction_percent:.2f}%")
                else:
                    failed_compressions += 1
    
    # Print summary
    print("\nCompression Summary:")
    print(f"Total MOV files found: {total_files}")
    print(f"Successfully compressed: {successful_compressions}")
    print(f"Failed compressions: {failed_compressions}")

# Example usage
if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Compress MOV files to MP4 format recursively")
    parser.add_argument("directory", help="Root directory to search for MOV files")
    parser.add_argument("--codec", default="hevc", help="Video codec to use (default: hevc)")
    parser.add_argument("--crf", type=int, default=23, help="Quality parameter (default: 23, lower is better quality)")
    
    args = parser.parse_args()
    
    print(f"Starting recursive compression in: {args.directory}")
    print(f"Using codec: {args.codec}, CRF: {args.crf}")
    
    batch_compress_recursive(args.directory, args.codec, args.crf)
