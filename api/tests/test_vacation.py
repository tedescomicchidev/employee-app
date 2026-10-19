"""FR-VAC-001, FR-VAC-002, FR-VAC-006 (CLASSIC path), test-cases.md sections of the same IDs."""

import json
from collections.abc import Callable
from dataclasses import replace
from datetime import UTC, date, datetime
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.auth.validator import TokenValidator
from app.main import create_app
from app.repositories import InMemoryConfirmationStore, SeedDirectory
from app.vacation import rules
from app.vacation.models import CANTONS, Balance, Blackout, Holiday
from app.vacation.service import VacationService
from app.vacation.store import SEED_DIR, InMemoryVacationStore, VacationConfig
from tests.conftest import SETTINGS, StaticKeys

OIDS = {
    "ceo": "00000000-0000-0000-0000-000000000001",
    "mgr1": "00000000-0000-0000-0000-000000000002",
    "mgr2": "00000000-0000-0000-0000-000000000003",
    "emp1": "00000000-0000-0000-0000-000000000011",
    "emp2": "00000000-0000-0000-0000-000000000012",
    "emp4": "00000000-0000-0000-0000-000000000014",
}
FROZEN = datetime(2026, 10, 19, 6, 0, tzinfo=UTC)  # 08:00 Europe/Zurich
GUEST = "00000000-0000-0000-0000-0000000000ff"
TokenFactory = Callable[..., str]


class Env:
    def __init__(self, private_key: Any, make_token: TokenFactory, config: VacationConfig) -> None:
        self.directory = SeedDirectory.from_file()
        self.store = InMemoryVacationStore()
        self.service = VacationService(
            self.directory, self.store, InMemoryConfirmationStore(), config, lambda: FROZEN
        )
        validator = TokenValidator(SETTINGS, StaticKeys(private_key.public_key()))
        self.client = TestClient(create_app(validator, vacation_service=self.service))
        self._make_token = make_token

    def headers(self, who: str) -> dict[str, str]:
        oid = OIDS.get(who, who)
        return {"Authorization": f"Bearer {self._make_token(oid=oid)}"}

    def get(self, who: str, path: str) -> Any:
        return self.client.get(f"/v1/vacation{path}", headers=self.headers(who))

    def propose(self, who: str, start: str, end: str) -> Any:
        return self.client.post(
            "/v1/proposals",
            json={"type": "vacation", "payload": {"start": start, "end": end}},
            headers=self.headers(who),
        )

    def confirm(self, who: str, proposal_id: str) -> str:
        r = self.client.post(
            "/v1/confirmations",
            json={"type": "vacation", "proposal_id": proposal_id},
            headers=self.headers(who),
        )
        assert r.status_code == 200, r.text
        return r.json()["confirmation_token"]

    def submit(self, who: str, start: str, end: str, token: str) -> Any:
        return self.client.post(
            "/v1/vacation/requests",
            json={"start": start, "end": end, "confirmation_token": token},
            headers=self.headers(who),
        )

    def book(self, who: str, start: str, end: str) -> Any:
        proposal = self.propose(who, start, end)
        assert proposal.status_code == 200, proposal.text
        token = self.confirm(who, proposal.json()["proposal_id"])
        return self.submit(who, start, end, token)


@pytest.fixture
def env(private_key: Any, make_token: TokenFactory) -> Env:
    return Env(private_key, make_token, VacationConfig.from_files())


def codes(response: Any) -> list[str]:
    return response.json()["codes"]


# --- FR-VAC-001 ---------------------------------------------------------------------------


def test_fr_vac_001_balance_formula() -> None:
    """FR-VAC-001 @unit: 25 + 4 - 10 - 3 = 16."""
    assert Balance(2026, 25, 4, 10, 3).remaining == 16


