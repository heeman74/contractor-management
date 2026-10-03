# Self-hosted fonts

Geist, Geist Mono and Archivo, latin subset, as variable fonts.

They live here rather than being fetched through `next/font/google` because that
downloads them **during the build**. The deploy build failed on exactly that:

    at <unknown> ([next]/internal/font/google/archivo_….module.css:9:9)
    at <unknown> (https://nextjs.org/docs/messages/module-not-found)
    error: failed to solve: process "/bin/sh -c npm run build" exit code: 1

A build that reaches out to a third party is a build that fails when that third
party is unreachable from the builder — and a web deploy that cannot build means
no fix ships, however correct it is.

Each file is the variable version covering the whole weight axis, so one file per
family serves every weight the app uses.

Both families are licensed under the SIL Open Font License, which permits
redistribution. Re-fetch with the `latin` subset from Google Fonts if they ever
need updating.
