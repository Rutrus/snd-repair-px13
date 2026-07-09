# Publicar en GitHub personal

> [English](../GITHUB.md) | **Español**

## Qué incluye el repositorio

- Documentación, parches, scripts, series upstream y datos de validación.
- **No** incluye el árbol `linux-source-*` ni el `.deb` de fuentes (varios GB). Cada clon los genera localmente.

## Pasos

### 1. Inicializar git (si aún no lo está)

```bash
cd ~/snd_repair   # o la ruta donde tengas el repo
git init
git add .
git status        # revisar que no entren linux-source-* ni .deb
git commit -m "Audio TAS2783 ASUS ProArt PX13: firmware + parches kernel"
```

### 2. Crear repositorio vacío en GitHub

En https://github.com/new:

- Nombre sugerido: `snd-repair-px13` o `asus-proart-px13-audio`
- **Sin** README, `.gitignore` ni licencia (ya los tienes localmente)
- Visibilidad: **público** (documentación) o **privado** (si prefieres)

### 3. Enlazar y subir

Sustituye `TU_USUARIO` y `NOMBRE_REPO`:

```bash
git branch -M main
git remote add origin git@github.com:TU_USUARIO/NOMBRE_REPO.git
git push -u origin main
```

Con HTTPS:

```bash
git remote add origin https://github.com/TU_USUARIO/NOMBRE_REPO.git
git push -u origin main
```

### 4. Comprobar tamaño

```bash
git count-objects -vH
```

Debe quedar en pocos MB. Si ves cientos de MB, algo de `linux-source-*` se coló en el commit:

```bash
git rm -r --cached linux-source-* '*.deb' 2>/dev/null
echo "linux-source-*/" >> .gitignore
git commit --amend   # solo si aún no has hecho push
```

### 5. README en GitHub

El [`README.md`](../../README.md) (inglés) y [`README.es.md`](../../README.es.md) (español) son la portada del repo.

## Notas legales

- Los binarios de firmware **no** están en este repo (propietarios ASUS/TI). La documentación explica cómo extraerlos del instalador oficial.
- Los parches del kernel son contribuciones propias; las series en `upstream/` están pensadas para envío a mantenedores.

## Clonar en otra máquina

```bash
git clone git@github.com:TU_USUARIO/NOMBRE_REPO.git
cd NOMBRE_REPO
# Seguir README.md → prepare-kernel-tree.sh → build-production-modules.sh
```