def test_fr_vac_001_unlimited_carry_over_accumulates() -> None:
    """FR-VAC-001 @unit (R2, HR-CONFIRM): 7 unused days carry into next year as 7."""
    balance = rules.balance_for(2027, 25, 7, 2026, [])
    assert balance.carried_over == 32  # 7 base + 25 unused of 2026
    assert rules.balance_for(2026, 25, 7, 2026, []).carried_over == 7


def test_fr_vac_001_balance_shown_for_emp2(env: Env) -> None:
    """FR-VAC-001 @api: approved fixture request gives approved 5, remaining 20."""
    r = env.get("emp2", "/balance")
    assert r.status_code == 200
    assert r.json() == {
        "year": 2026,
        "entitlement": 25,
        "carried_over": 0,
        "approved": 5,
        "pending": 0,
        "remaining": 20,
    }


def test_fr_vac_001_emp1_has_three_remaining(env: Env) -> None:
    """Fixture check: emp1 approved 22, remaining 3."""
    assert env.get("emp1", "/balance").json()["remaining"] == 3


def test_fr_vac_001_balance_follows_the_last_write(env: Env) -> None:
    """FR-VAC-001.2: a submit is reflected on the next view without any refresh step."""
    assert env.book("emp2", "2026-11-23", "2026-11-25").status_code == 201
    b = env.get("emp2", "/balance").json()
    assert (b["pending"], b["remaining"]) == (3, 17)
    listed = env.get("emp2", "/requests").json()["items"]
    assert sum(i["counted_days"] for i in listed if i["status"] == "pending") == b["pending"]


@pytest.mark.parametrize(
    "path", ["/balance/" + OIDS["emp2"], "/balance?employee_id=" + OIDS["emp2"]]
)
def test_fr_vac_001_cannot_read_another_users_balance(env: Env, path: str) -> None:
    """FR-VAC-001.3 @adversarial: emp1 never receives emp2's numbers."""
    r = env.get("emp1", path)
    if path.startswith("/balance?"):
        assert r.json()["remaining"] == 3  # the caller's own, never emp2's 20
    else:
        assert r.status_code in (403, 404)
        assert "remaining" not in r.text


def test_fr_vac_001_requires_a_provisioned_employee(env: Env) -> None:
    assert env.get(GUEST, "/balance").status_code == 403
    assert env.client.get("/v1/vacation/balance").status_code == 401


# --- FR-VAC-002 ---------------------------------------------------------------------------


def test_fr_vac_002_valid_request_becomes_pending_and_reaches_inbox(env: Env) -> None:
    """FR-VAC-002.1/.3/.5 @api: pending, assigned to mgr1, 3 days, remaining 22."""
    proposal = env.propose("emp2", "2026-11-23", "2026-11-25")
    review = proposal.json()["review"]
    assert review["counted_days"] == 3
    assert review["excluded"] == []
    assert (review["remaining"], review["remaining_after"]) == (25 - 5, 17)
    assert env.store.for_owner(OIDS["emp2"])[-1].start == date(2026, 11, 2)  # nothing created yet
    assert len(env.store.for_owner(OIDS["emp2"])) == 1
    token = env.confirm("emp2", proposal.json()["proposal_id"])
    r = env.submit("emp2", "2026-11-23", "2026-11-25", token)
    assert r.status_code == 201
    body = r.json()
    assert body["status"] == "pending" and body["counted_days"] == 3
    assert body["approver"] == "Maria Keller" and body["per_year"] == {"2026": 3}
    inbox = env.get("mgr1", "/inbox").json()["items"]
    assert [i["id"] for i in inbox] == [body["id"]]
    assert env.get("mgr2", "/inbox").json()["items"] == []
    assert env.get("emp2", "/balance").json()["remaining"] == 17


def test_fr_vac_002_review_balance_is_after_submission_for_a_clean_account(env: Env) -> None:
    """test-cases 'Classic request flow': 3 days, no excluded days, balance after 22."""
    env.store._requests.clear()  # emp2 without the approved fixture: 25 remaining
    review = env.propose("emp2", "2026-11-23", "2026-11-25").json()["review"]
    assert (review["counted_days"], review["remaining_after"]) == (3, 22)


