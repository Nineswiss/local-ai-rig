@echo off
rem Double-click this to open the image generation gate page - tells you
rem when the GPU is actually free for ComfyUI instead of guessing. Uses
rem the system Python (no venv needed, stdlib only). The script opens
rem your browser itself once the server is actually ready.
python "%~dp0image-gate.py"
