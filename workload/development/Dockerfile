FROM ubuntu:latest

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Update packages and install SSH server, network troubleshooting tools, and Python
RUN apt-get update && apt-get install -y \
    openssh-server \
    net-tools \
    iputils-ping \
    python3-pip \
    vim \
    sudo \
    python3-venv \
 && rm -rf /var/lib/apt/lists/*

# Set up SSH
RUN mkdir /var/run/sshd
RUN echo 'root:password' | chpasswd
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Add a user for SSH access (avoid using root)
RUN useradd -m -s /bin/bash -G sudo dante
RUN echo 'dante:password' | chpasswd

# Update pip and install the latest Python packages as needed
RUN python3 -m pip install --upgrade pip

# Copy startup script and make it executable
COPY start-ssh.sh /start-ssh.sh
RUN chmod +x /start-ssh.sh

# Expose SSH port
EXPOSE 22

CMD ["/start-ssh.sh"]
