"""The blueprint must point at files that exist.

A deploy failed with:

    #1 transferring dockerfile: 2B done
    error: failed to solve: failed to read dockerfile: open Dockerfile:
    no such file or directory

That particular failure was a service configured in the dashboard rather than
from this file, but the class of mistake is worth catching here: a path in the
blueprint that does not resolve costs a full clone, build and deploy cycle to
discover, and says nothing about which path was wrong.
"""

from __future__ import annotations

import pathlib
import re

import pytest

_REPO = pathlib.Path(__file__).resolve().parent.parent.parent
_BLUEPRINT = _REPO / "render.yaml"


def _blueprint() -> str:
    return _BLUEPRINT.read_text()


def _values(key: str) -> list[str]:
    return re.findall(rf"^\s*{key}:\s*(\S+)\s*$", _blueprint(), re.M)


def test_the_blueprint_is_where_the_tests_think_it_is() -> None:
    """Otherwise everything below passes by finding nothing."""
    assert _BLUEPRINT.exists(), _BLUEPRINT
    assert _values("dockerfilePath"), "no dockerfilePath entries found to check"


@pytest.mark.parametrize("path", _values("dockerfilePath"))
def test_each_dockerfile_exists(path: str) -> None:
    resolved = (_REPO / path.lstrip("./")).resolve()
    assert resolved.is_file(), f"{path} does not resolve to a file"


@pytest.mark.parametrize("path", _values("dockerfilePath"))
def test_each_dockerfile_has_contents(path: str) -> None:
    """A two-byte Dockerfile is what the failed build reported transferring."""
    resolved = (_REPO / path.lstrip("./")).resolve()
    assert resolved.stat().st_size > 50, f"{path} is suspiciously small"
    assert "FROM" in resolved.read_text(), f"{path} has no FROM instruction"


@pytest.mark.parametrize("path", _values("dockerContext"))
def test_each_build_context_exists(path: str) -> None:
    resolved = (_REPO / path.lstrip("./")).resolve()
    assert resolved.is_dir(), f"{path} is not a directory"


def test_each_dockerfile_sits_inside_its_build_context() -> None:
    """Docker cannot read a Dockerfile from outside the context it was given,
    and the two are configured separately — so they can disagree."""
    blueprint = _blueprint()
    pairs = re.findall(r"dockerfilePath:\s*(\S+)\s*\n\s*dockerContext:\s*(\S+)", blueprint)
    assert pairs, "expected dockerfilePath and dockerContext to be declared together"

    for dockerfile, context in pairs:
        resolved_file = (_REPO / dockerfile.lstrip("./")).resolve()
        resolved_context = (_REPO / context.lstrip("./")).resolve()
        assert resolved_context in resolved_file.parents, f"{dockerfile} is not inside {context}"


# ---------------------------------------------------------------------------
# The root Dockerfile
#
# It builds the web app from the repository root, because a service is
# configured with the root as its build context and four deploys failed on
# "open Dockerfile: no such file or directory". It is web/Dockerfile with the
# paths rebased, and the risk is that the two drift: a change made in one and
# not the other would ship a different image depending on which settings the
# service happens to have.
# ---------------------------------------------------------------------------

_ROOT_DOCKERFILE = _REPO / "Dockerfile"
_WEB_DOCKERFILE = _REPO / "web" / "Dockerfile"


def _instructions(path: pathlib.Path) -> list[str]:
    """Instruction lines only, so prose and comments do not count."""
    return [
        " ".join(line.split())
        for line in path.read_text().splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]


def test_the_root_dockerfile_builds_the_web_app() -> None:
    assert _ROOT_DOCKERFILE.is_file()
    assert "npm run build" in _ROOT_DOCKERFILE.read_text()


def test_it_takes_its_sources_from_web() -> None:
    """Rebased paths are the whole difference; without them the build fails on
    a package.json it cannot find."""
    contents = _ROOT_DOCKERFILE.read_text()

    assert "COPY web/package.json" in contents
    assert "COPY web/ ./" in contents


def test_the_two_dockerfiles_have_not_drifted() -> None:
    """Same stages, same base images, same command — only the paths differ."""
    root = _instructions(_ROOT_DOCKERFILE)
    web = _instructions(_WEB_DOCKERFILE)

    def shape(lines: list[str]) -> list[str]:
        return [
            line
            for line in lines
            if line.startswith(("FROM ", "WORKDIR ", "USER ", "EXPOSE ", "CMD ", "ENV "))
        ]

    assert shape(root) == shape(web), (
        "the root Dockerfile and web/Dockerfile have diverged beyond their paths"
    )
    assert len([line for line in root if line.startswith("RUN ")]) == len(
        [line for line in web if line.startswith("RUN ")]
    )


def test_the_blueprint_still_points_at_the_real_one() -> None:
    """The root file is a workaround for a misconfigured service, not the path
    anything should be configured to use."""
    assert "./Dockerfile" not in _values("dockerfilePath")
    assert "./web/Dockerfile" in _values("dockerfilePath")
