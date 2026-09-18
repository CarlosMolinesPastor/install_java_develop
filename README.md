# Java + Spring Boot Development Setup

Script de instalación automática para preparar un entorno de desarrollo Java, Spring Boot y Neovim en Arch Linux y distribuciones derivadas (Manjaro, EndeavourOS, Artix, etc.).

## 📋 Características

- ✅ Instala **OpenJDK 25 (LTS)**, la versión recomendada para proyectos modernos.
- ✅ Instala **Apache Maven** y **Gradle**, los gestores de construcción más usados.
- ✅ Instala **Spring Boot CLI** desde AUR para crear proyectos rápidamente.
- ✅ Configura automáticamente las variables de entorno `JAVA_HOME` y `PATH`.
- ✅ Instala **Neovim** con tu configuración personalizada ([CarlosMolinesPastor/nvim](https://github.com/CarlosMolinesPastor/nvim)), optimizada para Java y Spring Boot.
- ✅ Instala todas las dependencias de Neovim: `ripgrep`, `fd`, `jq`, `silicon`, etc.
- ✅ Instala **Nerd Fonts** (JetBrainsMono, CascadiaCode, Iosevka, Noto) para una experiencia visual consistente.
- ✅ Ofrece la opción de instalar **IntelliJ IDEA Community Edition**.
- ✅ **Instala automáticamente `paru`** si no está presente, sin intervención manual.

## 🚀 Instalación Rápida

```sh
git clone https://github.com/CarlosMolinesPastor/install_java_develop.git
cd install_java_develop
chmod +x install.sh
./install.sh
```
