#!/usr/bin/env python3
"""Independent reference implementation used to generate language-neutral
FACETS rule fixtures (probability calibration and resolution cases).

It deliberately shares no code with the GDScript implementation, so the
GDScript test suite cross-checks two implementations of the same rules.
Usage: python3 tools/generate_rule_fixtures.py
"""
import itertools
import json
import os

ROOT = os.path.join(os.path.dirname(__file__), "..", "tests", "fixtures", "rules")
TARGETS = {"favorable": 9, "standard": 11, "demanding": 13, "severe": 15, "extreme": 17, "legendary": 19}


def band(margin, costly):
    if margin >= 4:
        return "strong_success"
    if margin >= 0:
        return "success"
    if margin >= -2:
        return "costly_offer" if costly else "failure"
    return "failure"


def clamp(value, low, high):
    return max(low, min(high, value))


def counts(facet, skill, modifier_sum, target, costly, push=False, resolve=False):
    result = {"failure": 0, "costly_offer": 0, "success": 0, "strong_success": 0}
    for d1, d2 in itertools.product(range(1, 7), repeat=2):
        total = d1 + d2 + facet + skill + clamp(modifier_sum, -3, 3) + (1 if push else 0) + (2 if resolve else 0)
        result[band(total - target, costly)] += 1
    return result


def calibration():
    rows = []
    # Representative facet/skill splits covering bonus 2..9 and all tiers.
    for facet, skill in [(2, 0), (2, 1), (2, 2), (3, 2), (4, 2), (4, 3), (5, 3), (5, 4)]:
        for tier, target in TARGETS.items():
            for modifier_sum in (-4, -1, 0, 2, 5):
                for costly in (True, False):
                    rows.append({
                        "facet": facet, "skill": skill, "modifier_sum": modifier_sum,
                        "target": target, "tier": tier, "allows_costly_success": costly,
                        "push": False, "resolve": False,
                        "expected": counts(facet, skill, modifier_sum, target, costly),
                    })
    for push, resolve in [(True, False), (False, True), (True, True)]:
        for facet, skill, target in [(3, 2, 13), (5, 3, 14), (2, 0, 11)]:
            rows.append({
                "facet": facet, "skill": skill, "modifier_sum": 0, "target": target,
                "tier": "", "allows_costly_success": True, "push": push, "resolve": resolve,
                "expected": counts(facet, skill, 0, target, True, push, resolve),
            })
    return rows


def resolution_cases():
    cases = []
    def add(name, facet, skill, target, costly, dice, mods_sum=0, push=False, resolve=False, note=""):
        total = dice[0] + dice[1] + facet + skill + clamp(mods_sum, -3, 3) + (1 if push else 0) + (2 if resolve else 0)
        cases.append({
            "name": name, "note": note,
            "check": {"facet": facet, "skill": skill, "target": target, "allows_costly_success": costly},
            "modifier_sum": mods_sum, "push": push, "resolve": resolve, "dice": list(dice),
            "expected": {"total": total, "margin": total - target, "band": band(total - target, costly)},
        })
    add("spec_api_example", 3, 2, 13, True, (3, 3), note="Spec section 5 example: total 11, margin -2, costly offer")
    add("mara_branch_c_resolve", 3, 2, 13, True, (3, 3), resolve=True, note="Branch C: +2 Resolve gives total 13, clean success")
    add("margin_minus_3", 3, 2, 13, True, (1, 4))
    add("margin_minus_2", 3, 2, 13, True, (2, 4))
    add("margin_minus_1", 3, 2, 13, True, (3, 4))
    add("margin_0", 3, 2, 13, True, (4, 4))
    add("margin_3", 3, 2, 13, True, (5, 6))
    add("margin_4", 3, 2, 13, True, (6, 6))
    add("margin_minus_2_costly_disabled", 3, 2, 13, False, (2, 4))
    add("snake_eyes_no_critical", 5, 4, 9, True, (1, 1), note="Natural 2 is not an automatic failure")
    add("boxcars_no_critical", 2, 0, 19, True, (6, 6), note="Natural 12 is not an automatic success")
    add("modifier_cap_positive", 3, 2, 13, True, (3, 3), mods_sum=5)
    add("modifier_cap_negative", 3, 2, 13, True, (3, 3), mods_sum=-6)
    add("push_outside_cap", 3, 2, 13, True, (3, 3), mods_sum=4, push=True)
    add("push_and_resolve_outside_cap", 3, 2, 13, True, (2, 2), mods_sum=3, push=True, resolve=True)
    return cases


def main():
    os.makedirs(ROOT, exist_ok=True)
    spec_fixture = {
        "name": "pitch_correction_cunning5_technology3_vs14",
        "note": "Spec section 7 fixture; advanced build (facet 5, skill 3 exceed standard creation).",
        "facet": 5, "skill": 3, "modifier_sum": 0, "target": 14,
        "with_costly": {"failure": 3, "costly_offer": 7, "success": 20, "strong_success": 6},
        "without_costly": {"failure": 10, "costly_offer": 0, "success": 20, "strong_success": 6},
        "percent_with_costly": {"failure": "8.33%", "costly_offer": "19.44%", "success": "55.56%", "strong_success": "16.67%"},
        "percent_without_costly": {"failure": "27.78%"},
    }
    assert counts(5, 3, 0, 14, True) == spec_fixture["with_costly"]
    assert counts(5, 3, 0, 14, False) == spec_fixture["without_costly"]
    with open(os.path.join(ROOT, "probability_calibration.json"), "w") as handle:
        json.dump({"schema_version": 1, "generator": "tools/generate_rule_fixtures.py",
                   "spec_fixture": spec_fixture, "rows": calibration()}, handle, indent=1, sort_keys=True)
        handle.write("\n")
    with open(os.path.join(ROOT, "resolution_cases.json"), "w") as handle:
        json.dump({"schema_version": 1, "generator": "tools/generate_rule_fixtures.py",
                   "cases": resolution_cases()}, handle, indent=1, sort_keys=True)
        handle.write("\n")
    print("wrote", len(calibration()), "calibration rows and", len(resolution_cases()), "resolution cases")


if __name__ == "__main__":
    main()
