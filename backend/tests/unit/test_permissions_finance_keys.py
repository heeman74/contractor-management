"""Pure-unit regression tests for the finance.* permission keys.

Proves FINSEC-01/03 at the catalog/derivation layer (no DB, no fixtures):
admin's derived default set excludes finance.* by construction, while
project_manager's default set includes all three, and the catalog exposes
them correctly grouped under "Finance".
"""

from app.core.permissions import (
    _FINANCE_ONLY_KEYS,
    DEFAULT_ROLE_PERMISSIONS,
    PERMISSION_CATALOG,
    PERMISSION_KEYS,
)

FINANCE_KEYS = frozenset({"finance.view", "finance.manage", "finance.rates.manage"})


def test_admin_default_has_no_finance_keys():
    assert FINANCE_KEYS.isdisjoint(set(DEFAULT_ROLE_PERMISSIONS["admin"]))


def test_project_manager_default_has_all_finance_keys():
    assert set(DEFAULT_ROLE_PERMISSIONS["project_manager"]) >= FINANCE_KEYS


def test_finance_keys_present_in_catalog_with_finance_group():
    finance_entries = [entry for entry in PERMISSION_CATALOG if entry["group"] == "Finance"]
    assert {entry["key"] for entry in finance_entries} == FINANCE_KEYS
    assert len(finance_entries) == 3
    assert FINANCE_KEYS <= PERMISSION_KEYS


def test_finance_exclusion_tuple_matches_finance_keys():
    assert set(_FINANCE_ONLY_KEYS) == FINANCE_KEYS


def test_gc_and_worker_defaults_have_no_finance_keys():
    assert FINANCE_KEYS.isdisjoint(set(DEFAULT_ROLE_PERMISSIONS["gc"]))
    assert FINANCE_KEYS.isdisjoint(set(DEFAULT_ROLE_PERMISSIONS["worker"]))
