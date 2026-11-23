# floci-aws — Laboratorio AWS local con Floci

Levanta un **emulador de la API de AWS** ([Floci](https://hub.docker.com/r/floci/floci)) en Docker. Funciona con la AWS CLI real, kubectl y docker, sin tocar Amazon.

| Componente | Contenedor | URL |
|---|---|---|
| API de AWS (S3, ECR, EKS, RDS, IAM…) | `floci` | http://localhost:4566 |
| Consola web | `floci-aws-ui` | http://localhost:4500 |
| Registry ECR (lo crea Floci) | `floci-aws-ecr-registry` | 127.0.0.1:5100 |
| Clusters EKS / k3s (los crea Floci) | `floci-aws-eks-<cluster>` | localhost:6500 |

El estado se guarda en `~/floci-data`, así que no se pierde al reiniciar.

## Arranque rápido

```bash
git clone https://github.com/Leonix89cdmx/floci-aws.git ~/floci-aws
cd ~/floci-aws
chmod +x start_aws_floci.sh
./start_aws_floci.sh
```

El script es **idempotente**. Crea la red `floci-net`, la carpeta de datos y los contenedores, y arranca lo que esté parado. Si algo está mal configurado, lo recrea sin borrar los datos. Al final verifica que todo responde.

Para instalarlo en un equipo nuevo con Windows + WSL2, ve a **[docs/INSTALACION-WSL.md](docs/INSTALACION-WSL.md)**.

## Conectar la AWS CLI

```bash
export AWS_ENDPOINT_URL=http://localhost.floci.io:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

aws sts get-caller-identity   # arn:aws:iam::000000000000:root
```

Si tienes la CLI `floci`, basta con `eval "$(floci env)"`.

## Reglas importantes

- ⚠️ **No uses `floci start`.** Recrea el contenedor sin la red `floci-net` y ECR vuelve a dar `503`. Usa `./start_aws_floci.sh` o `docker start|stop|restart floci`.
- Mientras `AWS_ENDPOINT_URL` esté definida, **todo `aws` va a Floci**. Para AWS real: `unset AWS_ENDPOINT_URL`.
- `floci-data/` contiene secretos. Está en `.gitignore`: no lo subas nunca a un repo público.

## Configuración aplicada (y por qué)

| Ajuste | Problema que resuelve |
|---|---|
| Red Docker propia `floci-net` | En la red `bridge` Floci no alcanzaba su registry: `503 ECR registry is unavailable`. |
| `FLOCI_SERVICES_ECR_DOCKER_NETWORK=floci-net` | Le dice a Floci en qué red crear el registry ECR. |
| `FLOCI_STORAGE_MODE=persistent` + bind mount de `~/floci-data` | Por defecto todo vive en memoria y se pierde al reiniciar. |
| UI apuntando a `http://floci:4566` | Evita depender de una IP de contenedor que cambia. |
| `-v /var/run/docker.sock` | Floci crea contenedores reales (ECR, EKS, RDS). |

## Versiones probadas

Docker Engine 29.9.3 · imagen `floci/floci` 2.4.0 · `floci/floci-ui` 0.7.0 · AWS CLI 2.40.3 · kubectl 1.36.1 · CLI `floci` 0.4.0 · Ubuntu 24.04 en WSL2.
