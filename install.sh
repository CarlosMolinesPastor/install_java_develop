#!/bin/bash

# ============================================================
#  SCRIPT DE INSTALACIÓN PARA DESARROLLO JAVA + SPRING BOOT
#  Para Arch Linux y derivados (Manjaro, EndeavourOS, etc.)
#  Incluye: JDK 25 LTS, Maven, Gradle, Spring Boot CLI, Neovim, Nerd Fonts
# ============================================================

# Colores para los mensajes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # Sin color

# Función para mostrar mensajes
msg() {
    echo -e "${BLUE}[*]${NC} $1"
}

error() {
    echo -e "${RED}[!]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# ------------------------------------------------------------
# 1. Verificar que se ejecuta en Arch Linux o derivado
# ------------------------------------------------------------
if ! grep -q "Arch\|Artix\|EndeavourOS\|Manjaro" /etc/*-release; then
    error "Este script solo funciona en distribuciones basadas en Arch Linux."
fi

# ------------------------------------------------------------
# 2. Actualizar el sistema
# ------------------------------------------------------------
msg "Actualizando el sistema..."
sudo pacman -Syu --noconfirm || error "Fallo al actualizar el sistema."

# ------------------------------------------------------------
# 3. Verificar e instalar paru si no está presente
# ------------------------------------------------------------
if ! command -v paru &> /dev/null; then
    warn "paru no está instalado. Procediendo a instalarlo..."
    sudo pacman -S --needed --noconfirm base-devel git || error "Fallo al instalar dependencias base para paru."
    
    # Directorio temporal para la instalación de paru
    PARU_TMP_DIR=$(mktemp -d)
    msg "Clonando paru en $PARU_TMP_DIR..."
    git clone https://aur.archlinux.org/paru.git "$PARU_TMP_DIR" || error "Fallo al clonar paru."
    
    cd "$PARU_TMP_DIR" || error "No se pudo acceder al directorio de paru."
    makepkg -si --noconfirm || error "Fallo al compilar e instalar paru."
    
    cd - > /dev/null
    rm -rf "$PARU_TMP_DIR"
    success "paru instalado correctamente."
else
    success "paru ya está instalado."
fi

# ------------------------------------------------------------
# 4. Instalar JDK 25 (LTS)
# ------------------------------------------------------------
msg "Instalando OpenJDK 25 (LTS)..."
sudo pacman -S --noconfirm jdk25-openjdk || error "Fallo al instalar el JDK."

# ------------------------------------------------------------
# 5. Instalar Maven y Gradle
# ------------------------------------------------------------
msg "Instalando Maven y Gradle..."
sudo pacman -S --noconfirm maven gradle || error "Fallo al instalar Maven/Gradle."

# ------------------------------------------------------------
# 6. Instalar Spring Boot CLI desde AUR
# ------------------------------------------------------------
msg "Instalando Spring Boot CLI desde AUR..."
paru -S --noconfirm spring-boot-cli || error "Fallo al instalar Spring Boot CLI."

# ------------------------------------------------------------
# 7. Configurar JAVA_HOME y PATH
# ------------------------------------------------------------
msg "Configurando JAVA_HOME y PATH..."

# Detectar la ruta del JDK 25 instalado
JAVA_DIR=$(ls -d /usr/lib/jvm/java-25-openjdk 2>/dev/null)

if [ -z "$JAVA_DIR" ]; then
    error "No se pudo detectar la ruta del JDK 25."
fi

# Crear archivo de configuración si no existe
PROFILE_FILE="/etc/profile.d/java.sh"
if [ ! -f "$PROFILE_FILE" ]; then
    sudo bash -c "cat > $PROFILE_FILE" <<EOF
export JAVA_HOME=$JAVA_DIR
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
    sudo chmod +x "$PROFILE_FILE"
    success "Variables de entorno configuradas en $PROFILE_FILE"
else
    msg "El archivo $PROFILE_FILE ya existe. Saltando configuración."
fi

# ------------------------------------------------------------
# 8. Instalar dependencias para Neovim (LazyVim)
# ------------------------------------------------------------
msg "Instalando dependencias para Neovim (LazyVim)..."
sudo pacman -S --noconfirm neovim ripgrep fd jq || error "Fallo al instalar dependencias de Neovim."

# ------------------------------------------------------------
# 9. Instalar Silicon (para capturas de código)
# ------------------------------------------------------------
msg "Instalando Silicon (generador de capturas de código)..."
sudo pacman -S --noconfirm silicon || error "Fallo al instalar Silicon."

# ------------------------------------------------------------
# 10. Clonar y configurar Neovim
# ------------------------------------------------------------
msg "Configurando Neovim con tu repositorio personalizado..."
NVIM_CONFIG_DIR="$HOME/.config/nvim"

if [ -d "$NVIM_CONFIG_DIR" ]; then
    warn "Ya existe una configuración de Neovim en $NVIM_CONFIG_DIR"
    read -p "¿Quieres hacer un backup y reemplazarla? [s/N]: " backup_nvim
    if [[ "$backup_nvim" =~ ^[sS]$ ]]; then
        mv "$NVIM_CONFIG_DIR" "${NVIM_CONFIG_DIR}.bak.$(date +%Y%m%d%H%M%S)"
        success "Backup creado."
    else
        warn "Saltando la configuración de Neovim."
        NVIM_CONFIG_DIR=""
    fi
fi

if [ -n "$NVIM_CONFIG_DIR" ]; then
    git clone https://github.com/CarlosMolinesPastor/nvim.git "$NVIM_CONFIG_DIR" || error "Fallo al clonar la configuración de Neovim."
    success "Configuración de Neovim clonada en $NVIM_CONFIG_DIR"
fi

# ------------------------------------------------------------
# 11. Instalar Nerd Fonts
# ------------------------------------------------------------
msg "Instalando Nerd Fonts..."
FONTS_TMP_DIR=$(mktemp -d)
cd "$FONTS_TMP_DIR" || error "No se pudo acceder al directorio temporal de fuentes."

wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/2.2.0-RC/CascadiaCode.zip
wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/2.2.0-RC/Iosevka.zip
wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/2.2.0-RC/JetBrainsMono.zip
wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/2.2.0-RC/Noto.zip

unzip -q '*.zip' -d "$FONTS_TMP_DIR/fonts"
sudo cp -R "$FONTS_TMP_DIR/fonts/"* /usr/share/fonts/
rm -rf "$FONTS_TMP_DIR"
success "Nerd Fonts instaladas en /usr/share/fonts/"

# ------------------------------------------------------------
# 12. Regenerar caché de fuentes
# ------------------------------------------------------------
msg "Regenerando caché de fuentes..."
sudo fc-cache -fv

# ------------------------------------------------------------
# 13. (Opcional) Instalar IntelliJ IDEA Community
# ------------------------------------------------------------
read -p "¿Quieres instalar IntelliJ IDEA Community? [s/N]: " instalar_idea
if [[ "$instalar_idea" =~ ^[sS]$ ]]; then
    msg "Instalando IntelliJ IDEA Community..."
    sudo pacman -S --noconfirm intellij-idea-community-edition || error "Fallo al instalar IntelliJ IDEA."
    success "IntelliJ IDEA Community instalado."
else
    msg "Saltando instalación de IntelliJ IDEA."
fi

# ------------------------------------------------------------
# 14. Verificar instalaciones
# ------------------------------------------------------------
msg "Verificando instalaciones..."
echo "-----------------------------"
java -version
echo "-----------------------------"
mvn -version
echo "-----------------------------"
gradle -version
echo "-----------------------------"
spring --version
echo "-----------------------------"
nvim --version | head -n 1
echo "-----------------------------"

success "¡Entorno de desarrollo Java, Spring Boot y Neovim listo!"
warn "Reinicia la sesión o ejecuta 'source /etc/profile.d/java.sh' para aplicar los cambios de entorno."
msg "Para empezar con Neovim, abre una terminal y ejecuta 'nvim'."
