# Release manifest — v1.0.0

Release purpose: freeze the reproducibility software and evidence identities supporting the paper **A Reproducible Audit of Exact Appraisal-Policy Revision Binding in Confidential Containers Trustee EAR Tokens**.

## Release identity

- Repository: `yonezaemon1-hub/trustee-ear-policy-binding-audit`
- Intended tag: `v1.0.0`
- Upstream Trustee commit: `512fed65642015b849f38fb13bfdec7806639987`
- Exact test: `test_native_inert_revision_binding`
- Rust/Cargo: `1.95.0`
- Windows protoc: `31.1`

## Frozen witness hashes

- `test_snippet.rs` SHA-256: `1e69a6d7d3eaede9bcd9082ea0a01fd9ad01b0894a7d359c995b3416efe9662d`
- `patched_broker.rs` SHA-256: `0b34df6b20e90625c28555f36930b7502f5f36b08a349de219f232ea29ebad71`
- `injection.diff` SHA-256: `8e5d163d2b5eaf538aea2d73d8585100853cb3b113f316fa8176824a94cdf502`

## Measured policy-source digests

- SHA-384 Policy A: `7e907f6f05704b64f32ec883ab0069c376606e547f6a9667d34d500db9d5c72b01fd8812063006e2abb291a06d3233fd`
- SHA-384 Policy B: `515cfecc2386e935be44369093cbee8bd9c6c133cde6aa14b35d1654c77971e0fb3be9a8c030a792f876b77cd6411094`

## Replication evidence

- Ubuntu 24.04 hosted run: `35049279405` — PASS
- Ubuntu artifact: `NO16_UBUNTU24_R5_EVIDENCE`
- Ubuntu artifact ZIP SHA-256: `8be8dbccc909fd83621114e15a2d60189a6fb760b53fce1f282cce51c8a8d2ed`

- Windows Server 2025 hosted run: `35054556409` — PASS
- Windows artifact: `NO16_WINDOWS2025_R5_EVIDENCE_V4`
- Windows artifact ZIP SHA-256: `bf26b9c85dfc050d4fb645bc1418e71473ee9f9eccc29ec02a0bd6da2c477295`

- Physical Windows 10 local evidence ZIP SHA-256: `bf25033fbf9d475ad0bd9abb7e3d3fc66fe6778b0742cc0251a0ce1cefed10e3`

## Claim boundary

This release supports the implementation-specific claim that, for the pinned Trustee commit and tested EAR path, two byte-distinct / SHA-384-distinct appraisal-policy source revisions can be evaluated under the same logical policy identity while the signed EAR payload does not expose either measured source digest or an explicit policy-hash field path, and the decoded payloads are equal after removing only predetermined `iat` and `exp` fields.

The release does not claim different Rego evaluation semantics between Policy A and Policy B, does not independently establish semantic equivalence, and does not claim signature forgery, unauthorized policy replacement, or universal applicability across Trustee versions/configurations.

## Publication freeze order

1. Merge this release-preparation state to `main`.
2. Create immutable GitHub tag/release `v1.0.0` at the resulting release commit.
3. Archive that GitHub release in Zenodo as a Software record and obtain the Software DOI.
4. Insert the Software DOI into the paper/metadata.
5. Regenerate and re-audit the final PDF.
6. Compute the final publication PDF SHA-256 exactly once after DOI insertion.
7. Publish the Paper record and link Paper ↔ Software records.
