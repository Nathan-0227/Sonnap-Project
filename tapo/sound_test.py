import subprocess
import numpy as np
import time
import sys
import os
from pathlib import Path

FFMPEG_PATH = r"C:\Users\USER\AppData\Local\Microsoft\WinGet\Links\ffmpeg.exe"
# ⚠️ 帳密不寫死（本 repo 公開）。從同目錄 .env 或環境變數讀。
_env = Path(__file__).parent / ".env"
if _env.exists():
    for _raw in _env.read_text(encoding="utf-8").splitlines():
        _line = _raw.strip()
        if _line and not _line.startswith("#") and "=" in _line:
            _k, _v = _line.split("=", 1)
            os.environ.setdefault(_k.strip(), _v.strip())

tapo_url = os.environ.get("CAMERA_RTSP_URL", "").strip()
if not tapo_url:
    sys.exit("找不到 CAMERA_RTSP_URL，請複製 .env.example 成 .env 並填入攝影機網址。")

print("=" * 60)
print("🎤 RECORDING AUDIO TEST")
print("=" * 60)
print("📢 Make some noise near the camera!")
print("⏳ Recording for 5 seconds...")
print()

# FFmpeg command to capture audio
cmd = [
    FFMPEG_PATH,
    '-rtsp_transport', 'tcp',
    '-i', tapo_url,
    '-vn',  # No video
    '-acodec', 'pcm_s16le',
    '-ar', '16000',
    '-ac', '1',
    '-f', 's16le',
    '-t', '5',  # 5 seconds
    '-'
]

# Hide window
startupinfo = None
if sys.platform == "win32":
    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startupinfo.wShowWindow = subprocess.SW_HIDE

process = subprocess.Popen(
    cmd,
    stdout=subprocess.PIPE,
    stderr=subprocess.DEVNULL,
    bufsize=0,
    startupinfo=startupinfo
)

# Read audio data
audio_data = b""
frames = 0

while True:
    raw_data = process.stdout.read(4096)
    if not raw_data:
        break
    audio_data += raw_data
    frames += 1
    
    # Show progress
    if frames % 10 == 0:
        print(f"   Receiving... {len(audio_data)} bytes", end="\r")

process.wait()

if len(audio_data) > 0:
    # Analyze audio
    audio_array = np.frombuffer(audio_data, dtype=np.int16)
    
    # Calculate statistics
    rms = np.sqrt(np.mean(audio_array**2))
    db = 20 * np.log10(rms) if rms > 0 else 0
    max_amp = np.max(np.abs(audio_array))
    
    print("\n" + "=" * 60)
    print("📊 AUDIO RESULTS")
    print("=" * 60)
    print(f"📦 Data size: {len(audio_data):,} bytes")
    print(f"🎵 Samples: {len(audio_array):,}")
    print(f"⏱️ Duration: {len(audio_array)/16000:.2f} seconds")
    print(f"📈 RMS: {rms:.2f}")
    print(f"🔊 dB Level: {db:.1f} dB")
    print(f"📊 Max amplitude: {max_amp}")
    
    # Determine sound level
    print("\n🔍 Sound Level Classification:")
    if db > 1500:
        print("   🔴 VERY LOUD (snoring/loud noise)")
    elif db > 500:
        print("   🟡 MODERATE (breathing/quiet talking)")
    elif db > 100:
        print("   🟢 QUIET (normal room)")
    else:
        print("   🔵 VERY QUIET (almost silent)")
    
    # Show waveform as a simple bar chart
    print("\n📊 Audio Waveform (simplified):")
    chunk_size = max(1, len(audio_array) // 40)
    for i in range(0, min(len(audio_array), 40 * chunk_size), chunk_size):
        chunk = audio_array[i:i+chunk_size]
        if len(chunk) > 0:
            amplitude = int(np.mean(np.abs(chunk)) / 50)
            bar = "█" * min(amplitude, 50)
            print(f"   {bar}")
    
    print("\n✅ SUCCESS! Audio is working!")
    print("   The system can detect sound from your camera.")
    
    # Test if it would trigger your events
    print("\n📋 Would trigger events:")
    if db > 1500:
        print("   ✅ Snoring/Noise detection would trigger")
    elif db > 500:
        print("   ✅ Breathing heavy detection would trigger")
    else:
        print("   ⚠️ Sound is quiet - might not trigger events")
        print("   💡 Suggestion: Lower thresholds in your code")
        print("      AUDIO_SNOOZE_THRESHOLD = 300")
        print("      AUDIO_SILENCE_THRESHOLD = 50")
    
else:
    print("\n❌ No audio data received!")
    print("\nPossible solutions:")
    print("1. Audio is disabled in Tapo app")
    print("2. RTSP stream doesn't include audio")
    print("3. Try different stream URL")

process.terminate()

print("\n" + "=" * 60)