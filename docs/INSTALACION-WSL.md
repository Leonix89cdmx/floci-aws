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

## 2. Instalar Docker Desktop (en Windows)

1. Descarga e instala **Docker Desktop**: https://www.docker.com/products/docker-desktop/
2. Durante la instalación, deja marcado **Use WSL 2 instead of Hyper-V**.
3. Abre Docker Desktop → **Settings**:
   - **General** → ✅ *Use the WSL 2 based engine*.
   - **Resources → WSL integration** → ✅ activa **Ubuntu-24.04** → *Apply & restart*.
   - (Opcional) **Kubernetes** → *Enable Kubernetes* si también usarás el cluster de Docker Desktop.

Verifícalo **desde Ubuntu**:

```bash
docker version        # debe mostrar Client y Server
docker run --rm hello-world
```

> ❌ Si sale `docker: command not found` o `Cannot connect to the Docker daemon`, la integración WSL no está activada para tu distro (paso 3) o Docker Desktop no está abierto.

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

### 3.3 CLI `floci` (opcional)

No es necesaria: el script levanta todo con `docker`. Solo sirve para `floci env`, `floci status` y `floci doctor`. Si la quieres, copia el binario desde el equipo original. En el original:

```bash
cp /usr/local/bin/floci /mnt/c/Users/Public/floci
```

Pásalo al equipo nuevo (USB, red…) y ponlo en la misma ruta. En el nuevo:

```bash
sudo install -m 0755 /mnt/c/Users/Public/floci /usr/local/bin/floci
floci --version
```

---

## 4. Clonar el repo y levantar Floci

```bash
git clone https://github.com/Leonix89cdmx/floci-aws.git ~/floci-aws
cd ~/floci-aws
chmod +x start_aws_floci.sh
./start_aws_floci.sh
```

La primera vez descarga las imágenes `floci/floci` y `floci/floci-ui`, así que puede tardar varios minutos. Al terminar debe verse:

```
  ✔ Floci healthy
  ✔ Persistencia activa
  ✔ ECR responde (200)
  ✔ UI responde (200)

  Laboratorio AWS listo 🚀
```

> 💡 Clona el repo **dentro de Linux** (`~/…`), no en `/mnt/c/…`. Los bind mounts sobre el disco de Windows son lentos y dan problemas de permisos.

---

## 5. Conectar la AWS CLI en cada terminal

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

Si instalaste la CLI `floci`, puedes usar en su lugar la línea `eval "$(floci env)"`.

> ⚠️ Con esto, **todo comando `aws` va a Floci**. Para usar AWS real: `unset AWS_ENDPOINT_URL` y configura credenciales reales.

---

## 6. Verificación

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

## 7. (Opcional) Migrar los datos del equipo original

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

## 8. Uso diario

| Acción | Comando |
|---|---|
| Levantar / reparar todo | `~/floci-aws/start_aws_floci.sh` |
| Parar | `docker stop floci floci-aws-ui` |
| Reiniciar | `docker restart floci` |
| Logs | `docker logs -f floci` |
| Datos en otra ruta | `FLOCI_DATA_DIR=/ruta ./start_aws_floci.sh` |

Los contenedores usan `--restart unless-stopped`, así que **arrancan solos con Docker Desktop**. Tras reiniciar Windows basta con abrir Docker Desktop. Si algo falla, ejecuta el script.

---

## 9. Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `Docker no responde` | Docker Desktop cerrado o sin integración WSL. | Abre Docker Desktop y revisa *Settings → Resources → WSL integration*. |
| `503 ECR registry is unavailable` | Alguien ejecutó `floci start` y recreó Floci sin `floci-net`. | `./start_aws_floci.sh` (lo detecta y lo recrea). |
| `port is already allocated` (4566 / 4500) | Otro LocalStack/Floci o servicio usa el puerto. | `docker ps` → para el que lo ocupa. |
| Los datos desaparecen al reiniciar | Floci arrancó en modo memoria. | `docker logs floci \| grep Storage` debe decir `persistent`. Si no, ejecuta el script. |
| `localhost.floci.io` no resuelve | DNS sin internet o bloqueado. | Usa `export AWS_ENDPOINT_URL=http://localhost:4566`. |
| `Permission denied` en `floci-data/` | Archivos creados por el contenedor (otro UID). | Normal. Para copiarlos usa `sudo`. |
| Floci no llega a `healthy` | Falta RAM o la imagen está corrupta. | `docker logs floci`. Sube la memoria de WSL en `%UserProfile%\.wslconfig` (`[wsl2]` → `memory=8GB`) y `wsl --shutdown`. |
