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
# It exists only to turn "open Dockerfile: no such file or directory" — which
# names neither the service nor the setting that caused it — into instructions,
# in the build log the operator is already reading. It must never build
# something, because a service pointed at the root is misconfigured and
# succeeding would hide that.
# ---------------------------------------------------------------------------

_ROOT_DOCKERFILE = _REPO / "Dockerfile"


def test_the_root_dockerfile_refuses_to_build() -> None:
    assert _ROOT_DOCKERFILE.is_file()
    assert "exit 1" in _ROOT_DOCKERFILE.read_text()


def test_it_names_both_real_dockerfiles() -> None:
    """Whichever service lands here, the way out is in front of them."""
    contents = _ROOT_DOCKERFILE.read_text()

    assert "web/Dockerfile" in contents
    assert "backend/Dockerfile" in contents


def test_it_does_not_copy_an_application_into_itself() -> None:
    """Building the web app from here would mean a misconfigured API service
    quietly deploys the wrong application, and succeeds doing it.

    Reads instructions rather than the whole file: the explanation mentions the
    web image's first COPY, and matching prose would fail on the comment that
    exists to prevent exactly this.
    """
    instructions = [
        line.split()[0].upper()
        for line in _ROOT_DOCKERFILE.read_text().splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]

    assert "COPY" not in instructions, instructions
    assert "ADD" not in instructions, instructions


def test_the_blueprint_still_points_elsewhere() -> None:
    """Adding a root Dockerfile must not become the path anything uses."""
    assert "./Dockerfile" not in _values("dockerfilePath")
