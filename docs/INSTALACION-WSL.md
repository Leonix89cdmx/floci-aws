# Guía: instalar Floci en otro equipo (Windows + WSL2)

Pasos para dejar un equipo nuevo igual que el original: Ubuntu en WSL2, Docker Desktop, AWS CLI, kubectl y Floci con persistencia.

Tiempo estimado: 30–45 min (casi todo son descargas).

---

## 0. Requisitos del equipo

- Windows 10 22H2 o Windows 11, de 64 bits, con la **virtualización activada** en la BIOS/UEFI.
- 16 GB de RAM recomendados (EKS levanta un k3s) y unos 20 GB libres.
- Usuario con permisos de administrador en Windows.

---

## 1. Instalar WSL2 + Ubuntu (en Windows)

Abre **PowerShell como administrador**:

```powershell
wsl --install -d Ubuntu-24.04
```

Reinicia cuando te lo pida. Al abrir **Ubuntu** por primera vez, crea tu usuario y contraseña de Linux.

Comprueba que es la versión 2:

```powershell
wsl -l -v          # VERSION debe ser 2
wsl --set-default-version 2
```

---

## 2. Instalar Docker

Floci corre en Docker y crea contenedores reales (ECR, EKS, RDS), así que Docker es obligatorio. Elige **una** de las dos opciones.

### Opción A — Docker Desktop (recomendada; es la que usa el equipo original)

1. Descarga e instala **Docker Desktop for Windows**: https://www.docker.com/products/docker-desktop/
2. Durante la instalación, deja marcado **Use WSL 2 instead of Hyper-V**.
3. Abre Docker Desktop → **Settings**:
   - **General** → ✅ *Use the WSL 2 based engine*.
   - **Resources → WSL integration** → ✅ activa **Ubuntu-24.04** → *Apply & restart*.
   - (Opcional) **Kubernetes** → *Enable Kubernetes* si también usarás el cluster de Docker Desktop.
4. No instales `docker.io` ni `docker-ce` dentro de Ubuntu: Docker Desktop ya pone el comando `docker` en tu distro.

> ℹ️ Docker Desktop es gratis para uso personal, educación y empresas pequeñas. En empresas grandes requiere licencia: en ese caso usa la opción B.

### Opción B — Docker Engine dentro de Ubuntu (sin Docker Desktop)

Requiere systemd en WSL (Ubuntu 24.04 lo trae activado). Compruébalo:

```bash
cat /etc/wsl.conf          # debe contener: [boot]  systemd=true
```

Si no aparece, agrégalo y reinicia WSL:

```bash
printf '[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf
# en PowerShell:  wsl --shutdown   y vuelve a abrir Ubuntu
```

Instala Docker Engine desde el repositorio oficial de Docker:

```bash
sudo apt update && sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Usar docker sin sudo y arrancarlo con WSL
sudo usermod -aG docker $USER
sudo systemctl enable --now docker
```

Cierra y vuelve a abrir la terminal de Ubuntu para que tome el grupo `docker`.

### Verificación (ambas opciones)

```bash
docker version        # debe mostrar Client y Server
docker run --rm hello-world
ls -l /var/run/docker.sock   # Floci lo necesita
```

> ❌ `docker: command not found` o `Cannot connect to the Docker daemon`:
> - Opción A: Docker Desktop no está abierto o la integración WSL no está activada para tu distro.
> - Opción B: `sudo systemctl status docker`; si da `permission denied`, falta cerrar y abrir la terminal tras `usermod`.

---

## 3. Herramientas en Ubuntu

```bash
sudo apt update && sudo apt install -y git curl unzip ca-certificates
```

### 3.1 AWS CLI v2

```bash
cd /tmp
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q awscliv2.zip && sudo ./aws/install
aws --version
```

### 3.2 kubectl

```bash
cd /tmp
curl -fsSLO "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

---

## 4. Instalar Floci

Floci tiene dos piezas:

| Pieza | Qué es | Cómo se instala |
|---|---|---|
| **Emulador** | Imágenes Docker `floci/floci` (API de AWS) y `floci/floci-ui` (consola web). | `docker pull` (el script del paso 5 también las descarga si faltan). |
| **CLI `floci`** | Binario de ayuda: `floci env`, `floci status`, `floci doctor`. | Script oficial de instalación. |

### 4.1 Imágenes del emulador

```bash
docker pull floci/floci:latest
docker pull floci/floci-ui:0.7.0
docker images | grep floci
```

> 💡 Para tener exactamente la misma versión del servidor que el equipo original (2.4.0), usa su digest:
> `docker pull floci/floci@sha256:5ee85db604c4aa74ac76e07ea5cc83086f37bb472bf3dbb97e34019e48efae9c`

### 4.2 CLI `floci`

Script oficial ([floci-io/floci-cli](https://github.com/floci-io/floci-cli)). Descarga el binario `floci-linux-amd64` del último release, verifica su SHA-256 y lo deja en `/usr/local/bin/floci`:

```bash
curl -fsSL https://floci.io/install.sh | sh
floci --version
```

La última versión es la 1.0.0. Para fijar la misma que usa el equipo original y que está probada con este script (0.4.0):

```bash
curl -fsSL https://floci.io/install.sh | FLOCI_CLI_VERSION=0.4.0 sh
```

Otras opciones: `brew install floci-io/floci/floci` (si usas Homebrew en Linux), o descargar `floci-linux-amd64` a mano desde https://github.com/floci-io/floci-cli/releases.

Comprueba el entorno:

```bash
floci doctor
```

> ⚠️ Instala la CLI, pero **no arranques Floci con `floci start`**: crea el contenedor sin la red `floci-net` y ECR falla con `503`. Para arrancar usa siempre el script del paso 5.

---

## 5. Clonar el repo y levantar Floci

```bash
git clone https://github.com/Leonix89cdmx/floci-aws.git ~/floci-aws
cd ~/floci-aws
chmod +x start_aws_floci.sh
./start_aws_floci.sh
```

Si no hiciste el paso 4.1, la primera vez descarga las imágenes y tarda unos minutos. Al terminar debe verse:

```
  ✔ Floci healthy
  ✔ Persistencia activa
  ✔ ECR responde (200)
  ✔ UI responde (200)

  Laboratorio AWS listo 🚀