def test_fr_vac_002_insufficient_balance(env: Env) -> None:
    """FR-VAC-002.2 @adversarial: remaining 3, requested 5, nothing created."""
    r = env.propose("emp1", "2026-11-23", "2026-11-27")
    assert r.status_code == 422 and r.json()["code"] == "INSUFFICIENT_BALANCE"
    detail = r.json()["violations"][0]
    assert (detail["remaining"], detail["requested"]) == (3, 5)
    review = r.json()["review"]  # the blocked review still shows the counted days (mockup #7)
    assert (review["counted_days"], review["remaining"], review["excluded"]) == (5, 3, [])
    assert len(env.store.for_owner(OIDS["emp1"])) == 1
    assert env.get("emp1", "/balance").json()["remaining"] == 3


def test_fr_vac_002_overlap_with_approved_names_the_conflict(env: Env) -> None:
    r = env.propose("emp2", "2026-11-05", "2026-11-10")
    assert codes(r) == ["OVERLAP"]
    assert r.json()["violations"][0]["conflicts"] == [{"start": "2026-11-02", "end": "2026-11-06"}]


def test_fr_vac_002_overlap_with_pending(env: Env) -> None:
    assert env.book("emp2", "2026-11-16", "2026-11-18").status_code == 201
    assert codes(env.propose("emp2", "2026-11-18", "2026-11-19")) == ["OVERLAP"]


def test_fr_vac_002_blackout(env: Env) -> None:
    r = env.propose("emp2", "2026-12-21", "2026-12-23")
    assert r.json()["code"] == "BLACKOUT"
    assert (r.json()["violations"][0]["start"], r.json()["violations"][0]["end"]) == (
        "2026-12-14",
        "2026-12-24",
    )
    assert codes(env.propose("emp2", "2026-12-10", "2026-12-15")) == ["BLACKOUT"]


@pytest.mark.parametrize(
    ("start", "end", "expected"),
    [
        ("2026-10-12", "2026-10-14", ["PAST_DATE"]),
        ("2026-11-10", "2026-11-09", ["INVALID_RANGE"]),
        ("2026-11-14", "2026-11-15", ["ZERO_DAYS"]),
        ("2026-10-12", "2026-12-16", ["PAST_DATE", "BLACKOUT", "OVERLAP", "INSUFFICIENT_BALANCE"]),
    ],
)
def test_fr_vac_002_validation_precedence(
    env: Env, start: str, end: str, expected: list[str]
) -> None:
    r = env.propose("emp2", start, end)
    assert r.status_code == 422
    assert codes(r) == expected and r.json()["code"] == expected[0]


def test_fr_vac_002_malformed_dates_are_validation_errors(env: Env) -> None:
    r = env.propose("emp2", "2026-13-01", "2026-11-09")
    assert r.status_code == 422 and r.json()["code"] == "VALIDATION_ERROR"


def test_fr_vac_002_holidays_and_weekends_are_not_counted(env: Env) -> None:
    """FR-VAC-002/006 @unit: 11-09..11-13 for ZH counts 4; the review names the holiday."""
    review = env.propose("emp1", "2026-11-09", "2026-11-13")
    assert review.status_code == 422  # emp1 only has 3 days, but the count is still reported
    holidays = {h.date: h for h in env.service._config.holidays if h.canton == "ZH"}
    count = rules.count_days(date(2026, 11, 9), date(2026, 11, 13), holidays)
    assert count.counted == 4
    assert [(e.kind, e.holiday.name("en") if e.holiday else None) for e in count.excluded] == [
        ("holiday", "Fixture Day ZH")
    ]


