# Centralized Laravel development

The shared stack runs one Nginx and one MySQL container. Each Laravel project runs
only its own PHP-FPM container and bind-mounts its repository, so PHP, Blade, route,
and configuration source changes do not require an image rebuild or container restart.

Run all commands from the workspace root.

## Host platform support: macOS and Windows

This development environment works on both macOS and Windows because Docker runs
the same Linux containers on either host. Compose uses relative bind-mount paths,
so no developer-specific absolute path is stored in the project files.

Supported host setups:

- macOS with Docker Desktop or Colima.
- Windows with Docker Desktop, the WSL 2 backend, and Linux containers enabled.

Every developer must preserve this directory layout and the exact repository
directory names:

```text
Workspace/
├── docker-infra/
├── projects/
└── repositories/
    ├── TIS-Admin/
    ├── TFS-QMS-Cron/
    └── ...
```

The `repositories/` directory is intentionally not tracked by this infrastructure
repository. Each application must be cloned separately into it. Each developer
also needs the appropriate application `.env` files; secrets must be distributed
through an approved secure channel rather than committed to Git.

Unless a section is explicitly marked otherwise, the one-line `docker compose`
commands in this guide work unchanged in macOS Terminal, Windows PowerShell, and
a WSL terminal.

### macOS setup

Install and start Docker Desktop, or start the existing Colima runtime:

```sh
colima start
docker compose version
docker info
```

