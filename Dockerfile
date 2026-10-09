# Deliberately not a buildable image.
#
# This repository holds two services, each with its own Dockerfile:
#
#     web/Dockerfile      the Next.js app
#     backend/Dockerfile  the FastAPI API
#
# A build that reaches this file is a service pointed at the repository root
# instead of one of those. The platform's own words for that are
#
#     failed to read dockerfile: open Dockerfile: no such file or directory
#
# which name neither the service nor the setting that sent it here. This file
# exists so that build fails with instructions instead.
#
# Building the web app from here was the obvious alternative and is worse: if
# the API service were ever misconfigured the same way it would quietly build
# and deploy the wrong application, and succeed while doing it.
FROM alpine:3.20
RUN echo "" >&2; \
    echo "=============================================================" >&2; \
    echo " This service is pointed at the repository root." >&2; \
    echo " There is no application here — there are two, in web/ and" >&2; \
    echo " backend/, each with its own Dockerfile." >&2; \
    echo "" >&2; \
    echo " Fix it in the service's Settings -> Build & Deploy, using" >&2; \
    echo " ONE of these two rows. Mixing them produces this error:" >&2; \
    echo "" >&2; \
    echo "   Root Directory | Dockerfile Path      | Build Context" >&2; \
    echo "   ---------------+----------------------+--------------" >&2; \
    echo "   (blank)        | ./web/Dockerfile     | ./web" >&2; \
    echo "   web            | ./Dockerfile         | ." >&2; \
    echo "" >&2; \
    echo " For the API service, read backend/ for web/ throughout." >&2; \
    echo "" >&2; \
    echo " The web image must be built with web/ as its context: its" >&2; \
    echo " first COPY takes package.json from the context root." >&2; \
    echo "=============================================================" >&2; \
    echo "" >&2; \
    exit 1