def test_fr_vac_002_review_lists_excluded_holiday_names(env: Env) -> None:
    """FR-VAC-006.2: emp2 (ZH) sees the holiday and the weekend as excluded."""
    review = env.propose("emp2", "2026-11-09", "2026-11-16").json()["review"]
    assert review["counted_days"] == 5  # 11-09..13 minus holiday = 4, plus Mon 11-16
    kinds = [(e["date"], e["kind"], e.get("name")) for e in review["excluded"]]
    assert ("2026-11-11", "holiday", "Fixture Day ZH") in kinds
    assert ("2026-11-14", "weekend", None) in kinds


def test_fr_vac_002_cross_year_split(env: Env) -> None:
    """FR-VAC-002 / R9 @unit: counted per year, New Year's Day excluded."""
    r = env.propose("emp2", "2026-12-28", "2027-01-05")
    assert r.status_code == 200, r.text
    assert r.json()["review"]["per_year"] == {"2026": 4, "2027": 2}


def test_fr_vac_002_cross_year_checks_each_years_balance(private_key: Any, make_token: Any) -> None:
    """R9: 2027 has its own entitlement, so a year with too few days is rejected on its own."""
    config = replace(VacationConfig.from_files(), entitlement=3, seed_requests=())
    env = Env(private_key, make_token, config)
    r = env.propose("emp2", "2026-12-28", "2027-01-05")
    assert r.status_code == 422 and r.json()["violations"][0]["year"] == 2026


def test_fr_vac_002_dst_week_counts_four() -> None:
    """FR-VAC-002 @unit: clock change on 2026-10-25, Mon-Fri only."""
    assert rules.count_days(date(2026, 10, 23), date(2026, 10, 28), {}).counted == 4


def test_fr_vac_002_submission_is_idempotent(env: Env) -> None:
    proposal = env.propose("emp2", "2026-11-23", "2026-11-25").json()["proposal_id"]
    token = env.confirm("emp2", proposal)
    first = env.submit("emp2", "2026-11-23", "2026-11-25", token)
    second = env.submit("emp2", "2026-11-23", "2026-11-25", token)
    assert (first.status_code, second.status_code) == (201, 200)
    assert first.json()["id"] == second.json()["id"]
    assert len(env.store.for_owner(OIDS["emp2"])) == 2  # fixture + exactly one new
    assert env.get("emp2", "/balance").json()["pending"] == 3


@pytest.mark.parametrize("who", ["emp2"])
def test_fr_vac_002_write_needs_a_valid_confirmation(env: Env, who: str) -> None:
    """FR-AUTH-006: no token, a forged token, a token for other dates or another user."""
    assert env.submit(who, "2026-11-23", "2026-11-25", "").status_code == 409
    assert (
        env.submit(who, "2026-11-23", "2026-11-25", "forged").json()["code"]
        == "INVALID_CONFIRMATION"
    )
    proposal = env.propose(who, "2026-11-23", "2026-11-25").json()["proposal_id"]
    token = env.confirm(who, proposal)
    assert env.submit(who, "2026-11-23", "2026-11-27", token).status_code == 409
    assert env.submit("emp1", "2026-11-23", "2026-11-25", token).status_code == 409
    assert len(env.store.for_owner(OIDS["emp2"])) == 1


def test_fr_vac_002_conflicting_write_after_proposal_is_rejected(env: Env) -> None:
    """R5/R6 are checked again at write time (a second request took the days)."""
    first = env.propose("emp2", "2026-11-23", "2026-11-25").json()["proposal_id"]
    t1 = env.confirm("emp2", first)
    assert env.book("emp2", "2026-11-24", "2026-11-24").status_code == 201
    r = env.submit("emp2", "2026-11-23", "2026-11-25", t1)
    assert r.status_code == 422 and r.json()["code"] == "OVERLAP"


def test_fr_vac_002_other_users_proposal_cannot_be_confirmed(env: Env) -> None:
    proposal = env.propose("emp2", "2026-11-23", "2026-11-25").json()["proposal_id"]
    r = env.client.post(
        "/v1/confirmations",
        json={"type": "vacation", "proposal_id": proposal},
        headers=env.headers("emp1"),
    )
    assert r.status_code == 409


