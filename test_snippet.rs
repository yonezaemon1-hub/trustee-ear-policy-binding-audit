    #[tokio::test]
    async fn test_native_inert_revision_binding() {
        use sha2::{Digest, Sha384};

        // The policy bytes below come directly from the fixed Trustee commit.
        let policy_a_bytes =
            include_bytes!("../../tests/coco-as/policy/opa/ear_no_rv_policy_cpu.rego");
        let policy_a = String::from_utf8(policy_a_bytes.to_vec()).unwrap();
        let policy_b = format!("{policy_a}# No.16 R5: comment-only source revision\n");
        assert_ne!(policy_a, policy_b);
        let sha384_a = hex::encode(Sha384::digest(policy_a_bytes));
        let sha384_b = hex::encode(Sha384::digest(policy_b.as_bytes()));
        assert_ne!(sha384_a, sha384_b);

        let (_key, private_key_bytes, public_key_bytes) = generate_ec_keys().unwrap();
        let mut key_file = NamedTempFile::new().unwrap();
        key_file.write_all(&private_key_bytes).unwrap();
        let mut config = EarTokenConfiguration::default();
        config.signer = Some(TokenSignerConfig {
            key_path: key_file.path().to_str().unwrap().to_string(),
            cert_url: None,
            cert_path: None,
        });
        let storage = KeyValueStorageStructConfig::default()
            .to_client_with_namespace(KeyValueStorageType::Memory, AS_POLICY_STORAGE_NAMESPACE)
            .await
            .unwrap();
        let broker = EarAttestationTokenBroker::new(config, storage).await.unwrap();

        let effective_key = "audit_cpu";
        let external_id = "audit";
        broker
            .set_policy(effective_key.into(), policy_a.clone())
            .await
            .unwrap();
        assert_eq!(broker.get_policy(effective_key.into()).await.unwrap(), policy_a);

        let claims = || {
            vec![TeeClaims {
                tee: Tee::Sample,
                tee_class: "cpu".into(),
                claims: json!({"claim": "claim1"}),
                runtime_data_claims: json!({"runtime_data": "111"}),
                init_data_claims: json!({"initdata": "111"}),
            }]
        };
        let token_a = broker
            .issue(claims(), vec![external_id.into()], None)
            .await
            .unwrap();
        broker
            .set_policy(effective_key.into(), policy_b.clone())
            .await
            .unwrap();
        assert_eq!(broker.get_policy(effective_key.into()).await.unwrap(), policy_b);
        let token_b = broker
            .issue(claims(), vec![external_id.into()], None)
            .await
            .unwrap();

        let public_key = DecodingKey::from_ec_pem(&public_key_bytes).unwrap();
        let ear_a = Ear::from_jwt(&token_a, jsonwebtoken::Algorithm::ES256, &public_key).unwrap();
        let ear_b = Ear::from_jwt(&token_b, jsonwebtoken::Algorithm::ES256, &public_key).unwrap();
        let policy_id_a = ear_a.submods.get("cpu0").unwrap().policy_id.as_deref();
        let policy_id_b = ear_b.submods.get("cpu0").unwrap().policy_id.as_deref();
        assert_eq!(policy_id_a, Some(external_id));
        assert_eq!(policy_id_b, Some(external_id));

        fn decoded_signed_payload(token: &str) -> Value {
            let segments: Vec<&str> = token.split('.').collect();
            assert_eq!(segments.len(), 3);
            serde_json::from_slice(&URL_SAFE_NO_PAD.decode(segments[1]).unwrap()).unwrap()
        }
        fn scan_digest(value: &Value, digest: &str) -> bool {
            match value {
                Value::Object(fields) => fields.iter().any(|(key, nested)| {
                    key.to_ascii_lowercase().contains(digest)
                        || scan_digest(nested, digest)
                }),
                Value::Array(items) => items.iter().any(|item| scan_digest(item, digest)),
                Value::String(text) => text.to_ascii_lowercase().contains(digest),
                _ => false,
            }
        }
        fn collect_explicit_policy_hash_fields(value: &Value, path: &str, found: &mut Vec<String>) {
            match value {
                Value::Object(fields) => {
                    for (key, nested) in fields {
                        let lower = key.to_ascii_lowercase();
                        let next = format!("{path}/{key}");
                        if lower.contains("policy") && lower.contains("hash") {
                            found.push(next.clone());
                        }
                        collect_explicit_policy_hash_fields(nested, &next, found);
                    }
                }
                Value::Array(items) => {
                    for (index, nested) in items.iter().enumerate() {
                        collect_explicit_policy_hash_fields(
                            nested,
                            &format!("{path}/{index}"),
                            found,
                        );
                    }
                }
                _ => {}
            }
        }
        // Predetermined issuance-time exclusions: iat and exp only.
        fn strip_predetermined_temporal_fields(value: &mut Value) {
            match value {
                Value::Object(fields) => {
                    fields.remove("iat");
                    fields.remove("exp");
                    for nested in fields.values_mut() {
                        strip_predetermined_temporal_fields(nested);
                    }
                }
                Value::Array(items) => {
                    for nested in items {
                        strip_predetermined_temporal_fields(nested);
                    }
                }
                _ => {}
            }
        }

        let mut payload_a = decoded_signed_payload(&token_a);
        let mut payload_b = decoded_signed_payload(&token_b);
        let digest_a_absent = !scan_digest(&payload_a, &sha384_a)
            && !scan_digest(&payload_b, &sha384_a);
        let digest_b_absent = !scan_digest(&payload_a, &sha384_b)
            && !scan_digest(&payload_b, &sha384_b);
        assert!(digest_a_absent, "observed SHA-384(A) found in a signed payload");
        assert!(digest_b_absent, "observed SHA-384(B) found in a signed payload");
        let mut hash_fields_a = Vec::new();
        let mut hash_fields_b = Vec::new();
        collect_explicit_policy_hash_fields(&payload_a, "", &mut hash_fields_a);
        collect_explicit_policy_hash_fields(&payload_b, "", &mut hash_fields_b);
        assert!(hash_fields_a.is_empty(), "explicit policy hash fields in A: {hash_fields_a:?}");
        assert!(hash_fields_b.is_empty(), "explicit policy hash fields in B: {hash_fields_b:?}");
        strip_predetermined_temporal_fields(&mut payload_a);
        strip_predetermined_temporal_fields(&mut payload_b);
        assert_eq!(payload_a, payload_b);

        println!("sha384_a={sha384_a}");
        println!("sha384_b={sha384_b}");
        println!("effective_policy_key={effective_key}");
        println!("external_policy_id={external_id}");
        println!("policy_id_a={}", policy_id_a.unwrap());
        println!("policy_id_b={}", policy_id_b.unwrap());
        println!("same_logical_policy_identity=true");
        println!("signature_a_verified=true");
        println!("signature_b_verified=true");
        println!("digest_a_absent_from_both_signed_payloads={digest_a_absent}");
        println!("digest_b_absent_from_both_signed_payloads={digest_b_absent}");
        println!("observed_explicit_policy_hash_field_paths_a={hash_fields_a:?}");
        println!("observed_explicit_policy_hash_field_paths_b={hash_fields_b:?}");
        println!("temporal_exclusions=iat,exp");
        println!("normalized_non_temporal_payload_equal=true");
        println!("PASS_NATIVE_INERT_REVISION_BINDING_TEST");
    }
