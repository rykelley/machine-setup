#!/usr/bin/env bash

# DevOps shell setup script (zsh + bash)
# Detects OS (macOS/Linux) and installs accordingly

set -e  # Exit on error
APT_UPDATED="false"
INSTALL_ALIAS_TOOLS="true"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

usage() {
    cat << 'EOF'
Usage: ./machine-setup.sh [options]

Options:
  --install-tools   Install alias-related CLI tools (default)
  --skip-tools      Skip alias-related CLI tool installation
  -h, --help        Show this help message
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --install-tools)
                INSTALL_ALIAS_TOOLS="true"
                ;;
            --skip-tools)
                INSTALL_ALIAS_TOOLS="false"
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo ""
                usage
                exit 1
                ;;
        esac
        shift
    done
}

csv_to_array() {
    local csv="$1"
    local -n out_array="$2"
    out_array=()

    if [[ -z "$csv" ]]; then
        return
    fi

    IFS=',' read -r -a out_array <<< "$csv"
}

apt_update_once() {
    if [[ "$APT_UPDATED" == "true" ]]; then
        return
    fi

    sudo apt update
    APT_UPDATED="true"
}

try_install_apt() {
    local packages_csv="$1"
    local packages=()
    local pkg

    csv_to_array "$packages_csv" packages

    if [[ ${#packages[@]} -eq 0 ]]; then
        return 1
    fi

    for pkg in "${packages[@]}"; do
        if apt-cache show "$pkg" > /dev/null 2>&1; then
            apt_update_once
            if sudo apt install -y "$pkg"; then
                return 0
            fi
        fi
    done

    return 1
}

try_install_dnf() {
    local packages_csv="$1"
    local packages=()
    local pkg

    csv_to_array "$packages_csv" packages

    if [[ ${#packages[@]} -eq 0 ]]; then
        return 1
    fi

    for pkg in "${packages[@]}"; do
        if sudo dnf install -y "$pkg"; then
            return 0
        fi
    done

    return 1
}

try_install_brew() {
    local packages_csv="$1"
    local packages=()
    local pkg

    csv_to_array "$packages_csv" packages

    if [[ ${#packages[@]} -eq 0 ]]; then
        return 1
    fi

    for pkg in "${packages[@]}"; do
        if brew install "$pkg"; then
            return 0
        fi
    done

    return 1
}

install_cli_tool() {
    local binary_name="$1"
    local tool_name="$2"
    local brew_packages="$3"
    local apt_packages="$4"
    local dnf_packages="$5"

    if command -v "$binary_name" > /dev/null 2>&1; then
        print_warning "${tool_name} already installed"
        return
    fi

    print_step "Installing ${tool_name}..."

    if [[ "$OS" == "macos" ]]; then
        if command -v brew > /dev/null 2>&1; then
            if try_install_brew "$brew_packages"; then
                print_success "${tool_name} installed"
            else
                print_warning "Could not install ${tool_name} via brew. Please install manually."
            fi
        else
            print_warning "Homebrew not found. Skipping ${tool_name} install."
        fi
        return
    fi

    if command -v apt > /dev/null 2>&1; then
        if try_install_apt "$apt_packages"; then
            print_success "${tool_name} installed"
            return
        fi
    fi

    if command -v dnf > /dev/null 2>&1; then
        if try_install_dnf "$dnf_packages"; then
            print_success "${tool_name} installed"
            return
        fi
    fi

    print_warning "Could not auto-install ${tool_name}. Please install manually."
}

try_install_snap() {
    local snap_name="$1"
    local snap_flags="${2:-}"

    if ! command -v snap > /dev/null 2>&1; then
        return 1
    fi

    # shellcheck disable=SC2086
    if sudo snap install $snap_flags "$snap_name"; then
        return 0
    fi

    return 1
}

install_git() {
    if command -v git > /dev/null 2>&1; then
        print_warning "git already installed"
        return
    fi
    print_step "Installing git..."
    if [[ "$OS" == "macos" ]]; then
        brew install git && print_success "git installed" || true
    elif command -v apt > /dev/null 2>&1; then
        apt_update_once && sudo apt install -y git && print_success "git installed"
    elif command -v dnf > /dev/null 2>&1; then
        sudo dnf install -y git && print_success "git installed"
    fi
}

install_kubectl() {
    if command -v kubectl > /dev/null 2>&1; then
        print_warning "kubectl already installed"
        return
    fi
    print_step "Installing kubectl..."
    if [[ "$OS" == "macos" ]]; then
        brew install kubectl && print_success "kubectl installed" && return
    fi
    # Try snap first (works on Ubuntu/Zorin out of the box)
    if try_install_snap kubectl --classic; then
        print_success "kubectl installed via snap"
        return
    fi
    # Official binary install
    local KUBE_VER
    KUBE_VER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KUBE_VER}/bin/linux/amd64/kubectl"
    chmod +x /tmp/kubectl
    sudo mv /tmp/kubectl /usr/local/bin/kubectl
    print_success "kubectl installed via official binary"
}

install_helm() {
    if command -v helm > /dev/null 2>&1; then
        print_warning "helm already installed"
        return
    fi
    print_step "Installing helm..."
    if [[ "$OS" == "macos" ]]; then
        brew install helm && print_success "helm installed" && return
    fi
    if try_install_snap helm --classic; then
        print_success "helm installed via snap"
        return
    fi
    # Official install script
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    print_success "helm installed via official script"
}

install_terraform() {
    if command -v terraform > /dev/null 2>&1; then
        print_warning "terraform already installed"
        return
    fi
    print_step "Installing terraform..."
    if [[ "$OS" == "macos" ]]; then
        brew tap hashicorp/tap
        brew install hashicorp/tap/terraform && print_success "terraform installed" && return
    fi
    if try_install_snap terraform; then
        print_success "terraform installed via snap"
        return
    fi
    # HashiCorp apt repo
    if command -v apt > /dev/null 2>&1; then
        wget -qO- https://apt.releases.hashicorp.com/gpg \
            | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
            | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
        APT_UPDATED="false"
        apt_update_once
        sudo apt install -y terraform
        print_success "terraform installed via HashiCorp apt repo"
        return
    fi
    if command -v dnf > /dev/null 2>&1; then
        sudo dnf config-manager --add-repo \
            https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
        sudo dnf install -y terraform
        print_success "terraform installed via HashiCorp dnf repo"
        return
    fi
    print_warning "Could not auto-install terraform. See https://developer.hashicorp.com/terraform/install"
}

install_ansible() {
    if command -v ansible > /dev/null 2>&1; then
        print_warning "ansible already installed"
        return
    fi
    print_step "Installing ansible..."
    if [[ "$OS" == "macos" ]]; then
        brew install ansible && print_success "ansible installed" && return
    fi
    if command -v apt > /dev/null 2>&1; then
        apt_update_once
        sudo apt install -y ansible && print_success "ansible installed via apt" && return
    fi
    if command -v dnf > /dev/null 2>&1; then
        sudo dnf install -y ansible && print_success "ansible installed via dnf" && return
    fi
    # pip fallback
    if command -v pip3 > /dev/null 2>&1; then
        pip3 install --user ansible && print_success "ansible installed via pip3" && return
    fi
    print_warning "Could not auto-install ansible. See https://docs.ansible.com/ansible/latest/installation_guide/"
}

install_docker() {
    if command -v docker > /dev/null 2>&1; then
        print_warning "docker already installed"
    else
        print_step "Installing docker..."
        if [[ "$OS" == "macos" ]]; then
            print_warning "Please install Docker Desktop for Mac: https://docs.docker.com/desktop/mac/install/"
        else
            # Official convenience script (works on Ubuntu, Debian, Zorin, Fedora, etc.)
            curl -fsSL https://get.docker.com | sudo sh
            sudo usermod -aG docker "$USER"
            print_success "docker installed (re-login required for group membership)"
        fi
    fi

    # Ensure docker compose plugin is available
    if command -v docker > /dev/null 2>&1 && ! docker compose version > /dev/null 2>&1; then
        print_step "Installing docker compose plugin..."
        if [[ "$OS" == "macos" ]]; then
            brew install docker-compose || true
        elif command -v apt > /dev/null 2>&1; then
            apt_update_once
            sudo apt install -y docker-compose-plugin || true
        elif command -v dnf > /dev/null 2>&1; then
            sudo dnf install -y docker-compose-plugin || true
        fi
        print_success "docker compose plugin installed"
    fi
}

install_kubectx() {
    if command -v kubectx > /dev/null 2>&1; then
        print_warning "kubectx already installed"
        return
    fi
    print_step "Installing kubectx..."
    if [[ "$OS" == "macos" ]]; then
        brew install kubectx && print_success "kubectx installed" && return
    fi
    if try_install_snap kubectx --classic; then
        print_success "kubectx installed via snap"
        return
    fi
    # GitHub release binary
    local KUBECTX_VER
    KUBECTX_VER="$(curl -fsSL https://api.github.com/repos/ahmetb/kubectx/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)"
    curl -fsSLo /tmp/kubectx.tar.gz \
        "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VER}/kubectx_${KUBECTX_VER}_linux_x86_64.tar.gz"
    tar -xzf /tmp/kubectx.tar.gz -C /tmp kubectx
    sudo mv /tmp/kubectx /usr/local/bin/kubectx
    rm -f /tmp/kubectx.tar.gz
    print_success "kubectx installed via GitHub release"
}

install_alias_tools() {
    print_step "Installing tools used by aliases..."

    install_git
    install_kubectl
    install_helm
    install_terraform
    install_ansible
    install_docker
    install_kubectx
}

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        print_success "Detected macOS"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
        print_success "Detected Linux"
    else
        print_error "Unsupported OS: $OSTYPE"
        exit 1
    fi
}

# Detect if zsh is available
detect_zsh() {
    if command -v zsh > /dev/null 2>&1; then
        HAS_ZSH="true"
        print_success "Detected zsh"
    else
        HAS_ZSH="false"
        print_warning "zsh not found. Skipping zsh/oh-my-zsh setup and configuring bash only."
    fi
}

# Install oh-my-zsh
install_ohmyzsh() {
    if [[ "$HAS_ZSH" != "true" ]]; then
        return
    fi

    print_step "Installing oh-my-zsh..."
    
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        print_warning "oh-my-zsh already installed, skipping..."
    else
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        print_success "oh-my-zsh installed"
    fi
}

# Install oh-my-zsh plugins
install_plugins() {
    if [[ "$HAS_ZSH" != "true" ]]; then
        return
    fi

    print_step "Installing zsh plugins..."
    
    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    
    # zsh-autosuggestions
    if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
        print_success "Installed zsh-autosuggestions"
    else
        print_warning "zsh-autosuggestions already installed"
    fi
    
    # zsh-syntax-highlighting
    if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
        print_success "Installed zsh-syntax-highlighting"
    else
        print_warning "zsh-syntax-highlighting already installed"
    fi
    
    # kubectx (optional but useful)
    if [[ ! -d "$ZSH_CUSTOM/plugins/kubectx" ]]; then
        git clone https://github.com/ahmetb/kubectx "$ZSH_CUSTOM/plugins/kubectx"
        print_success "Installed kubectx"
    else
        print_warning "kubectx already installed"
    fi
}

# Install eza
install_eza() {
    print_step "Installing eza..."
    
    if command -v eza &> /dev/null; then
        print_warning "eza already installed"
        return
    fi
    
    if [[ "$OS" == "macos" ]]; then
        if command -v brew &> /dev/null; then
            brew install eza
            print_success "eza installed via Homebrew"
        else
            print_error "Homebrew not found. Please install Homebrew first: https://brew.sh"
            exit 1
        fi
    else
        # Linux installation
        if command -v apt &> /dev/null; then
            # Try apt first
            if apt-cache show eza &> /dev/null; then
                sudo apt update && sudo apt install -y eza
                print_success "eza installed via apt"
            else
                # Fall back to cargo
                install_eza_cargo
            fi
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y eza
            print_success "eza installed via dnf"
        else
            install_eza_cargo
        fi
    fi
}

# Install eza via cargo (fallback)
install_eza_cargo() {
    if command -v cargo &> /dev/null; then
        cargo install eza
        print_success "eza installed via cargo"
    else
        print_warning "Cannot install eza. Please install manually or install Rust/cargo first."
    fi
}

# Install Nerd Font
install_nerd_font() {
    print_step "Installing FiraCode Nerd Font..."
    
    local FONT_VERSION="v3.1.1"
    local FONT_NAME="FiraCode"
    
    if [[ "$OS" == "macos" ]]; then
        local FONT_DIR="$HOME/Library/Fonts"
        mkdir -p "$FONT_DIR"
        
        cd "$FONT_DIR"
        
        if ls FiraCode*Nerd* 1> /dev/null 2>&1; then
            print_warning "FiraCode Nerd Font already installed"
        else
            curl -fLo "${FONT_NAME}.zip" \
                "https://github.com/ryanoasis/nerd-fonts/releases/download/${FONT_VERSION}/${FONT_NAME}.zip"
            
            unzip -o "${FONT_NAME}.zip" -d "$FONT_NAME"
            mv "$FONT_NAME"/*.ttf .
            rm -rf "$FONT_NAME" "${FONT_NAME}.zip"
            
            # Refresh font cache
            print_step "Refreshing font cache..."
            sudo atsutil databases -removeUser
            sudo atsutil server -shutdown
            sudo atsutil server -ping
            
            print_success "FiraCode Nerd Font installed"
        fi
    else
        # Linux
        local FONT_DIR="$HOME/.local/share/fonts"
        mkdir -p "$FONT_DIR"
        
        cd "$FONT_DIR"
        
        if ls FiraCode*Nerd* 1> /dev/null 2>&1; then
            print_warning "FiraCode Nerd Font already installed"
        else
            wget "https://github.com/ryanoasis/nerd-fonts/releases/download/${FONT_VERSION}/${FONT_NAME}.zip"
            unzip -o "${FONT_NAME}.zip"
            rm "${FONT_NAME}.zip"
            
            # Refresh font cache
            fc-cache -fv
            
            print_success "FiraCode Nerd Font installed"
        fi
    fi
}

# Install vivid (for LS_COLORS)
install_vivid() {
    print_step "Installing vivid (color scheme generator)..."
    
    if command -v vivid &> /dev/null; then
        print_warning "vivid already installed"
        return
    fi
    
    if [[ "$OS" == "macos" ]]; then
        if command -v brew &> /dev/null; then
            brew install vivid
            print_success "vivid installed via Homebrew"
        else
            install_vivid_cargo
        fi
    else
        if command -v apt &> /dev/null; then
            if apt-cache show vivid &> /dev/null; then
                sudo apt install -y vivid
                print_success "vivid installed via apt"
            else
                install_vivid_cargo
            fi
        else
            install_vivid_cargo
        fi
    fi
}

install_vivid_cargo() {
    if command -v cargo &> /dev/null; then
        cargo install vivid
        print_success "vivid installed via cargo"
    else
        print_warning "Cannot install vivid. Skipping (optional)..."
    fi
}

# Backup existing shell config
backup_shell_rc() {
    local rc_file="$1"

    if [[ -f "$rc_file" ]]; then
        local BACKUP="${rc_file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$rc_file" "$BACKUP"
        print_success "Backed up existing ${rc_file##*/} to $BACKUP"
    fi
}

# Configure .zshrc
configure_zshrc() {
    if [[ "$HAS_ZSH" != "true" ]]; then
        return
    fi

    print_step "Configuring .zshrc..."
    
    backup_shell_rc "$HOME/.zshrc"
    
    # Create new .zshrc content
    cat > "$HOME/.zshrc" << 'EOF'
# Path to oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME="robbyrussell"

# Plugins
plugins=(
  git
  kubectl
  docker
  terraform
  ansible
  helm
  systemd
  sudo
  zsh-autosuggestions
  zsh-syntax-highlighting
  history-substring-search
  colored-man-pages
  kubectx
)

source $ZSH/oh-my-zsh.sh

# ==========================================
# Custom Configuration
# ==========================================

# History settings
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY

# Better directory navigation
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS

# ==========================================
# eza (modern ls replacement)
# ==========================================

if command -v eza &> /dev/null; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -lh --icons --group-directories-first --git'
    alias la='eza -lah --icons --group-directories-first --git'
    alias lt='eza --tree --level=2 --icons --git-ignore'
    alias llt='eza -lh --tree --level=2 --icons --git-ignore'
    alias tree='eza --tree --git-ignore --icons'
    alias tree2='eza --tree --level=2 --git-ignore --icons'
    alias tree3='eza --tree --level=3 --git-ignore --icons'
fi

# ==========================================
# DevOps Aliases
# ==========================================

# Kubernetes
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgn='kubectl get nodes'
alias kgs='kubectl get svc'
alias kgd='kubectl get deployments'
alias kns='kubectl config set-context --current --namespace'
alias kctx='kubectx'

# Helm
alias h='helm'
alias hls='helm list'
alias hlsa='helm list -A'

# Terraform
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'

# Ansible
alias a='ansible'
alias ap='ansible-playbook'
alias av='ansible-vault'

# Docker
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'

# Git shortcuts
alias gst='git status'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gpl='git pull'
alias gps='git push'
alias gcm='git commit -m'
alias gaa='git add .'

# ==========================================
# Colors (vivid or dircolors)
# ==========================================

if command -v vivid &> /dev/null; then
    export LS_COLORS="$(vivid generate molokai)"
elif command -v dircolors &> /dev/null; then
    eval $(dircolors -b)
fi

# ==========================================
# Kubernetes completion
# ==========================================

if command -v kubectl &> /dev/null; then
    source <(kubectl completion zsh)
fi

# ==========================================
# Optional: Custom prompt with k8s context
# ==========================================

# Uncomment to show current k8s context in prompt
# RPROMPT='%{$fg[blue]%}($ZSH_KUBECTL_PROMPT)%{$reset_color%}'

EOF

    print_success ".zshrc configured"
}

# Configure .bashrc
configure_bashrc() {
    print_step "Configuring .bashrc..."

    backup_shell_rc "$HOME/.bashrc"

    cat > "$HOME/.bashrc" << 'EOF'
# ==========================================
# DevOps shell configuration (bash)
# ==========================================

# History settings
HISTSIZE=50000
HISTFILESIZE=50000
HISTCONTROL=ignoredups:erasedups
shopt -s histappend

# Better directory navigation
shopt -s autocd
shopt -s cdspell

# ==========================================
# eza (modern ls replacement)
# ==========================================

if command -v eza > /dev/null 2>&1; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza -lh --icons --group-directories-first --git'
    alias la='eza -lah --icons --group-directories-first --git'
    alias lt='eza --tree --level=2 --icons --git-ignore'
    alias llt='eza -lh --tree --level=2 --icons --git-ignore'
    alias tree='eza --tree --git-ignore --icons'
    alias tree2='eza --tree --level=2 --git-ignore --icons'
    alias tree3='eza --tree --level=3 --git-ignore --icons'
fi

# ==========================================
# DevOps aliases
# ==========================================

# Kubernetes
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgpa='kubectl get pods -A'
alias kgn='kubectl get nodes'
alias kgs='kubectl get svc'
alias kgd='kubectl get deployments'
alias kns='kubectl config set-context --current --namespace'
alias kctx='kubectx'

# Helm
alias h='helm'
alias hls='helm list'
alias hlsa='helm list -A'

# Terraform
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'

# Ansible
alias a='ansible'
alias ap='ansible-playbook'
alias av='ansible-vault'

# Docker
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'

# Git shortcuts
alias gst='git status'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gpl='git pull'
alias gps='git push'
alias gcm='git commit -m'
alias gaa='git add .'

# ==========================================
# Colors (vivid or dircolors)
# ==========================================

if command -v vivid > /dev/null 2>&1; then
    export LS_COLORS="$(vivid generate molokai)"
elif command -v dircolors > /dev/null 2>&1; then
    eval "$(dircolors -b)"
fi

# ==========================================
# Kubernetes completion
# ==========================================

if command -v kubectl > /dev/null 2>&1; then
    source <(kubectl completion bash)
    complete -o default -F __start_kubectl k
fi
EOF

    print_success ".bashrc configured"
}

# Main installation flow
main() {
    echo -e "${GREEN}"
    echo "=========================================="
    echo "  DevOps Shell Setup Script"
    echo "=========================================="
    echo -e "${NC}"
    
    detect_os
    detect_zsh
    
    print_step "Starting installation..."
    echo ""
    
    install_ohmyzsh
    install_plugins
    if [[ "$INSTALL_ALIAS_TOOLS" == "true" ]]; then
        install_alias_tools
    else
        print_warning "Skipping alias-related CLI tool installation (--skip-tools)"
    fi
    install_eza
    install_nerd_font
    install_vivid
    configure_zshrc
    configure_bashrc
    
    echo ""
    echo -e "${GREEN}=========================================="
    echo "  Installation Complete!"
    echo "==========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "1. ${YELLOW}Configure your terminal to use 'FiraCode Nerd Font'${NC}"
    if [[ "$OS" == "macos" ]]; then
        echo "   - iTerm2: Preferences → Profiles → Text → Font"
        echo "   - Terminal.app: Preferences → Profiles → Font"
    else
        echo "   - Check your terminal preferences and set font to 'FiraCode Nerd Font'"
    fi
    echo ""
    echo "2. ${YELLOW}Restart your terminal or run:${NC}"
    if [[ "$HAS_ZSH" == "true" ]]; then
        echo "   source ~/.zshrc   # if using zsh"
    fi
    echo "   source ~/.bashrc  # if using bash"
    echo ""
    echo "3. ${YELLOW}Test your setup:${NC}"
    echo "   ll"
    echo ""
    echo "Your old shell config files were backed up with timestamps"
    echo ""
}

# Run main function
parse_args "$@"
main