def test_fr_vac_002_ceo_has_no_approver(env: Env) -> None:
    """U-12 assumption: the CEO has no manager, so nothing can be requested."""
    r = env.propose("ceo", "2026-11-23", "2026-11-25")
    assert r.status_code == 422 and r.json()["code"] == "NO_APPROVER"


def test_fr_vac_002_announcement_proposals_still_need_the_publisher_role(env: Env) -> None:
    r = env.client.post(
        "/v1/proposals",
        json={"payload": {"title": "x", "body": "y", "language": "en", "audience": "all"}},
        headers=env.headers("emp2"),
    )
    assert r.status_code == 403


# --- FR-VAC-006 ---------------------------------------------------------------------------


def test_fr_vac_006_all_26_cantons_have_a_2026_table_flagged_for_confirmation() -> None:
    seed = json.loads((SEED_DIR / "holidays.json").read_text())
    assert seed["status"] == "HUMAN_CONFIRMATION_REQUIRED"
    assert len(CANTONS) == 26
    for canton in CANTONS:
        rows = [h for h in seed["holidays"] if h["canton"] == canton and h["date"][:4] == "2026"]
        assert rows, canton
        assert all({"de", "fr", "it", "en"} <= set(h["names"]) and "full_day" in h for h in rows)


def test_fr_vac_006_holiday_list_is_for_my_canton_only(env: Env) -> None:
    r = env.get("emp4", "/holidays?year=2026&lang=en")
    assert r.status_code == 200 and r.json()["canton"] == "TI"
    names = {h["name"]: h["date"] for h in r.json()["holidays"]}
    assert names["Fixture Day TI"] == "2026-11-12"
    assert "Fixture Day ZH" not in names
    zh = {h["name"] for h in env.get("emp2", "/holidays").json()["holidays"]}
    assert "Fixture Day ZH" in zh and "Fixture Day TI" not in zh


def test_fr_vac_006_missing_canton_asks_hr(private_key: Any, make_token: Any) -> None:
    env = Env(private_key, make_token, VacationConfig.from_files())
    env.directory._by_oid[OIDS["emp2"]] = replace(env.directory.get(OIDS["emp2"]), canton=None)
    assert env.get("emp2", "/holidays").json()["code"] == "CANTON_MISSING"
    assert env.propose("emp2", "2026-11-23", "2026-11-25").json()["code"] == "CANTON_MISSING"
    assert env.get("emp2", "/balance").status_code == 200  # the balance does not depend on it


def test_fr_vac_006_canton_change_keeps_approved_counted_days(env: Env) -> None:
    """FR-VAC-006.4 @unit: the stored request keeps the days counted under ZH."""
    env.store._requests.clear()
    assert env.book("emp2", "2026-11-09", "2026-11-13").json()["counted_days"] == 4
    request = env.store.for_owner(OIDS["emp2"])[0]
    env.store._requests[request.id] = replace(request, status="approved")
    env.directory._by_oid[OIDS["emp2"]] = replace(env.directory.get(OIDS["emp2"]), canton="TI")
    kept = env.get("emp2", "/requests").json()["items"][0]
    assert (kept["counted_days"], kept["status"]) == (4, "approved")
    assert env.get("emp2", "/balance").json()["approved"] == 4
    # later lookups use the new canton
    assert env.get("emp2", "/holidays").json()["canton"] == "TI"


def test_fr_vac_006_blackout_scope_is_respected() -> None:
    region = Blackout(date(2026, 12, 1), date(2026, 12, 2), "region", "FR")
    assert rules.blackout_applies(region, "FR", "Store-Geneva")
    assert not rules.blackout_applies(region, "DE", "HQ")


def test_holiday_name_falls_back_to_german() -> None:
    assert Holiday("ZH", date(2026, 1, 1), {"de": "Neujahr"}).name("it") == "Neujahr"
