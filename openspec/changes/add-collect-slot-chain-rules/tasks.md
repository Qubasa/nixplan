## 1. Design record

- [x] 1.1 Assign the owning bead for `§30`: either open a new `bd` issue for the collector-chain rules or attach to an existing one, then verify `bd show <id>` prints it and that its description names `notes/clan-portable-services-design.md §30`
- [x] 1.2 Write `## §30 Collect slots and the collector chain — DECIDED 2026-08-31 (<bead-id>)` in `notes/clan-portable-services-design.md` after `§29`, with subsections for the defect, the corrected resolution order, `order`, transitive exclusion, stratified `impl`, per-export set dependence, the group-as-subject rule, what it retires and what it costs; verify the section heading matches the `§25`/`§29` header format by comparing against `grep -nE '^## §2[59]' notes/clan-portable-services-design.md`
- [x] 1.3 In `§30`, cite `openspec/specs/planner/collect-slots/spec.md` as the normative source and state that the rules are decided while collect slots remain unadopted; verify by grepping the new section for both the spec path and the word `unadopted`
- [x] 1.4 In `§30`'s cost subsection, record the two residuals from `design.md` — the unit graph is not a manifest object, and the guarantee covers only planner-generated stop edges; verify both appear and neither is stated as solved

## 2. New example: interfaces and modules

- [x] 2.1 Create `examples/quiesce-group/interfaces/default.nix` with `quiesceParticipant` (a `writer` unit reference plus `holds`), `stateSubject` (`holds` plus the `copy` union) and `stateStaging`, every export `machine-local`, with a header comment stating which are collected and by whom; verify `nixfmt --check` reports only "not formatted" and never a parse error
- [x] 2.2 Create `examples/quiesce-group/modules/postgres/{default.nix,service.nix}`: answers the participation question with `writer = unit.postgres`, does not answer the outer question; verify the file contains no `contributes.state` and that `nixfmt` parses it
- [x] 2.3 Create `examples/quiesce-group/modules/keycloak/{default.nix,service.nix}`: same shape, plus `uses.db` wired to postgres, which is the edge the wire ordering is derived from; verify the slot is declared with an interface and that `nixfmt` parses it
- [x] 2.4 Create `examples/quiesce-group/modules/zfs/{default.nix,service.nix}`: the group owner — `collects.participants` with `order = "wire"`, `contributes.state` staged from its own snapshot unit, a `requirements.machine.capability` that takes it off a machine with no snapshots, and one comment explaining why the stop bracket lives inside the unit; verify `nixfmt` parses it and the collect slot carries all five fields
- [x] 2.5 Create `examples/quiesce-group/modules/backup/{default.nix,service.nix}`: `collects.state`, and a real answer to the participation question so the deployment reproduces the deadlock condition before exclusion; verify both the collect slot and the participation contribution are present
- [x] 2.6 Create `examples/quiesce-group/modules/sshd/{default.nix,service.nix}` as the `copy.live` control that joins no group; verify it declares no participation contribution

## 3. New example: deployment and plan