Docker Desktop users do not need Colima; start Docker Desktop and run only the
two Docker verification commands. See the official
[Docker Desktop for Mac installation guide](https://docs.docker.com/desktop/setup/install/mac-install/).

Create the shared infrastructure environment file on first setup:

```sh
cp docker-infra/.env.example docker-infra/.env
```

### Windows setup

Install Docker Desktop, enable its WSL 2 engine and WSL integration, and make sure
Docker is using Linux containers. See Docker's official
[WSL 2 backend guide](https://docs.docker.com/desktop/features/wsl/).

For the best bind-mount and hot-reload performance, clone `Workspace` inside the
WSL Linux filesystem, such as `~/Workspace`, and run the commands from a WSL
terminal. Docker recommends the Linux filesystem instead of `/mnt/c/...` for
bind-mounted source code. PowerShell with a normal Windows checkout also works,
but filesystem access and file watching may be slower.

From PowerShell, create the infrastructure environment file with:

```powershell
Copy-Item docker-infra/.env.example docker-infra/.env
docker compose version
docker info
```

The root `.gitattributes` keeps container shell scripts and Docker configuration
on Unix `LF` line endings. This prevents errors such as `/bin/sh^M` after a
Windows checkout.

### First-time image builds on either platform

Images tagged `:local` exist only inside each developer's Docker installation;
they do not need an artifact registry. Build only the versions needed by that
developer's applications. For the QMS Laravel applications, build PHP 8.1 first
and then its derived MSSQL image:

```sh
docker build -f docker-infra/images/php-dev/Dockerfile.php81 -t laravel-php81-dev:local docker-infra/images/php-dev
docker build -f docker-infra/images/php-dev/Dockerfile.php81-mssql -t laravel-php81-mssql-dev:local docker-infra/images/php-dev
```

Other available local images can be built independently:

```sh
docker build -f docker-infra/images/php-dev/Dockerfile -t laravel-php83-dev:local docker-infra/images/php-dev
docker build -f docker-infra/images/php-dev/Dockerfile.php74 -t laravel-php74-dev:local docker-infra/images/php-dev
```

If Buildx is missing, use the classic builder for that terminal session.

macOS Terminal or WSL:

```sh
export DOCKER_BUILDKIT=0
# Run the required docker build commands.
unset DOCKER_BUILDKIT
```

Windows PowerShell:

```powershell
$env:DOCKER_BUILDKIT = "0"
# Run the required docker build commands.
Remove-Item Env:DOCKER_BUILDKIT
```

Start the shared services after the required images have been built:

```sh
docker compose -f docker-infra/compose.yml up -d
docker compose -f docker-infra/monitoring/compose.yml up -d
```

The `*.localhost` URLs normally resolve to `127.0.0.1` on both platforms, so no
hosts-file entries should be necessary. Applications using online MSSQL still
require the corporate VPN/network route to be available inside Docker Desktop or
Colima; host access to the VPN does not always guarantee VM access.

## TIS-Admin

Start the shared services and the application:

```sh
docker compose -f docker-infra/compose.yml up -d mysql nginx
docker compose -f projects/tisph-cms.yml up -d --build app
```

Open <http://tisph-cms-ben-local.localhost:8080/admin/auth>.

After the first successful image build, ordinary starts do not need `--build`:

```sh
docker compose -f projects/tisph-cms.yml up -d app
```

The reusable `docker-infra/scripts/start-laravel-php-fpm.sh` startup script removes
a stale `public/hot` marker before PHP-FPM starts. Start the PHP container before
running Vite so an active Vite marker is not removed.

Stop only TIS-Admin while leaving shared infrastructure running:

```sh
docker compose -f projects/tisph-cms.yml down
```

Run Laravel and Composer commands in the application container:

```sh
docker compose -f projects/tisph-cms.yml exec app php artisan optimize:clear
docker compose -f projects/tisph-cms.yml exec app php artisan migrate
docker compose -f projects/tisph-cms.yml exec app composer install
```

Migrations, seeders, and Composer installs are deliberately never run on container
startup. Run them manually only when the project requires them.

## Frontend hot reload

Frontend tooling runs directly on the host, so TIS-Admin needs only one Docker
container. From `repositories/TIS-Admin`, install dependencies once and start Vite:

```sh
npm install
npm run dev
```

Keep that terminal open while editing Vue, JavaScript, or CSS. Stop Vite with
`Ctrl+C`. PHP and Blade changes do not require Vite; refresh the browser normally.

## TIS-Website

TIS-Website reuses the same PHP 8.3 development image and shared Nginx, MySQL, and
Docker network. Start it independently:

```sh
docker compose -f projects/tisph-website.yml up -d app
```

Open <http://tisph-website-ben-local.localhost:8080>. Both TIS applications use Nginx port
`8080`; Nginx selects the application by hostname. Their PHP-FPM containers both
use port `9000` internally without conflict.

For TIS-Website frontend hot reload, run this separately on the host:

```sh
cd repositories/TIS-Website
npm run dev -- --port 5174
```

Stop only TIS-Website with:

```sh
docker compose -f projects/tisph-website.yml down
```

## TFS Website and CMS

The public website uses PHP 8.3, while the older Laravel 8 CMS uses the separate
PHP 8.1 development image required by its locked Composer dependencies.

```sh
docker compose -f projects/tfs-website.yml up -d app
docker compose -f projects/tfs-cms.yml up -d --build app
```

Open:

- <http://tfs-website-ben-local.localhost:8080>
- <http://tfs-cms-ben-local.localhost:8080>

Both projects use Laravel Mix. Run `npm run watch` from each repository when you
want frontend source changes compiled continuously to the bind-mounted `public`
directory. No extra frontend container or application HTTP port is required.

## SGV Website and CMS

Both SGV applications use Laravel 7 and their locked Composer dependencies require
PHP 7.4. Start their PHP-FPM containers independently:

```sh
docker compose -f projects/sgv-website.yml up -d app
docker compose -f projects/sgv-cms.yml up -d app
```

Open:

- <http://sgv-website-ben-local.localhost:8080>
- <http://sgv-cms-ben-local.localhost:8080>

Both projects use Laravel Mix. Run `npm run watch` from the relevant repository
for frontend compilation. PHP source remains bind-mounted and needs only a browser
refresh.

## Ortigas Land Website and CMS

The locked Ortigas Land dependencies require PHP 7.x, so both applications reuse
the dedicated PHP 7.4 development image:

```sh
docker compose -f projects/ortigas-land-website.yml up -d app
docker compose -f projects/ortigas-land-cms.yml up -d app
```

Open:

- <http://ortigas-land-website-ben-local.localhost:8080>
- <http://ortigas-land-cms-ben-local.localhost:8080>

The Website uses Vite (`npm run dev` or `npm run watch`), while the CMS uses
Laravel Mix (`npm run watch`). PHP source remains bind-mounted.

## Centralized logs

Grafana, Loki, and Alloy collect the Laravel log files from all configured applications.
Start the monitoring stack independently from the applications:

```sh
docker compose -f docker-infra/monitoring/compose.yml up -d
```

Open <http://grafana-ben-local.localhost:8080>, sign in with `admin` / `admin`, and
open the application dashboard inside its TIS, TFS, SGV, Ortigas Land, Globe, or QMS folder. The local password can
be overridden with `GRAFANA_ADMIN_PASSWORD` when the Grafana data volume is first
initialized. Existing Grafana volumes retain their current password.

Alloy reads each bind-mounted `storage/logs/laravel*.log` file and sends it to
Loki with `app`, `env=local`, and `job=laravel` labels. Laravel stack traces are
grouped into a single multiline log entry. No application logging configuration
change is required.

## When to rebuild

Rebuild `laravel-php83-dev:local` only when the PHP version, extensions, system
packages, Composer binary, or files under `docker-infra/images/php-dev` change:

```sh
docker compose -f projects/tisph-cms.yml build app
docker compose -f projects/tisph-cms.yml up -d app
```

`DOCKER_BUILDKIT=0` is currently needed only on a workstation whose Docker CLI is
configured with a missing `buildx` plugin. Developers with a working Buildx
installation should omit it. The platform-specific syntax is documented above.

Do not rebuild for changes to controllers, models, routes, Blade or Vue files, CSS,
or other bind-mounted application source. Run `composer install` in the existing
container when `composer.json` or `composer.lock` changes. If Laravel is using a
previously generated cache after a configuration or route change, run
`php artisan optimize:clear` once.

## Add another Laravel project

1. Reuse `laravel-php83-dev:local` when PHP 8.3 and its extensions are compatible.
   Create another version-specific development image for a different PHP version.
2. Add a project Compose file under `projects/` with one PHP-FPM service, the
   repository mounted at `/app`, its existing `.env` supplied through `env_file`,
   and the external `dev-network`. Override `DB_HOST=mysql` only when the project
   is intentionally using the shared local MySQL service; preserve external
   database settings for applications such as QMS.
   Mount `docker-infra/scripts/start-laravel-php-fpm.sh` to reuse the same safe
   startup behavior.
3. Add the repository as a read-only mount on `docker-infra/compose.yml`'s Nginx
   service. Use a unique mount path when multiple applications are enabled at once.
4. Add an Nginx virtual host under `docker-infra/nginx/conf.d/` that routes PHP to
   the project's PHP-FPM service name on port 9000.
5. Recreate only shared Nginx after adding its new mount, then start the individual
   project container. Do not add another Nginx or MySQL service.

PHP OPcache and the realpath cache are disabled in the development image, ensuring
that bind-mounted PHP changes are read on the next request. PHP-FPM uses on-demand
workers so an idle project has a small memory footprint.

## Globe Digitest

Globe Digitest uses Laravel 12 on the shared PHP 8.3 development image. Its local
`.env` is based on the repository example and retains the database name there.

```sh
docker compose -f projects/globe-digitest.yml up -d app
```

Open <http://globe-digitest-ben-local.localhost:8080>. Run `composer install` in
the container once when `vendor/` is absent. Run `npm run dev` from
`repositories/globe-digitest` for Vite hot reload.

## QMS applications

QMS Kiosk is a Next.js application and therefore runs a Node development server,
not PHP-FPM. Install its Linux dependencies into the persistent Docker volume once,
then start it:

```sh
docker compose -f projects/qms-kiosk.yml run --rm app npm ci
docker compose -f projects/qms-kiosk.yml up -d app
```

Open <http://qms-kiosk-ben-local.localhost:8080>. Source code is bind-mounted and
Next.js development hot reload is enabled. Follow its stdout logs with:

```sh
docker compose -f projects/qms-kiosk.yml logs -f app
```

QMS Cron is a Laravel 8 API whose locked dependencies require PHP 8.1. It uses
a dedicated image layered on the general PHP 8.1 image with Microsoft ODBC 18,
`sqlsrv`, and `pdo_sqlsrv`. Its online MSSQL connection settings come directly
from the repository `.env` and are not replaced with local MySQL values:

```sh
docker compose -f projects/qms-cron.yml up -d app
```

Its API is available at <http://qms-cron-ben-local.localhost:8080>. The Compose
service intentionally runs only PHP-FPM. It does not automatically start
`php artisan schedule:work`, preventing scheduled jobs from calling external
systems unexpectedly during local development.

QMS CMS, Appointment, and Counter are Laravel 8 applications. They reuse the
same PHP 8.1 MSSQL image as QMS Cron, while each application has its own source
mount, PHP-FPM container, Nginx host, and log stream:

```sh
docker compose -f projects/qms-cms.yml up -d app
docker compose -f projects/qms-appointment.yml up -d app
docker compose -f projects/qms-counter.yml up -d app
```

Open them at:

- <http://qms-cms-ben-local.localhost:8080>
- <http://qms-appointment-ben-local.localhost:8080>
- <http://qms-counter-ben-local.localhost:8080>

All QMS applications retain their existing online MSSQL settings. The Docker
runtime must therefore have a network route to that server. If DNS resolves but
port `1433` times out, connect the required VPN and ensure the Docker/Colima VM
can use the VPN route; changing Laravel credentials will not fix a TCP timeout.

Do not run migrations or seeders against a QMS database unless that online
environment and the intended change have been explicitly confirmed.
