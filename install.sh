#!/usr/bin/env bash
#
# ============================================================
#  SCRIPT DE INSTALACIÓN PARA DESARROLLO JAVA + SPRING BOOT
#  Para Arch Linux y derivados (Manjaro, EndeavourOS, Artix...)
#  Incluye: JDK 25 LTS, Maven, Gradle, Spring Boot CLI,
#           Neovim (config personalizada) y Nerd Fonts
# ============================================================
#
#  Uso:
#    ./install.sh [OPCIONES]
#
#  Opciones:
#    -y, --yes           Asume "sí" en todas las preguntas (no interactivo)
#        --skip-update   No ejecuta 'pacman -Syu' al inicio
#        --no-fonts      No instala Nerd Fonts
#        --no-nvim       No instala ni configura Neovim
#        --with-idea     Instala IntelliJ IDEA Community sin preguntar
#        --log           Guarda la salida en un fichero de log
#    -h, --help          Muestra esta ayuda
#
# ============================================================

set -Eeuo pipefail

# ------------------------------------------------------------
# Configuración global
# ------------------------------------------------------------
readonly SCRIPT_NAME="${0##*/}"
readonly NVIM_CONFIG_REPO="https://github.com/CarlosMolinesPastor/nvim.git"
readonly JDK_PACMAN_PKG="jdk25-openjdk"
readonly JDK_VERSION="25"

# Paquetes oficiales de Arch para las Nerd Fonts
readonly FONT_PACKAGES=(
    ttf-jetbrains-mono-nerd
    ttf-cascadia-code-nerd
    ttf-iosevka-nerd
    ttf-noto-nerd
)

# Familias a descargar como respaldo si el paquete no existe
readonly FONT_FALLBACK_ZIPS=(
    JetBrainsMono
    CascadiaCode
    Iosevka
    Noto
)

# Opciones por defecto
ASSUME_YES=0
SKIP_UPDATE=0
INSTALL_FONTS=1
INSTALL_NVIM=1
FORCE_IDEA=0
ENABLE_LOG=0

# Directorios temporales a limpiar al salir
TEMP_DIRS=()

# ------------------------------------------------------------
# Colores (solo si la salida es un terminal)
# ------------------------------------------------------------
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN='' BLUE='' RED='' YELLOW='' NC=''
fi

# ------------------------------------------------------------
# Funciones de mensajería
# ------------------------------------------------------------
msg()     { echo -e "${BLUE}[*]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*" >&2; }
err()     { echo -e "${RED}[✗]${NC} $*" >&2; }

die() {
    err "$*"
    exit 1
}

usage() {
    sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# ------------------------------------------------------------
# Gestión de errores y limpieza
# ------------------------------------------------------------
on_error() {
    local exit_code=$?
    local line_no=$1
    err "El script falló en la línea ${line_no} (código ${exit_code})."
    [[ ${ENABLE_LOG} -eq 1 ]] && err "Revisa el log para más detalles."
    exit "$exit_code"
}

cleanup() {
    local dir
    for dir in "${TEMP_DIRS[@]:-}"; do
        [[ -n "$dir" && -d "$dir" ]] && rm -rf -- "$dir"
    done
}

trap 'on_error $LINENO' ERR
trap cleanup EXIT INT TERM

make_temp_dir() {
    local dir
    dir="$(mktemp -d)"
    TEMP_DIRS+=("$dir")
    printf '%s' "$dir"
}

# ------------------------------------------------------------
# Utilidades
# ------------------------------------------------------------

# confirm "¿Mensaje? [s/N]"
# Devuelve 0 si el usuario acepta. En modo no interactivo usa el valor por defecto.
confirm() {
    local prompt="$1"
    local reply

    if [[ ${ASSUME_YES} -eq 1 ]]; then
        return 0
    fi

    if [[ ! -t 0 ]]; then
        warn "Entrada no interactiva detectada. Saltando: ${prompt}"
        return 1
    fi

    read -r -p "$(echo -e "${YELLOW}[?]${NC} ${prompt} ")" reply || return 1
    [[ "$reply" =~ ^[sSyY]$ ]]
}

# Wrapper de pacman: idempotente y con un único punto de fallo
pacman_install() {
    local missing=()
    local pkg

    for pkg in "$@"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        success "Ya instalados: $*"
        return 0
    fi

    msg "Instalando: ${missing[*]}"
    sudo pacman -S --needed --noconfirm "${missing[@]}"
}

require_commands() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null || die "Falta el comando requerido: '${cmd}'."
    done
}

