#FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu20.04

# Stage 1: Base image with common dependencies
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04 

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1 
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3-pip \
    git \
    wget \
    libgl1 \
    ffmpeg \
    && ln -sf /usr/bin/python3.11 /usr/bin/python3 \
    && ln -sf /usr/bin/python3.11 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Install pip for Python 3.11 specifically
RUN wget https://bootstrap.pypa.io/get-pip.py && \
python3.11 get-pip.py && \
python3.11 -m pip install --upgrade pip && \
rm get-pip.py

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Clone ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git comfyui

# Install torch
RUN pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu124

# Change working directory to ComfyUI
WORKDIR /comfyui

# Install requirements
RUN pip install -r requirements.txt

WORKDIR /
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager /comfyui/custom_nodes/ComfyUI-Manager && \
    chmod +x /comfyui/custom_nodes/ComfyUI-Manager/cm-cli.py && \
    pip install -r /comfyui/custom_nodes/ComfyUI-Manager/requirements.txt && \
    # Debug info
    echo "Python path: $(which python)" && \
    echo "Python version: $(python --version)" && \
    echo "Pip version: $(pip --version)" && \
    echo "Installed packages:" && \
    pip list | grep typer 


# Go back to comfyui
WORKDIR /comfyui

# Install runpod
RUN pip install runpod requests

# Install AV
RUN pip install av

#install imageio-ffmpeg
RUN pip install imageio-ffmpeg

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Download the LatentSync checkpoint files
RUN echo "Starting model downloads..."

RUN mkdir -p /comfyui/custom_nodes/ComfyUI-LatentSyncWrapper/checkpoints/whisper && \
    wget -O /comfyui/custom_nodes/ComfyUI-LatentSyncWrapper/checkpoints/latentsync_unet.pt \
    https://huggingface.co/ByteDance/LatentSync/resolve/main/latentsync_unet.pt && \
    wget -O /comfyui/custom_nodes/ComfyUI-LatentSyncWrapper/checkpoints/whisper/tiny.pt \
    https://huggingface.co/ByteDance/LatentSync/resolve/main/whisper/tiny.pt


# Add scripts
ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh /restore_snapshot.sh

# Optionally copy the snapshot file
ADD *snapshot*.json /

# Before running restore_snapshot.sh, verify Python environment and typer
RUN echo "Verifying Python environment:" && \
    python --version && \
    pip --version && \
    echo "Installing typer..." && \
    pip install typer==0.15.1 && \
    echo "Verifying typer installation:" && \
    python -c "import typer; print(f'Typer is installed at: {typer.__file__}')"

# Restore the snapshot to install custom nodes
RUN /restore_snapshot.sh

# Single CMD at the end
CMD ["/start.sh"]