```

> 💡 Clona el repo **dentro de Linux** (`~/…`), no en `/mnt/c/…`. Los bind mounts sobre el disco de Windows son lentos y dan problemas de permisos.

---

## 6. Conectar la AWS CLI en cada terminal

Añádelo a `~/.bashrc` para que se cargue siempre:

```bash
cat >> ~/.bashrc <<'EOF'

# --- Floci (AWS local) ---
export AWS_ENDPOINT_URL=http://localhost.floci.io:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
EOF
source ~/.bashrc
```

Con la CLI `floci` instalada, puedes usar en su lugar la línea `eval "$(floci env)"`.

> ⚠️ Con esto, **todo comando `aws` va a Floci**. Para usar AWS real: `unset AWS_ENDPOINT_URL` y configura credenciales reales.

---

## 7. Verificación

```bash
docker inspect floci --format '{{.State.Health.Status}}'             # healthy
docker logs floci 2>&1 | grep "Storage:"                              # Storage:   persistent
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4566/v2/    # 200
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:4500/       # 200
aws sts get-caller-identity                                           # arn:aws:iam::000000000000:root

# Prueba de persistencia
aws s3 mb s3://prueba-persistencia
docker restart floci && sleep 20
aws s3 ls                                                             # el bucket sigue ahí
```

Abre la consola en el navegador de Windows: **http://localhost:4500**

---

## 8. (Opcional) Migrar los datos del equipo original

El repo **no** incluye `floci-data` porque contiene secretos. Si quieres llevarte los recursos creados (buckets, repos ECR, clusters…), cópialos a mano.

**En el equipo original:**

```bash
docker stop floci                                     # para que el estado quede consistente
sudo tar czf /mnt/c/Users/Public/floci-data.tgz -C ~ floci-data
docker start floci
```

Usa `sudo`: algunos archivos (`tls/`, `eks/keys`, `rds/`) los crea el contenedor con otro dueño.

**En el equipo nuevo**, antes de ejecutar el script, o con `docker stop floci` si ya lo ejecutaste:

```bash
sudo tar xzf /mnt/c/Users/Public/floci-data.tgz -C ~
./start_aws_floci.sh
```

> 🔒 Ese `.tgz` tiene secretos: no lo subas a GitHub ni lo dejes en carpetas compartidas. Bórralo de `C:\Users\Public` al terminar.

> ℹ️ Los contenedores que crea Floci (registry ECR, k3s de EKS, RDS) no viajan en el `.tgz`. Floci los recrea a partir del estado. Si un cluster EKS no vuelve, bórralo y créalo de nuevo con `aws eks`.

---

## 9. Uso diario

| Acción | Comando |
|---|---|
| Levantar / reparar todo | `~/floci-aws/start_aws_floci.sh` |
| Parar | `docker stop floci floci-aws-ui` |
| Reiniciar | `docker restart floci` |
| Logs | `docker logs -f floci` |
| Datos en otra ruta | `export FLOCI_DATA_DIR=/ruta` en `~/.bashrc` (el script se detiene si no coincide con la del contenedor) |

Los contenedores usan `--restart unless-stopped`, así que **arrancan solos con Docker Desktop**. Tras reiniciar Windows basta con abrir Docker Desktop. Si algo falla, ejecuta el script.

---

## 10. Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `Docker no responde` | Docker Desktop cerrado o sin integración WSL. | Abre Docker Desktop y revisa *Settings → Resources → WSL integration*. |
| `503 ECR registry is unavailable` | Alguien ejecutó `floci start` y recreó Floci sin `floci-net`. | `./start_aws_floci.sh` (lo detecta y lo recrea). |
| `port is already allocated` (4566 / 4500) | Otro LocalStack/Floci o servicio usa el puerto. | `docker ps` → para el que lo ocupa. |
| Los datos desaparecen al reiniciar | Floci arrancó en modo memoria. | `docker logs floci \| grep Storage` debe decir `persistent`. Si no, ejecuta el script. |
| `localhost.floci.io` no resuelve | DNS sin internet o bloqueado. | Usa `export AWS_ENDPOINT_URL=http://localhost:4566`. |
| `Permission denied` en `floci-data/` | Archivos creados por el contenedor (otro UID). | Normal. Para copiarlos usa `sudo`. |
| Floci no llega a `healthy` | Falta RAM o la imagen está corrupta. | `docker logs floci`. Sube la memoria de WSL en `%UserProfile%\.wslconfig` (`[wsl2]` → `memory=8GB`) y `wsl --shutdown`. |