# ------------------------------------------------------------
# 0. Parseo de argumentos
# ------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)        ASSUME_YES=1 ;;
            --skip-update)   SKIP_UPDATE=1 ;;
            --no-fonts)      INSTALL_FONTS=0 ;;
            --no-nvim)       INSTALL_NVIM=0 ;;
            --with-idea)     FORCE_IDEA=1 ;;
            --log)           ENABLE_LOG=1 ;;
            -h|--help)       usage 0 ;;
            *)               err "Opción desconocida: $1"; usage 1 ;;
        esac
        shift
    done
}

enable_logging() {
    [[ ${ENABLE_LOG} -eq 1 ]] || return 0

    local log_file="${HOME}/install_java_develop_$(date +%Y%m%d_%H%M%S).log"
    # shellcheck disable=SC2064
    exec > >(tee -a "$log_file") 2>&1
    msg "Registrando la salida en: ${log_file}"
}

# ------------------------------------------------------------
# 1. Comprobaciones previas
# ------------------------------------------------------------
precheck() {
    msg "Comprobando requisitos previos..."

    # No ejecutar como root: makepkg y paru se niegan a funcionar como root
    if [[ ${EUID} -eq 0 ]]; then
        die "No ejecutes este script como root. Úsalo con tu usuario normal (se pedirá sudo cuando haga falta)."
    fi

    require_commands sudo git pacman

    # sudo válido durante toda la instalación
    sudo -v || die "No se pudieron obtener privilegios de sudo."

    # Detección robusta de la distribución vía os-release
    if [[ ! -r /etc/os-release ]]; then
        die "No se encuentra /etc/os-release. ¿Es esto un sistema Arch?"
    fi

    # shellcheck source=/dev/null
    . /etc/os-release

    local supported=0
    case " ${ID:-} ${ID_LIKE:-} " in
        *arch*|*artix*|*endeavouros*|*manjaro*) supported=1 ;;
    esac

    if [[ ${supported} -eq 0 ]]; then
        die "Distribución no soportada: '${PRETTY_NAME:-desconocida}'. Este script es para Arch Linux y derivados."
    fi

    success "Distribución detectada: ${PRETTY_NAME:-Arch Linux}"
}

# ------------------------------------------------------------
# 2. Actualizar el sistema
# ------------------------------------------------------------
update_system() {
    if [[ ${SKIP_UPDATE} -eq 1 ]]; then
        warn "Se omite la actualización del sistema (--skip-update)."
        return 0
    fi

    msg "Actualizando el sistema (pacman -Syu)..."
    sudo pacman -Syu --noconfirm
    success "Sistema actualizado."
}

# ------------------------------------------------------------
# 3. Instalar un helper de AUR (paru) si no existe
# ------------------------------------------------------------
ensure_aur_helper() {
    if command -v paru &>/dev/null; then
        success "paru ya está instalado."
        return 0
    fi

    if command -v yay &>/dev/null; then
        warn "paru no está instalado, pero se detectó yay. Se usará yay."
        AUR_HELPER="yay"
        return 0
    fi

    AUR_HELPER="paru"
    warn "paru no está instalado. Procediendo a instalarlo..."

    pacman_install base-devel git

    local tmp_dir
    tmp_dir="$(make_temp_dir)"

    msg "Clonando paru desde AUR en ${tmp_dir}..."
    git clone --depth 1 https://aur.archlinux.org/paru.git "${tmp_dir}/paru"

    # Subshell: no modificamos el CWD del script principal
    (
        cd "${tmp_dir}/paru"
        makepkg -si --noconfirm --needed
    )

    command -v paru &>/dev/null || die "Fallo al compilar e instalar paru."
    success "paru instalado correctamente."
}

# ------------------------------------------------------------
# 4. Instalar JDK, Maven y Gradle
# ------------------------------------------------------------
install_java_toolchain() {
    msg "Instalando OpenJDK ${JDK_VERSION} (LTS), Maven y Gradle..."
    pacman_install "${JDK_PACMAN_PKG}" maven gradle
    success "Toolchain de Java instalado."
}

# ------------------------------------------------------------
# 5. Instalar Spring Boot CLI desde AUR
# ------------------------------------------------------------
install_spring_boot_cli() {
    local helper="${AUR_HELPER:-paru}"

    msg "Instalando Spring Boot CLI desde AUR con ${helper}..."
    "${helper}" -S --needed --noconfirm spring-boot-cli
    success "Spring Boot CLI instalado."
}