- [x] 3.1 Create `examples/quiesce-group/deployment/machines.nix` with two machines — one that hosts the group owner and one that cannot, so the no-group control sits beside the group case; verify `nixfmt` parses it and the second machine's class or tags explain the drop
- [x] 3.2 Create `examples/quiesce-group/deployment/instances.nix` placing postgres, keycloak, the snapshotter, sshd and two backup instances with different repositories and schedules, one `wire` entry for keycloak's database, and the two `answers.state.nothing = true` lines that silence the group members; verify `nixfmt` parses it and both silencing lines are present
- [x] 3.3 Create `examples/quiesce-group/plan/participants.json`: the group owner's question resolved on the hosting machine, showing the ordered member sequence, the `excluded` map with the transitive entry and its reason, and the stratum assigned to each entry; verify `jq -e . ` parses it and the excluded map names the backup instance
- [x] 3.4 Create `examples/quiesce-group/plan/state.json`: the outer question on both machines, showing the group owner's single staged answer, `requires` edges from both backup units to the one snapshot unit, the demand-start marking, and the control machine where every answer is `copy.live` and no edges are emitted; verify `jq -e .` parses it and both machines appear
- [x] 3.5 Create `examples/quiesce-group/plan/diagnostics.txt` with a header census derived from `deployment/`, the rows this deployment produces, and the rows it could produce; verify `grep -cE '^  [x!] '` equals the count stated in the header
- [x] 3.6 In `plan/diagnostics.txt`, include the row for the deadlock that transitive exclusion prevents, written as the exclusion plus its warning rather than as a refusal, and the two agreement rows for a member claimed-but-not-silenced and silenced-but-not-claimed; verify all three rows exist and that none of the three is an error row for the first case

## 4. New example: README

- [x] 4.1 Write `examples/quiesce-group/README.md` opening with the disclaimer naming every construct that exists in no tree, then the machine census, then a section per finding: the group is one subject, the chain is three strata, exclusion before stratification, and the deadlock the eval-cycle rule cannot see; verify the manifest block lists every file the folder actually contains
- [x] 4.2 In that README, add the escalation table from `design.md` — today's accidental refusal, stratification alone, and both corrections — and a Provenance section citing `§30`, the spec path and `clan/clan-core#5869`; verify the three states and all three citations are present

## 5. Firewall folder reconciliation

- [x] 5.1 Move the two `zeta` rows and the `x prod` refcount row out of `examples/firewall/plan/diagnostics.txt` into the new folder's diagnostics, keeping no duplicate; verify `grep -c zeta` in the firewall diagnostics drops by the number of rows moved and that each moved row appears exactly once across both files
- [x] 5.2 Convert the consistency-group, collector-as-subject and restore entries in `examples/firewall/README.md` "What this folder does not answer" into one cross-reference to `../quiesce-group/`; verify the three original paragraphs are gone and the cross-reference resolves to an existing directory
- [x] 5.3 Re-derive the firewall folder's census in all three places it is stated — the README manifest line, the README prose, and the diagnostics header — from the files themselves; verify the row count from `grep -cE '^  [x!] '` matches both README and diagnostics header, and that the instance and machine counts match `deployment/instances.nix` and `deployment/machines.nix`

## 6. Blog

- [x] 6.1 Update the collector section of `pkgs/qubasa-blog/posts/07-reading-real-fleets.md`: make the backup row's residual specific, and add the chain case beside the four collectors without adding a new section; verify the post's front matter, its "Part 7 of 7" framing and its other sections are unchanged by inspecting the diff
- [x] 6.2 Confirm `pkgs/qubasa-blog/posts/03-evaluation-order.md` is untouched, so the eight-round trace still describes wired slots only; verify the file has no diff

## 7. Verification

- [x] 7.1 Cross-walk every requirement and scenario in `openspec/changes/add-collect-slot-chain-rules/specs/planner/collect-slots/spec.md` to a row in the new folder's `plan/diagnostics.txt` or a field in one of its plan files, and record the mapping plus any scenario the example deliberately does not exercise in the new README; verify all nine requirements are covered and every uncovered scenario is named
- [x] 7.2 Run `jq -e .` over every JSON file in `examples/quiesce-group/plan/` and `nixfmt --check` over every `.nix` file in `examples/quiesce-group/`, treating only a parse error as a failure since these folders are not formatter-clean at baseline; verify no parse errors
- [x] 7.3 Check that no file states a rule the others contradict: grep `§30`, the new README and the spec for `order`, `exclusion` and `stratum`, and confirm the three describe the same resolution order; verify by listing the three statements side by side
- [x] 7.4 Run `openspec validate add-collect-slot-chain-rules --strict` and confirm it passes with the artifacts as implemented
