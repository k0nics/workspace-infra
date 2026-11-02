# Centralized Laravel development

The shared stack runs one Nginx and one MySQL container. Each Laravel project runs
only its own PHP-FPM container and bind-mounts its repository, so PHP, Blade, route,
and configuration source changes do not require an image rebuild or container restart.

Run all commands from the workspace root.

## TIS-Admin

Start the shared services and the application:

```sh
docker compose -f docker-infra/compose.yml up -d mysql nginx
DOCKER_BUILDKIT=0 docker compose -f projects/tisph-cms.yml up -d --build app
```

Open <http://tisph-cms.localhost:8080/admin/auth>.

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

Open <http://tisph-website.localhost:8080>. Both TIS applications use Nginx port
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
DOCKER_BUILDKIT=0 docker compose -f projects/tfs-cms.yml up -d --build app
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
DOCKER_BUILDKIT=0 docker compose -f projects/tisph-cms.yml build app
docker compose -f projects/tisph-cms.yml up -d app
```

`DOCKER_BUILDKIT=0` is currently needed on this workstation because Docker is
configured with a missing `buildx` CLI plugin. It can be dropped after `buildx` is
installed or the stale CLI-plugin configuration is fixed.

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
   and the external `dev-network`. Override `DB_HOST=mysql` only in Compose.
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