# ------------------------------------------------------------
# 6. Configurar JAVA_HOME y PATH
# ------------------------------------------------------------
detect_java_home() {
    local candidate
    # Orden de preferencia: versión concreta -> cualquier java-XX-openjdk -> default
    for candidate in \
        "/usr/lib/jvm/java-${JDK_VERSION}-openjdk" \
        /usr/lib/jvm/java-"${JDK_VERSION}"-openjdk-* \
        /usr/lib/jvm/default ; do
        if [[ -x "${candidate}/bin/java" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

configure_java_env() {
    msg "Configurando JAVA_HOME y PATH..."

    # 1) Fijar el JDK por defecto con la herramienta oficial de Arch
    if command -v archlinux-java &>/dev/null; then
        local default_name
        default_name="$(archlinux-java get 2>/dev/null || true)"
        if [[ "$default_name" != "java-${JDK_VERSION}-openjdk" ]]; then
            sudo archlinux-java set "java-${JDK_VERSION}-openjdk" \
                && success "JDK por defecto fijado a java-${JDK_VERSION}-openjdk (archlinux-java)." \
                || warn "No se pudo fijar el JDK por defecto con archlinux-java."
        else
            success "java-${JDK_VERSION}-openjdk ya es el JDK por defecto."
        fi
    fi

    # 2) Detectar la ruta real
    local java_dir
    if ! java_dir="$(detect_java_home)"; then
        die "No se pudo detectar la ruta del JDK ${JDK_VERSION} en /usr/lib/jvm/."
    fi

    # 3) Escribir SIEMPRE el profile (idempotente, no se salta si ya existe)
    local profile_file="/etc/profile.d/java.sh"

    sudo tee "$profile_file" >/dev/null <<EOF
# Generado automáticamente por ${SCRIPT_NAME} el $(date '+%Y-%m-%d %H:%M:%S')
export JAVA_HOME="${java_dir}"
export PATH="\${JAVA_HOME}/bin:\${PATH}"
EOF

    sudo chmod 0644 "$profile_file"

    # 4) Aplicarlo también a la sesión actual para que las verificaciones funcionen
    export JAVA_HOME="${java_dir}"
    export PATH="${JAVA_HOME}/bin:${PATH}"

    success "JAVA_HOME=${java_dir}"
    success "Variables de entorno escritas en ${profile_file}"
}

# ------------------------------------------------------------
# 7. Instalar Neovim y sus dependencias
# ------------------------------------------------------------
install_neovim() {
    [[ ${INSTALL_NVIM} -eq 1 ]] || { warn "Neovim omitido (--no-nvim)."; return 0; }

    msg "Instalando Neovim y dependencias (LazyVim)..."
    pacman_install neovim ripgrep fd jq silicon

    msg "Configurando Neovim con tu repositorio personalizado..."
    local nvim_dir="${HOME}/.config/nvim"

    if [[ -e "$nvim_dir" ]]; then
        if confirm "Ya existe una configuración en ${nvim_dir}. ¿Hacer backup y reemplazarla? [s/N]"; then
            local backup="${nvim_dir}.bak.$(date +%Y%m%d%H%M%S)"
            mv -- "$nvim_dir" "$backup"
            success "Backup creado en ${backup}"
        else
            warn "Se conserva la configuración existente de Neovim."
            return 0
        fi
    fi

    git clone --depth 1 "$NVIM_CONFIG_REPO" "$nvim_dir"
    success "Configuración de Neovim clonada en ${nvim_dir}"
}

# ------------------------------------------------------------
# 8. Instalar Nerd Fonts
# ------------------------------------------------------------

# Descarga directa desde la última release de Nerd Fonts (respaldo)
install_fonts_from_release() {
    warn "Recurriendo a la descarga directa desde GitHub Releases (última versión)."

    pacman_install wget unzip fontconfig

    local tmp_dir fonts_dir family url zip_file
    tmp_dir="$(make_temp_dir)"
    fonts_dir="${tmp_dir}/fonts"
    mkdir -p "$fonts_dir"

    for family in "${FONT_FALLBACK_ZIPS[@]}"; do
        url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${family}.zip"
        zip_file="${tmp_dir}/${family}.zip"

        msg "Descargando ${family}..."
        if ! wget -q --show-progress -O "$zip_file" "$url"; then
            warn "No se pudo descargar ${family}. Se omite."
            continue
        fi

        if ! unzip -q -o "$zip_file" -d "$fonts_dir"; then
            warn "No se pudo descomprimir ${family}. Se omite."
            continue
        fi
    done

    # ¿Se ha extraído algo realmente?
    if [[ -z "$(ls -A "$fonts_dir" 2>/dev/null)" ]]; then
        die "No se pudo instalar ninguna Nerd Font."
    fi

    # Instalación a nivel de usuario: no requiere sudo y no ensucia /usr/share/fonts
    local user_fonts_dir="${HOME}/.local/share/fonts"
    mkdir -p "$user_fonts_dir"

    find "$fonts_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' \) \
        -exec cp -f {} "$user_fonts_dir/" \;

    success "Nerd Fonts instaladas en ${user_fonts_dir}"
}

install_nerd_fonts() {
    [[ ${INSTALL_FONTS} -eq 1 ]] || { warn "Nerd Fonts omitidas (--no-fonts)."; return 0; }

    msg "Instalando Nerd Fonts..."

    # Preferencia 1: paquetes oficiales de Arch (rápido, sin sudo extra, sin descargas)
    if install_fonts_from_pacman; then
        success "Nerd Fonts instaladas desde los repositorios de Arch."
    else
        # Preferencia 2: descarga directa de la última release
        install_fonts_from_release
    fi

    msg "Regenerando caché de fuentes..."
    if command -v fc-cache &>/dev/null; then
        fc-cache -f >/dev/null 2>&1 || warn "fc-cache devolvió un error (no crítico)."
        success "Caché de fuentes regenerada."
    else
        warn "fc-cache no está disponible. Instala 'fontconfig' para regenerar la caché."
    fi

    warn "Recuerda seleccionar una Nerd Font (p. ej. 'JetBrainsMono Nerd Font') en tu terminal."
}

# ------------------------------------------------------------
# 9. (Opcional) Instalar IntelliJ IDEA Community
# ------------------------------------------------------------
install_intellij_idea() {
    local want=0

    if [[ ${FORCE_IDEA} -eq 1 ]]; then
        want=1
    elif confirm "¿Quieres instalar IntelliJ IDEA Community? [s/N]"; then
        want=1
    fi

    if [[ ${want} -eq 0 ]]; then
        msg "Saltando instalación de IntelliJ IDEA."
        return 0
    fi

    msg "Instalando IntelliJ IDEA Community..."
    pacman_install intellij-idea-community-edition
    success "IntelliJ IDEA Community instalado."
}

# ------------------------------------------------------------
# 10. Verificar instalaciones
# ------------------------------------------------------------
check_tool() {
    local label="$1"
    local binary="$2"
    shift 2

    if ! command -v "$binary" &>/dev/null; then
        printf '  %-14s %s\n' "${label}:" "${RED}NO ENCONTRADO${NC}"
        return 1
    fi

    local version
    version="$("$@" 2>&1 | head -n 1 || true)"
    printf '  %-14s %s\n' "${label}:" "${GREEN}${version}${NC}"
    return 0
}

verify_installations() {
    msg "Verificando instalaciones..."
    echo "--------------------------------------------------"

    local failures=0

    check_tool "Java"     java   java -version   || ((failures++)) || true
    check_tool "Maven"    mvn    mvn -version    || ((failures++)) || true
    check_tool "Gradle"   gradle gradle -version || ((failures++)) || true
    check_tool "Spring"   spring spring --version || ((failures++)) || true
    check_tool "Neovim"   nvim   nvim --version  || ((failures++)) || true

    echo "--------------------------------------------------"

    if [[ ${failures} -gt 0 ]]; then
        warn "${failures} herramienta(s) no pudieron verificarse."
        warn "Si acabas de instalar Java, ejecuta: source /etc/profile.d/java.sh"
        return 0
    fi

    success "Todas las herramientas verificadas correctamente."
}

# ------------------------------------------------------------
# 11. Resumen final
# ------------------------------------------------------------
print_summary() {
    echo
    success "¡Entorno de desarrollo Java, Spring Boot y Neovim listo!"
    echo
    msg "Próximos pasos:"
    echo "    1. Reinicia la sesión o ejecuta:  source /etc/profile.d/java.sh"
    echo "    2. Abre Neovim:                   nvim"
    echo "    3. Crea un proyecto Spring Boot:  spring init --dependencies=web my-app"
    echo
    [[ ${ENABLE_LOG} -eq 1 ]] && msg "Log completo disponible en el fichero indicado al inicio."
}

# ------------------------------------------------------------
# main
# ------------------------------------------------------------
main() {
    parse_args "$@"
    enable_logging

    echo
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  Instalador de entorno Java + Spring Boot (Arch Linux)${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo

    precheck
    update_system
    ensure_aur_helper
    install_java_toolchain
    install_spring_boot_cli
    configure_java_env
    install_neovim
    install_nerd_fonts
    install_intellij_idea
    verify_installations
    print_summary
}

main "$@"

