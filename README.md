# Trustee EAR appraisal-policy revision binding audit

Reproducibility repository for:

**A Reproducible Audit of Exact Appraisal-Policy Revision Binding in Confidential Containers Trustee EAR Tokens**  
Ryutaro Yonezu — Independent Researcher

This repository contains the frozen R5 witness and replication runners used to audit exact appraisal-policy **source-revision provenance** in Confidential Containers Trustee EAR tokens.

## Claim boundary

R5 tests whether two byte-distinct / SHA-384-distinct policy-source revisions, installed under the same logical policy identity, are distinguishable from the signed EAR payload in the audited path.

Policy B is Policy A plus a single comment line. Therefore this repository does **not** claim that the two Rego policies have different evaluation semantics, nor does it independently establish semantic equivalence. It also does not claim signature forgery, unauthorized policy replacement, or applicability to every Trustee release or configuration.

## Pinned upstream revision

Confidential Containers Trustee commit:

`512fed65642015b849f38fb13bfdec7806639987`

Exact native test:

`test_native_inert_revision_binding`

Pinned Rust/Cargo toolchain:

`1.95.0`

Pinned Windows protoc:

`31.1`

## Frozen R5 identities

- `test_snippet.rs` SHA-256: `1e69a6d7d3eaede9bcd9082ea0a01fd9ad01b0894a7d359c995b3416efe9662d`
- `patched_broker.rs` SHA-256: `0b34df6b20e90625c28555f36930b7502f5f36b08a349de219f232ea29ebad71`
- `injection.diff` SHA-256: `8e5d163d2b5eaf538aea2d73d8585100853cb3b113f316fa8176824a94cdf502`

Measured policy-source SHA-384 digests:

- Policy A: `7e907f6f05704b64f32ec883ab0069c376606e547f6a9667d34d500db9d5c72b01fd8812063006e2abb291a06d3233fd`
- Policy B: `515cfecc2386e935be44369093cbee8bd9c6c133cde6aa14b35d1654c77971e0fb3be9a8c030a792f876b77cd6411094`

## R5 observations

The successful witness establishes all of the following for the tested path and commit:

- Policy A and Policy B source bytes differ.
- SHA-384(A) and SHA-384(B) differ.
- Effective Trustee policy key: `audit_cpu`.
- Signed appraisal policy id for both revisions: `audit`.
- Both EAR signatures verify.
- Neither measured source digest appears in either decoded signed payload.
- No explicit field path whose key contains both `policy` and `hash` is observed.
- Predetermined temporal exclusions are exactly `iat` and `exp`.
- After removing only those temporal fields, the decoded signed payloads are equal.
- Exact native Rust test result: `1 passed; 0 failed`.

## Replication matrix

| Environment | Result | Evidence |
| --- | --- | --- |
| Ubuntu 24.04, GitHub-hosted | PASS | Actions run `35049279405`; artifact `NO16_UBUNTU24_R5_EVIDENCE`; ZIP SHA-256 `8be8dbccc909fd83621114e15a2d60189a6fb760b53fce1f282cce51c8a8d2ed` |
| Windows Server 2025, GitHub-hosted | PASS | Actions run `35054556409`; artifact `NO16_WINDOWS2025_R5_EVIDENCE_V4`; ZIP SHA-256 `bf26b9c85dfc050d4fb645bc1418e71473ee9f9eccc29ec02a0bd6da2c477295` |
| Windows 10, physical host | PASS | Local evidence ZIP SHA-256 `bf25033fbf9d475ad0bd9abb7e3d3fc66fe6778b0742cc0251a0ce1cefed10e3` |

The downloaded hosted evidence packages were separately checked against their internal `SHA256SUMS.txt` manifests. The physical Windows 10 evidence package also passed its internal manifest check.

## Exact test command

```text
cargo +1.95.0 -vv test --locked -p attestation-service --lib test_native_inert_revision_binding -- --nocapture
```

## Repository layout

- `test_snippet.rs` — frozen exact R5 witness.
- `.github/workflows/no16-ubuntu-r5.yml` — Ubuntu 24.04 hosted replication.
- `.github/workflows/no16-windows-r5-v4.yml` — successful Windows Server 2025 hosted replication.
- `RUN_LOCAL_WINDOWS_R5_RECHECK_V5.ps1` — final physical-Windows wrapper used for the successful local run.
- Earlier local runner revisions are retained as provenance for the debugging history; they are not the final successful local wrapper.

## Publication status

The paper is being released separately as a preprint. This software snapshot is intended to receive its own Zenodo Software DOI. The paper record should link to this software record as supplementary reproducibility material.

## Upstream software

This audit targets the public Confidential Containers Trustee repository at the pinned commit shown above. No claim is made that this repository is an upstream Trustee release or that the audit witness is part of upstream Trustee.
